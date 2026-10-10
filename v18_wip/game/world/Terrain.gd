class_name Terrain
extends Node3D
## Large-world heightmap terrain.
##
## Geometry is chunked and each chunk picks a mesh LOD from its distance to the
## player, so a 1.5 km world costs roughly what the visible slice costs. Meshes
## are cached per (chunk, step) and rebuilt only when a chunk changes LOD.
## Terrain also answers the surface queries the rest of the game needs:
## height, normal, slope, biome and material type under a point.

const DATA_PATH := "res://assets/terrain/world.json"
const CHUNK_M := 96.0

# LOD ring distances (metres) for vertex strides 1, 2, 4, 8; beyond -> 16
var lod_dist := [190.0, 380.0, 620.0, 900.0]

var size := 1536.0
var grid := 769
var cell := 2.0
var water_level := 6.0
var max_height := 152.0
var heights := PackedFloat32Array()
var splat_img: Image
var biome_img: Image
var river_img: Image
## v0.13 main river (tools/make_river.py): water surface height per grid
## vertex (0 = dry) and a 0..255 bank-proximity field used for wet banks,
## foliage and the river ambience.
var river_surf := PackedFloat32Array()
var river_prox := PackedByteArray()
var river_main := {}
var loaded := false
var zones := {}

var _mat: ShaderMaterial
var _chunks := []
var _mesh_cache := {}
var _cache_order := []
var _player: Node3D
var _tick := 0.0
var _lod_bias := 1.0
var _built_this_frame := 0

const BIOME_NAMES := ["grassland", "farmland", "tallgrass", "bamboo", "rocky",
	"alpine", "shrine", "forest", "village", "shore"]

func _ready() -> void:
	_load_data()
	if not _load_heightmap():
		push_error("Terrain: heightmap could not be loaded")
		return
	loaded = true
	_build_material()
	_build_chunks()
	_build_collision()
	_build_distant_range()

# ------------------------------------------------------------------ data
func _load_data() -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null: return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) != TYPE_DICTIONARY: return
	size = float(d.get("size", size))
	grid = int(d.get("n", grid))
	cell = float(d.get("cell", size / float(grid - 1)))
	water_level = float(d.get("water_level", water_level))
	max_height = float(d.get("height_max", max_height))
	zones = d.get("zones", {})
	river_main = d.get("river_main", {})

func _load_heightmap() -> bool:
	var bin := "res://assets/terrain/heightmap.bin"
	if FileAccess.file_exists(bin):
		var f := FileAccess.open(bin, FileAccess.READ)
		if f != null:
			var buf := f.get_buffer(f.get_length())
			f.close()
			heights = buf.to_float32_array()
	if heights.size() != grid * grid:
		# fallback: 16-bit height texture
		var img: Image = null
		if ResourceLoader.exists("res://assets/terrain/height16.png"):
			var t := load("res://assets/terrain/height16.png") as Texture2D
			if t != null: img = t.get_image()
		if img != null:
			heights.resize(grid * grid)
			for z in grid:
				for x in grid:
					var c := img.get_pixel(mini(x, img.get_width() - 1), mini(z, img.get_height() - 1))
					heights[z * grid + x] = (c.r * 255.0 * 256.0 + c.g * 255.0) / 65535.0 * max_height
	splat_img = _img("res://assets/terrain/splat.png")
	biome_img = _img("res://assets/terrain/biome.png")
	river_img = _img("res://assets/terrain/river.png")
	_load_main_river()
	if heights.size() == grid * grid: _relax_edges()
	return heights.size() == grid * grid

## v0.14: the generator's thermal erosion used np.roll, which wraps, so every
## border traded material with the opposite one and grew a 20-45 m wall (or a
## trench) in its last dozen metres. From the castle plateau, the mountain or
## any cinematic camera that wall was a brown striped band all round the map,
## standing between the land and the distant range. Relax the outer 24 m to
## the interior height, keeping a low shore wherever the lake reaches the
## border. Everything that stands on the ground samples these heights at run
## time, and invisible walls 4 m inside the border keep the player in.
const EDGE_CELLS := 12
func _relax_edges() -> void:
	var g := grid
	var k_n := mini(EDGE_CELLS, g / 4)
	for side in 4:
		for j in g:
			var ref := heights[_edge_idx(side, j, k_n, g)]
			for k in k_n:
				var t := float(k) / float(k_n)
				var w := t * t * (3.0 - 2.0 * t)
				var i := _edge_idx(side, j, k, g)
				var v := ref + (heights[i] - ref) * w
				heights[i] = maxf(v, water_level + 1.5 - 3.5 * t)

func _edge_idx(side: int, j: int, k: int, g: int) -> int:
	match side:
		0: return j * g + (g - 1 - k)     # east  (x = size)
		1: return j * g + k               # west  (x = 0)
		2: return (g - 1 - k) * g + j     # south (z = size)
	return k * g + j                      # north (z = 0)

func _load_main_river() -> void:
	var path := "res://assets/terrain/river_main.bin"
	if not FileAccess.file_exists(path): return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return
	var n := grid * grid
	if f.get_length() < n * 5:
		f.close()
		return
	river_surf = f.get_buffer(n * 4).to_float32_array()
	river_prox = f.get_buffer(n)
	f.close()

## Bank proximity as an R8 texture (1 = in the channel, 0 = 12 m past the
## bank) for the terrain shader's wet-bank darkening.
func river_prox_texture() -> ImageTexture:
	if river_prox.size() != grid * grid: return null
	var img := Image.create_from_data(grid, grid, false, Image.FORMAT_R8, river_prox)
	return ImageTexture.create_from_image(img)

func _img(path: String) -> Image:
	if not ResourceLoader.exists(path): return null
	var t := load(path) as Texture2D
	return t.get_image() if t != null else null

# ------------------------------------------------------------------ queries
func sample_height(x: float, z: float) -> float:
	if not loaded: return 0.0
	var fx := clampf(x / cell, 0.0, float(grid - 1))
	var fz := clampf(z / cell, 0.0, float(grid - 1))
	var x0 := int(fx); var z0 := int(fz)
	var x1 := mini(x0 + 1, grid - 1); var z1 := mini(z0 + 1, grid - 1)
	var tx := fx - float(x0); var tz := fz - float(z0)
	var h00 := heights[z0 * grid + x0]
	var h10 := heights[z0 * grid + x1]
	var h01 := heights[z1 * grid + x0]
	var h11 := heights[z1 * grid + x1]
	# Planar over the SAME triangle the collider uses, not bilinear.
	#
	# Three surfaces have to agree here or the game lies about where the
	# ground is: the mesh you can see, the HeightMapShape3D you stand on, and
	# this function -- which places grass, props and the foot IK's reference
	# plane. Godot's HeightMapShape3D splits every cell on the 00-11 diagonal.
	# Bilinear interpolation is a curved surface that matches neither
	# triangle, and measured against the collider it was out by up to 2.08 m
	# on a 2 m cell. Sample the same triangle and the error is zero.
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)

func sample_normal(x: float, z: float) -> Vector3:
	var d := cell
	var hl := sample_height(x - d, z); var hr := sample_height(x + d, z)
	var hd := sample_height(x, z - d); var hu := sample_height(x, z + d)
	return Vector3(hl - hr, 2.0 * d, hd - hu).normalized()

func slope_at(x: float, z: float) -> float:
	return 1.0 - clampf(sample_normal(x, z).y, 0.0, 1.0)

func is_water(x: float, z: float) -> bool:
	return sample_height(x, z) < water_level or main_river_depth(x, z) > 0.05

## Water surface of the main river at a point, or -INF where it is dry.
## Nearest-vertex lookup: the field is only written inside the channel (plus
## one metre), so a bilinear mix with the zeros outside would sink the edge.
func river_water_surface(x: float, z: float) -> float:
	if river_surf.size() != grid * grid: return -INF
	var xi := clampi(int(round(x / cell)), 0, grid - 1)
	var zi := clampi(int(round(z / cell)), 0, grid - 1)
	var y := river_surf[zi * grid + xi]
	return y if y > 0.0 else -INF

func main_river_depth(x: float, z: float) -> float:
	var y := river_water_surface(x, z)
	if y == -INF: return 0.0
	return maxf(0.0, y - sample_height(x, z))

## Height of the water surface over a point (lake or main river), -INF if dry.
func water_surface_y(x: float, z: float) -> float:
	var r := river_water_surface(x, z)
	if sample_height(x, z) < water_level: return maxf(water_level, r)
	return r

## Depth of standing or running water at a point (0 on dry land).
func water_depth_at(x: float, z: float) -> float:
	return maxf(water_level - sample_height(x, z), main_river_depth(x, z))

## 0..1: how close to the main river's banks (1 = in the channel).
func river_prox_at(x: float, z: float) -> float:
	if river_prox.size() != grid * grid: return 0.0
	var xi := clampi(int(round(x / cell)), 0, grid - 1)
	var zi := clampi(int(round(z / cell)), 0, grid - 1)
	return float(river_prox[zi * grid + xi]) / 255.0

func _px(img: Image, x: float, z: float) -> Color:
	if img == null: return Color(0, 0, 0, 0)
	var xi := clampi(int(x / size * float(img.get_width())), 0, img.get_width() - 1)
	var zi := clampi(int(z / size * float(img.get_height())), 0, img.get_height() - 1)
	return img.get_pixel(xi, zi)

## Biome name under a point, used by foliage, audio and weather.
func biome_at(x: float, z: float) -> String:
	var c := _px(biome_img, x, z)
	var id := int(round(c.r * 255.0))
	return BIOME_NAMES[id] if id >= 0 and id < BIOME_NAMES.size() else "grassland"

func grass_density_at(x: float, z: float) -> float:
	return _px(biome_img, x, z).b

func tree_density_at(x: float, z: float) -> float:
	return _px(biome_img, x, z).a

func river_at(x: float, z: float) -> float:
	return _px(river_img, x, z).r

## Alpha is the carved channel -- the cells WaterSystem actually surfaces.
## R is the wider damp valley around it, which is still walkable ground.
func river_channel_at(x: float, z: float) -> float:
	return _px(river_img, x, z).a

## Is this point under rendered river surface?
##
## river_channel_at() reads the ALPHA channel, which marks every drainage line
## in the map including 900-odd hairlines that carry no water. Suppressing
## grass on all of them scratched thin bald lines across the fields. The water
## mesh is built from the R (main stem) channel dilated by one cell, so that
## is what has to be tested here for the two to agree.
func river_surface_at(x: float, z: float) -> bool:
	if main_river_depth(x, z) > 0.0: return true
	if river_img == null: return false
	var c := cell
	return (_px(river_img, x, z).r > 0.5
		or _px(river_img, x - c, z).r > 0.5 or _px(river_img, x + c, z).r > 0.5
		or _px(river_img, x, z - c).r > 0.5 or _px(river_img, x, z + c).r > 0.5)

## Dominant material under a point -> footstep + traversal surface type.
func surface_at(x: float, z: float) -> String:
	if sample_height(x, z) < water_level + 0.25: return "water"
	if main_river_depth(x, z) > 0.12: return "water"
	var c := _px(splat_img, x, z)
	var best := "grass"; var bv := c.r
	if c.g > bv: best = "dirt"; bv = c.g
	if c.b > bv: best = "rock"; bv = c.b
	if c.a > bv: best = "mud"; bv = c.a
	return best

func zone_at(x: float, z: float) -> String:
	var best := "shrine"; var bd := INF
	for k in zones.keys():
		var p: Dictionary = zones[k]
		var d := Vector2(float(p.get("x", 0)) - x, float(p.get("z", 0)) - z).length_squared()
		if d < bd: bd = d; best = str(k)
	return best

func zone_distance(zone: String, x: float, z: float) -> float:
	if not zones.has(zone): return INF
	var p: Dictionary = zones[zone]
	return Vector2(float(p.get("x", 0)) - x, float(p.get("z", 0)) - z).length()

# ------------------------------------------------------------------ material
func _build_material() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/terrain.gdshader")
	_mat.set_shader_parameter("world_size", size)
	_mat.set_shader_parameter("water_level", water_level)
	# v0.13: Poly Haven CC0 sets packed by tools/make_ground_arrays.py
	_mat.set_shader_parameter("albedo_arr", load("res://assets/textures/terrain/ground_albedo.jpg"))
	_mat.set_shader_parameter("data_arr", load("res://assets/textures/terrain/ground_data.png"))
	_mat.set_shader_parameter("macro_tex", load("res://assets/textures/terrain/ground_macro.jpg"))
	var pt := river_prox_texture()
	if pt != null: _mat.set_shader_parameter("prox_tex", pt)
	if splat_img != null:
		_mat.set_shader_parameter("splat_tex", ImageTexture.create_from_image(splat_img))
	if biome_img != null:
		_mat.set_shader_parameter("biome_tex", ImageTexture.create_from_image(biome_img))
	set_quality(int(Game.settings.get("quality", 2)))

## Quality tier -> shader branches (0: no de-tiling or triplanar).
func set_quality(level: int) -> void:
	if _mat != null: _mat.set_shader_parameter("quality", clampi(level, 0, 3))

func material() -> ShaderMaterial:
	return _mat

func set_wetness(w: float) -> void:
	if _mat != null: _mat.set_shader_parameter("wetness", clampf(w, 0.0, 1.0))

func set_snow(s: float) -> void:
	if _mat != null: _mat.set_shader_parameter("snow", clampf(s, 0.0, 1.0))

func set_lod_bias(b: float) -> void:
	_lod_bias = clampf(b, 0.35, 3.0)

# ------------------------------------------------------------------ chunks
func _build_chunks() -> void:
	var per_side := int(ceil(size / CHUNK_M))
	for cz in per_side:
		for cx in per_side:
			var mi := MeshInstance3D.new()
			mi.name = "C_%d_%d" % [cx, cz]
			mi.material_override = _mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mi)
			_chunks.append({
				"mi": mi, "cx": cx, "cz": cz, "step": -1,
				"c": Vector3((cx + 0.5) * CHUNK_M, 0.0, (cz + 0.5) * CHUNK_M),
			})
	# build the near ring immediately so the first frame is not empty
	_refresh_lod(Vector3(size * 0.5, 0.0, size * 0.5), 999)

func set_player(p: Node3D) -> void:
	_player = p

func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.25 or _player == null or not is_instance_valid(_player):
		return
	_tick = 0.0
	_refresh_lod(_player.global_position, 3)

func _step_for(d: float) -> int:
	var b := _lod_bias
	if d < lod_dist[0] * b: return 1
	if d < lod_dist[1] * b: return 2
	if d < lod_dist[2] * b: return 4
	if d < lod_dist[3] * b: return 8
	return 16

func _refresh_lod(from: Vector3, budget: int) -> void:
	_built_this_frame = 0
	var fl := Vector3(from.x, 0.0, from.z)
	for c in _chunks:
		var d: float = fl.distance_to(c["c"])
		var want := _step_for(d)
		if want == int(c["step"]):
			continue
		# amortise mesh construction across frames to avoid hitches
		if _built_this_frame >= budget and int(c["step"]) > 0:
			continue
		var mi: MeshInstance3D = c["mi"]
		mi.mesh = _chunk_mesh(int(c["cx"]), int(c["cz"]), want)
		c["step"] = want
		_built_this_frame += 1

func _chunk_mesh(cx: int, cz: int, step: int) -> ArrayMesh:
	var key := "%d_%d_%d" % [cx, cz, step]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var cells := int(CHUNK_M / cell)                 # heightmap cells per chunk
	var x0 := cx * cells
	var z0 := cz * cells
	var n := int(cells / step) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	verts.resize(n * n); uvs.resize(n * n); norms.resize(n * n)
	for j in n:
		for i in n:
			var hx := mini(x0 + i * step, grid - 1)
			var hz := mini(z0 + j * step, grid - 1)
			var wx := float(hx) * cell
			var wz := float(hz) * cell
			var y := heights[hz * grid + hx]
			var idx := j * n + i
			verts[idx] = Vector3(wx, y, wz)
			uvs[idx] = Vector2(wx / size, wz / size)
			norms[idx] = sample_normal(wx, wz)
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			var b := j * n + i + 1
			var c2 := (j + 1) * n + i
			var d := (j + 1) * n + i + 1
			# Winding matters: Godot's front face is the one that the
			# (v1-v0) x (v2-v0) cross product points AWAY from. An up-facing
			# surface therefore needs a -Y cross. The old [a,c2,b]/[b,c2,d]
			# order produced +Y, so every terrain chunk was back-face culled
			# and the "ground" on screen was really the fogged sky dome.
			#
			# The DIAGONAL matters just as much. This split the cell 10-01;
			# HeightMapShape3D splits it 00-11. Two different surfaces over
			# the same height grid, differing by the saddle depth of every
			# cell -- measured at 0.23 m on average and 2.08 m at worst. That
			# is the gap the character's feet were disappearing into: he was
			# standing correctly on a floor nobody could see. Both triangles
			# below keep the -Y cross product.
			for tri in [[a, b, d], [a, d, c2]]:
				for vi in tri:
					st.set_uv(uvs[vi]); st.set_normal(norms[vi]); st.add_vertex(verts[vi])
	# Skirt: drop a wall around the chunk edge so neighbouring chunks at a
	# coarser LOD cannot show a crack of sky between them.
	# Keep the skirt short. It only needs to cover sub-metre LOD cracks; a
	# skirt that scales with the stride becomes a tens-of-metres wall that is
	# clearly visible from the side at coarse LOD.
	var skirt := minf(2.0 + cell * float(step) * 0.15, 5.0)
	for e in 4:
		for i in n - 1:
			var i0 := i; var i1 := i + 1
			var p0: Vector3; var p1: Vector3
			match e:
				0: p0 = verts[i0]; p1 = verts[i1]
				1: p0 = verts[(n - 1) * n + i1]; p1 = verts[(n - 1) * n + i0]
				2: p0 = verts[i1 * n]; p1 = verts[i0 * n]
				_: p0 = verts[i0 * n + (n - 1)]; p1 = verts[i1 * n + (n - 1)]
			var q0 := p0 - Vector3(0, skirt, 0)
			var q1 := p1 - Vector3(0, skirt, 0)
			for v in [p0, q0, p1, q1, p1, q0]:
				st.set_uv(Vector2(v.x / size, v.z / size))
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	var m := st.commit()
	_mesh_cache[key] = m
	_cache_order.append(key)
	# bound memory: coarse LODs are tiny, fine LODs are not
	while _cache_order.size() > 420:
		var old: String = _cache_order.pop_front()
		if old != key: _mesh_cache.erase(old)
	return m

# ------------------------------------------------------------------ collision
func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = grid
	shape.map_depth = grid
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	# HeightMapShape3D samples sit on a 1-unit lattice centred on the shape
	# origin, so sample i lands at local (i - (grid-1)/2). The visual mesh puts
	# sample i at world i*cell, so the shape must be scaled by `cell` and its
	# centre placed at (grid-1)*cell/2 -- NOT size/2 - cell/2, which is a metre
	# short and shifted the whole collision surface diagonally. On any slope
	# that offset dropped the collision floor up to 1.5 m below the terrain you
	# can see, which is what let the player sink into hillsides.
	var mid := float(grid - 1) * cell * 0.5
	cs.position = Vector3(mid, 0.0, mid)
	cs.scale = Vector3(cell, 1.0, cell)
	body.add_child(cs)
	add_child(body)
	_build_bounds()

## Invisible walls 4 m inside the border (collision layer 8). Bodies that walk
## - player, horse, enemies - mask it; the camera and ground probes do not.
const BOUND_LAYER := 8
func _build_bounds() -> void:
	var b := StaticBody3D.new()
	b.name = "WorldBounds"
	b.collision_layer = BOUND_LAYER
	b.collision_mask = 0
	var m := 4.0
	var th := 6.0
	var tall := max_height + 400.0
	var span := size + 2.0 * th
	for side in 4:
		var box := BoxShape3D.new()
		var cs := CollisionShape3D.new()
		var x := size * 0.5
		var z := size * 0.5
		if side < 2:
			box.size = Vector3(th, tall, span)
			x = (size - m + th * 0.5) if side == 0 else (m - th * 0.5)
		else:
			box.size = Vector3(span, tall, th)
			z = (size - m + th * 0.5) if side == 2 else (m - th * 0.5)
		cs.shape = box
		cs.position = Vector3(x, tall * 0.5 - 60.0, z)
		b.add_child(cs)
	add_child(b)

# ------------------------------------------------------------------ backdrop
## Distant mountain range outside the playable bounds. Gives every region a big
## far silhouette to navigate by without adding playable geometry.
func _build_distant_range() -> void:
	# v0.14: a real heightfield ring of hills and mountains around the map
	# (v0.13 stood flat ridge cut-outs on a circle). The polar grid starts
	# exactly on the playable square's edge at the terrain's own edge height,
	# so there is no gap or cliff at the border.
	# v0.17: ~4x the resolution (1024 bearings x ~60 rings, written straight
	# into an ArrayMesh instead of through SurfaceTool) and real mountain
	# shapes: domain-warped ridged noise with weighted octaves - sharp crests,
	# smoother valley floors - under a massif envelope, forested foothills
	# near the border and a high rocky range 2.5-4.7 km out, with crags on
	# the crests (slopes kept to what real ranges have - the first try
	# at 1/1500 m made needle karst). Layered ridgelines instead of one smooth pale wall;
	# distant_land.gdshader adds the small relief, rock, snow and cloud
	# shadows, and the depth fog hazes each ridge a little more than the last.
	var cx := size * 0.5
	var cz := size * 0.5
	var half := size * 0.5
	var na := 1024
	var offs := PackedFloat32Array([-1.0])
	var od := 20.0
	while od < 4700.0:
		offs.append(od)
		od += clampf(od * 0.09, 20.0, 150.0)
	offs.append(4700.0)
	var nr := offs.size()
	var mass := FastNoiseLite.new()
	mass.seed = 4127
	mass.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mass.fractal_type = FastNoiseLite.FRACTAL_FBM
	mass.fractal_octaves = 3
	mass.frequency = 1.0 / 5200.0
	var ridge := FastNoiseLite.new()
	ridge.seed = 7731
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 5
	ridge.fractal_lacunarity = 2.1
	ridge.fractal_gain = 0.45
	ridge.fractal_weighted_strength = 0.6
	ridge.frequency = 1.0 / 2600.0
	ridge.domain_warp_enabled = true
	ridge.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	ridge.domain_warp_amplitude = 380.0
	ridge.domain_warp_frequency = 1.0 / 3200.0
	ridge.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE
	ridge.domain_warp_fractal_octaves = 2
	var hills := FastNoiseLite.new()
	hills.seed = 911
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	hills.fractal_octaves = 5
	hills.frequency = 1.0 / 700.0
	var crag := FastNoiseLite.new()
	crag.seed = 5519
	crag.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	crag.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	crag.fractal_octaves = 3
	crag.frequency = 1.0 / 320.0
	var nv := na * nr
	var pos := PackedVector3Array()
	pos.resize(nv)
	var uvs := PackedVector2Array()
	uvs.resize(nv)
	for ia in na:
		var th := TAU * float(ia) / float(na)
		var dx := cos(th)
		var dz := sin(th)
		var rin := half / maxf(absf(dx), absf(dz))
		var eh := sample_height(cx + dx * (rin - 2.0), cz + dz * (rin - 2.0))
		for ir in nr:
			var d: float = offs[ir]
			var r := rin + d
			var x := cx + dx * r
			var z := cz + dz * r
			var h := eh - 0.8
			if ir > 0:
				var hl := hills.get_noise_2d(x, z) * 0.5 + 0.5
				var rr := clampf((ridge.get_noise_2d(x, z) * 0.5 + 0.5 - 0.38) / 0.55, 0.0, 1.0)
				var ms := mass.get_noise_2d(x, z) * 0.5 + 0.5
				var foot := 25.0 + 150.0 * hl + 60.0 * rr * rr
				var hi := 120.0 + (450.0 + 650.0 * ms) * pow(rr, 1.35) + 70.0 * hl
				var far := smoothstep(500.0, 3200.0, d)
				var mh := lerpf(foot, hi, far)
				mh += (crag.get_noise_2d(x, z) * 0.5 + 0.5) * 40.0 * far * smoothstep(0.45, 0.85, rr)
				h = lerpf(eh, eh * 0.55 + mh, smoothstep(0.0, 520.0, d))
			pos[ia * nr + ir] = Vector3(x, h, z)
			uvs[ia * nr + ir] = Vector2(maxf(d, 0.0), 0.0)
	var nrm := PackedVector3Array()
	nrm.resize(nv)
	for ia in na:
		var ja := ((ia + 1) % na) * nr
		var jb := ((ia - 1 + na) % na) * nr
		var i0 := ia * nr
		for ir in nr:
			var n := (pos[i0 + mini(ir + 1, nr - 1)] - pos[i0 + maxi(ir - 1, 0)]).cross(
				pos[ja + ir] - pos[jb + ir]).normalized()
			if n.y < 0.0: n = -n
			nrm[i0 + ir] = n
	var idx := PackedInt32Array()
	idx.resize(na * (nr - 1) * 6)
	var k := 0
	for ia in na:
		var a0 := ia * nr
		var b0 := ((ia + 1) % na) * nr
		for ir in nr - 1:
			# clockwise seen from above: A -> D -> C, A -> C -> B
			idx[k] = a0 + ir; idx[k + 1] = a0 + ir + 1; idx[k + 2] = b0 + ir + 1
			idx[k + 3] = a0 + ir; idx[k + 4] = b0 + ir + 1; idx[k + 5] = b0 + ir
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "DistantRange"
	mi.mesh = am
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/distant_land.gdshader")
	if _mat != null:
		m.set_shader_parameter("albedo_arr", _mat.get_shader_parameter("albedo_arr"))
		m.set_shader_parameter("macro_tex", _mat.get_shader_parameter("macro_tex"))
	mi.material_override = m
	mi.extra_cull_margin = 64.0
	add_child(mi)

## One ridge span: a quad from the base line up to two neighbouring apexes,
## vertex-coloured from forested foot to snow cap and washed toward the sky by
## the layer's haze.
func _peak_quad(st: SurfaceTool, a: Vector3, ha: float, b: Vector3, hb: float,
		haze: float, nrm: Vector3) -> void:
	var ta := a + Vector3(0, ha, 0)
	var tb := b + Vector3(0, hb, 0)
	var ca := _peak_col(0.0, haze)
	var cb := _peak_col(0.0, haze)
	var cta := _peak_col(ha, haze)
	var ctb := _peak_col(hb, haze)
	_peak_v(st, a, ca, nrm); _peak_v(st, b, cb, nrm); _peak_v(st, tb, ctb, nrm)
	_peak_v(st, a, ca, nrm); _peak_v(st, tb, ctb, nrm); _peak_v(st, ta, cta, nrm)

func _peak_v(st: SurfaceTool, p: Vector3, c: Color, n: Vector3) -> void:
	st.set_normal(n)
	st.set_color(c)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(p)

func _peak_col(h: float, haze: float) -> Color:
	var rock := Color(0.31, 0.34, 0.39)
	var snow := Color(0.88, 0.91, 0.96)
	var wood := Color(0.17, 0.23, 0.19)
	var sky := Color(0.60, 0.69, 0.80)
	var c := rock.lerp(snow, clampf((h - 335.0) / 185.0, 0.0, 1.0))
	c = c.lerp(wood, clampf(1.0 - h / 215.0, 0.0, 1.0) * 0.60)
	return c.lerp(sky, haze)
