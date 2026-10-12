class_name TreeSystem
extends Node3D
## Tree ecosystem: families, per-family mesh variants, and distance LOD.
##
## Trees come from world.json (placed by tools/worldgen.py using biome density),
## are grouped into a two-level chunk hierarchy (v0.14):
##
##   * far field: one 192 m chunk per family draws every tree at LOD2;
##   * when the camera comes within FAR_BEGIN of that chunk, it hands over to
##     its 64 m sub-chunks (Godot visibility_parent = HLOD), each of which
##     swaps LOD0 <-> LOD1 at NEAR_END.
##
## Every swap pair shares one AABB and one hysteresis margin, so a tree is
## always drawn exactly once - no doubled canopies, no holes - and only the
## trees near the player pay for the detailed mesh. The engine does all the
## swapping and frustum culling; there is no per-frame script work.

const BIG_M := 192.0
const SMALL_M := 64.0
const NEAR_END := 100.0     # LOD0 -> LOD1, from the 64 m chunk centre
## v0.15: the LOD2 cards used to take over at 260 m, close enough to read as
## blocks, and the far field ended at 760 m, so whole hillsides of forest
## appeared as you rode toward them. LOD2 now starts at 400 m and is never
## culled by distance (the world is 1.5 km across; 3 km covers any view).
const FAR_BEGIN := 400.0    # 192 m chunk: LOD2 -> its 64 m chunks
const FAR_END := 3000.0
const SWAP_M := 6.0         # hysteresis on both sides of every swap
const VARIANTS := 2

var terrain: Terrain
var quality := 2
var range_scale := 1.0

var _meshes := {}      # "family_variant_lod" -> ArrayMesh
var _mats := {}        # "family_lod" -> ShaderMaterial
var _families := {}
var total_trees := 0
var mm_nodes := 0
var _last_list: Array = []

const SEASON := {"maple": 0.12, "sakura": 0.0, "cedar": 0.0, "pine": 0.0,
	"dead_tree": 0.0, "young_tree": 0.0, "bamboo": 0.0}

## v0.14: per-family bark (Poly Haven CC0 sets in assets/textures/bark/) and
## leaf tints. Leaf colour now comes from the atlas itself; the tints only
## nudge it, base -> alt across instances, so a stand of maples is not one red.
const BARK_SET := {"pine": "pine", "cedar": "cedar", "maple": "maple", "sakura": "sakura",
	"young_tree": "maple", "dead_tree": "pine", "bamboo": ""}
const BARK_TINT := {"pine": Color(0.92, 0.90, 0.88), "cedar": Color(0.95, 0.88, 0.84),
	"maple": Color(0.95, 0.93, 0.92), "sakura": Color(0.92, 0.86, 0.86),
	"young_tree": Color(0.95, 0.93, 0.90), "dead_tree": Color(0.72, 0.71, 0.70), "bamboo": Color(1, 1, 1)}
const LEAF_TINT := {
	"pine": [Color(0.86, 0.92, 0.84), Color(0.76, 0.86, 0.66)],
	"cedar": [Color(0.84, 0.92, 0.86), Color(0.96, 0.88, 0.64)],
	"maple": [Color(0.96, 0.96, 0.95), Color(1.03, 0.93, 0.78)],
	"sakura": [Color(1.0, 1.0, 1.0), Color(1.02, 0.94, 0.97)],
	"bamboo": [Color(0.96, 1.0, 0.94), Color(1.06, 1.04, 0.78)],
	"young_tree": [Color(1.0, 1.0, 1.0), Color(1.10, 1.04, 0.76)],
	"dead_tree": [Color(1.0, 1.0, 1.0), Color(0.88, 0.86, 0.84)],
}
## leaf flutter (m per unit wind) and whole-tree lean per family
const SWAY := {"pine": [0.05, 0.010], "cedar": [0.05, 0.008], "maple": [0.08, 0.012],
	"sakura": [0.08, 0.012], "bamboo": [0.12, 0.035], "young_tree": [0.09, 0.020],
	"dead_tree": [0.03, 0.008]}

func setup(t: Terrain) -> void:
	terrain = t

## Rebuild at a new quality tier. Cheap enough to do on a settings change
## because the meshes are cached; only the MultiMesh instances are re-packed.
func set_quality(level: int) -> void:
	if _last_list.is_empty() or level == quality: return
	# Newest first: each near/mid chunk leaves the tree while the far chunk it
	# names as visibility parent is still there. Removing a far chunk first
	# made every sub-chunk log "Can't find visibility parent" on its way out.
	var kids := get_children()
	kids.reverse()
	for c in kids:
		remove_child(c)
		c.queue_free()
	mm_nodes = 0
	build(_last_list, level)

func build(trees: Array, level: int) -> void:
	_last_list = trees
	quality = level
	var rs: Array = [0.55, 0.8, 1.0, 1.25]
	range_scale = float(rs[clampi(level, 0, 3)])
	# Placement density per tier, not only draw range: a phone should render
	# fewer trunks, not the same forest pulled closer. The keep test is a stable
	# hash of world position, so the same trees survive every rebuild and the
	# forest does not reshuffle when quality changes.
	var keep: float = float(Perf.PRESETS[clampi(level, 0, 3)].get("trees", 1.0))
	# group by big chunk + family
	var groups := {}
	for tr in trees:
		if keep < 0.999:
			var hx := int(float(tr.get("x", 0.0)) * 8.0)
			var hz := int(float(tr.get("z", 0.0)) * 8.0)
			var hv := float(absi(hash(Vector2i(hx, hz))) % 1000) / 1000.0
			if hv > keep: continue
		var fam: String = str(tr.get("kind", "pine"))
		var cx := int(floor(float(tr.get("x", 0.0)) / BIG_M))
		var cz := int(floor(float(tr.get("z", 0.0)) / BIG_M))
		var key := "%d_%d_%s" % [cx, cz, fam]
		if not groups.has(key): groups[key] = []
		groups[key].append(tr)
		_families[fam] = true
	total_trees = 0
	for gk in groups.keys(): total_trees += (groups[gk] as Array).size()
	# distances per tier; the far hand-over never comes closer than 230 m so a
	# phone does not see LOD2 cards next to the road
	var near_end: float = maxf(NEAR_END * range_scale, 50.0)
	var far_begin: float = maxf(FAR_BEGIN * range_scale, 260.0)
	var far_end: float = maxf(FAR_END * range_scale, 1600.0)
	# LOD1 shadows only on Ultra: they keep mid-distance forest grounded
	var lod1_shadow := level >= 3
	for key in groups.keys():
		var key_s: String = str(key)
		# maxsplit 2: "young_tree" / "dead_tree" keep their underscore (a plain
		# split turned them into "young" / "dead" and built generic broadleaves)
		var fam: String = key_s.split("_", true, 2)[2]
		var list: Array = groups[key]
		var variant: int = absi(hash(key_s)) % VARIANTS
		var far := _chunk_mmi(list, fam, variant, 2, "F_" + key_s)
		if far == null: continue
		far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		far.visibility_range_begin = far_begin
		far.visibility_range_begin_margin = SWAP_M * 2.0
		far.visibility_range_end = far_end
		far.visibility_range_end_margin = 20.0
		add_child(far)
		mm_nodes += 1
		# sub-chunks
		var subs := {}
		for tr in list:
			var sk := Vector2i(int(floor(float(tr["x"]) / SMALL_M)), int(floor(float(tr["z"]) / SMALL_M)))
			if not subs.has(sk): subs[sk] = []
			subs[sk].append(tr)
		for sk in subs.keys():
			var sl: Array = subs[sk]
			var nm := "%s_%d_%d" % [key_s, sk.x, sk.y]
			var n0 := _chunk_mmi(sl, fam, variant, 0, "N_" + nm)
			var n1 := _chunk_mmi(sl, fam, variant, 1, "M_" + nm)
			if n0 == null or n1 == null: continue
			# one shared box: both LODs measure the same distance
			var box: AABB = n0.multimesh.get_aabb().merge(n1.multimesh.get_aabb())
			n0.custom_aabb = box
			n1.custom_aabb = box
			n0.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			n0.visibility_range_end = near_end
			n0.visibility_range_end_margin = SWAP_M
			n1.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod1_shadow
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			n1.visibility_range_begin = near_end
			n1.visibility_range_begin_margin = SWAP_M
			add_child(n0)
			add_child(n1)
			# HLOD: only drawn while the far chunk is hidden for being too close
			n0.visibility_parent = n0.get_path_to(far)
			n1.visibility_parent = n1.get_path_to(far)
			mm_nodes += 2

## One MultiMesh instance for a list of trees at one LOD. The per-instance
## custom data (variation hash, scale) is identical across LODs so tints and
## wind phase do not jump at a swap.
func _chunk_mmi(list: Array, fam: String, variant: int, lod: int, nm: String) -> MultiMeshInstance3D:
	var mesh := _mesh_for(fam, variant, lod)
	if mesh == null or list.is_empty(): return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		var tr: Dictionary = list[i]
		var x := float(tr["x"])
		var z := float(tr["z"])
		var s := float(tr.get("s", 1.0))
		var rot := deg_to_rad(float(tr.get("rot", 0.0)))
		var y := float(tr.get("y", 0.0))
		if terrain != null and terrain.loaded:
			y = terrain.sample_height(x, z) - 0.15
		# coarse LODs are slightly wider so silhouettes match at range
		var sw: float = s * (1.0 if lod == 0 else (1.04 if lod == 1 else 1.10))
		var b := Basis(Vector3.UP, rot).scaled(Vector3(sw, s, sw))
		mm.set_instance_transform(i, Transform3D(b, Vector3(x, y, z)))
		var r := fmod(absf(sin(x * 12.9898 + z * 78.233)) * 43758.5453, 1.0)
		mm.set_instance_custom_data(i, Color(r, s, fmod(r * 5.17, 1.0), 0.0))
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	return mi

func _mesh_for(fam: String, variant: int, lod: int) -> ArrayMesh:
	var k := "%s_%d_%d" % [fam, variant, lod]
	if _meshes.has(k): return _meshes[k]
	var m := MeshLib.tree(fam, lod, variant * 31 + 5)
	if m != null and m.get_surface_count() >= 2:
		m.surface_set_material(0, _bark_mat(fam, lod))
		m.surface_set_material(1, _leaf_mat(fam, lod))
	_meshes[k] = m
	return m

func _bark_mat(fam: String, lod: int) -> ShaderMaterial:
	var k := "%s_%d_bark" % [fam, lod]
	if _mats.has(k): return _mats[k]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/tree_bark.gdshader")
	var set_name: String = BARK_SET.get(fam, "pine")
	if set_name == "":
		m.set_shader_parameter("bamboo", 1.0)
	else:
		m.set_shader_parameter("bark_albedo", load("res://assets/textures/bark/%s_diff.jpg" % set_name))
		m.set_shader_parameter("bark_normal", load("res://assets/textures/bark/%s_nor.jpg" % set_name))
	m.set_shader_parameter("bark_tint", BARK_TINT.get(fam, Color(1, 1, 1)))
	m.set_shader_parameter("normal_depth", 1.0 if lod == 0 else 0.6)
	var sw: Array = SWAY.get(fam, [0.07, 0.012])
	m.set_shader_parameter("sway_scale", float(sw[0]))
	m.set_shader_parameter("trunk_sway", float(sw[1]))
	_mats[k] = m
	return m

func _leaf_mat(fam: String, lod: int) -> ShaderMaterial:
	var k := "%s_%d_leaf" % [fam, lod]
	if _mats.has(k): return _mats[k]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/tree_leaf.gdshader")
	m.set_shader_parameter("leaf_atlas", load("res://assets/textures/foliage/leaf_atlas.png"))
	var tints: Array = LEAF_TINT.get(fam, [Color(1, 1, 1), Color(1, 1, 1)])
	m.set_shader_parameter("leaf_tint", tints[0])
	m.set_shader_parameter("leaf_tint_alt", tints[1])
	var sw: Array = SWAY.get(fam, [0.07, 0.012])
	# distant LODs move less: their cards are bigger, so the same motion reads larger
	m.set_shader_parameter("sway_scale", float(sw[0]) * (1.0 if lod == 0 else 0.6))
	m.set_shader_parameter("trunk_sway", float(sw[1]))
	m.set_shader_parameter("season", SEASON.get(fam, 0.0))
	m.set_shader_parameter("translucency", 0.65 if fam == "sakura" or fam == "maple" else 0.5)
	_mats[k] = m
	return m

func set_wind(dir: Vector2, strength: float, gust: float) -> void:
	for m in _mats.values():
		var sm: ShaderMaterial = m
		sm.set_shader_parameter("wind_dir", dir)
		sm.set_shader_parameter("wind_strength", strength)
		sm.set_shader_parameter("gust", gust)
		sm.set_shader_parameter("gust_speed", 1.2 + strength * 1.6)

func set_wetness(w: float) -> void:
	for m in _mats.values():
		(m as ShaderMaterial).set_shader_parameter("wetness", w)

func set_snow(s: float) -> void:
	for m in _mats.values():
		(m as ShaderMaterial).set_shader_parameter("snow", s)

func stats() -> Dictionary:
	return {"trees": total_trees, "mm_nodes": mm_nodes, "families": _families.keys().size()}
