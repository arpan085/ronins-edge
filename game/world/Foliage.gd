class_name Foliage
extends Node3D
## v0.15 ground cover: photo-scanned grass cards placed on the GPU.
##
## The v0.14 system built every clump on the CPU, chunk by chunk, out of wide
## ribbon blades; chunks came in ten per 0.2 s in scan order (so grass visibly
## grew in around you), and a quality change threw every chunk away.
##
## Now each ring around the camera is a pool of tiles that all draw one shared
## MultiMesh -- just a grid of instance origins. grass_gpu.gdshader turns each
## grid point into a plant from the terrain's own data maps (height, biome,
## density, splat, river), so moving a tile is a single transform write and
## the whole field is there the moment you look at it. Rings hand over by
## dissolving instance by instance over a band (each plant has its own fade
## distance), never by swapping chunks. Placement is hashed from world
## coordinates, so a spot always grows the same plants.
##
## The approach follows Terrain3D (GPU data maps, CPU-moved instancer cells,
## colour-map tinting), written natively for Godot 4.3.

# ---- atlas (tools/make_grass_atlas.py -> tools/grass_atlas.json)
# name: [u, v, w, h, width_m, height_m]
const ATLAS := {
	"medA": [0.0, 0.0, 0.25, 0.125, 1.0, 0.5], "medB": [0.25, 0.0, 0.25, 0.125, 0.92, 0.46],
	"medD": [0.5, 0.0, 0.25, 0.125, 0.84, 0.42], "medE": [0.75, 0.0, 0.25, 0.125, 1.1, 0.55],
	"dryA": [0.0, 0.125, 0.25, 0.125, 1.0, 0.5], "dryB": [0.25, 0.125, 0.25, 0.125, 0.92, 0.46],
	"dryD": [0.5, 0.125, 0.25, 0.125, 0.84, 0.42], "medC": [0.75, 0.125, 0.25, 0.125, 0.96, 0.48],
	"short0": [0.0, 0.25, 0.25, 0.125, 0.44, 0.22], "short1": [0.25, 0.25, 0.25, 0.125, 0.44, 0.22],
	"short2": [0.5, 0.25, 0.25, 0.125, 0.44, 0.22], "shortdry": [0.75, 0.25, 0.25, 0.125, 0.44, 0.22],
	"tall0": [0.0, 0.375, 0.25, 0.25, 1.0, 1.0], "tall1": [0.25, 0.375, 0.25, 0.25, 1.1, 1.1],
	"susuki": [0.5, 0.375, 0.25, 0.25, 1.3, 1.3], "talldry": [0.75, 0.375, 0.25, 0.25, 1.05, 1.05],
	"flowerY": [0.0, 0.625, 0.25, 0.125, 0.6, 0.3], "flowerW": [0.25, 0.625, 0.25, 0.125, 0.6, 0.3],
	"flowerP": [0.5, 0.625, 0.25, 0.125, 0.64, 0.32], "herb": [0.75, 0.625, 0.25, 0.125, 0.56, 0.28],
	"frond0": [0.0, 0.75, 0.125, 0.25, 0.4, 0.8], "frond1": [0.125, 0.75, 0.125, 0.25, 0.4, 0.8],
	"frond2": [0.25, 0.75, 0.125, 0.25, 0.4, 0.8], "frond3": [0.375, 0.75, 0.125, 0.25, 0.4, 0.8],
	"under0": [0.5, 0.75, 0.25, 0.125, 0.6, 0.3], "dryE": [0.75, 0.75, 0.25, 0.125, 1.1, 0.55],
	"short3": [0.5, 0.875, 0.25, 0.125, 0.48, 0.24], "dryC": [0.75, 0.875, 0.25, 0.125, 0.96, 0.48],
}
## Mean linear luminance of each cell's opaque texels (measured from the
## atlas). The shader regrades a texel by its brightness RELATIVE TO ITS OWN
## CELL: one atlas-wide mean made the bright cells (dry, plumes, flowers) two to
## three times the ground's brightness and blew the near ring out to white.
const CELL_LUM := {
	"medA": 0.087, "medB": 0.095, "medD": 0.072, "medE": 0.093, "dryA": 0.146, "dryB": 0.142,
	"dryD": 0.149, "medC": 0.086, "short0": 0.076, "short1": 0.077, "short2": 0.075, "shortdry": 0.213,
	"tall0": 0.087, "tall1": 0.246, "susuki": 0.213, "talldry": 0.192, "flowerY": 0.082, "flowerW": 0.115,
	"flowerP": 0.083, "herb": 0.053, "frond0": 0.080, "frond1": 0.105, "frond2": 0.090, "frond3": 0.070,
	"under0": 0.055, "dryE": 0.165, "short3": 0.072, "dryC": 0.143,
}
## Grass categories. Each is a run of atlas cells at a size multiplier; the
## three cards of one instance show three different cells of its category.
## "short" reuses the scanned meadow clumps at half size, which keeps their
## fine blades -- the bermuda mats alone read as broad-leaved weeds.
const CATS := ["short", "medium", "tall", "dry", "flower", "undergrowth"]
const CAT_VARIANTS := [
	[["short0", 1.0], ["short1", 1.0], ["medA", 0.50], ["medB", 0.52], ["short2", 1.0], ["medD", 0.56], ["short3", 1.0]],
	[["medA", 1.0], ["medB", 1.0], ["medD", 1.0], ["medE", 1.0], ["medC", 1.0]],
	[["tall0", 1.0], ["tall1", 1.0], ["susuki", 1.0], ["medE", 1.7]],
	[["dryA", 1.0], ["dryB", 1.0], ["dryD", 1.0], ["dryE", 1.0], ["dryC", 1.0], ["shortdry", 1.0], ["talldry", 0.9]],
	[["flowerY", 1.0], ["flowerW", 1.0], ["flowerP", 1.0]],
	[["herb", 1.0], ["under0", 1.0], ["short1", 1.1], ["medD", 0.7]],
]
## per category: wind stiffness, colour regrade toward the ground tint, size
## jitter, translucency
const CAT_PROPS := [
	Vector4(0.55, 0.60, 0.25, 0.45), Vector4(1.0, 0.55, 0.22, 0.55), Vector4(1.25, 0.50, 0.18, 0.65),
	Vector4(1.0, 0.12, 0.22, 0.40), Vector4(0.8, 0.30, 0.20, 0.50), Vector4(0.5, 0.35, 0.25, 0.35),
]
## biome (Terrain.BIOME_NAMES order) -> four slots of [category, cumulative
## weight], ordered thin -> deep so the smooth patch field that picks between
## them lays grass down in banks across a hillside.
const PALETTES := [
	[[0, 0.28], [4, 0.36], [1, 0.84], [2, 1.0]],   # grassland
	[[0, 0.30], [1, 0.55], [3, 1.0], [3, 1.0]],    # farmland
	[[0, 0.12], [1, 0.40], [3, 0.48], [2, 1.0]],   # tallgrass
	[[5, 0.55], [0, 0.85], [1, 1.0], [1, 1.0]],    # bamboo
	[[0, 0.35], [3, 0.80], [1, 1.0], [1, 1.0]],    # rocky
	[[0, 0.30], [3, 1.0], [3, 1.0], [3, 1.0]],     # alpine
	[[0, 0.28], [4, 0.38], [1, 0.82], [2, 1.0]],   # shrine
	[[5, 0.45], [0, 0.80], [1, 1.0], [1, 1.0]],    # forest
	[[0, 0.32], [4, 0.42], [1, 0.85], [2, 1.0]],   # village
	[[0, 0.10], [1, 0.55], [2, 1.0], [2, 1.0]],    # shore
]

## Rings per quality tier: tile size (m), grid spacing (m), inner edge + band,
## outer edge + band, per-plant shrink width, size multiplier, cards, card
## segments, camera-facing, casts shadow. Each ring's inner band is exactly the
## previous ring's outer band, so the two populations cross-fade.
const RINGS := {
	0: [
		{"tile": 12.0, "sp": 0.50, "r0": 0.0, "rin": 0.0, "r1": 24.0, "rout": 8.0, "fw": 2.5, "size": 1.15, "planes": 2, "segs": 3, "bb": false, "shadow": false},
		{"tile": 24.0, "sp": 1.20, "r0": 16.0, "rin": 8.0, "r1": 60.0, "rout": 18.0, "fw": 5.0, "size": 1.6, "planes": 2, "segs": 2, "bb": false, "shadow": false},
		{"tile": 64.0, "sp": 3.20, "r0": 42.0, "rin": 18.0, "r1": 160.0, "rout": 60.0, "fw": 10.0, "size": 2.2, "planes": 1, "segs": 1, "bb": true, "shadow": false},
	],
	1: [
		{"tile": 12.0, "sp": 0.44, "r0": 0.0, "rin": 0.0, "r1": 30.0, "rout": 10.0, "fw": 3.0, "size": 1.12, "planes": 3, "segs": 2, "bb": false, "shadow": false},
		{"tile": 24.0, "sp": 1.00, "r0": 20.0, "rin": 10.0, "r1": 84.0, "rout": 24.0, "fw": 6.0, "size": 1.5, "planes": 2, "segs": 2, "bb": false, "shadow": false},
		{"tile": 64.0, "sp": 8.0 / 3.0, "r0": 60.0, "rin": 24.0, "r1": 240.0, "rout": 80.0, "fw": 12.0, "size": 2.1, "planes": 1, "segs": 1, "bb": true, "shadow": false},
	],
	2: [
		{"tile": 12.0, "sp": 0.36, "r0": 0.0, "rin": 0.0, "r1": 34.0, "rout": 10.0, "fw": 3.0, "size": 1.05, "planes": 3, "segs": 3, "bb": false, "shadow": true},
		{"tile": 24.0, "sp": 0.75, "r0": 24.0, "rin": 10.0, "r1": 100.0, "rout": 28.0, "fw": 6.0, "size": 1.45, "planes": 2, "segs": 2, "bb": false, "shadow": false},
		{"tile": 64.0, "sp": 2.00, "r0": 72.0, "rin": 28.0, "r1": 320.0, "rout": 110.0, "fw": 14.0, "size": 2.1, "planes": 1, "segs": 1, "bb": true, "shadow": false},
	],
	3: [
		{"tile": 12.0, "sp": 0.30, "r0": 0.0, "rin": 0.0, "r1": 42.0, "rout": 12.0, "fw": 3.5, "size": 1.0, "planes": 3, "segs": 3, "bb": false, "shadow": true},
		{"tile": 24.0, "sp": 0.60, "r0": 30.0, "rin": 12.0, "r1": 130.0, "rout": 36.0, "fw": 7.0, "size": 1.4, "planes": 2, "segs": 2, "bb": false, "shadow": false},
		{"tile": 64.0, "sp": 1.60, "r0": 94.0, "rin": 36.0, "r1": 400.0, "rout": 130.0, "fw": 16.0, "size": 2.0, "planes": 1, "segs": 1, "bb": true, "shadow": false},
	],
}

var terrain: Terrain
var player: Node3D
var quality := -1
var instance_count := 0

var _rings: Array = []          # [{cfg, mm, mat, active: {Vector2i: MMI}, pool: [], hcache: {}}]
var _tex := {}
var _wind_dir := Vector2(0.86, 0.51)
var _wind := 0.6
var _gust := 0.0
var _wet := 0.0
var _snow := 0.0
var _trail := []
var _trail_t := 0.0
var _cam := Vector3.ZERO
var _last_update := Vector3(INF, 0, INF)
var _detail: GroundDetail

func setup(t: Terrain, p: Node3D) -> void:
	terrain = t
	player = p

func _ready() -> void:
	_detail = GroundDetail.new()
	_detail.name = "GroundDetail"
	add_child(_detail)

# ------------------------------------------------------------------ data maps
func _data_textures() -> Dictionary:
	if not _tex.is_empty() or terrain == null or not terrain.loaded:
		return _tex
	var g: int = terrain.grid
	var himg := Image.create_from_data(g, g, false, Image.FORMAT_RF, terrain.heights.to_byte_array())
	_tex["height"] = ImageTexture.create_from_image(himg)
	if terrain.biome_img != null: _tex["biome"] = ImageTexture.create_from_image(terrain.biome_img)
	if terrain.splat_img != null: _tex["splat"] = ImageTexture.create_from_image(terrain.splat_img)
	if terrain.river_img != null: _tex["river"] = ImageTexture.create_from_image(terrain.river_img)
	var pt: ImageTexture = terrain.river_prox_texture()
	if pt != null: _tex["prox"] = pt
	_tex["atlas"] = load("res://assets/textures/foliage/grass_atlas.png")
	_tex["macro"] = load("res://assets/textures/terrain/ground_macro.jpg")
	return _tex

## Shared terrain-data uniforms for both grass and ground-detail materials.
func apply_data(m: ShaderMaterial) -> void:
	var t := _data_textures()
	m.set_shader_parameter("height_tex", t.get("height"))
	m.set_shader_parameter("biome_tex", t.get("biome"))
	m.set_shader_parameter("biome_lin", t.get("biome"))
	m.set_shader_parameter("splat_tex", t.get("splat"))
	m.set_shader_parameter("river_tex", t.get("river"))
	m.set_shader_parameter("prox_tex", t.get("prox"))
	m.set_shader_parameter("world_size", terrain.size)
	m.set_shader_parameter("cell", terrain.cell)
	m.set_shader_parameter("grid", terrain.grid)
	m.set_shader_parameter("water_level", terrain.water_level)
	m.set_shader_parameter("chunk_m", Terrain.CHUNK_M)

func _variant_tables() -> Dictionary:
	var rects := PackedVector4Array()
	var sizes := PackedVector2Array()
	var ranges := PackedVector2Array()
	var lums := PackedFloat32Array()
	for ci in CAT_VARIANTS.size():
		var first := rects.size()
		for pair in CAT_VARIANTS[ci]:
			var a: Array = ATLAS[str(pair[0])]
			var k: float = float(pair[1])
			# half a texel in, so the bilinear tap never reads the next cell
			var inset := 0.5 / 2048.0
			rects.append(Vector4(float(a[0]) + inset, float(a[1]) + inset, float(a[2]) - inset * 2.0, float(a[3]) - inset * 2.0))
			sizes.append(Vector2(float(a[4]) * k, float(a[5]) * k))
			lums.append(float(CELL_LUM.get(str(pair[0]), 0.085)))
		ranges.append(Vector2(first, rects.size() - first))
	while rects.size() < 40:
		rects.append(Vector4.ZERO); sizes.append(Vector2.ZERO); lums.append(0.085)
	while ranges.size() < 8:
		ranges.append(Vector2(0, 1))
	var props := PackedVector4Array()
	for v in CAT_PROPS: props.append(v)
	while props.size() < 8: props.append(Vector4(1, 0.5, 0.2, 0.5))
	var pc := PackedVector4Array()
	var pw := PackedVector4Array()
	for pal in PALETTES:
		pc.append(Vector4(pal[0][0], pal[1][0], pal[2][0], pal[3][0]))
		pw.append(Vector4(pal[0][1], pal[1][1], pal[2][1], pal[3][1]))
	return {"rects": rects, "sizes": sizes, "lums": lums, "ranges": ranges, "props": props, "pc": pc, "pw": pw}

# ------------------------------------------------------------------ meshes
## `planes` crossed cards through the clump centre, each `segs` rows tall.
## COLOR.r = height along the card (wind weight), COLOR.g = card index / 2.
## UV v = 1 on the ground, matching the atlas cells' roots-at-the-bottom.
static func card_mesh(planes: int, segs: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for k in planes:
		var a := PI * float(k) / float(planes)
		var ax := Vector3(cos(a), 0.0, sin(a))
		var n := Vector3(-sin(a), 0.0, cos(a))
		var base := verts.size()
		for r in segs + 1:
			var t := float(r) / float(segs)
			for c in 2:
				var x := float(c) - 0.5
				verts.append(ax * x + Vector3(0.0, t, 0.0))
				norms.append(n)
				uvs.append(Vector2(float(c), 1.0 - t))
				cols.append(Color(t, float(k) * 0.5, 0.0, 1.0))
		for r in segs:
			var i0 := base + r * 2
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

## Instance grid for a tile: origins at cell centres, identity basis.
static func grid_multimesh(mesh: Mesh, tile: float, spacing: float) -> MultiMesh:
	var n := int(round(tile / spacing))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n * n
	var buf := PackedFloat32Array()
	buf.resize(n * n * 12)
	var i := 0
	for b in n:
		for a in n:
			var o := i * 12
			buf[o] = 1.0; buf[o + 3] = (float(a) + 0.5) * spacing
			buf[o + 5] = 1.0
			buf[o + 10] = 1.0; buf[o + 11] = (float(b) + 0.5) * spacing
			i += 1
	mm.buffer = buf
	return mm

# ------------------------------------------------------------------ quality
func set_quality(level: int) -> void:
	level = clampi(level, 0, 3)
	if level == quality and not _rings.is_empty():
		return
	quality = level
	_build_rings()
	if _detail != null: _detail.set_quality(level, self)
	_last_update = Vector3(INF, 0, INF)

func _build_rings() -> void:
	for r in _rings:
		for mi in (r["active"] as Dictionary).values(): (mi as Node).queue_free()
		for mi in r["pool"]: (mi as Node).queue_free()
	_rings.clear()
	if terrain == null or not terrain.loaded: return
	var tables := _variant_tables()
	var sh: Shader = load("res://shaders/grass_gpu.gdshader")
	for cfg in RINGS[quality]:
		var mat := ShaderMaterial.new()
		mat.shader = sh
		apply_data(mat)
		mat.set_shader_parameter("atlas", _tex.get("atlas"))
		mat.set_shader_parameter("macro_tex", _tex.get("macro"))
		mat.set_shader_parameter("v_rect", tables["rects"])
		mat.set_shader_parameter("v_size", tables["sizes"])
		mat.set_shader_parameter("v_lum", tables["lums"])
		mat.set_shader_parameter("cat_range", tables["ranges"])
		mat.set_shader_parameter("cat_props", tables["props"])
		mat.set_shader_parameter("pal_cat", tables["pc"])
		mat.set_shader_parameter("pal_w", tables["pw"])
		mat.set_shader_parameter("spacing", float(cfg["sp"]))
		mat.set_shader_parameter("ring_r0", float(cfg["r0"]))
		mat.set_shader_parameter("ring_in", float(cfg["rin"]))
		mat.set_shader_parameter("ring_r1", float(cfg["r1"]))
		mat.set_shader_parameter("ring_out", float(cfg["rout"]))
		mat.set_shader_parameter("fade_w", float(cfg["fw"]))
		mat.set_shader_parameter("size_mul", float(cfg["size"]))
		mat.set_shader_parameter("billboard", 1 if bool(cfg["bb"]) else 0)
		# the near ring's shadow pass draws every other plant out to 70 %
		# of the ring: grass shadow is speckle, and this halves its cost
		mat.set_shader_parameter("shadow_keep", 0.5)
		mat.set_shader_parameter("shadow_r", float(cfg["r1"]) * 0.7)
		var mesh := card_mesh(int(cfg["planes"]), int(cfg["segs"]))
		var mm := grid_multimesh(mesh, float(cfg["tile"]), float(cfg["sp"]))
		_rings.append({"cfg": cfg, "mm": mm, "mat": mat, "active": {}, "pool": [], "hcache": {}})
	_push_uniforms()

func set_wind(dir: Vector2, strength: float, gust: float) -> void:
	_wind_dir = dir
	_wind = strength
	_gust = gust

func set_wetness(w: float) -> void:
	_wet = w

func set_snow(s: float) -> void:
	_snow = s

# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	if terrain == null or not terrain.loaded: return
	if _rings.is_empty():
		set_quality(int(Game.settings.get("quality", 2)) if quality < 0 else quality)
	_update_trail(delta)
	_cam = _camera_pos()
	_push_uniforms()
	# tiles only change when the camera has moved a little
	if Vector2(_cam.x - _last_update.x, _cam.z - _last_update.z).length() > 0.75:
		_update_tiles(_cam)

func _camera_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null: return cam.global_position
	if player != null and is_instance_valid(player): return player.global_position + Vector3(0, 1.6, 0)
	return _cam

## Place every ring around `pos` at once (level load / teleport).
func prime(pos: Vector3, _passes := 0) -> void:
	if _rings.is_empty(): set_quality(int(Game.settings.get("quality", 2)) if quality < 0 else quality)
	_cam = pos + Vector3(0, 1.6, 0)
	_update_tiles(_cam)
	_push_uniforms()
	if _detail != null: _detail.prime(_cam)

func _update_trail(delta: float) -> void:
	for t in _trail:
		t["w"] = maxf(0.0, float(t["w"]) - delta * 1.25)
	var i := _trail.size() - 1
	while i >= 0:
		if float(_trail[i]["w"]) <= 0.001: _trail.remove_at(i)
		i -= 1
	_trail_t += delta
	if player == null or not is_instance_valid(player): return
	var speed := 0.0
	if player is CharacterBody3D:
		var v: Vector3 = (player as CharacterBody3D).velocity
		speed = Vector3(v.x, 0, v.z).length()
	var interval := 0.09 if speed > 3.0 else 0.16
	if _trail_t >= interval:
		_trail_t = 0.0
		var w := clampf(0.45 + speed * 0.10, 0.3, 1.0)
		_trail.push_back({"pos": player.global_position, "w": w})
		while _trail.size() > 12:
			_trail.pop_front()

func _push_uniforms() -> void:
	var arr := PackedVector4Array()
	arr.resize(12)
	for i in 12:
		if i < _trail.size():
			var t: Dictionary = _trail[i]
			var p: Vector3 = t["pos"]
			arr[i] = Vector4(p.x, p.y, p.z, float(t["w"]))
	var lc := player.global_position if player != null and is_instance_valid(player) else _cam
	var b: float = terrain._lod_bias if terrain != null else 1.0
	var ld: Array = terrain.lod_dist if terrain != null else [190.0, 380.0, 620.0, 900.0]
	var lod := Vector4(float(ld[0]) * b, float(ld[1]) * b, float(ld[2]) * b, float(ld[3]) * b)
	var gs := 0.8 + _wind * 0.9
	var mats: Array = []
	for r in _rings: mats.append(r["mat"])
	if _detail != null: mats.append_array(_detail.materials())
	for i in mats.size():
		var m: ShaderMaterial = mats[i]
		m.set_shader_parameter("cam_pos", _cam)
		m.set_shader_parameter("lod_center", lc)
		m.set_shader_parameter("lod_dist", lod)
		m.set_shader_parameter("wind_dir", _wind_dir)
		m.set_shader_parameter("wind_strength", _wind)
		m.set_shader_parameter("gust", _gust)
		m.set_shader_parameter("gust_speed", gs)
		m.set_shader_parameter("wetness", _wet)
		m.set_shader_parameter("snow", _snow)
		# only the near ring is close enough for footsteps to matter
		if i == 0 or (_detail != null and i >= _rings.size()):
			m.set_shader_parameter("trail", arr)
			m.set_shader_parameter("trail_n", _trail.size())

# ------------------------------------------------------------------ tiles
func _update_tiles(c: Vector3) -> void:
	_last_update = c
	instance_count = 0
	for r in _rings:
		_update_ring(r, c)
	if _detail != null: _detail.update_tiles(c)

func _update_ring(r: Dictionary, c: Vector3) -> void:
	var cfg: Dictionary = r["cfg"]
	var tile: float = float(cfg["tile"])
	var r0: float = float(cfg["r0"])
	var r1: float = float(cfg["r1"]) + 1.5
	var active: Dictionary = r["active"]
	var wanted := {}
	var i0 := floori((c.x - r1) / tile)
	var i1 := floori((c.x + r1) / tile)
	var j0 := floori((c.z - r1) / tile)
	var j1 := floori((c.z + r1) / tile)
	var n_side := int(ceil(terrain.size / tile))
	for j in range(maxi(j0, 0), mini(j1, n_side - 1) + 1):
		for i in range(maxi(i0, 0), mini(i1, n_side - 1) + 1):
			var x0 := float(i) * tile
			var z0 := float(j) * tile
			var nx := clampf(c.x, x0, x0 + tile) - c.x
			var nz := clampf(c.z, z0, z0 + tile) - c.z
			if nx * nx + nz * nz > r1 * r1: continue
			if r0 > 0.0:
				var fx := maxf(absf(c.x - x0), absf(c.x - x0 - tile))
				var fz := maxf(absf(c.z - z0), absf(c.z - z0 - tile))
				if fx * fx + fz * fz < (r0 - 1.5) * (r0 - 1.5): continue
			var key := Vector2i(i, j)
			wanted[key] = true
			if not active.has(key):
				active[key] = _take_tile(r, key)
	for key in active.keys():
		if not wanted.has(key):
			var mi: MultiMeshInstance3D = active[key]
			mi.visible = false
			(r["pool"] as Array).append(mi)
			active.erase(key)
		elif bool(cfg["shadow"]):
			_tile_shadow(r, active[key], key)
	instance_count += active.size() * (r["mm"] as MultiMesh).instance_count

func _take_tile(r: Dictionary, key: Vector2i) -> MultiMeshInstance3D:
	var cfg: Dictionary = r["cfg"]
	var tile: float = float(cfg["tile"])
	var pool: Array = r["pool"]
	var mi: MultiMeshInstance3D
	if pool.is_empty():
		mi = MultiMeshInstance3D.new()
		mi.multimesh = r["mm"]
		mi.material_override = r["mat"]
		mi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(cfg["shadow"])
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mi)
	else:
		mi = pool.pop_back()
	var hc: Dictionary = r["hcache"]
	var hr: Vector2
	if hc.has(key): hr = hc[key]
	else:
		hr = _height_range(float(key.x) * tile, float(key.y) * tile, tile)
		hc[key] = hr
	mi.position = Vector3(float(key.x) * tile, 0.0, float(key.y) * tile)
	_tile_shadow(r, mi, key)
	# the shader moves every plant onto the terrain, so the engine has to be
	# told where that is or it culls the tile against its flat grid
	var top := 1.6 * float(cfg["size"]) + 0.5
	mi.custom_aabb = AABB(Vector3(-2.0, hr.x - 1.5, -2.0), Vector3(tile + 4.0, hr.y - hr.x + 1.5 + top, tile + 4.0))
	mi.visible = true
	return mi

## Only the tiles that overlap the shadow radius cast shadows: the shadow pass
## runs the full vertex shader over every tile it is given, and grass shadow
## further out is speckle nobody can resolve.
func _tile_shadow(r: Dictionary, mi: MultiMeshInstance3D, key: Vector2i) -> void:
	var cfg: Dictionary = r["cfg"]
	if not bool(cfg["shadow"]):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	var tile: float = float(cfg["tile"])
	var x0 := float(key.x) * tile
	var z0 := float(key.y) * tile
	var nx := clampf(_last_update.x, x0, x0 + tile) - _last_update.x
	var nz := clampf(_last_update.z, z0, z0 + tile) - _last_update.z
	var sr: float = float(cfg["r1"]) * 0.7
	var on := nx * nx + nz * nz < sr * sr
	var want := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mi.cast_shadow != want: mi.cast_shadow = want

func _height_range(x0: float, z0: float, tile: float) -> Vector2:
	var g: int = terrain.grid
	var cs: float = terrain.cell
	var a0 := clampi(int(floor((x0 - 2.0) / cs)), 0, g - 1)
	var a1 := clampi(int(ceil((x0 + tile + 2.0) / cs)), 0, g - 1)
	var b0 := clampi(int(floor((z0 - 2.0) / cs)), 0, g - 1)
	var b1 := clampi(int(ceil((z0 + tile + 2.0) / cs)), 0, g - 1)
	var lo := INF
	var hi := -INF
	var h: PackedFloat32Array = terrain.heights
	for b in range(b0, b1 + 1):
		var row := b * g
		for a in range(a0, a1 + 1):
			var v := h[row + a]
			lo = minf(lo, v); hi = maxf(hi, v)
	if lo == INF: return Vector2(0, 10)
	return Vector2(lo, hi)

func stats() -> Dictionary:
	var tiles := 0
	for r in _rings: tiles += (r["active"] as Dictionary).size()
	var out := {"chunks": tiles, "mm_nodes": tiles, "instances": instance_count}
	if _detail != null: out["detail"] = _detail.stats()
	return out
