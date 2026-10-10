class_name World
extends Node3D
## Builds and runs the single connected open world (5 zones), day/night, weather,
## prop instancing, enemy spawning, quest triggers and checkpoints.

signal prompt_changed(text: String)
signal zone_entered(zone: String)
signal enemy_died(kind: String, zone: String)
signal boss_downed

const DATA_PATH := "res://assets/terrain/world.json"
const PROP_DIR := "res://assets/props/"
const SPAWN_RADIUS := 60.0
const DESPAWN_RADIUS := 100.0
const INTERACT_RADIUS := 4.5
const QUEST_SPOTS := {
	"forest_marker": Vector3(885.8, 0, 721.7), "castle_gate": Vector3(1210, 0, 482),
	"watchtower": Vector3(241, 0, 474.9), "well": Vector3(1176, 0, 1113.1),
	"shrine_hall": Vector3(620, 0, 566),
}
const ZONE_RADIUS := 26.0

var data := {}
var terrain: Terrain
var player: Player
var hud: Node
var touch: Node
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var world_env: WorldEnvironment
var camera: PlayerCamera
var sky_mat: ShaderMaterial
var petals: GPUParticles3D
var water: WaterSystem
var foliage: Foliage
var tree_system: TreeSystem
var story: Story
var solids: SolidBodies
var weather: Weather
var daynight: DayNight
var time_of_day := 7.2
var day_minutes := 9.0
var enemies: Array = []
var spawn_table: Array = []
var _spawn_cursor := 0
var _live_ids := {}
var lanterns: Array = []
var markers: Array = []
var checkpoints: Array = []
var rewards: Array = []
var wild: Wildlife
var hitodama: Hitodama
var _prompt := ""
var _zone := "shrine"
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var boss: Node = null
var loaded := false
var horse: Horse = null

func _ready() -> void:
	_rng.seed = 20260926
	_load_data()
	_build_terrain()
	_build_environment()
	_build_water()
	_build_trees()
	_build_foliage()
	add_to_group("world")
	_build_props()
	_build_landmarks()
	_build_solids()
	_build_markers()
	_build_spawn_table()
	_build_player()
	_build_fx()
	_build_ui()
	_build_story()
	_build_petals()
	_build_wildlife()
	hitodama = Hitodama.new()
	hitodama.name = "Hitodama"
	add_child(hitodama)
	hitodama.setup(self, player, terrain)
	_build_weather()
	_build_ambience()
	if terrain != null: terrain.set_player(player)
	if foliage != null and player != null:
		foliage.prime(player.global_position)
	_build_post()
	Perf.apply_quality(int(Game.settings.get("quality", 2)))
	Audio.play_music(Game.zone)
	loaded = true

func _load_data() -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("world.json missing")
		data = {"size": 480.0, "zones": {}, "props": [], "landmarks": []}
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	data = parsed if typeof(parsed) == TYPE_DICTIONARY else {}

# ------------------------------------------------------------------ build
func _build_terrain() -> void:
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	if terrain.loaded:
		terrain.water_level = float(data.get("water_level", 2.6))

func _build_environment() -> void:
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnv"
	world_env.add_to_group("world_env")
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	# ProceduralSkyMaterial can only draw a colour ramp, so every shot had an
	# empty sky. shaders/sky.gdshader adds a cumulus deck, cirrus, a sun disc
	# with a silver lining and stars; DayNight and Weather drive its uniforms.
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("top_color", Color(0.28, 0.46, 0.80))
	sky_mat.set_shader_parameter("horizon_color", Color(0.74, 0.80, 0.86))
	sky_mat.set_shader_parameter("ground_color", Color(0.20, 0.20, 0.18))
	sky_mat.set_shader_parameter("octaves", 5)
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	# white 6.0 crushed the midtones to mud; 3.0 keeps highlights but lets
	# grass and wood keep their colour.
	e.tonemap_white = 4.0
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_depth_begin = 240.0
	e.fog_depth_end = 2400.0
	e.fog_depth_curve = 1.55
	e.fog_light_color = Color(0.66, 0.70, 0.72)
	# v0.17: the fog takes most of its colour from the sky behind it, so far
	# ridges fade into the actual horizon instead of into a flat grey
	e.fog_aerial_perspective = 0.75
	e.fog_density = 0.78
	e.fog_sky_affect = 0.15
	e.glow_enabled = true
	# A low sun blooming through the grass is most of the reference look, and
	# 0.28/0.05 at a 1.1 threshold barely registered: almost nothing in the
	# scene is above 1.1 except the sun disc itself.
	# ...but SCREEN blending at a 0.92 threshold bloomed the whole lit ground,
	# not the sun: screen saturates toward white, and at golden hour every
	# sunlit surface is above 0.92. The frame came out milky pink with no
	# contrast anywhere. Additive above a threshold nothing but the sun and
	# the brightest backlit grass tips can reach is what gives a defined sun
	# disc with a halo instead of a uniform wash.
	e.glow_intensity = 0.42
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 1.45
	e.glow_hdr_scale = 1.8
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	e.ssao_enabled = false
	# Tighter and stronger. A 1.6 m radius at 1.5 intensity produced a broad
	# soft dimming that read as haze; contact darkening is what actually
	# grounds a blade of grass in the soil it grows out of, and that lives in
	# the first half metre.
	e.ssao_radius = 0.95
	e.ssao_intensity = 2.4
	e.ssao_power = 1.7
	e.ssao_detail = 0.85
	e.ssao_horizon = 0.05
	e.ssao_sharpness = 0.98
	e.ssao_light_affect = 0.15
	e.ssao_ao_channel_affect = 0.4
	e.ssil_enabled = false
	e.ssil_radius = 3.0
	e.ssil_intensity = 0.7
	e.ssil_normal_rejection = 1.0
	# Volumetric fog: off by default, switched on per tier by Perf and driven
	# across the day by DayNight. The sun's volumetric energy is what turns the
	# directional light into visible shafts through the canopy.
	e.volumetric_fog_enabled = false
	e.volumetric_fog_density = 0.016
	e.volumetric_fog_albedo = Color(0.86, 0.90, 0.96)
	e.volumetric_fog_emission_energy = 0.0
	e.volumetric_fog_anisotropy = 0.45
	e.volumetric_fog_length = 128.0
	e.volumetric_fog_detail_spread = 2.0
	# v0.14: volumetric fog only spans its 128 m length and everything beyond
	# receives the whole slab, so at 0.016 the far half of every vista sat
	# behind ~70% haze. Perf now sets ~1/3 of that; less ambient is injected
	# too, which was tinting the haze grass-green.
	e.volumetric_fog_ambient_inject = 0.20
	e.volumetric_fog_sky_affect = 0.3
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.10
	e.adjustment_contrast = 1.05
	world_env.environment = e

	# Exposure. Auto exposure was tried and removed. Godot meters the AVERAGE
	# luminance of the frame, and at golden hour a grassland is mostly dark
	# grass under a very bright sky: the average lands low, the metering
	# pushes exposure up, and the sun side of the frame goes to white paper.
	# Measured against the same settled frame with metering off, the fixed
	# exposure kept ground colour the auto version had erased. Time of day
	# already varies the light; the camera does not need to fight it.
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = false
	ca.exposure_multiplier = 1.0
	ca.dof_blur_far_enabled = false
	ca.dof_blur_near_enabled = false
	world_env.camera_attributes = ca
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.add_to_group("sun")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# Splits were at the engine defaults, which spend most of the atlas on
	# ground the player never looks at. Pulling the first three in puts the
	# resolution where the character and the props are.
	sun.directional_shadow_split_1 = 0.055
	sun.directional_shadow_split_2 = 0.165
	sun.directional_shadow_split_3 = 0.42
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.88
	# Peter-panning came from a 0.06 constant bias applied at every cascade.
	# Normal-offset bias scales with the cascade instead, so contact stays
	# tight up close and the far cascade still does not acne.
	sun.shadow_bias = 0.026
	sun.shadow_normal_bias = 1.6
	# Angular distance is the sun's apparent size. At 0 every shadow edge is a
	# razor line no matter how large the atlas is; the real sun subtends about
	# half a degree, and that penumbra is most of what sells outdoor light.
	sun.light_angular_distance = 0.55
	sun.shadow_blur = 1.0
	sun.light_energy = 1.25
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = false
	moon.light_energy = 0.0
	moon.light_color = Color(0.55, 0.65, 0.95)
	add_child(moon)

	# DayNight owns the lighting curve from here on.
	daynight = DayNight.new()
	daynight.name = "DayNight"
	add_child(daynight)
	daynight.setup(sun, moon, e, sky_mat)
	daynight.set_hour(time_of_day, true)


# ------------------------------------------------------------------ v0.17 film
var post_layer: CanvasLayer
var post_rect: ColorRect
var _grade_lut: GradientTexture1D

## Film layer between the 3D view and the HUD (shaders/post_film.gdshader),
## plus a gentle colour grade through the Environment's 1D LUT: shadows lean
## a touch cool, highlights a touch warm, the way a print film renders a
## landscape. Both are tier- and setting-controlled in apply_post().
func _build_post() -> void:
	post_layer = CanvasLayer.new()
	post_layer.name = "FilmLayer"
	post_layer.layer = 2
	add_child(post_layer)
	post_rect = ColorRect.new()
	post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/post_film.gdshader")
	post_rect.material = m
	post_layer.add_child(post_rect)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 0.82, 1.0])
	g.colors = PackedColorArray([Color(0.0, 0.006, 0.018), Color(0.172, 0.180, 0.192),
		Color(0.505, 0.500, 0.494), Color(0.832, 0.822, 0.806), Color(1.0, 0.992, 0.972)])
	_grade_lut = GradientTexture1D.new()
	_grade_lut.gradient = g
	_grade_lut.width = 256
	_grade_lut.use_hdr = false

## Called by Perf on every tier change and by the settings toggle.
## Low: nothing. Medium: vignette and grade. High: + grain. Ultra: + a faint
## far depth-of-field, which softens the 300 m+ landscape the way a long lens
## and the haze would.
func apply_post(level: int) -> void:
	var on: bool = bool(Game.settings.get("film_fx", true))
	if post_rect != null:
		post_layer.visible = on and level >= 1
		var m := post_rect.material as ShaderMaterial
		var vs := get_viewport().get_visible_rect().size
		m.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
		m.set_shader_parameter("grain", 0.032 if level >= 2 else 0.0)
		m.set_shader_parameter("vignette", 0.26)
	if world_env != null and world_env.environment != null:
		world_env.environment.adjustment_color_correction = _grade_lut if (on and level >= 1) else null
	if world_env != null and world_env.camera_attributes is CameraAttributesPractical:
		var ca := world_env.camera_attributes as CameraAttributesPractical
		ca.dof_blur_far_enabled = level >= 3
		ca.dof_blur_far_distance = 320.0
		ca.dof_blur_far_transition = 400.0
		ca.dof_blur_amount = 0.035

func _build_water() -> void:
	water = WaterSystem.new()
	water.name = "Water"
	add_child(water)
	water.setup(terrain)
	water.build(data)
	water.set_quality(int(Game.settings.get("quality", 2)))
	# The water builds after DayNight, so hand it over and re-apply once to get
	# the sky colour into the reflection straight away.
	if daynight != null:
		daynight.water = water
		daynight.apply(true)

func _build_trees() -> void:
	tree_system = TreeSystem.new()
	tree_system.name = "Trees"
	add_child(tree_system)
	tree_system.setup(terrain)
	tree_system.build(data.get("trees", []), int(Game.settings.get("quality", 2)))

func _build_foliage() -> void:
	foliage = Foliage.new()
	foliage.name = "Foliage"
	add_child(foliage)
	foliage.setup(terrain, null)
	foliage.set_quality(int(Game.settings.get("quality", 2)))

func _build_weather() -> void:
	weather = Weather.new()
	weather.name = "Weather"
	add_child(weather)
	if foliage != null: foliage.player = player
	weather.setup(terrain, foliage, tree_system, daynight, player)
	weather.set_quality(int(Game.settings.get("quality", 2)))

## Kinds the generator places that have no authored GLB are built procedurally.
const PROC_PROPS := {
	"stone_small": "stone", "branch": "branch", "log": "log", "stump": "stump",
	"root": "root", "boulder": "boulder", "crate": "crate", "barrel": "barrel",
	"basket": "basket", "sign": "sign", "fern": "fern", "shrub": "shrub",
	"flower": "flower", "mushroom": "mushroom",
}

func _proc_mesh(name: String) -> Mesh:
	match PROC_PROPS.get(name, ""):
		"stone": return MeshLib.stone(1.0, 3, 0)
		"boulder": return MeshLib.boulder(1, 0)
		"branch": return MeshLib.branch(0)
		"log": return MeshLib.log_mesh(0)
		"stump": return MeshLib.stump(0)
		"root": return MeshLib.root(0)
		"crate": return MeshLib.crate(0)
		"barrel": return MeshLib.barrel(0)
		"basket": return MeshLib.basket(0)
		"sign": return MeshLib.sign_post(0)
		"fern": return MeshLib.fern(0)
		"shrub": return MeshLib.shrub(0)
		"flower": return MeshLib.flower(0)
		"mushroom": return MeshLib.mushroom(0)
	return null

func _prop_mesh(name: String) -> Mesh:
	var proc := _proc_mesh(name)
	if proc != null: return proc
	var path := PROP_DIR + name + ".glb"
	if not ResourceLoader.exists(path): return null
	var ps := load(path) as PackedScene
	if ps == null: return null
	var inst := ps.instantiate()
	var mesh: Mesh = null
	for c in inst.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			mesh = (c as MeshInstance3D).mesh
			break
	inst.free()
	return mesh

func _make_multimesh(prop: String, list: Array, tint = null, sway := 0.0) -> MultiMeshInstance3D:
	var mesh := _prop_mesh(prop)
	if mesh == null: return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		var p: Dictionary = list[i]
		var basis := Basis(Vector3.UP, deg_to_rad(float(p.get("rot", 0.0))))
		basis = basis.scaled(Vector3.ONE * float(p.get("s", 1.0)))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(float(p["x"]), float(p["y"]), float(p["z"]))))
	var mi := MultiMeshInstance3D.new()
	mi.name = "MM_" + prop
	mi.multimesh = mm
	var pm := _prop_material(prop)
	if pm != null: mi.material_override = pm
	if sway > 0.0 or tint != null:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/foliage.gdshader")
		m.set_shader_parameter("tint", tint if tint != null else Color(1, 1, 1))
		m.set_shader_parameter("sway", sway)
		m.set_shader_parameter("sway_speed", 0.8 + sway * 0.4)
		m.set_shader_parameter("base_tex", load("res://assets/textures/terrain_c.png"))
		m.set_shader_parameter("norm_tex", load("res://assets/textures/terrain_n.png"))
		m.set_shader_parameter("rough_tex", load("res://assets/textures/ground_grass_r.png"))
		m.set_shader_parameter("uv_scale", 2.0)
		m.set_shader_parameter("norm_strength", 0.8)
		m.set_shader_parameter("rough_min", 0.68)
		m.set_shader_parameter("rough_max", 0.94)
		m.set_shader_parameter("ao_strength", 0.5)
		m.set_shader_parameter("variation", 0.18)
		mi.material_override = m
	return mi

## v0.14: rocks and loose stones share one photographic material (Poly Haven
## "mossy_rock", CC0) in world-space triplanar, so every boulder gets its own
## patch of lichen and the small stones are no longer the engine's default white.
var _rock_mat: StandardMaterial3D
func _rock_material() -> StandardMaterial3D:
	if _rock_mat != null: return _rock_mat
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/rock/mossy_rock_diff.jpg")
	m.albedo_color = Color(0.86, 0.86, 0.84)
	m.normal_enabled = true
	m.normal_texture = load("res://assets/textures/rock/mossy_rock_nor.jpg")
	m.normal_scale = 1.1
	m.roughness = 0.93
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3(0.42, 0.42, 0.42)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_rock_mat = m
	return m

## Procedural props (MeshLib) carry no material of their own; before v0.14
## logs, stumps, branches, crates and wild flowers fell back to the engine's
## plain white material.
var _prop_mats := {}
func _prop_material(kind: String) -> Material:
	if _prop_mats.has(kind): return _prop_mats[kind]
	var m: Material = null
	match kind:
		"rock", "stone_small", "boulder":
			m = _rock_material()
		"log", "stump", "branch", "root":
			m = _tri_mat("res://assets/textures/bark/pine_diff.jpg", "res://assets/textures/bark/pine_nor.jpg",
				Color(0.80, 0.76, 0.72), 0.85)
		"crate", "barrel", "basket", "sign":
			m = _tri_mat("res://assets/props/bridge_wood_c.png", "res://assets/props/bridge_wood_n.png",
				Color(0.92, 0.88, 0.82), 1.1)
		"flower", "mushroom":
			var g := ShaderMaterial.new()
			g.shader = load("res://shaders/grass.gdshader")
			g.set_shader_parameter("base_tex", load("res://assets/textures/ground_grass_c.png"))
			var flower := kind == "flower"
			g.set_shader_parameter("tint_lush", Color(0.62, 0.55, 0.68) if flower else Color(0.58, 0.48, 0.40))
			g.set_shader_parameter("tint_dry", Color(0.58, 0.54, 0.26))
			g.set_shader_parameter("bend_scale", 0.45 if flower else 0.05)
			m = g
	_prop_mats[kind] = m
	return m

func _tri_mat(albedo: String, normal: String, tint: Color, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(albedo)
	m.albedo_color = tint
	if ResourceLoader.exists(normal):
		m.normal_enabled = true
		m.normal_texture = load(normal)
	m.roughness = 0.9
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 3.0
	m.uv1_scale = Vector3.ONE * scale
	return m

func _build_props() -> void:
	var props: Array = data.get("props", [])
	if terrain != null and terrain.loaded:
		for p in props:
			p["y"] = terrain.sample_height(float(p["x"]), float(p["z"]))
	# split by zone so distant foliage groups can be range-culled
	var by_zone := {}
	for p in props:
		var z: String = terrain.zone_at(float(p["x"]), float(p["z"])) if terrain != null else "shrine"
		if not by_zone.has(z): by_zone[z] = {}
		var k: String = p["kind"]
		if not by_zone[z].has(k): by_zone[z][k] = []
		by_zone[z][k].append(p)
	var tints := {
		"grass": Color(0.40, 0.55, 0.26), "bamboo": Color(0.44, 0.58, 0.24),
		"sakura": Color(0.92, 0.66, 0.74),
	}
	var swaying := ["grass", "bamboo", "sakura"]
	for z in by_zone.keys():
		for k in by_zone[z].keys():
			var list: Array = by_zone[z][k]
			var sway := 0.05 if swaying.has(k) else 0.0
			var node := _make_multimesh(k, list, tints.get(k, null) if swaying.has(k) else null, sway)
			if node == null: continue
			node.name = "MM_%s_%s" % [k, z]
			if k == "grass":
				node.visibility_range_end = 210.0
			elif k in ["bamboo", "fence", "banner"]:
				node.visibility_range_end = 400.0
			add_child(node)
			if k == "lantern":
				for p in list: _add_lantern(Vector3(float(p["x"]), float(p["y"]), float(p["z"])))

func _add_lantern(pos: Vector3) -> void:
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0, 1.05, 0)
	l.light_color = Color(1.0, 0.72, 0.40)
	l.light_energy = 2.4
	l.omni_range = 9.0
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	l.visible = false
	add_child(l)
	lanterns.append(l)

func _build_landmarks() -> void:
	var lods := ["", "_LOD1", "_LOD2"]
	for lm in data.get("landmarks", []):
		var kind: String = lm["kind"]
		var x := float(lm["x"]); var z := float(lm["z"])
		var y := terrain.sample_height(x, z) if terrain != null and terrain.loaded else float(lm["y"])
		var holder := Node3D.new()
		holder.name = "LM_" + kind
		holder.position = Vector3(x, y, z)
		holder.rotation_degrees = Vector3(0, float(lm.get("rot", 0.0)), 0)
		var s := float(lm.get("s", 1.0))
		var added := false
		for i in lods.size():
			var mesh := _prop_mesh(kind + lods[i])
			if mesh == null: continue
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.scale = Vector3.ONE * s
			mi.cast_shadow = MeshInstance3D.SHADOW_CASTING_SETTING_ON if i == 0 else MeshInstance3D.SHADOW_CASTING_SETTING_OFF
			if i == 1:
				mi.visibility_range_begin = 90.0
				mi.visibility_range_end = 220.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			elif i == 2:
				mi.visibility_range_begin = 200.0
			holder.add_child(mi)
			added = true
		if added:
			add_child(holder)
			# Collision for landmarks is built by SolidBodies, not here, so
			# every structure is handled by one measured table instead of a
			# hand-placed box on a single building.

## Give the world real collision. Props and trees are MultiMesh draws with no
## bodies of their own, so without this pass you walk through every building,
## boulder and tree trunk in the game.
func _build_solids() -> void:
	solids = SolidBodies.new()
	solids.name = "Solids"
	add_child(solids)
	solids.setup(terrain)
	solids.add_structures(data.get("props", []), data.get("landmarks", []))
	solids.add_boulders(data.get("props", []))
	solids.add_trees(data.get("trees", []))
	for lm in data.get("landmarks", []):
		if String(lm.get("kind", "")) == "cedar":
			solids.add_trees([lm])

func _build_markers() -> void:
	var zones: Dictionary = data.get("zones", {})
	for k in zones.keys():
		var z: Dictionary = zones[k]
		_marker(String(k), Vector3(float(z["x"]), 0, float(z["z"])), ZONE_RADIUS, "zone", "Enter %s" % Game.ZONE_TITLE.get(k, k))
		_checkpoint(Vector3(float(z["x"]), 0, float(z["z"])))
	# v13: these were still at the old 480 m map's coordinates, so the forest
	# marker, the castle gate, the watchtower and the village well pointed at
	# empty land. They now sit on real props (tools/fix_markers.py placed the
	# well, the mountain watchtower and the forest lanterns).
	for id in QUEST_SPOTS.keys():
		var p: Vector3 = QUEST_SPOTS[id]
		_marker(id, p, 7.0, "reach", "Reach %s" % id.replace("_", " "))
	# hidden exploration rewards along the secret paths
	var hidden: Array = data.get("hidden_paths", [])
	for hp in hidden:
		for pt in hp.get("points", []):
			rewards.append(Vector3(float(pt[0]), 0, float(pt[1])))

func _marker(id: String, pos: Vector3, radius: float, kind: String, prompt: String) -> void:
	markers.append({"id": id, "pos": pos, "radius": radius, "kind": kind, "prompt": prompt, "used": false})

## Register a checkpoint. Zone markers are authored on the map centre, and some
## of those centres are under water (the lake marker sits at y=0 with the water
## line at 6 m), so walk the position to dry land before it is ever used as a
## respawn point.
func _checkpoint(pos: Vector3) -> void:
	var p := pos
	if terrain != null and terrain.loaded:
		var tries := 0
		while terrain.sample_height(p.x, p.z) < terrain.water_level + 0.6 and tries < 40:
			tries += 1
			var a := TAU * float(tries) * 0.61803
			var r := 8.0 * float(tries)
			p = Vector3(pos.x + cos(a) * r, 0.0, pos.z + sin(a) * r)
	checkpoints.append({"pos": p, "used": false})

## v0.16 camps. Every zone's soldiers hold a camp a little way off the zone
## centre: sentries at their posts looking outward, a patrol walking a loop
## round it, archers as lookouts on the edge. Each camp is one alert group
## (EnemyBase.group): when one soldier raises the alarm the rest join in.
## (v0.15 and older placed them with a bounds check left over from the old
## 480 m map, so in every zone but the mountain the whole garrison stood in a
## single diagonal line from the zone centre.) Ids keep the old
## <zone>_<kind>_<n> scheme, so defeats in older saves still count.
const CAMPS := {
	"shrine": {"sentry": [["ashigaru", 1]], "patrol": [["ashigaru", 1]], "lookout": [["archer", 1]]},
	"forest": {"sentry": [["ashigaru", 2]], "patrol": [["ashigaru", 2]], "lookout": [["archer", 2]]},
	"village": {"sentry": [["ashigaru", 1]], "patrol": [["ashigaru", 2]], "lookout": [["archer", 2]]},
	"castle": {"sentry": [["ashigaru", 2], ["captain", 2]], "patrol": [["ashigaru", 2]], "lookout": [["archer", 1]]},
	"mountain": {"sentry": [["ashigaru", 1]], "patrol": [["ashigaru", 2]], "lookout": [["archer", 3]]},
	"bamboo": {"sentry": [["ashigaru", 1]], "patrol": [["ashigaru", 1]], "lookout": [["archer", 1]]},
	"ruins": {"sentry": [["ashigaru", 2]], "patrol": [["ashigaru", 1]], "lookout": [["archer", 1]]},
}
const CAMP_ORDER := ["shrine", "forest", "village", "castle", "mountain", "bamboo", "ruins"]
var camps := {}          ## zone -> {"center": Vector3, "route": Array}

func _build_spawn_table() -> void:
	var zones: Dictionary = data.get("zones", {})
	var salt := 0
	for zone in CAMP_ORDER:
		if not zones.has(zone): continue
		var zc := Vector2(float(zones[zone]["x"]), float(zones[zone]["z"]))
		var plan: Dictionary = CAMPS[zone]
		var c := _camp_point(zc, 22.0, 40.0, salt * 31 + 5)
		salt += 1
		var c2 := Vector2(c.x, c.z)
		var route := _camp_route(c2, 16.0, salt)
		camps[zone] = {"center": c, "route": route}
		var counter := {}
		var placed: Array = []
		var group: String = String(zone) + "_camp"
		for role in ["sentry", "patrol", "lookout"]:
			for pair in plan.get(role, []):
				var kind: String = pair[0]
				for i in int(pair[1]):
					var n := int(counter.get(kind, 0))
					counter[kind] = n + 1
					var pos := c
					var yaw := 0.0
					var r: Array = []
					match role:
						"sentry":
							pos = _camp_slot(c2, 2.5, 6.5, placed, salt * 7 + n + (11 if kind == "captain" else 0))
						"lookout":
							pos = _camp_slot(c2, 10.0, 16.0, placed, salt * 13 + n + 3)
						"patrol":
							# patrollers share the loop, each starting at a different waypoint
							var k := (int(counter.get("patrol", 0))) % maxi(route.size(), 1)
							counter["patrol"] = int(counter.get("patrol", 0)) + 2
							r = route.duplicate()
							if not r.is_empty():
								for _j in k: r.push_back(r.pop_front())
								pos = r[0]
					var out := Vector2(pos.x - c.x, pos.z - c.z)
					if out.length() > 0.5: yaw = atan2(out.x, out.y)
					else: yaw = float(salt) * 1.3
					placed.append(Vector2(pos.x, pos.z))
					spawn_table.append({"id": "%s_%s_%d" % [zone, kind, n], "kind": kind, "zone": zone,
						"pos": pos, "boss": false, "group": group, "role": role, "yaw": yaw, "route": r})
	# the boss waits in the courtyard before the keep (v0.14: this was a stale
	# coordinate from an older map, 1 km away in the north-west hills, so the
	# final duel never found him)
	var keep := Vector3(1210, 0, 452)
	if zones.has("castle"):
		keep = Vector3(float(zones["castle"]["x"]), 0.0, float(zones["castle"]["z"]) + 32.0)
	spawn_table.append({"id": "boss_captain", "kind": "captain", "zone": "castle", "pos": keep, "boss": true,
		"group": "keep", "role": "sentry", "yaw": 0.0, "route": []})

func _spot_ok(x: float, z: float) -> bool:
	var size := float(data.get("size", 1536.0))
	if x < 12.0 or z < 12.0 or x > size - 12.0 or z > size - 12.0: return false
	if terrain == null or not terrain.loaded: return true
	if terrain.slope_at(x, z) > 24.0: return false
	if terrain.is_water(x, z) or terrain.water_depth_at(x, z) > 0.2: return false
	return true

func _ground(x: float, z: float) -> Vector3:
	var y := 0.0
	if terrain != null and terrain.loaded: y = terrain.sample_height(x, z)
	return Vector3(x, y, z)

## A flat, dry camp centre between r0 and r1 from the zone centre.
func _camp_point(center: Vector2, r0: float, r1: float, salt: int) -> Vector3:
	var r := RandomNumberGenerator.new()
	r.seed = 1601 + salt
	for attempt in 80:
		var a := r.randf() * TAU
		var d := lerpf(r0, r1, r.randf()) * (1.0 if attempt < 50 else 0.6)
		var x := center.x + cos(a) * d
		var z := center.y + sin(a) * d
		if not _spot_ok(x, z): continue
		# the camp itself wants a few metres of level ground all round
		var good := true
		for k in 4:
			var aa := TAU * float(k) / 4.0
			if not _spot_ok(x + cos(aa) * 5.0, z + sin(aa) * 5.0): good = false
		if good: return _ground(x, z)
	return _find_spawn_point(center, r0, salt)

## A free post between r0 and r1 from the camp centre, 2.5 m from the others.
func _camp_slot(c: Vector2, r0: float, r1: float, placed: Array, salt: int) -> Vector3:
	var r := RandomNumberGenerator.new()
	r.seed = 4409 + salt * 17
	for attempt in 40:
		var a := r.randf() * TAU
		var d := lerpf(r0, r1, r.randf())
		var x := c.x + cos(a) * d
		var z := c.y + sin(a) * d
		if not _spot_ok(x, z): continue
		var clash := false
		for q in placed:
			if Vector2(x, z).distance_to(q) < 2.5: clash = true
		if clash: continue
		return _ground(x, z)
	return _ground(c.x + r0, c.y)

## A patrol loop: up to six waypoints on a ring round the camp, each pulled
## in until it is on dry, walkable ground.
func _camp_route(c: Vector2, radius: float, salt: int) -> Array:
	var out: Array = []
	var n := 5
	var phase := float(salt) * 0.9
	for i in n:
		var a := phase + TAU * float(i) / float(n)
		var rr := radius
		while rr > 6.0:
			var x := c.x + cos(a) * rr
			var z := c.y + sin(a) * rr
			if _spot_ok(x, z):
				out.append(_ground(x, z))
				break
			rr -= 3.0
	return out

## v0.15 fallback picker, bounds fixed for the 1536 m map.
func _find_spawn_point(center: Vector2, min_dist: float, salt: int) -> Vector3:
	var r := RandomNumberGenerator.new()
	r.seed = 777 + salt * 13
	for attempt in 60:
		var a := r.randf() * TAU
		var d := min_dist + r.randf() * 34.0
		var x := center.x + cos(a) * d
		var z := center.y + sin(a) * d
		if not _spot_ok(x, z): continue
		return _ground(x, z)
	var fallback := Vector3(center.x + min_dist, 0, center.y + min_dist)
	if terrain != null and terrain.loaded:
		fallback.y = terrain.sample_height(fallback.x, fallback.z)
	return fallback

func _build_player() -> void:
	player = Player.new()
	player.name = "Kaito"
	add_child(player)
	var zones: Dictionary = data.get("zones", {})
	# v0.14: a new game starts at the foot of the torii steps below the Sakura
	# Shrine, facing up them - where the prologue and chapter one put Kaito
	# (it used to be a hilltop 470 m away). Player forward is +Z.
	var spawn := Vector3(620, 0, 412)
	if Game.checkpoint["pos"] != Vector3.ZERO:
		spawn = Game.checkpoint["pos"]
	if terrain != null and terrain.loaded:
		# never start the player submerged
		var guard := 0
		while terrain.sample_height(spawn.x, spawn.z) < terrain.water_level + 0.6 and guard < 40:
			guard += 1
			var ga := TAU * float(guard) * 0.61803
			spawn = Vector3(spawn.x + cos(ga) * 8.0 * float(guard), 0.0,
				spawn.z + sin(ga) * 8.0 * float(guard))
		spawn.y = terrain.sample_height(spawn.x, spawn.z) + 1.2
	player.global_position = spawn
	camera = PlayerCamera.new()
	camera.name = "PlayerCamera"
	add_child(camera)
	camera.setup(player)
	camera.global_position = spawn + Vector3(0, 2.0, 4.0)
	player.setup(self, camera)
	Game.player_ref = player
	Game.world_ref = self
	player.died.connect(_on_player_died)
	if solids != null:
		solids.player = player
		solids.prime(spawn)
	_build_horse()

## Kaito's horse waits beside him at the start and after fast travel; the
## call_horse key (H) whistles it over from wherever it is.
func _build_horse() -> void:
	horse = Horse.new()
	horse.name = "Horse"
	horse.world = self
	horse.camera = camera
	add_child(horse)
	place_horse_near(player.global_position, player.rotation.y)

func place_horse_near(pp: Vector3, yaw: float) -> void:
	if horse == null: return
	var b := Basis(Vector3.UP, yaw)
	var spot := pp + b.x * 2.8 + b.z * 0.6
	if is_inside_tree() and get_world_3d() != null: spot = _free_spot(spot)
	if terrain != null and terrain.loaded:
		spot.y = terrain.sample_height(spot.x, spot.z) + 0.15
	horse.global_position = spot
	horse.rotation = Vector3(0.0, yaw, 0.0)
	horse.velocity = Vector3.ZERO
	if horse.has_method("set_rider") and horse.rider == null: horse.set_rider(null)

func call_horse() -> void:
	if horse == null or player == null: return
	if player.is_mounted(): return
	var d := horse.global_position.distance_to(player.global_position)
	if d < 4.0:
		Game.notice.emit("Your horse is right here — %s to mount" % Game.bind_label("interact"), "info")
		return
	horse.call_to(player)
	Audio.play_sfx("whistle", null, 1.0, 0.0)
	Game.notice.emit("You whistle for your horse", "info")

## True when the player can mount: close to the horse's flank, not riding,
## and no shrine/quest interaction competing for the same key.
func horse_near(p: Node3D) -> bool:
	if horse == null or p == null or horse.rider != null: return false
	if _prompt != "" and not _prompt.begins_with("Mount"): return false
	var to := horse.global_position - p.global_position
	return Vector2(to.x, to.z).length() < 2.9 and absf(to.y) < 1.6

## Fast travel (pause menu): only to visited provinces and never mid-fight.
func fast_travel(zone: String) -> bool:
	if player == null or not data.has("zones") or not data["zones"].has(zone): return false
	if not Game.visited_zones.has(zone):
		Game.notice.emit("You have not been to %s yet" % Game.ZONE_TITLE.get(zone, zone), "warn")
		return false
	if player.is_in_combat():
		Game.notice.emit("Cannot travel while enemies are hunting you", "warn")
		return false
	if player.is_mounted() and player.has_method("_drop_from_horse"): player._drop_from_horse()
	var z: Dictionary = data["zones"][zone]
	warp_to(Vector3(float(z["x"]), 0.0, float(z["z"])))
	place_horse_near(player.global_position, player.rotation.y)
	if camera != null and camera.has_method("snap"): camera.snap()
	Game.notice.emit("Travelled to %s" % Game.ZONE_TITLE.get(zone, zone), "checkpoint")
	return true

var hitfx: HitFx
var ambience: Ambience

func _build_fx() -> void:
	hitfx = HitFx.new()
	hitfx.name = "HitFx"
	add_child(hitfx)

func _build_ui() -> void:
	hud = load("res://ui/HUD.gd").new()
	hud.name = "HUD"
	add_child(hud)
	hud.bind(self)
	touch = load("res://ui/TouchControls.gd").new()
	touch.name = "Touch"
	add_child(touch)
	touch.bind(self)

func _build_story() -> void:
	story = Story.new()
	story.name = "Story"
	add_child(story)
	story.setup(self)

## v0.14: real petal shapes that only fall where there are sakura. Every half
## second the emitter re-centres on the cherry trees around the player and its
## emission rate follows how many there are; elsewhere it stops and the last
## petals simply land. Lit (not unshaded), so they darken at dusk like the rest.
var _sakura_xz := PackedVector2Array()
var _petal_t := 0.0
var _petal_mat: ParticleProcessMaterial

func _build_petals() -> void:
	var p := Perf.preset()
	var amount := int(p["petals"])
	if amount <= 0: return
	for tr in data.get("trees", []):
		if str(tr.get("kind", "")) == "sakura":
			_sakura_xz.append(Vector2(float(tr.get("x", 0.0)), float(tr.get("z", 0.0))))
	petals = GPUParticles3D.new()
	petals.name = "Petals"
	petals.amount = amount
	petals.amount_ratio = 0.0
	petals.lifetime = 11.0
	petals.preprocess = 4.0
	petals.local_coords = false
	petals.visibility_aabb = AABB(Vector3(-80, -30, -80), Vector3(160, 50, 160))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(10, 1.5, 10)
	mat.direction = Vector3(0.3, -1, 0.15)
	mat.spread = 35.0
	mat.initial_velocity_min = 0.2
	mat.initial_velocity_max = 0.7
	mat.gravity = Vector3(0.45, -0.55, 0.25)
	# flutter: turbulence makes them drift and swirl instead of falling straight
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 1.6
	mat.turbulence_noise_scale = 3.5
	mat.turbulence_noise_speed_random = 0.4
	mat.turbulence_influence_min = 0.06
	mat.turbulence_influence_max = 0.16
	mat.damping_min = 0.2
	mat.damping_max = 0.6
	mat.angle_min = -180.0
	mat.angle_max = 180.0
	mat.angular_velocity_min = -90.0
	mat.angular_velocity_max = 90.0
	mat.scale_min = 0.75
	mat.scale_max = 1.25
	mat.color = Color(1.0, 1.0, 1.0)
	var hue := Gradient.new()
	hue.set_color(0, Color(1.0, 0.97, 0.98))
	hue.set_color(1, Color(0.97, 0.88, 0.92))
	var ht := GradientTexture1D.new()
	ht.gradient = hue
	mat.color_initial_ramp = ht
	_petal_mat = mat
	petals.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.055, 0.065)
	var qmat := StandardMaterial3D.new()
	qmat.albedo_texture = load("res://assets/textures/foliage/petal.png")
	qmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	qmat.alpha_scissor_threshold = 0.45
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qmat.vertex_color_use_as_albedo = true
	qmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	qmat.roughness = 0.75
	# thin petals glow a little when the sun is behind them
	qmat.backlight_enabled = true
	qmat.backlight = Color(0.55, 0.38, 0.42)
	quad.material = qmat
	petals.draw_pass_1 = quad
	petals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(petals)
	_update_petals(1.0)

func _update_petals(delta: float) -> void:
	if petals == null or player == null: return
	_petal_t -= delta
	if _petal_t > 0.0: return
	_petal_t = 0.5
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var sum := Vector2.ZERO
	var lo := Vector2(INF, INF)
	var hi := -lo
	var n := 0
	for q in _sakura_xz:
		if q.distance_squared_to(pp) < 3025.0:      # 55 m
			sum += q
			lo = lo.min(q)
			hi = hi.max(q)
			n += 1
	if n == 0:
		petals.amount_ratio = 0.0
		return
	var c := sum / float(n)
	var ext := ((hi - lo) * 0.5 + Vector2(5, 5)).min(Vector2(45, 45))
	var gy := player.global_position.y
	if terrain != null and terrain.loaded: gy = terrain.sample_height(c.x, c.y)
	petals.global_position = Vector3(c.x, gy + 5.0, c.y)
	_petal_mat.emission_box_extents = Vector3(ext.x, 1.6, ext.y)
	if weather != null:
		var w: Vector3 = weather.wind_vector()
		_petal_mat.gravity = Vector3(w.x * 0.9, -0.55, w.z * 0.9)
	petals.amount_ratio = clampf(float(n) / 8.0, 0.2, 1.0)

func _build_wildlife() -> void:
	wild = Wildlife.new()
	wild.name = "Wildlife"
	add_child(wild)
	wild.setup(terrain, player)

# ------------------------------------------------------------------ runtime
func _process(delta: float) -> void:
	if not loaded: return
	_t += delta
	_update_day_night(delta)
	_update_zone()
	_update_enemies(delta)
	_update_fox()
	_update_triggers(delta)
	_update_beacon(delta)
	_update_lanterns()
	_update_petals(delta)

func _update_day_night(delta: float) -> void:
	if daynight == null: return
	daynight.advance(delta)
	daynight.apply()
	time_of_day = daynight.hour

## Harness / gameplay hook: jump the clock and settle lighting immediately.
func set_time_of_day(h: float) -> void:
	time_of_day = fposmod(h, 24.0)
	if daynight != null:
		daynight.set_hour(time_of_day, true)
		if weather != null: weather._apply()

func set_weather(name: String, instant := false) -> void:
	if weather != null:
		weather.auto = false
		weather.set_weather(name, instant)

func weather_name() -> String:
	return weather.describe() if weather != null else "clear"

func wind_vector() -> Vector3:
	return weather.wind_vector() if weather != null else Vector3.ZERO

## Surface under a world point, used for footsteps and traversal feel.
func surface_at(x: float, z: float) -> String:
	return terrain.surface_at(x, z) if terrain != null and terrain.loaded else "grass"

## 0..1 loudness of running water around a point, for the ambience layer.
## The main river's bank field reaches 12 m past the banks; a ring of probes
## carries it to ~40 m, fading with distance. Waterfalls have their own
## positional roar (WaterSystem), so this is just the burble of the channel.
func water_proximity(pos: Vector3) -> float:
	if terrain == null or not terrain.loaded: return 0.0
	var best: float = terrain.river_prox_at(pos.x, pos.z)
	if best < 0.99:
		for r in [8.0, 16.0, 26.0]:
			var fall: float = 1.0 - r / 38.0
			if best >= fall: break
			for i in 8:
				var a := TAU * (float(i) + 0.5 * float(r == 16.0)) / 8.0
				var p: float = terrain.river_prox_at(pos.x + cos(a) * r, pos.z + sin(a) * r)
				if p > 0.0: best = maxf(best, p * fall)
	# the old streams are narrower and quieter
	if best < 0.5 and terrain.river_at(pos.x, pos.z) > 0.2: best = 0.5
	return clampf(best, 0.0, 1.0)

## Reposition the player and immediately settle the streamed world around them.
## Teleport the player. Landmark buildings sit exactly on their zone markers,
## so warping to a checkpoint used to drop the player inside solid geometry (the
## castle keep in particular). Spiral outwards until the capsule actually fits.
func warp_to(pos: Vector3) -> void:
	if player == null: return
	# Stream nearby trunks/boulders in first, otherwise _free_spot tests a
	# location whose collision has not been built yet.
	if solids != null: solids.prime(pos)
	var p := _free_spot(pos)
	if terrain != null and terrain.loaded:
		p.y = terrain.sample_height(p.x, p.z) + 1.2
	player.global_position = p
	if player is CharacterBody3D: player.velocity = Vector3.ZERO
	if terrain != null: terrain._refresh_lod(p, 9999)
	if foliage != null: foliage.prime(p)
	if solids != null: solids.prime(p)

## Nearest point around `pos` where a 0.45 m radius / 1.9 m tall capsule is
## clear of world geometry. Samples the marker first, then rings at 3, 6, 10,
## 15 and 22 m, eight directions each.
func _free_spot(pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.45
	shape.height = 1.9
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.collide_with_areas = false
	for ring in [0.0, 3.0, 6.0, 10.0, 15.0, 22.0]:
		var steps := 1 if ring <= 0.01 else 8
		for i in steps:
			var a := TAU * float(i) / float(steps)
			var c := Vector3(pos.x + cos(a) * ring, 0.0, pos.z + sin(a) * ring)
			if terrain != null and terrain.loaded:
				if terrain.sample_height(c.x, c.z) < terrain.water_level + 0.2: continue
				c.y = terrain.sample_height(c.x, c.z) + 1.15
			else:
				c.y = pos.y
			q.transform = Transform3D(Basis.IDENTITY, c)
			if space.intersect_shape(q, 1).is_empty():
				return c
	return pos

func _build_ambience() -> void:
	ambience = Ambience.new()
	ambience.name = "Ambience"
	ambience.setup(self, player, terrain)
	add_child(ambience)

func env_stats() -> Dictionary:
	var out := {}
	if foliage != null: out["grass"] = foliage.stats()
	if tree_system != null: out["trees"] = tree_system.stats()
	if water != null: out["water"] = water.stats()
	out["weather"] = weather_name()
	out["hour"] = snappedf(time_of_day, 0.1)
	return out

func _update_zone() -> void:
	if player == null or terrain == null: return
	var z := terrain.zone_at(player.global_position.x, player.global_position.z)
	if z != _zone:
		_zone = z
		Game.set_zone(z)
		zone_entered.emit(z)

func _update_enemies(delta: float) -> void:
	if player == null: return
	var pp := player.global_position
	var budget := 2
	for s in spawn_table:
		if budget <= 0: break
		var id := String(s["id"])
		if _live_ids.has(id): continue
		if Game.is_defeated(id): continue
		if Vector3(s["pos"]).distance_to(pp) > SPAWN_RADIUS: continue
		if _spawn_enemy(s) != null: budget -= 1
	# free enemies that died long ago, or that the player left far behind
	for i in range(enemies.size() - 1, -1, -1):
		var e = enemies[i]
		if not is_instance_valid(e):
			enemies.remove_at(i); continue
		if e.is_dead and e.death_timer > 4.0:
			_live_ids.erase(e.spawn_id)
			e.queue_free(); enemies.remove_at(i); continue
		if e.global_position.distance_to(pp) > DESPAWN_RADIUS and not e.in_combat:
			_live_ids.erase(e.spawn_id)
			e.queue_free(); enemies.remove_at(i)

func _spawn_enemy(s: Dictionary) -> Node3D:
	var sid := String(s["id"])
	if Game.is_defeated(sid): return null
	if _live_ids.has(sid): return null
	var node: Node3D = null
	match String(s["kind"]):
		"ashigaru": node = Ashigaru.new()
		"archer": node = Archer.new()
		"captain": node = Captain.new()
		_: node = Ashigaru.new()
	node.name = "Enemy_" + String(s["id"])
	node.spawn_id = String(s["id"])
	node.zone = String(s["zone"])
	node.is_boss = bool(s.get("boss", false))
	node.group = String(s.get("group", ""))
	node.post_yaw = float(s.get("yaw", 0.0))
	node.rotation.y = node.post_yaw
	var rt: Array = s.get("route", [])
	node.route = rt.duplicate()
	add_child(node)
	var pos: Vector3 = s["pos"]
	# a post inside a hut wall or a boulder: the nearest clear spot instead
	if not bool(s.get("test", false)) and is_inside_tree():
		var fs := _free_spot(pos + Vector3(0, 1.15, 0))
		pos.x = fs.x; pos.z = fs.z
	if terrain != null and terrain.loaded:
		pos.y = terrain.sample_height(pos.x, pos.z) + 0.1
	node.global_position = pos
	node.setup(self, player)
	node.died.connect(_on_enemy_died.bind(node))
	enemies.append(node)
	_live_ids[sid] = true
	if node.is_boss: boss = node
	return node

func enemies_in_combat() -> int:
	var n := 0
	for e in enemies:
		if is_instance_valid(e) and e.in_combat and not e.is_dead: n += 1
	return n

func _on_enemy_died(kind: String, zone: String, node = null) -> void:
	var was_boss := kind == "captain" and zone == "castle"
	if node != null and is_instance_valid(node):
		Game.mark_defeated(String(node.spawn_id))
		was_boss = bool(node.is_boss)
		# v0.16 kills earn mastery: a soldier 1, a captain 3, Kuroda 5
		if not node.has_meta("test"):
			Game.add_xp(5 if was_boss else (3 if kind == "captain" else 1))
		# Spirit Mending: every kill near you heals
		if Skills.has("p_mend") and player != null and node.global_position.distance_to(player.global_position) < 30.0:
			player.heal(6.0)
	enemy_died.emit(kind, zone)
	Quests.progress("kill", zone, 1)
	if was_boss:
		boss_downed.emit()
		Quests.progress("boss", "captain", 1)
		Game.boss_defeated = true
func _on_player_died() -> void:
	Game.notice.emit("You fall... returning to the last checkpoint", "death")
	await get_tree().create_timer(2.2).timeout
	respawn()

func respawn() -> void:
	var pos: Vector3 = Game.checkpoint["pos"]
	if pos == Vector3.ZERO and data.has("zones"):
		var z: Dictionary = data["zones"].get("shrine", {"x": 240, "z": 268})
		pos = Vector3(float(z["x"]), 0, float(z["z"]))
	# Route the respawn through warp_to. Some zone markers (the lake in
	# particular) sit at or below the water line, so respawning straight onto the
	# marker dropped the player under the surface with the camera inside the
	# water volume; _free_spot() rejects submerged and blocked spots.
	warp_to(pos)
	player.revive()
	Game.hp = Game.max_hp
	Game.posture = 0.0
	Game.refill_gourd()
	Game.notice.emit("Checkpoint restored", "checkpoint")

func rest_here() -> void:
	Game.refill_gourd()
	if player != null: player.heal(player.max_hp)
	Audio.play_sfx("heal", null, 1.0, 0.0)
	Game.save_game()
	Game.notice.emit("Rested — health restored, gourd refilled (%d/%d)" % [Game.gourd, Game.gourd_max], "checkpoint")

func _update_triggers(delta: float) -> void:
	if player == null: return
	var pp := player.global_position
	var best_prompt := ""
	var best_d := 1e9
	for m in markers:
		var d: float = Vector3(m["pos"]).distance_to(pp)
		if m["kind"] == "zone":
			if d < float(m["radius"]) and not m["used"]:
				m["used"] = true
				# v0.14: chapters start from the story, not from wandering
				# into a zone (that used to stack several quests at once)
				if story == null: Quests.start_next()
				Game.tutorial_done = true
			continue
		if m["kind"] == "reach" and d < float(m["radius"]) and not m["used"]:
			m["used"] = true
			Quests.progress("reach", String(m["id"]), 1)
			Game.add_xp(1)
			Audio.play_sfx("quest", null, 1.0, -6.0)
		if d < INTERACT_RADIUS and d < best_d and not m["used"]:
			best_d = d
			best_prompt = "Interact — %s" % String(m["id"]).replace("_", " ")
	if best_prompt == "" and horse != null and not player.is_mounted() and horse.rider == null:
		var hd := horse.global_position - pp
		if Vector2(hd.x, hd.z).length() < 2.9 and absf(hd.y) < 1.6:
			best_prompt = "Mount horse — %s" % Game.bind_label("interact")
	if Game.cinematic: best_prompt = ""
	if best_prompt != "" and not best_prompt.begins_with("Mount") and Input.is_action_just_pressed("interact"):
		for m in markers:
			if Vector3(m["pos"]).distance_to(pp) < INTERACT_RADIUS and not m["used"]:
				m["used"] = true
				Quests.progress("interact", String(m["id"]), 1)
				Game.add_xp(1)
				Audio.play_sfx("quest", null, 1.0, -6.0)
				break
	# checkpoints
	for c in checkpoints:
		if not c["used"] and Vector3(c["pos"]).distance_to(pp) < ZONE_RADIUS:
			c["used"] = true
			var p: Vector3 = c["pos"]
			if terrain != null and terrain.loaded: p.y = terrain.sample_height(p.x, p.z) + 1.2
			Game.set_checkpoint(_zone, p)
			# v0.15: a new checkpoint is a place to rest, so it refills the gourd
			if Game.refill_gourd() > 0:
				Game.notice.emit("Gourd refilled", "reward")
			Game.save_game()
	# hidden rewards
	for i in range(rewards.size() - 1, -1, -1):
		var r: Vector3 = rewards[i]
		if Vector3(r.x, pp.y, r.z).distance_to(pp) < 5.0:
			rewards.remove_at(i)
			Game.add_xp(2)
			Game.heal_player(25.0)
			Game.refill_gourd(1)
			Audio.play_sfx("discover", null, 1.0, 0.0)
			Game.notice.emit("Hidden cache found — +2 mastery, +25 health, +1 gourd", "reward")
	# v0.15 hunting: a carcass at your feet can be harvested for meat
	if best_prompt == "" and wild != null and not player.is_mounted() and not Game.cinematic:
		var carcass: WildAnimal = wild.carcass_near(pp, 2.8)
		if carcass != null:
			best_prompt = "%s — %s" % [wild.harvest_label(carcass), Game.bind_label("interact")]
			if Input.is_action_just_pressed("interact"):
				wild.harvest(carcass)
				best_prompt = ""
	# v0.15 resting: any checkpoint you have reached is a place to rest. Resting
	# refills the gourd and the health bar and saves.
	if best_prompt == "" and not player.is_mounted() and not Game.in_combat and not Game.cinematic:
		var need_rest := Game.gourd < Game.gourd_max or player.hp < player.max_hp - 1.0
		if need_rest:
			for c in checkpoints:
				if bool(c["used"]) and Vector2(Vector3(c["pos"]).x - pp.x, Vector3(c["pos"]).z - pp.z).length() < 9.0:
					best_prompt = "Rest — heal and refill gourd  %s" % Game.bind_label("interact")
					if Input.is_action_just_pressed("interact"):
						rest_here()
						best_prompt = ""
					break
	if best_prompt != _prompt:
		_prompt = best_prompt
		prompt_changed.emit(_prompt)

func _update_lanterns() -> void:
	if player == null: return
	var night := time_of_day < 6.5 or time_of_day > 18.5
	var budget := int(Perf.preset()["lights"])
	var sorted := lanterns.duplicate()
	var pp := player.global_position
	sorted.sort_custom(func(a, b): return a.global_position.distance_to(pp) < b.global_position.distance_to(pp))
	for i in sorted.size():
		var l: OmniLight3D = sorted[i]
		l.visible = night and i < budget and l.global_position.distance_to(pp) < 45.0

# ------------------------------------------------------------------ objective beacon
## World position of the current objective (Vector3) or null.
func objective_position() -> Variant:
	var o: Dictionary = Quests.current_objective()
	if o.is_empty(): return null
	var zones: Dictionary = data.get("zones", {})
	var typ := String(o["type"])
	var tgt := String(o["target"])
	if typ == "deflect": return null
	if (typ == "reach" or typ == "interact") and QUEST_SPOTS.has(tgt): return QUEST_SPOTS[tgt]
	if typ == "boss":
		for e in enemies:
			if is_instance_valid(e) and not e.is_dead and bool(e.get("is_boss")): return e.global_position
	var z := tgt if zones.has(tgt) else String(o["zone"])
	if typ == "kill" and tgt == "": return null
	if zones.has(z): return Vector3(float(zones[z]["x"]), 0.0, float(zones[z]["z"]))
	return null

var _beacon: MeshInstance3D = null
var _beacon_t := 0.0

## A soft gold light pillar over the objective, visible from far away and gone
## once you are close (quest spots used to be invisible trigger spheres).
func _update_beacon(delta: float) -> void:
	_beacon_t -= delta
	if _beacon_t > 0.0 or player == null: return
	_beacon_t = 0.25
	var pos = objective_position()
	if _beacon == null:
		_beacon = MeshInstance3D.new()
		_beacon.name = "ObjectiveBeacon"
		var cm := CylinderMesh.new()
		cm.top_radius = 0.9
		cm.bottom_radius = 0.9
		cm.height = 90.0
		cm.radial_segments = 12
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		_beacon.mesh = cm
		var sh := Shader.new()
		sh.code = BEACON_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		_beacon.material_override = m
		_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_beacon)
	if pos == null:
		_beacon.visible = false
		return
	var p: Vector3 = pos
	var d := Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length()
	# no gameplay marker in the middle of a cinematic shot
	_beacon.visible = d > 18.0 and not Game.cinematic
	if terrain != null and terrain.loaded: p.y = terrain.sample_height(p.x, p.z)
	_beacon.global_position = p + Vector3(0, 44.0, 0)
	(_beacon.material_override as ShaderMaterial).set_shader_parameter("fade", clampf((d - 18.0) / 25.0, 0.0, 1.0))

const BEACON_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform float fade = 1.0;
varying float v_h;
void vertex() { v_h = VERTEX.y / 90.0 + 0.5; }
void fragment() {
	float edge = abs(dot(NORMAL, VIEW));
	float core = pow(edge, 3.0);
	float vert = pow(1.0 - v_h, 1.6) * smoothstep(0.0, 0.03, v_h);
	float pulse = 0.85 + 0.15 * sin(TIME * 2.2 - v_h * 9.0);
	ALBEDO = vec3(1.0, 0.78, 0.38) * (0.35 + core * 0.9);
	ALPHA = clamp(core * vert * pulse * fade * 0.55, 0.0, 1.0);
}
"""

# ------------------------------------------------------------------ helpers
func current_prompt() -> String:
	return _prompt

func zone_name() -> String:
	return _zone

var _test_id_counter := 0

func spawn_enemy_at(kind: String, pos: Vector3, id: String = "", is_boss := false) -> Node3D:
	_test_id_counter += 1
	var s := {"id": id if id != "" else "test_%d" % _test_id_counter, "kind": kind,
		"zone": _zone, "pos": pos, "boss": is_boss, "test": true}
	var n := _spawn_enemy(s)
	if n != null: n.set_meta("test", true)
	return n

# ================================================================ v0.16 alarms & spirits
const SHOUT_GROUP := 34.0      ## a camp hears its own alarm this far
const SHOUT_NEAR := 14.0       ## anyone this close joins in, camp or not
const SHOUT_HEAR := 24.0       ## further than that, others come to look
const WITNESS_RANGE := 16.0

## A soldier raised the alarm at `pos`: his camp joins the fight, anyone else
## close by does too, and further off they come and look.
func alert_allies(src: Node, pos: Vector3) -> void:
	if src == null or not is_instance_valid(src): return
	var sp: Vector3 = (src as Node3D).global_position
	var grp := String(src.get("group"))
	for e in enemies:
		if e == src or not is_instance_valid(e) or e.is_dead or e.in_combat: continue
		var d: float = e.global_position.distance_to(sp)
		var same := grp != "" and String(e.group) == grp
		if (same and d < SHOUT_GROUP) or d < SHOUT_NEAR:
			e.ally_alert(pos)
		elif d < SHOUT_HEAR:
			e.hear_noise(pos, 0.9)

## Someone was assassinated: whoever has the body in view gets suspicious
## (close and looking straight at it: the alarm).
func witness(victim: Node) -> void:
	if victim == null or not is_instance_valid(victim): return
	var vp: Vector3 = (victim as Node3D).global_position
	var space := get_world_3d().direct_space_state
	for e in enemies:
		if e == victim or not is_instance_valid(e) or e.is_dead or e.in_combat: continue
		if e.is_blind(): continue
		var d: float = e.global_position.distance_to(vp)
		if d > WITNESS_RANGE: continue
		if e._angle_to(vp) > EnemyBase.PERIPH_HALF: continue
		var q := PhysicsRayQueryParameters3D.create(e.global_position + Vector3(0, 1.6, 0), vp + Vector3(0, 1.0, 0), 1)
		q.exclude = [e.get_rid()]
		if not space.intersect_ray(q).is_empty(): continue
		if d < 7.0 and e._angle_to(vp) < EnemyBase.SIGHT_HALF:
			e.ally_alert(vp)
		else:
			e.hear_noise(vp, 0.8)

## Something loud at pos (other than the player's own noise, which enemies
## poll through Player.noise_radius): an explosion, a falling body.
func make_noise(pos: Vector3, radius: float, loud := 0.6) -> void:
	for e in enemies:
		if not is_instance_valid(e) or e.is_dead or e.in_combat: continue
		if e.global_position.distance_to(pos) < radius: e.hear_noise(pos, loud)

# ---------------------------------------------------------------- spirit fox
var fox: Node3D = null

func _update_fox() -> void:
	var want := Skills.has("p_fox") and player != null
	if want and (fox == null or not is_instance_valid(fox)):
		fox = SpiritFox.new()
		fox.name = "SpiritFox"
		add_child(fox)
		fox.setup(self, player)
	elif not want and fox != null and is_instance_valid(fox):
		fox.queue_free()
		fox = null
