class_name Terrain
extends Node3D
## Heightmap terrain: chunked visual mesh with distance LOD + one heightmap collider.

const SIZE := 480.0
const GRID := 481
const CELL := SIZE / float(GRID - 1)      # 1.0 m
const CHUNK_CELLS := 60                   # 60 m chunks
const CHUNK_COUNT := 8

var heights := PackedFloat32Array()
var max_height := 31.13
var water_level := 2.6
var splat_img: Image
var loaded := false
var lod_ranges := [70.0, 170.0]           # LOD0 end, LOD1 end
var _body: StaticBody3D
var _chunk_nodes := []
var _mat: ShaderMaterial

func _ready() -> void:
	_load_heightmap()
	if not loaded:
		push_error("Terrain: heightmap could not be loaded")
		return
	_build_collision()
	_build_material()
	_build_chunks()

# ------------------------------------------------------------------ loading
func _load_heightmap() -> void:
	var img: Image = null
	# 1) raw file (works when running from the project folder)
	var bin := "res://assets/terrain/heightmap.bin"
	if FileAccess.file_exists(bin):
		var f := FileAccess.open(bin, FileAccess.READ)
		if f:
			var n := GRID * GRID
			var buf := f.get_buffer(n * 4)
			f.close()
			if buf.size() == n * 4:
				heights = buf.to_float32_array()
	if heights.is_empty():
		# 2) png (works in exported builds)
		if FileAccess.file_exists("res://assets/terrain/height16.png"):
			img = Image.load_from_file("res://assets/terrain/height16.png")
		if img == null and ResourceLoader.exists("res://assets/terrain/height16.png"):
			var t := load("res://assets/terrain/height16.png") as Texture2D
			if t: img = t.get_image()
		if img != null:
			var n := GRID * GRID
			heights.resize(n)
			for z in GRID:
				for x in GRID:
					var c := img.get_pixel(x, z)
					heights[z * GRID + x] = (c.r * 255.0 * 256.0 + c.g * 255.0) / 65535.0 * max_height
	# splat
	if ResourceLoader.exists("res://assets/terrain/splat.png"):
		var st := load("res://assets/terrain/splat.png") as Texture2D
		if st: splat_img = st.get_image()
	loaded = heights.size() == GRID * GRID

func sample_height(x: float, z: float) -> float:
	if not loaded: return 0.0
	var fx := clampf(x / CELL, 0.0, float(GRID - 1.001))
	var fz := clampf(z / CELL, 0.0, float(GRID - 1.001))
	var x0 := int(fx); var z0 := int(fz)
	var tx := fx - float(x0); var tz := fz - float(z0)
	var h00 := heights[z0 * GRID + x0]
	var h10 := heights[z0 * GRID + mini(x0 + 1, GRID - 1)]
	var h01 := heights[mini(z0 + 1, GRID - 1) * GRID + x0]
	var h11 := heights[mini(z0 + 1, GRID - 1) * GRID + mini(x0 + 1, GRID - 1)]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

func sample_normal(x: float, z: float) -> Vector3:
	var d := CELL
	var hl := sample_height(x - d, z); var hr := sample_height(x + d, z)
	var hd := sample_height(x, z - d); var hu := sample_height(x, z + d)
	return Vector3(hl - hr, 2.0 * d, hd - hu).normalized()

func slope_at(x: float, z: float) -> float:
	return rad_to_deg(acos(clampf(sample_normal(x, z).y, -1.0, 1.0)))

func is_water(x: float, z: float) -> bool:
	return sample_height(x, z) <= water_level + 0.05

func zone_at(x: float, z: float) -> String:
	var best := "shrine"; var bd := 1e20
	var zones := {"shrine": Vector2(240, 240), "forest": Vector2(90, 250), "village": Vector2(390, 235),
		"castle": Vector2(250, 90), "mountain": Vector2(90, 95)}
	for k in zones.keys():
		var d: float = zones[k].distance_to(Vector2(x, z))
		if d < bd: bd = d; best = k
	return best

func dist_to_zone(zone: String, x: float, z: float) -> float:
	var zones := {"shrine": Vector2(240, 240), "forest": Vector2(90, 250), "village": Vector2(390, 235),
		"castle": Vector2(250, 90), "mountain": Vector2(90, 95)}
	if not zones.has(zone): return 1e9
	return zones[zone].distance_to(Vector2(x, z))

# ------------------------------------------------------------------ build
func _build_collision() -> void:
	_body = StaticBody3D.new()
	_body.name = "TerrainBody"
	_body.collision_layer = 1
	_body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = GRID
	shape.map_depth = GRID
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	# heightmap is centred on the shape origin
	cs.position = Vector3(SIZE * 0.5, 0.0, SIZE * 0.5)
	_body.add_child(cs)
	add_child(_body)

func _build_material() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/terrain.gdshader")
	_mat.set_shader_parameter("world_size", SIZE)
	_mat.set_shader_parameter("grass_tex", load("res://assets/textures/terrain_c.png"))
	_mat.set_shader_parameter("dirt_tex", load("res://assets/textures/wood_c.png"))
	_mat.set_shader_parameter("rock_tex", load("res://assets/textures/stone_c.png"))
	_mat.set_shader_parameter("detail_n", load("res://assets/textures/terrain_n.png"))
	_mat.set_shader_parameter("macro_tex", load("res://assets/textures/bark_n.png"))
	if splat_img != null:
		var it := ImageTexture.create_from_image(splat_img)
		_mat.set_shader_parameter("splat_tex", it)
	_mat.set_shader_parameter("grass_tint", Color(0.46, 0.56, 0.30))
	_mat.set_shader_parameter("dirt_tint", Color(0.44, 0.37, 0.25))
	_mat.set_shader_parameter("rock_tint", Color(0.55, 0.54, 0.52))

func _build_chunks() -> void:
	var steps := [1, 4, 8]
	for ci in CHUNK_COUNT:
		for cj in CHUNK_COUNT:
			var x0 := ci * CHUNK_CELLS
			var z0 := cj * CHUNK_CELLS
			for lod in 3:
				var mi := MeshInstance3D.new()
				mi.name = "Chunk_%d_%d_L%d" % [ci, cj, lod]
				mi.mesh = _build_chunk_mesh(x0, z0, CHUNK_CELLS, steps[lod])
				mi.material_override = _mat
				mi.cast_shadow = (MeshInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0
					else MeshInstance3D.SHADOW_CASTING_SETTING_OFF)
				if lod == 0:
					mi.visibility_range_end = lod_ranges[0]
					mi.visibility_range_end_margin = 12.0
					mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				elif lod == 1:
					mi.visibility_range_begin = lod_ranges[0] - 8.0
					mi.visibility_range_end = lod_ranges[1]
					mi.visibility_range_end_margin = 20.0
					mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				else:
					mi.visibility_range_begin = lod_ranges[1] - 10.0
					mi.visibility_range_end = 0.0
				add_child(mi)
				_chunk_nodes.append(mi)

func _build_chunk_mesh(x0: int, z0: int, cells: int, step: int) -> ArrayMesh:
	var n := cells / step + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.resize(n * n); norms.resize(n * n); uvs.resize(n * n)
	for j in n:
		for i in n:
			var gx := x0 + i * step
			var gz := z0 + j * step
			gx = mini(gx, GRID - 1); gz = mini(gz, GRID - 1)
			var wx := float(gx) * CELL
			var wz := float(gz) * CELL
			var k := j * n + i
			verts[k] = Vector3(wx, heights[gz * GRID + gx], wz)
			norms[k] = sample_normal(wx, wz)
			uvs[k] = Vector2(wx / SIZE, wz / SIZE)
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			idx.append_array([a, c, b, b, c, d])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

func apply_quality(lod_bias: float) -> void:
	var base := [70.0, 170.0]
	lod_ranges = [base[0] * (1.0 + lod_bias * 0.35), base[1] * (1.0 + lod_bias * 0.25)]
	for n in _chunk_nodes:
		var mi := n as MeshInstance3D
		var lod := int(mi.name.right(1))
		if lod == 0:
			mi.visibility_range_end = lod_ranges[0]
		elif lod == 1:
			mi.visibility_range_begin = lod_ranges[0] - 8.0
			mi.visibility_range_end = lod_ranges[1]

func triangle_count() -> int:
	var t := 0
	for n in _chunk_nodes:
		var mi := n as MeshInstance3D
		if mi.mesh and mi.visible:
			t += mi.mesh.get_faces().size() / 3
	return t
