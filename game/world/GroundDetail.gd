class_name GroundDetail
extends Node3D
## v0.15 ferns, shrubs, sasa and mushrooms, GPU-placed like the grass (see
## Foliage.gd and grass_common.gdshaderinc). One ring per kind, each kind on
## its own grid with its own probability per biome.

const LEAF_CELLS := [Vector4(0.0, 0.0, 0.25, 0.5), Vector4(0.25, 0.0, 0.25, 0.5), Vector4(0.5, 0.0, 0.25, 0.5),
	Vector4(0.75, 0.0, 0.25, 0.5), Vector4(0.0, 0.5, 0.25, 0.5), Vector4(0.25, 0.5, 0.25, 0.5),
	Vector4(0.5, 0.5, 0.25, 0.5), Vector4(0.75, 0.5, 0.25, 0.5)]
# probability per grid point by biome (Terrain.BIOME_NAMES order):
# grassland farmland tallgrass bamboo rocky alpine shrine forest village shore
const KINDS := [
	{"name": "fern", "sp": 2.0, "range": 60.0, "tex": "grass", "rects": ["frond0", "frond1", "frond2", "frond3"],
		"scale": 1.0, "jit": 0.3, "stiff": 0.55, "dome": 0.15, "lush": Color(0.25, 0.44, 0.17), "dry": Color(0.45, 0.45, 0.22),
		"regrade": 0.25, "lum": 0.08, "trans": 0.45, "canopy": 1.2, "shadow": true,
		"prob": [0.03, 0.0, 0.03, 0.12, 0.04, 0.02, 0.06, 0.40, 0.02, 0.05]},
	{"name": "shrub", "sp": 3.0, "range": 90.0, "tex": "leaf", "cells": [0, 7],
		"scale": 1.0, "jit": 0.35, "stiff": 0.25, "dome": 0.45, "lush": Color(0.26, 0.42, 0.18), "dry": Color(0.46, 0.44, 0.22),
		"regrade": 0.35, "lum": 0.07, "trans": 0.35, "canopy": 0.4, "shadow": true,
		"prob": [0.05, 0.03, 0.05, 0.04, 0.08, 0.06, 0.08, 0.12, 0.07, 0.07]},
	{"name": "sasa", "sp": 1.8, "range": 60.0, "tex": "leaf", "cells": [5],
		"scale": 1.0, "jit": 0.3, "stiff": 0.6, "dome": 0.25, "lush": Color(0.28, 0.46, 0.18), "dry": Color(0.50, 0.48, 0.24),
		"regrade": 0.30, "lum": 0.07, "trans": 0.5, "canopy": 0.6, "shadow": false,
		"prob": [0.0, 0.0, 0.01, 0.45, 0.0, 0.0, 0.03, 0.06, 0.0, 0.02]},
	{"name": "mushroom", "sp": 3.0, "range": 26.0, "tex": "", "scale": 1.2, "jit": 0.3, "stiff": 0.0, "dome": 0.05,
		"lush": Color(0.60, 0.50, 0.40), "dry": Color(0.66, 0.58, 0.46), "regrade": 0.0, "lum": 0.1, "trans": 0.1,
		"canopy": 1.5, "shadow": false,
		"prob": [0.0, 0.0, 0.0, 0.02, 0.0, 0.0, 0.01, 0.06, 0.0, 0.0]},
]
const TILE := 24.0

var _rings: Array = []
var _quality := 2

func materials() -> Array:
	var out := []
	for r in _rings: out.append(r["mat"])
	return out

func set_quality(level: int, fol: Foliage) -> void:
	_quality = level
	for r in _rings:
		for mi in (r["active"] as Dictionary).values(): (mi as Node).queue_free()
		for mi in r["pool"]: (mi as Node).queue_free()
	_rings.clear()
	if fol == null or fol.terrain == null or not fol.terrain.loaded: return
	var range_k: float = [0.55, 0.8, 1.0, 1.25][clampi(level, 0, 3)]
	var dens_k: float = [0.5, 0.75, 1.0, 1.2][clampi(level, 0, 3)]
	var sh: Shader = load("res://shaders/ground_detail.gdshader")
	var grass_atlas: Texture2D = load("res://assets/textures/foliage/grass_atlas.png")
	var leaf_atlas: Texture2D = load("res://assets/textures/foliage/leaf_atlas.png")
	for k in KINDS:
		if level == 0 and str(k["name"]) == "mushroom": continue
		var mat := ShaderMaterial.new()
		mat.shader = sh
		fol.apply_data(mat)
		var rects := PackedVector4Array()
		var mesh: Mesh
		match str(k["name"]):
			"fern":
				for nm in k["rects"]:
					var a: Array = Foliage.ATLAS[nm]
					rects.append(Vector4(a[0], a[1], a[2], a[3]))
				mat.set_shader_parameter("tex", grass_atlas)
				mesh = fern_mesh()
			"shrub":
				for ci in k["cells"]: rects.append(LEAF_CELLS[ci])
				mat.set_shader_parameter("tex", leaf_atlas)
				mesh = dome_mesh(9, 0.55, 0.42, 0.62)
			"sasa":
				for ci in k["cells"]: rects.append(LEAF_CELLS[ci])
				mat.set_shader_parameter("tex", leaf_atlas)
				mesh = _scaled(Foliage.card_mesh(3, 2), Vector3(0.95, 0.75, 0.95))
			_:
				mesh = MeshLib.mushroom(1)
		var nrect := rects.size()
		while rects.size() < 4: rects.append(Vector4(0, 0, 1, 1))
		mat.set_shader_parameter("rects", rects)
		mat.set_shader_parameter("nrect", maxi(nrect, 1))
		mat.set_shader_parameter("textured", 0 if str(k["tex"]) == "" else 1)
		var pr := PackedFloat32Array()
		for v in k["prob"]: pr.append(float(v))
		mat.set_shader_parameter("prob", pr)
		mat.set_shader_parameter("canopy_boost", float(k["canopy"]))
		mat.set_shader_parameter("base_scale", float(k["scale"]))
		mat.set_shader_parameter("scale_jitter", float(k["jit"]))
		mat.set_shader_parameter("stiff", float(k["stiff"]))
		mat.set_shader_parameter("dome_y", float(k["dome"]))
		mat.set_shader_parameter("tint_lush", k["lush"])
		mat.set_shader_parameter("tint_dry", k["dry"])
		mat.set_shader_parameter("regrade", float(k["regrade"]))
		mat.set_shader_parameter("tex_lum", float(k["lum"]))
		mat.set_shader_parameter("translucency", float(k["trans"]))
		var r1: float = float(k["range"]) * range_k
		var sp: float = float(k["sp"])
		mat.set_shader_parameter("spacing", sp)
		mat.set_shader_parameter("ring_r0", 0.0)
		mat.set_shader_parameter("ring_in", 0.0)
		mat.set_shader_parameter("ring_r1", r1)
		mat.set_shader_parameter("ring_out", r1 * 0.3)
		mat.set_shader_parameter("fade_w", 4.0)
		mat.set_shader_parameter("size_mul", 1.0)
		mat.set_shader_parameter("density_mul", dens_k)
		mat.set_shader_parameter("shadow_r", r1 * 0.6)
		var mm := Foliage.grid_multimesh(mesh, TILE, sp)
		_rings.append({"kind": k, "mat": mat, "mm": mm, "r1": r1, "active": {}, "pool": [],
			"shadow": bool(k["shadow"]) and level >= 2, "fol": fol})

## Leaf-cluster cards on a dome: a shrub's broken outline from a handful of
## alpha cards instead of hundreds of flat diamonds.
static func dome_mesh(cards: int, radius: float, height: float, card: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9151
	for i in cards:
		# spherical fibonacci over the upper hemisphere
		var t := (float(i) + 0.5) / float(cards)
		var el := asin(lerpf(0.15, 0.95, t))
		var az := float(i) * 2.39996 + rng.randf_range(-0.3, 0.3)
		var d := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
		var c := Vector3(d.x * radius * 0.55, height * 0.35 + d.y * height * 0.6, d.z * radius * 0.55)
		var right := Vector3.UP.cross(d)
		if right.length() < 0.01: right = Vector3.RIGHT
		right = right.normalized()
		var up := d.cross(right).normalized()
		var roll := rng.randf_range(-0.5, 0.5)
		var r2 := right * cos(roll) + up * sin(roll)
		var u2 := up * cos(roll) - right * sin(roll)
		var sz := card * rng.randf_range(0.8, 1.2)
		var base := verts.size()
		for q in 4:
			var su := -0.5 if q == 0 or q == 3 else 0.5
			var sv := -0.5 if q < 2 else 0.5
			var p := c + r2 * su * sz + u2 * sv * sz
			p.y = maxf(p.y, 0.0)
			verts.append(p)
			norms.append(d)
			uvs.append(Vector2(su + 0.5, 0.5 - sv))
			cols.append(Color(clampf(p.y / (height * 1.2), 0.0, 1.0), float(i % 8) / 8.0, 0.0, 1.0))
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## A fern: fronds that rise from the crown and arch over under their own
## weight, each one a strip textured with a scanned frond.
static func fern_mesh(fronds := 7, segs := 4) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4243
	for f in fronds:
		var a := TAU * float(f) / float(fronds) + rng.randf_range(-0.25, 0.25)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-sin(a), 0.0, cos(a))
		var L := rng.randf_range(0.55, 0.85)
		var half := L * 0.25
		var elev := rng.randf_range(0.95, 1.25)
		var droop := rng.randf_range(1.0, 1.5)
		var p := Vector3.ZERO
		var base := verts.size()
		for s in segs + 1:
			var t := float(s) / float(segs)
			if s > 0:
				var ang := elev - droop * (t - 0.5 / float(segs))
				p += (dir * cos(ang) + Vector3.UP * sin(ang)) * (L / float(segs))
			var nrm := (Vector3.UP + dir * 0.3).normalized()
			for c in 2:
				var x := float(c) - 0.5
				verts.append(p + side * x * 2.0 * half)
				norms.append(nrm)
				uvs.append(Vector2(float(c), 1.0 - t))
				cols.append(Color(t, float(f % 8) / 8.0, 0.0, 1.0))
		for s in segs:
			var i0 := base + s * 2
			idx.append_array(PackedInt32Array([i0, i0 + 2, i0 + 1, i0 + 1, i0 + 2, i0 + 3]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

static func _scaled(src: ArrayMesh, k: Vector3) -> ArrayMesh:
	var arr := src.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in v.size(): v[i] = v[i] * k
	arr[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

func prime(c: Vector3) -> void:
	update_tiles(c)

func update_tiles(c: Vector3) -> void:
	for r in _rings:
		_update_ring(r, c)

func _update_ring(r: Dictionary, c: Vector3) -> void:
	var fol: Foliage = r["fol"]
	var r1: float = float(r["r1"]) + 1.5
	var active: Dictionary = r["active"]
	var wanted := {}
	var n_side := int(ceil(fol.terrain.size / TILE))
	for j in range(maxi(floori((c.z - r1) / TILE), 0), mini(floori((c.z + r1) / TILE), n_side - 1) + 1):
		for i in range(maxi(floori((c.x - r1) / TILE), 0), mini(floori((c.x + r1) / TILE), n_side - 1) + 1):
			var x0 := float(i) * TILE
			var z0 := float(j) * TILE
			var nx := clampf(c.x, x0, x0 + TILE) - c.x
			var nz := clampf(c.z, z0, z0 + TILE) - c.z
			if nx * nx + nz * nz > r1 * r1: continue
			var key := Vector2i(i, j)
			wanted[key] = true
			if not active.has(key):
				active[key] = _take(r, key, fol)
	for key in active.keys():
		if not wanted.has(key):
			var mi: MultiMeshInstance3D = active[key]
			mi.visible = false
			(r["pool"] as Array).append(mi)
			active.erase(key)

func _take(r: Dictionary, key: Vector2i, fol: Foliage) -> MultiMeshInstance3D:
	var pool: Array = r["pool"]
	var mi: MultiMeshInstance3D
	if pool.is_empty():
		mi = MultiMeshInstance3D.new()
		mi.multimesh = r["mm"]
		mi.material_override = r["mat"]
		mi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(r["shadow"])
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mi)
	else:
		mi = pool.pop_back()
	var hr := fol._height_range(float(key.x) * TILE, float(key.y) * TILE, TILE)
	mi.position = Vector3(float(key.x) * TILE, 0.0, float(key.y) * TILE)
	mi.custom_aabb = AABB(Vector3(-2.0, hr.x - 1.5, -2.0), Vector3(TILE + 4.0, hr.y - hr.x + 4.0, TILE + 4.0))
	mi.visible = true
	return mi

func stats() -> Dictionary:
	var tiles := 0
	var inst := 0
	for r in _rings:
		tiles += (r["active"] as Dictionary).size()
		inst += (r["active"] as Dictionary).size() * (r["mm"] as MultiMesh).instance_count
	return {"tiles": tiles, "instances": inst}
