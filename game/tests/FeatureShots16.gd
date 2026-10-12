extends "res://tests/AdvQA.gd"
## v0.16 feature stills on the real Main.tscn (needs a renderer):
##   renv.sh res://tests/FeatureShots16.tscn -- out=/tmp/f16 [only=stealth,assassin,peril,smoke,skills] [w=960 h=540 q=1 hour=16.8]
## stealth   crouched in tall grass near a sentry: the ? awareness arc + the eye
## assassin  the stab from behind
## peril     a soldier winding up a perilous thrust: 危 and the DEFLECT / MIKIRI hint
## smoke     a smoke bomb going off, the spirit fox at heel, two soldiers blinded
## skills    the techniques screen (U) over the paused game, at 1280x720
## Reuses the AdvQA helpers (_reset, _enemy, _fight, _perilous_foe ...).

var out := "/tmp/f16"
var W := 960
var H := 540
var hour := 16.8
var _hold := {}           ## enemy -> awareness held for the photo

func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with(k + "="): return s.substr(k.length() + 1)
	return d

func _want(n: String) -> bool:
	var only := _arg("only", "")
	return only == "" or n in only.split(",")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS     # keeps running while a still is frozen
	process_priority = 900
	process_physics_priority = 900
	out = _arg("out", out)
	W = int(_arg("w", str(W)))
	H = int(_arg("h", str(H)))
	hour = float(_arg("hour", str(hour)))
	DirAccess.make_dir_recursive_absolute(out)
	get_viewport().get_window().size = Vector2i(W, H)
	Perf.apply_quality(int(_arg("q", "1")))
	# software rendering runs at seconds per frame: let each frame carry more
	# physics so the waits below cost fewer rendered frames
	Engine.max_physics_steps_per_frame = int(_arg("steps", "8"))
	Perf.adaptive = false
	_mark("start")
	await get_tree().create_timer(1.0).timeout
	main = get_parent().get_node_or_null("Main")
	main.start_world(false)
	_mark("start_world called")
	for i in 240:
		await get_tree().process_frame
		world = main.get("world")
		if world != null and main.get("loading") == null: break
	_mark("world built")
	Perf.apply_quality(int(_arg("q", "1")), true)
	# stills: full resolution, no adaptive scaling, FXAA instead of MSAA
	# (software rendering runs far below any frame budget)
	Perf.adaptive = false
	var vp := get_viewport()
	vp.scaling_3d_scale = 1.0
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	player = world.player
	terrain = world.terrain
	world.spawn_table.clear()
	_clear_enemies()
	world.wild.set("_target", 0)
	world.wild.set("_pack_cd", 1.0e9)
	for a in world.wild.animals().duplicate(): world.wild._remove(a)
	world.set_weather("clear", true)
	_mark("world ready")
	if _want("stealth") or _want("assassin"): await _shot_stealth()
	if _want("peril") or _want("smoke"): await _shot_fight()
	if _want("skills"): await _shot_skills()
	print("F16_DONE")
	get_tree().quit()

func _process(_d: float) -> void:
	if _arg("frames", "0") == "1" and Engine.get_process_frames() < 600:
		_mark("frame")
	for e in _hold.keys():
		if is_instance_valid(e): e.awareness = float(_hold[e])

func _snap(n: String) -> void:
	for i in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, n])
	print("F16 shot %s %s" % [n, img.get_size()])
	_mark("shot " + n)

## progress that survives a killed run (stdout is block-buffered off a tty)
func _mark(s: String) -> void:
	var path := "%s/progress.txt" % out
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null: return
	f.seek_end()
	f.store_line("%s  frame %d  t=%.1f s" % [s, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	f.close()

## camera behind the player looking along dir, swung by `swing` radians
func _frame_cam(dir: Vector3, swing: float, pitch: float, dist: float) -> void:
	var cam = player.camera
	cam.yaw = atan2(-dir.x, -dir.z) + swing
	cam.pitch = pitch
	cam.distance = dist
	cam.snap()

func _settle(t: float) -> void:
	await _wait(t)

func _tallgrass_near(c: Vector3) -> Vector3:
	var best := Vector3.INF
	var bg := 0.0
	for ring in range(0, 50):
		for k in 24:
			var a := TAU * float(k) / 24.0
			var x := c.x + cos(a) * float(ring) * 10.0
			var z := c.z + sin(a) * float(ring) * 10.0
			if x < 40.0 or z < 40.0 or x > 1490.0 or z > 1490.0: continue
			if terrain.biome_at(x, z) != "tallgrass": continue
			if not world.wild._ground_ok(x, z): continue
			var g := terrain.grass_density_at(x, z)
			if g > bg:
				bg = g
				best = Vector3(x, 0, z)
		if bg > 0.8: break
	return best

# ------------------------------------------------------------------ stealth
func _shot_stealth() -> void:
	var tg := _tallgrass_near(Vector3(903, 0, 1081))
	if tg == Vector3.INF:
		print("F16 no tall grass")
		return
	world.warp_to(tg)
	await _settle(2.0)
	_mark("warped to tall grass %s" % tg)
	spot = player.global_position
	face = await _open_dir(18.0)
	var side := face.cross(Vector3.UP).normalized()
	await _reset(["s_silent", "s_assassin"])
	world.set_time_of_day(hour)
	player.set_crouch(true)
	if _want("stealth"):
		var s1 := _enemy("ashigaru", spot + face * 9.0 + side * 2.0, side)
		var s2 := _enemy("ashigaru", spot + face * 17.0 - side * 5.0, -face)
		_hold[s1] = 0.55
		_hold[s2] = 0.12
		_frame_cam(face, 0.42, -0.10, 3.6)
		await _settle(float(_arg("settle", "3.0")))
		await _snap("stealth")
		_hold.clear()
	if _want("assassin"):
		await _reset(["s_silent", "s_assassin"])
		world.set_time_of_day(hour)
		player.set_crouch(true)
		var v := _enemy("ashigaru", spot + face * 1.9, face)
		_frame_cam(face, float(_arg("aswing", "1.45")), float(_arg("apitch", "-0.30")), float(_arg("adist", "3.0")))
		await _settle(2.0)
		await get_tree().physics_frame
		await _press("interact")
		var t := 0.0
		while t < 3.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if player.state == Player.S.ASSASSIN and bool(player.get("_assassin_struck")) and float(player.get("_state_t")) >= 0.16:
				break
		get_tree().paused = true
		await _snap("assassin")
		get_tree().paused = false
		await _settle(1.5)

# ------------------------------------------------------------------ fights
func _shot_fight() -> void:
	var c := _find_open(Vector3(1060, 0, 820))
	world.warp_to(c)
	await _settle(2.0)
	spot = player.global_position
	face = await _open_dir(20.0)
	var side := face.cross(Vector3.UP).normalized()
	if _want("peril"):
		await _reset(["b_deflect", "b_posture", "b_mikiri"])
		world.set_time_of_day(hour)
		if not player.drawn: player._set_drawn(true)
		var e := _perilous_foe("thrust")
		var e2 := _enemy("ashigaru", spot + face * 6.0 + side * 3.0, -face)
		_fight(e2)
		e2.set("_cd", 999.0)
		_frame_cam(face, 0.45, -0.12, 3.8)
		await _settle(float(_arg("settle", "1.2")))
		_start_attack(e)
		var t := 0.0
		while t < 3.0:
			# keep the camera on the soldier while it winds up (it may have
			# circled during the settle)
			var to: Vector3 = e.global_position - player.global_position
			to.y = 0.0
			if to.length() > 0.3:
				_frame_cam(to.normalized(), float(_arg("swing", "0.42")), -0.10, float(_arg("dist", "3.7")))
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if e.perilous_progress() >= 0.55: break
		get_tree().paused = true
		await _snap("peril")
		get_tree().paused = false
		await _settle(1.5)
	if _want("smoke"):
		await _reset(["s_silent", "s_assassin", "s_smoke", "p_fox"])
		world.set_time_of_day(hour)
		var a := _enemy("ashigaru", spot + face * 3.2 + side * 1.4, -face)
		var b := _enemy("ashigaru", spot + face * 3.8 - side * 1.6, -face)
		_fight(a); _fight(b)
		a.set("_cd", 999.0); b.set("_cd", 999.0)
		_frame_cam(face, 0.95, -0.16, 5.2)
		await _settle(3.5)
		await get_tree().physics_frame
		await _press("smoke")
		# several moments of the same burst; pick the best still
		var waited := 0.0
		var k := 0
		for at in _arg("smoke_t", "0.9").split(","):
			await _wait(maxf(0.0, float(at) - waited))
			waited = float(at)
			get_tree().paused = true
			await _snap("smoke" if k == 0 else "smoke_%d" % k)
			get_tree().paused = false
			k += 1
		await _settle(1.0)

# ------------------------------------------------------------------ techniques
func _shot_skills() -> void:
	get_viewport().get_window().size = Vector2i(1280, 720)
	if not _want("peril") and not _want("smoke") and not _want("stealth"):
		var c := _find_open(Vector3(1060, 0, 820))
		world.warp_to(c)
		await _settle(2.0)
		spot = player.global_position
		face = await _open_dir(20.0)
		await _reset()
	world.set_time_of_day(hour)
	_frame_cam(face, 0.5, -0.12, 4.2)
	await _settle(2.0)
	Skills.reset()
	for id in ["b_deflect", "b_posture", "s_silent", "s_assassin", "p_fox"]:
		Skills.unlocked.append(String(id))
	Game.mastery_points = 4
	world.hud.open_skills()
	var m = world.hud.get("_skills")
	if m != null:
		m.selected = _arg("sel", "b_mikiri")
		m.queue_redraw()
	for i in 6: await get_tree().process_frame
	await _snap("skills")
