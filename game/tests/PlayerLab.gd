extends Node3D
## Close-up lab for the real Player on a flat floor: runs a scripted action and
## photographs it at given times from fixed angles relative to the player.
##   renv.sh res://tests/PlayerLab.tscn -- acts=draw,guard_run views=side,q out=/tmp/pl
## acts: draw sheathe guard_run block k_chain heavy kick punch nodachi yari fists

var player: Player
var cam: Camera3D
var out := "/tmp/pl"
var views := ["side", "q"]

const ACTS := {
	"draw": {"setup": "", "press": ["sheathe"], "at": [0.10, 0.20, 0.30, 0.42, 0.7]},
	"sheathe": {"setup": "drawn", "press": ["sheathe"], "at": [0.14, 0.26, 0.38, 0.50, 0.8]},
	"guard_idle": {"setup": "drawn", "press": [], "at": [0.5]},
	"guard_run": {"setup": "drawn", "hold": ["move_forward"], "at": [1.0, 1.15, 1.3]},
	"guard_walk": {"setup": "drawn_walk", "hold": ["move_forward"], "at": [1.0, 1.3]},
	"block": {"setup": "drawn", "hold": ["block"], "at": [0.15, 0.5]},
	"block_fists": {"setup": "fists", "hold": ["block"], "at": [0.5]},
	"block_nodachi": {"setup": "nodachi", "hold": ["block"], "at": [0.5]},
	"block_yari": {"setup": "yari", "hold": ["block"], "at": [0.5]},
	"k_chain": {"setup": "drawn", "press": ["attack"], "again": [0.3, 0.62], "at": [0.22, 0.5, 0.85, 1.1]},
	"heavy": {"setup": "drawn", "press": ["heavy"], "at": [0.35, 0.6, 0.8]},
	"kick": {"setup": "drawn", "press": ["kick"], "at": [0.2, 0.32, 0.45]},
	"punch": {"setup": "fists", "press": ["attack"], "again": [0.3], "at": [0.15, 0.45]},
	"nodachi": {"setup": "nodachi", "press": ["heavy"], "at": [0.4, 0.7, 1.0]},
	"yari": {"setup": "yari", "press": ["attack"], "at": [0.25, 0.4]},
	"idle_fists": {"setup": "fists", "press": [], "at": [0.5]},
	"carry_nodachi": {"setup": "nodachi_sheathed", "press": [], "at": [0.4]},
	"carry_yari": {"setup": "yari_sheathed", "press": [], "at": [0.4]},
	"draw_nodachi": {"setup": "nodachi_sheathed", "press": ["sheathe"], "at": [0.12, 0.24, 0.36, 0.5, 0.8]},
	"draw_yari": {"setup": "yari_sheathed", "press": ["sheathe"], "at": [0.12, 0.24, 0.36, 0.5, 0.8]},
	"jab": {"setup": "fists", "press": ["attack"], "at": [0.06, 0.1, 0.13, 0.17, 0.25]},
}

func _ready() -> void:
	var acts := ["draw"]
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("acts="): acts = s.substr(5).split(",")
		elif s.begins_with("views="): views = s.substr(6).split(",")
		elif s.begins_with("out="): out = s.substr(4)
	get_viewport().get_window().size = Vector2i(420, 520)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.70)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var floor := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400, 1, 400)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	floor.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.36, 0.42, 0.28)
	mi.material_override = fm
	floor.add_child(mi)
	add_child(floor)
	cam = Camera3D.new()
	cam.fov = 36
	add_child(cam)
	for a in acts:
		await _run(String(a))
	get_tree().quit()

func _fresh() -> void:
	if player != null: player.queue_free()
	for k in ["move_forward", "block", "sprint", "attack", "heavy", "kick", "punch", "sheathe"]:
		Input.action_release(k)
	await get_tree().process_frame
	player = Player.new()
	add_child(player)
	player.global_position = Vector3.ZERO
	player.rotation.y = 0.0
	await get_tree().create_timer(0.4).timeout

func _press(k: String) -> void:
	Input.action_press(k)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(k)

func _ikprobe() -> void:
	await _fresh()
	player.set_physics_process(false)
	var r := player.rig
	var hb := r.skeleton.find_bone("hand_r")
	var hand := func() -> Vector3: return r.skeleton.global_transform * r.skeleton.get_bone_global_pose(hb).origin
	for i in 3: await get_tree().process_frame
	print("A baseline hand=", hand.call(), " clip=", r.current())
	r.set_layer_arms(true)
	r.set_layer_clip("K_Blocking", 0.5)
	r.layer.influence = 1.0
	for i in 3: await get_tree().process_frame
	print("B layer K_Blocking hand=", hand.call(), " layer.active=", r.layer.active, " infl=", r.layer.influence)
	r.layer.influence = 0.0
	for i in 3: await get_tree().process_frame
	print("C layer off hand=", hand.call())
	r.reach_for("Katana")
	r.ik.influence = 1.0
	for i in 3: await get_tree().process_frame
	print("D ik on hand=", hand.call(), " target=", r.ik_target.global_position, " running=", r.ik.is_running())
	r.ik.start()
	for i in 3: await get_tree().process_frame
	print("E ik after start() hand=", hand.call())
	var mods := []
	for c in r.skeleton.get_children():
		if c is SkeletonModifier3D: mods.append("%s(%s,%.1f)" % [c.name, c.get_class(), c.influence])
	print("modifiers: ", mods, " sk.modifier_callback_mode_process=", r.skeleton.modifier_callback_mode_process)

func _modpose() -> void:
	await _fresh()
	player.set_physics_process(false)
	var r := player.rig
	for i in 3: await get_tree().process_frame
	for v in views: await _shot("mod_base", 0, String(v))
	r.set_layer_arms(true)
	r.set_layer_clip("K_Blocking", 0.5)
	r.layer.influence = 1.0
	for i in 3: await get_tree().process_frame
	for v in views: await _shot("mod_layer", 0, String(v))
	r.layer.influence = 0.0
	r.reach_for("Katana")
	r.ik.influence = 1.0
	for i in 3: await get_tree().process_frame
	for v in views: await _shot("mod_ik", 0, String(v))

func _pausecheck() -> void:
	await _fresh()
	player.select_weapon("katana")
	player._set_drawn(true)
	await get_tree().create_timer(0.8).timeout
	for v in views: await _shot("pause_live", 0, String(v))
	get_tree().paused = true
	for i in 6: await get_tree().process_frame
	for v in views: await _shot("pause_paused", 0, String(v))
	get_tree().paused = false

func _run(act: String) -> void:
	if act == "pausecheck":
		await _pausecheck()
		return
	if act == "ikprobe":
		await _ikprobe()
		return
	if act == "modpose":
		await _modpose()
		return
	if not ACTS.has(act): return
	var a: Dictionary = ACTS[act]
	await _fresh()
	match String(a.get("setup", "")):
		"drawn", "drawn_walk":
			player.select_weapon("katana")
			player._set_drawn(true)
			if String(a["setup"]) == "drawn_walk": player.walk_mode = true
		"fists": player.select_weapon("fists")
		"nodachi":
			player.select_weapon("nodachi")
			player._set_drawn(true)
		"yari":
			player.select_weapon("yari")
			player._set_drawn(true)
		"nodachi_sheathed":
			player.select_weapon("nodachi")
			player._set_drawn(false)
		"yari_sheathed":
			player.select_weapon("yari")
			player._set_drawn(false)
	await get_tree().create_timer(0.6).timeout
	for h in a.get("hold", []): Input.action_press(String(h))
	for p in a.get("press", []): _press(String(p))
	var t0 := Time.get_ticks_msec()
	var gt := 0.0
	var agains: Array = a.get("again", []).duplicate()
	var ats: Array = a["at"]
	var n := 0
	while n < ats.size():
		await get_tree().physics_frame
		gt += get_physics_process_delta_time()
		if not agains.is_empty() and gt >= float(agains[0]):
			agains.pop_front()
			for p in a.get("press", []): _press(String(p))
		if gt >= float(ats[n]):
			# freeze with time_scale 0, not pause: a paused skeleton is redrawn
			# without its modifiers (layer / IK) in Godot 4.3
			Engine.time_scale = 0.0
			for v in views: await _shot(act, n, String(v))
			Engine.time_scale = 1.0
			n += 1
	for h in a.get("hold", []): Input.action_release(String(h))

func _shot(act: String, i: int, v: String) -> void:
	var c := player.global_position + Vector3(0, 1.05, 0)
	var b := Basis(Vector3.UP, player.rotation.y)
	var off := Vector3(3.6, 0.3, 0.3)
	match v:
		"side": off = Vector3(-3.8, 0.2, 0.2)      # character's right side (+Z forward, -X right)
		"left": off = Vector3(3.8, 0.2, 0.2)
		"front": off = Vector3(0.0, 0.3, 3.9)
		"back": off = Vector3(0.0, 0.5, -3.9)
		"q": off = Vector3(-2.6, 0.7, 2.7)
	cam.global_position = c + b * off
	cam.look_at(c, Vector3.UP)
	if v == String(views[0]):
		print("SHOT %s %d state=%d move=%s clip=%s layer=%.2f drawn=%s weapon=%s" % [act, i, player.state, player._move_id, player.rig.current(), player.rig.layer.influence, player.drawn, player.weapon])
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_%s_%d_%s.png" % [out, act, i, v])
