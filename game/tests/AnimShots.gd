extends Node3D
## Renders a contact sheet of real frames from the running game so the
## animation can be inspected visually, not just numerically.

var player: Player
var enemies: Array = []
var cam: Camera3D
var shots: Array = []
var idx := -1
var t := 0.0
var saved := 0

func _ready() -> void:
	process_physics_priority = 500
	get_viewport().get_window().size = Vector2i(1280, 720)
	_ground()
	_chars()
	shots = [
		{"n": "01_idle", "t": 1.6, "mv": Vector2.ZERO},
		{"n": "02_walk", "t": 1.4, "mv": Vector2(0, -0.40)},
		{"n": "03_jog", "t": 1.4, "mv": Vector2(0, -0.85)},
		{"n": "04_sprint", "t": 1.6, "mv": Vector2(0, -1.0), "sprint": true},
		{"n": "05_stop", "t": 0.5, "mv": Vector2.ZERO},
		{"n": "06_strafe", "t": 1.4, "mv": Vector2(1.0, 0), "lock": true},
		{"n": "07_backpedal", "t": 1.2, "mv": Vector2(0, 1.0), "lock": true},
		{"n": "08_attack", "t": 0.45, "mv": Vector2.ZERO, "act": "attack"},
		{"n": "09_attack2", "t": 0.40, "mv": Vector2.ZERO, "act": "attack"},
		{"n": "10_heavy", "t": 0.75, "mv": Vector2.ZERO, "act": "heavy"},
		{"n": "11_block", "t": 0.7, "mv": Vector2.ZERO, "hold": "block"},
		{"n": "12_dodge", "t": 0.45, "mv": Vector2(-1, 0), "act": "dodge"},
		{"n": "12b_walk_legs", "t": 2.2, "mv": Vector2(0, -0.4), "legs": true},
		{"n": "12c_jog_legs", "t": 2.2, "mv": Vector2(0, -0.85), "legs": true},
		{"n": "12d_sprint_legs", "t": 2.0, "mv": Vector2(0, -1.0), "sprint": true, "legs": true},
		{"n": "13_slope", "t": 2.2, "mv": Vector2(0, -0.85), "warp": Vector3(0, 0.3, -12)},
		{"n": "14_group", "t": 1.2, "mv": Vector2.ZERO, "warp": Vector3(2.5, 0.3, -2.0), "wide": true},
		{"n": "15_fight", "t": 1.6, "mv": Vector2.ZERO, "act": "attack", "wide": true},
	]

func _ground() -> void:
	_slab(Vector3(0, -0.5, 0), Vector3(90, 1, 90), Color(0.28, 0.31, 0.24))
	var ramp := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(14, 0.6, 22); mi.mesh = bm
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.33, 0.28, 0.21)
	mi.material_override = mat; ramp.add_child(mi)
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = bm.size
	cs.shape = bs; ramp.add_child(cs)
	ramp.position = Vector3(0, 1.9, -22); ramp.rotation.x = deg_to_rad(18.0)
	add_child(ramp)

func _slab(pos: Vector3, size: Vector3, col: Color) -> void:
	var sb := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size; mi.mesh = bm
	var mat := StandardMaterial3D.new(); mat.albedo_color = col
	mi.material_override = mat; sb.add_child(mi)
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = size
	cs.shape = bs; sb.add_child(cs)
	sb.position = pos
	add_child(sb)

func _chars() -> void:
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-42), deg_to_rad(34), 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	add_child(key)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new(); sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	e.ssao_enabled = true
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	cam = Camera3D.new()
	add_child(cam)
	cam.make_current()
	player = Player.new()
	player.position = Vector3(0, 0.2, 0)
	add_child(player)
	player.setup(null, null)
	for spec in [["ashigaru", Vector3(2.6, 0.2, -2.6)], ["archer", Vector3(-3.4, 0.2, -4.0)],
			["captain", Vector3(4.4, 0.2, -4.4)]]:
		var e2: EnemyBase
		match spec[0]:
			"ashigaru": e2 = Ashigaru.new()
			"archer": e2 = Archer.new()
			_: e2 = Captain.new()
		e2.spawn_id = "shot_%s" % spec[0]
		e2.position = spec[1]
		add_child(e2)
		e2.player = null
		enemies.append(e2)

func _physics_process(delta: float) -> void:
	if idx < 0:
		idx = 0; t = 0.0
		return
	if idx >= shots.size(): return
	var p: Dictionary = shots[idx]
	if t == 0.0:
		if p.has("warp"):
			player.global_position = p["warp"]
			player.velocity = Vector3.ZERO
		var want := bool(p.get("lock", false))
		if want and player._lock_target == null: player._toggle_lock()
		elif not want and player._lock_target != null: player._toggle_lock()
		if p.has("act"):
			var a := String(p["act"])
			if InputMap.has_action(a):
				Input.action_press(a)
	t += delta
	player.hp = player.max_hp
	for e in enemies:
		if is_instance_valid(e): e.player = player if bool(p.get("wide", false)) else null
	Game.touch_move = p.get("mv", Vector2.ZERO)
	Game.touch_sprint = bool(p.get("sprint", false))
	Game.touch_block = p.get("hold", "") == "block"
	if p.has("act") and t > 0.08:
		for a in ["attack", "heavy", "dodge"]:
			if InputMap.has_action(a): Input.action_release(a)
	# Frame the subject from its own 3/4 front with a long-ish lens, and aim
	# at the hips: a world-axis offset with the default 75 deg lens left the
	# character a sixth of the frame high and occasionally put the camera
	# inside the mesh when the subject ran toward it.
	var wide := bool(p.get("wide", false))
	var legs := bool(p.get("legs", false))
	cam.fov = 50.0 if wide else (34.0 if not legs else 28.0)
	var yaw: float = player.rotation.y
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(fwd.z, 0.0, -fwd.x)
	var dist: float = 8.5 if wide else (4.6 if not legs else 3.2)
	var hgt: float = 3.4 if wide else (1.35 if not legs else 0.42)
	var aim: float = 1.05 if wide else (0.95 if not legs else 0.30)
	var off: Vector3 = fwd * (dist * 0.72) + right * (dist * 0.62) + Vector3.UP * hgt
	cam.global_position = player.global_position + off
	cam.look_at(player.global_position + Vector3(0, aim, 0))
	if t >= float(p["t"]):
		_shoot(String(p["n"]))
		for a in ["attack", "heavy", "dodge", "block", "sprint"]:
			if InputMap.has_action(a): Input.action_release(a)
		Game.touch_move = Vector2.ZERO
		Game.touch_block = false
		idx += 1
		t = 0.0
		if idx >= shots.size():
			print("SHOTS_DONE saved=", saved)
			get_tree().quit()

func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://shot_%s.png" % name)
	saved += 1
	print("shot ", name)
