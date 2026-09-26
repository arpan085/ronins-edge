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
var sky_mat: ProceduralSkyMaterial
var petals: GPUParticles3D
var water: MeshInstance3D
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
var wildlife: Array = []
var _prompt := ""
var _zone := "shrine"
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var boss: Node = null
var loaded := false

func _ready() -> void:
	_rng.seed = 20260926
	_load_data()
	_build_terrain()
	_build_environment()
	_build_water()
	_build_props()
	_build_landmarks()
	_build_markers()
	_build_spawn_table()
	_build_player()
	_build_fx()
	_build_ui()
	_build_petals()
	_build_wildlife()
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
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.45, 0.72)
	sky_mat.sky_horizon_color = Color(0.72, 0.70, 0.62)
	sky_mat.ground_bottom_color = Color(0.18, 0.17, 0.15)
	sky_mat.ground_horizon_color = Color(0.60, 0.58, 0.52)
	sky_mat.sun_angle_max = 12.0
	sky_mat.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_white = 6.0
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_density = 0.0016
	e.fog_light_color = Color(0.66, 0.70, 0.72)
	e.fog_aerial_perspective = 0.4
	e.fog_sky_affect = 0.35
	e.glow_enabled = true
	e.glow_intensity = 0.35
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 1.1
	e.ssao_enabled = false
	e.ssao_radius = 1.2
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.04
	e.adjustment_contrast = 1.03
	world_env.environment = e
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.add_to_group("sun")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias = 0.06
	sun.light_energy = 1.25
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = false
	moon.light_energy = 0.0
	moon.light_color = Color(0.55, 0.65, 0.95)
	add_child(moon)

func _build_water() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(float(data.get("size", 480.0)) + 40.0, float(data.get("size", 480.0)) + 40.0)
	water = MeshInstance3D.new()
	water.name = "Water"
	water.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("ripple_n", load("res://assets/textures/metal_n.png"))
	water.material_override = mat
	water.position = Vector3(float(data.get("size", 480.0)) * 0.5, float(data.get("water_level", 2.6)), float(data.get("size", 480.0)) * 0.5)
	add_child(water)

func _prop_mesh(name: String) -> Mesh:
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
	if sway > 0.0 or tint != null:
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/foliage.gdshader")
		m.set_shader_parameter("tint", tint if tint != null else Color(1, 1, 1))
		m.set_shader_parameter("sway", sway)
		m.set_shader_parameter("sway_speed", 0.8 + sway * 0.4)
		m.set_shader_parameter("base_tex", load("res://assets/textures/terrain_c.png"))
		mi.material_override = m
	return mi

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
			if kind == "castle_keep":
				var coll := StaticBody3D.new()
				var cs := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3(16, 14, 14) * s
				cs.shape = box
				cs.position = Vector3(0, 7 * s, 0)
				coll.add_child(cs)
				holder.add_child(coll)

func _build_markers() -> void:
	var zones: Dictionary = data.get("zones", {})
	for k in zones.keys():
		var z: Dictionary = zones[k]
		_marker(String(k), Vector3(float(z["x"]), 0, float(z["z"])), ZONE_RADIUS, "zone", "Enter %s" % Game.ZONE_TITLE.get(k, k))
		_checkpoint(Vector3(float(z["x"]), 0, float(z["z"])))
	var named := {
		"forest_marker": Vector3(90, 0, 250), "castle_gate": Vector3(250, 0, 124),
		"watchtower": Vector3(120, 0, 125), "well": Vector3(376, 0, 245),
		"shrine_hall": Vector3(240, 0, 262),
	}
	for id in named.keys():
		var p: Vector3 = named[id]
		_marker(id, p, 7.0, "reach", "Reach %s" % id.replace("_", " "))
	# hidden exploration rewards along the secret paths
	var hidden: Array = data.get("hidden_paths", [])
	for hp in hidden:
		for pt in hp.get("points", []):
			rewards.append(Vector3(float(pt[0]), 0, float(pt[1])))

func _marker(id: String, pos: Vector3, radius: float, kind: String, prompt: String) -> void:
	markers.append({"id": id, "pos": pos, "radius": radius, "kind": kind, "prompt": prompt, "used": false})

func _checkpoint(pos: Vector3) -> void:
	checkpoints.append({"pos": pos, "used": false})

func _build_spawn_table() -> void:
	var plan := {
		"shrine": [["ashigaru", 2], ["archer", 1]],
		"forest": [["ashigaru", 4], ["archer", 2]],
		"village": [["ashigaru", 3], ["archer", 2]],
		"castle": [["ashigaru", 4], ["captain", 2], ["archer", 1]],
		"mountain": [["archer", 3], ["ashigaru", 3]],
	}
	var zones: Dictionary = data.get("zones", {})
	var idx := 0
	for zone in plan.keys():
		if not zones.has(zone): continue
		var c := Vector2(float(zones[zone]["x"]), float(zones[zone]["z"]))
		for pair in plan[zone]:
			var kind: String = pair[0]
			for i in int(pair[1]):
				var pos := _find_spawn_point(c, 16.0 + float(i) * 5.0, idx)
				idx += 1
				spawn_table.append({"id": "%s_%s_%d" % [zone, kind, i], "kind": kind,
					"zone": zone, "pos": pos, "boss": false})
	# the boss waits inside the keep
	var keep := Vector3(250, 0, 84)
	spawn_table.append({"id": "boss_captain", "kind": "captain", "zone": "castle", "pos": keep, "boss": true})

func _find_spawn_point(center: Vector2, min_dist: float, salt: int) -> Vector3:
	var r := RandomNumberGenerator.new()
	r.seed = 777 + salt * 13
	for attempt in 60:
		var a := r.randf() * TAU
		var d := min_dist + r.randf() * 34.0
		var x := center.x + cos(a) * d
		var z := center.y + sin(a) * d
		if x < 8.0 or z < 8.0 or x > 472.0 or z > 472.0: continue
		if terrain == null or not terrain.loaded: return Vector3(x, 0, z)
		if terrain.slope_at(x, z) > 26.0: continue
		if terrain.is_water(x, z): continue
		return Vector3(x, terrain.sample_height(x, z), z)
	var fallback := Vector3(center.x + min_dist, 0, center.y + min_dist)
	if terrain != null and terrain.loaded:
		fallback.y = terrain.sample_height(fallback.x, fallback.z)
	return fallback

func _build_player() -> void:
	player = Player.new()
	player.name = "Kaito"
	add_child(player)
	var zones: Dictionary = data.get("zones", {})
	var spawn := Vector3(240, 0, 268)
	if Game.checkpoint["pos"] != Vector3.ZERO:
		spawn = Game.checkpoint["pos"]
	if terrain != null and terrain.loaded:
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

var hitfx: HitFx

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

func _build_petals() -> void:
	var p := Perf.preset()
	var amount := int(p["petals"])
	if amount <= 0: return
	petals = GPUParticles3D.new()
	petals.name = "Petals"
	petals.amount = amount
	petals.lifetime = 9.0
	petals.preprocess = 2.0
	petals.local_coords = false
	petals.visibility_aabb = AABB(Vector3(-90, -20, -90), Vector3(180, 60, 180))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(70, 6, 70)
	mat.direction = Vector3(0.2, -1, 0.1)
	mat.spread = 25.0
	mat.initial_velocity_min = 0.6
	mat.initial_velocity_max = 1.8
	mat.gravity = Vector3(0.35, -0.9, 0.2)
	mat.angular_velocity_min = -60.0
	mat.angular_velocity_max = 60.0
	mat.scale_min = 0.35
	mat.scale_max = 0.85
	mat.color = Color(0.95, 0.72, 0.80)
	petals.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.13)
	var qmat := StandardMaterial3D.new()
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qmat.albedo_color = Color(0.98, 0.76, 0.84, 0.9)
	qmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = qmat
	petals.draw_pass_1 = quad
	add_child(petals)

func _build_wildlife() -> void:
	var kinds := ["fox", "deer", "bird"]
	for i in 6:
		var w := Node3D.new()
		w.name = "Wild_%d" % i
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, 0.5, 0.35) if kinds[i % 3] == "fox" else Vector3(1.1, 1.0, 0.5)
		body.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.55, 0.30, 0.16) if kinds[i % 3] == "fox" else Color(0.42, 0.34, 0.24)
		body.material_override = m
		body.position.y = 0.5
		w.add_child(body)
		var start := Vector3(_rng.randf_range(40, 440), 0, _rng.randf_range(40, 440))
		if terrain != null and terrain.loaded:
			start.y = terrain.sample_height(start.x, start.z)
		w.position = start
		w.set_meta("dir", _rng.randf() * TAU)
		w.set_meta("speed", 0.6 + _rng.randf() * 0.8)
		add_child(w)
		wildlife.append(w)

# ------------------------------------------------------------------ runtime
func _process(delta: float) -> void:
	if not loaded: return
	_t += delta
	_update_day_night(delta)
	_update_zone()
	_update_enemies(delta)
	_update_triggers(delta)
	_update_lanterns()
	_update_wildlife(delta)
	if petals != null and player != null:
		petals.global_position = player.global_position + Vector3(0, 8, 0)

func _update_day_night(delta: float) -> void:
	time_of_day += delta * (24.0 / (day_minutes * 60.0))
	if time_of_day >= 24.0: time_of_day -= 24.0
	var t := time_of_day
	var sun_angle := (t - 6.0) / 12.0 * PI     # 6h sunrise, 18h sunset
	var elev := sin(sun_angle)
	sun.rotation_degrees = Vector3(-rad_to_deg(sun_angle) + 90.0, 35.0, 0.0)
	moon.rotation_degrees = Vector3(-rad_to_deg(sun_angle) + 270.0, -20.0, 0.0)
	var day := clampf(elev, 0.0, 1.0)
	var night := clampf(-elev * 2.0, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(elev) * 3.5, 0.0, 1.0)
	sun.light_energy = maxf(0.0, day * 1.45)
	sun.light_color = Color(1.0, 0.97, 0.90).lerp(Color(1.0, 0.66, 0.38), dusk)
	moon.light_energy = night * 0.22
	sky_mat.sky_top_color = Color(0.06, 0.10, 0.22).lerp(Color(0.30, 0.46, 0.74), day).lerp(Color(0.42, 0.26, 0.30), dusk * 0.7)
	sky_mat.sky_horizon_color = Color(0.10, 0.12, 0.20).lerp(Color(0.74, 0.72, 0.64), day).lerp(Color(0.92, 0.48, 0.26), dusk)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color * 0.7
	var e: Environment = world_env.environment
	e.ambient_light_energy = lerpf(0.22, 1.0, day) + dusk * 0.15
	e.fog_light_color = sky_mat.sky_horizon_color.lerp(Color(0.6, 0.65, 0.7), 0.35)
	e.fog_density = (0.0026 if t < 6.0 or t > 19.0 else 0.0016) * float(Perf.preset()["fog"])
	e.fog_aerial_perspective = 0.4

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
	add_child(node)
	var pos: Vector3 = s["pos"]
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
	if node != null and is_instance_valid(node):
		Game.mark_defeated(String(node.spawn_id))
	enemy_died.emit(kind, zone)
	Quests.progress("kill", zone, 1)
	if kind == "captain" and zone == "castle":
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
	if terrain != null and terrain.loaded:
		pos.y = terrain.sample_height(pos.x, pos.z) + 1.2
	player.global_position = pos
	player.revive()
	Game.hp = Game.max_hp
	Game.posture = 0.0
	Game.notice.emit("Checkpoint restored", "checkpoint")

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
				Quests.start_next()
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
	if best_prompt != "" and Input.is_action_just_pressed("interact"):
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
			Game.save_game()
	# hidden rewards
	for i in range(rewards.size() - 1, -1, -1):
		var r: Vector3 = rewards[i]
		if Vector3(r.x, pp.y, r.z).distance_to(pp) < 5.0:
			rewards.remove_at(i)
			Game.add_xp(2)
			Game.heal_player(15.0)
			Audio.play_sfx("heal", null, 1.0, -4.0)
			Game.notice.emit("Hidden cache found — +2 mastery, restored health", "reward")
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

func _update_wildlife(delta: float) -> void:
	for w in wildlife:
		var dir: float = w.get_meta("dir")
		var spd: float = w.get_meta("speed")
		dir += _rng.randf_range(-0.4, 0.4) * delta
		w.set_meta("dir", dir)
		var np: Vector3 = w.global_position + Vector3(cos(dir), 0, sin(dir)) * spd * delta
		if np.x < 10 or np.x > 470 or np.z < 10 or np.z > 470: dir += PI
		if terrain != null and terrain.loaded:
			np.y = terrain.sample_height(np.x, np.z)
		w.global_position = np
		w.rotation.y = -dir
		w.set_meta("dir", dir)

# ------------------------------------------------------------------ helpers
func current_prompt() -> String:
	return _prompt

func zone_name() -> String:
	return _zone

var _test_id_counter := 0

func spawn_enemy_at(kind: String, pos: Vector3, id: String = "", is_boss := false) -> Node3D:
	_test_id_counter += 1
	var s := {"id": id if id != "" else "test_%d" % _test_id_counter, "kind": kind,
		"zone": _zone, "pos": pos, "boss": is_boss}
	return _spawn_enemy(s)
