extends Node
## Real-input QA for the v12 player: every check below is driven through the
## same InputEvents a keyboard and mouse produce (Input.parse_input_event with
## the bound physical keys / mouse buttons), against the real Main scene.
##   headless:  godot --headless --path . res://tests/PlayerQA.tscn
##   rendered:  renv.sh res://tests/PlayerQA.tscn -- shots      (/tmp/qa_*.png)
##   subset:    ... -- only=horse,weapons

var main: Node
var world: World
var player: Player
var horse: Horse
var pass_n := 0
var fail_n := 0
var fails: Array = []
var shots := false
var only: Array = []
var _t0 := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_t0 = Time.get_ticks_msec()
	var ua := OS.get_cmdline_user_args()
	shots = ua.has("shots")
	for a in ua:
		if String(a).begins_with("only="): only = String(a).substr(5).split(",")
	if DisplayServer.get_name() != "headless":
		get_viewport().get_window().size = Vector2i(960, 540)
	Game.reset_run()
	Game.reset_keybinds()
	await get_tree().create_timer(0.4).timeout
	Perf.apply_quality(0)
	main = get_parent().get_node("Main")
	main.start_world(false)
	var guard := 0
	while (main.world == null or not main.world.loaded or main.world.player == null) and guard < 600:
		guard += 1
		await get_tree().process_frame
	world = main.world
	player = world.player
	horse = world.horse
	# a quiet test range: no ambient spawns
	world.spawn_table.clear()
	for e in world.enemies.duplicate():
		if is_instance_valid(e): e.queue_free()
	world.enemies.clear()
	await _wait(1.2)
	print("=== PLAYER QA (", DisplayServer.get_name(), ") ===")
	if _on("boot"): await _boot()
	if _on("move"): await _move()
	if _on("weapons"): await _weapons()
	if _on("combat"): await _combat()
	if _on("horse"): await _horse()
	if _on("swim"): await _swim()
	if _on("travel"): await _travel()
	if _on("menu"): await _menu()
	_summary()

func _on(s: String) -> bool:
	return only.is_empty() or only.has(s)

# ---------------------------------------------------------------- input helpers
func key(code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.keycode = code as Key
	ev.pressed = down
	Input.parse_input_event(ev)

func tap(code: int, hold := 0.07) -> void:
	key(code, true)
	await _wait(hold)
	key(code, false)
	await _wait(0.02)

func mouse(btn: int, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = btn as MouseButton
	ev.pressed = down
	ev.position = Vector2(480, 270)
	Input.parse_input_event(ev)

func click(btn := MOUSE_BUTTON_LEFT) -> void:
	mouse(btn, true)
	await _wait(0.06)
	mouse(btn, false)
	await _wait(0.02)

func release_all() -> void:
	for k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_Q, KEY_CTRL, KEY_SPACE]:
		key(k, false)
	mouse(MOUSE_BUTTON_LEFT, false)
	mouse(MOUSE_BUTTON_RIGHT, false)

func click_at(c: Control) -> void:
	# no real pointer in a test run: tell the viewport the mouse is inside it,
	# otherwise GUI picking ignores the injected events
	get_viewport().notification(Node.NOTIFICATION_VP_MOUSE_ENTER)
	var pos := c.get_global_rect().get_center()
	var mm := InputEventMouseMotion.new()
	mm.position = pos; mm.global_position = pos
	get_viewport().push_input(mm, true)
	await get_tree().process_frame
	var hov = get_viewport().gui_get_hovered_control()
	if hov != c: print("    click %s at %s -> under the mouse: %s" % [(c as Button).text if c is Button else c.name, pos, str(hov.get_path()) if hov != null else "none"])
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = pos; e.global_position = pos
		# viewport coordinates: no window/stretch transform (headless has no window)
		get_viewport().push_input(e, true)
		await get_tree().process_frame
		await get_tree().process_frame

func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	var t := 0.0
	while t < sec:
		await get_tree().physics_frame
		t += get_physics_process_delta_time() * Engine.time_scale
		if Time.get_ticks_msec() - t0 > int(sec * 1000.0) * 40 + 20000: break

## Wait until `cond` holds (checked every physics frame) or `limit` seconds pass.
func _until(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while t < limit:
		if cond.call(): return true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return cond.call()

func check(name: String, ok: bool, detail := "") -> void:
	if ok: pass_n += 1
	else:
		fail_n += 1
		fails.append("%s %s" % [name, detail])
	print("  %s  %s  %s" % ["PASS" if ok else "FAIL", name, detail])

func shot(name: String) -> void:
	if not shots: return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/qa_%s.png" % name)
	print("  shot /tmp/qa_%s.png" % name)

func hspeed(n: Node3D) -> float:
	var v: Vector3 = n.velocity
	return Vector2(v.x, v.z).length()

## Average horizontal speed over `sec`.
func avg_speed(n: Node3D, sec: float) -> float:
	var s := 0.0
	var c := 0
	var t := 0.0
	while t < sec:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		s += hspeed(n); c += 1
	return s / maxf(1.0, float(c))

func open_ground() -> void:
	# A flat, clear run of ground so locomotion and riding numbers are clean:
	# candidates round the grassland are ranked by how flat the next 75 m
	# toward -Z are (the way the camera looks at yaw 0); the flattest one whose
	# run is free of trees, rocks and walls wins.
	var t := world.terrain
	var zc: Dictionary = world.data["zones"].get("grassland", {"x": 760, "z": 1180})
	var cands := []
	for i in 90:
		var a := TAU * float(i) / 90.0 * 7.0
		var r := 10.0 + float(i) * 2.5
		var c := Vector3(float(zc["x"]) + cos(a) * r, 0, float(zc["z"]) + sin(a) * r)
		var h0: float = t.sample_height(c.x, c.z)
		if h0 < t.water_level + 1.0: continue
		var v := 0.0
		var wet := false
		for k in 17:
			var dz := 8.0 - float(k) * 5.0
			var h: float = t.sample_height(c.x, c.z + dz)
			if h < t.water_level + 0.6: wet = true
			# v0.13: the carved main river and its muddy banks are not open ground
			for dx in [0.0, 3.0]:
				if t.water_depth_at(c.x + dx, c.z + dz) > 0.0 or t.river_prox_at(c.x + dx, c.z + dz) > 0.2 \
						or t.surface_at(c.x + dx, c.z + dz) in ["mud", "water"]:
					wet = true
			v += absf(h - h0)
		if not wet: cands.append([v, c])
	cands.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var best: Vector3 = cands[0][1] if not cands.is_empty() else player.global_position
	for ci in mini(cands.size(), 60):
		var c: Vector3 = cands[ci][1]
		var clear := _lane_clear(c)
		if OS.get_cmdline_user_args().has("dbg"): print("  DBG open_ground cand %d %s clear=%s" % [ci, str(c), str(clear)])
		if clear:
			best = c
			break
	world.warp_to(best)
	player.rotation.y = 0.0
	world.camera.yaw = 0.0
	world.camera.snap()
	world.place_horse_near(player.global_position + Vector3(0, 0, 6.0), 0.0)
	await _wait(0.6)

## True when no tree/boulder trunk (from the full streaming grid, not just the
## shapes currently streamed in) and no structure lies on the 80 m run toward -Z
## that the riding test uses, across the player's and the horse's lanes.
func _lane_clear(c: Vector3) -> bool:
	var x0 := c.x - 1.8
	var x1 := c.x + 4.6
	var z0 := c.z - 72.0
	var z1 := c.z + 10.0
	var sb: SolidBodies = world.solids
	if sb != null:
		for key in sb._grid:
			var k: Vector2i = key
			if float(k.x + 1) * SolidBodies.BUCKET < x0 - 2.0 or float(k.x) * SolidBodies.BUCKET > x1 + 2.0: continue
			if float(k.y + 1) * SolidBodies.BUCKET < z0 - 2.0 or float(k.y) * SolidBodies.BUCKET > z1 + 2.0: continue
			for it in sb._grid[key]:
				var p: Vector3 = it["p"]
				var r := float(it["r"])
				if p.x + r > x0 and p.x - r < x1 and p.z + r > z0 and p.z - r < z1: return false
	# structures are permanent shapes: sweep a box along the run for those
	var space := player.get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = Vector3(x1 - x0, 1.5, 5.0)
	var t := world.terrain
	for i in 17:
		var m := Vector3((x0 + x1) * 0.5, 0, z1 - (float(i) + 0.5) * 5.0)
		m.y = t.sample_height(m.x, m.z) + 1.25
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = box
		q.transform = Transform3D(Basis(), m)
		q.collision_mask = 1
		for r in space.intersect_shape(q, 8):
			var col = r.get("collider")
			if col != null and col.get_parent() is SolidBodies: return false
	return true

func fresh(e) -> void:
	e.hp = e.max_hp
	e.posture = 0.0
	e.posture_broken = false
	e.state = EnemyBase.S.IDLE

func dummy(offset: Vector3) -> Node3D:
	var p := player.global_position + offset
	p.y = world.terrain.sample_height(p.x, p.z) + 0.1
	var e = world.spawn_enemy_at("ashigaru", p, "qa_%d" % randi())
	await _wait(0.2)
	e.set_physics_process(false)
	# a training post: it takes the hits (and posture) but never falls over
	e.max_hp = 100000.0
	e.hp = e.max_hp
	return e

# ---------------------------------------------------------------- suites
func _boot() -> void:
	print("\n-- boot --")
	check("world loaded", world != null and world.loaded)
	check("player rig built", player.rig != null and player.rig.ok)
	check("anim library has the KayKit clips", player.anim.has_animation("K_Kick") and player.anim.has_animation("K_Dodge_L"),
		"clips=%d" % player.anim.get_animation_list().size())
	check("player on floor", await _until(func(): return player.is_on_floor(), 2.0))
	check("horse spawned", horse != null and is_instance_valid(horse))
	check("horse near the player at start", horse.global_position.distance_to(player.global_position) < 8.0,
		"d=%.1f" % horse.global_position.distance_to(player.global_position))
	check("horse stands on the ground", await _until(func(): return horse.is_on_floor(), 2.0))
	check("starts sheathed with the katana", player.weapon == "katana" and not player.drawn)
	check("idle clip", await _until(func(): return player.rig.current() == "Idle", 1.5), player.rig.current())

func _move() -> void:
	print("\n-- locomotion --")
	await open_ground()
	await tap(KEY_Z)
	check("Z toggles walk", await _until(func(): return player.walk_mode, 0.5))
	key(KEY_W, true)
	await _wait(0.8)
	var ws := await avg_speed(player, 0.6)
	check("walk speed ~1.45 m/s", absf(ws - 1.45) < 0.35, "v=%.2f" % ws)
	check("walk clip", player.rig.current() == "Walk", player.rig.current())
	await shot("walk")
	key(KEY_W, false)
	await tap(KEY_Z)
	check("Z toggles back to run", await _until(func(): return not player.walk_mode, 0.5))
	key(KEY_W, true)
	await _wait(0.8)
	var rs := await avg_speed(player, 0.6)
	check("run speed ~4.9 m/s", absf(rs - 4.9) < 0.8, "v=%.2f" % rs)
	check("run clip", player.rig.current() == "Jog_Fwd", player.rig.current())
	await shot("run")
	key(KEY_SHIFT, true)
	await _wait(1.4)
	var ss := await avg_speed(player, 0.6)
	check("sprint speed ~8.2 m/s", absf(ss - 8.2) < 1.3, "v=%.2f" % ss)
	check("sprint clip", player.rig.current() == "Sprint", player.rig.current())
	await shot("sprint")
	await tap(KEY_SPACE)
	var up := await _until(func(): return player.state == Player.S.JUMP and not player.is_on_floor(), 0.4)
	check("space jumps", up, "state=%d" % player.state)
	var down := await _until(func(): return player.is_on_floor() and player.state != Player.S.JUMP, 2.0)
	check("lands and keeps running", down, "state=%d" % player.state)
	key(KEY_SHIFT, false)
	key(KEY_W, false)
	await _wait(0.8)
	check("stops when keys released", hspeed(player) < 0.3, "v=%.2f" % hspeed(player))
	check("back to idle clip", player.rig.current() in ["Idle", "Jump_Land"], player.rig.current())
	# roll
	key(KEY_A, true)
	await _wait(0.1)
	await tap(KEY_CTRL)
	var rolled := await _until(func(): return player.state == Player.S.DODGE, 0.3)
	check("ctrl dodges", rolled, "state=%d" % player.state)
	check("dodge grants i-frames", await _until(func(): return player.has_iframes(), 0.25))
	key(KEY_A, false)
	check("dodge recovers", await _until(func(): return player.state in [Player.S.IDLE, Player.S.MOVE], 1.6))
	# camera-relative: yaw the camera 90 degrees, forward should follow it
	world.camera.yaw = PI * 0.5
	var p0 := player.global_position
	key(KEY_W, true)
	await _wait(0.9)
	key(KEY_W, false)
	var dv := player.global_position - p0
	var want := Vector3(-sin(PI * 0.5), 0, -cos(PI * 0.5))
	check("W moves along the camera forward", Vector3(dv.x, 0, dv.z).normalized().dot(want) > 0.9,
		"dir=%s" % str(Vector3(dv.x, 0, dv.z).normalized()))
	world.camera.yaw = 0.0
	await _wait(0.5)

func _weapons() -> void:
	print("\n-- weapons: draw / sheathe / switch --")
	await open_ground()
	var r := player.rig
	var kat: Node3D = r._nodes.get("Katana")
	check("katana starts in the saya", kat != null and kat.get_parent() == r.hip_sock)
	await tap(KEY_X)
	var reaching := await _until(func(): return player._carry == 1 and r.ik.influence > 0.2, 0.4)
	check("X starts the draw with an IK reach", reaching, "carry=%d ik=%.2f" % [player._carry, r.ik.influence])
	await shot("draw_reach")
	check("blade ends in the hand", await _until(func(): return player.drawn and kat.get_parent() == r.hand_sock, 1.0))
	await _wait(0.4)
	check("reach released after the draw", r.ik.influence < 0.1, "ik=%.2f" % r.ik.influence)
	check("guard layer on while drawn", r.layer.influence > 0.5, "layer=%.2f" % r.layer.influence)
	await shot("guard_idle")
	key(KEY_W, true)
	await _wait(1.0)
	check("guard layer kept while running", r.layer.influence > 0.3, "layer=%.2f" % r.layer.influence)
	await shot("guard_run")
	key(KEY_W, false)
	await _wait(0.8)
	check("never auto-sheathes (4 s idle)", await _still_drawn(4.0))
	# number keys
	await tap(KEY_2)
	check("2 selects the nodachi", await _until(func(): return player.weapon == "nodachi", 0.5))
	check("nodachi drawn (was holding a blade)", await _until(func(): return player.drawn and r._nodes["Nodachi"].get_parent() == r.hand_sock, 1.4))
	await shot("nodachi")
	await tap(KEY_3)
	check("3 selects the yari", await _until(func(): return player.weapon == "yari", 0.5))
	check("yari in hand", await _until(func(): return player.drawn and r._nodes["Yari"].get_parent() == r.hand_sock, 1.4))
	await shot("yari")
	await tap(KEY_4)
	check("4 selects fists", await _until(func(): return player.weapon == "fists" and player.drawn, 0.5))
	var in_hand := []
	for k in r._nodes:
		if r._nodes[k].visible and r._nodes[k].get_parent() == r.hand_sock: in_hand.append(k)
	check("empty hands with fists", in_hand.is_empty(), str(in_hand))
	# wheel
	mouse(MOUSE_BUTTON_WHEEL_DOWN, true); mouse(MOUSE_BUTTON_WHEEL_DOWN, false)
	await _wait(0.1)
	check("wheel down cycles to the katana", await _until(func(): return player.weapon == "katana", 0.5), player.weapon)
	await _until(func(): return player.drawn, 1.2)
	mouse(MOUSE_BUTTON_WHEEL_UP, true); mouse(MOUSE_BUTTON_WHEEL_UP, false)
	await _wait(0.1)
	check("wheel up cycles back to fists", await _until(func(): return player.weapon == "fists", 0.5), player.weapon)
	await tap(KEY_1)
	await _until(func(): return player.drawn, 1.2)
	check("1 selects the katana", await _until(func(): return player.weapon == "katana", 0.5))
	await tap(KEY_X)
	check("X sheathes", await _until(func(): return not player.drawn and kat.get_parent() == r.hip_sock, 1.2))
	await _wait(0.5)
	check("guard layer off when sheathed", r.layer.influence < 0.2, "layer=%.2f" % r.layer.influence)
	await shot("sheathed")

func _still_drawn(sec: float) -> bool:
	var t := 0.0
	while t < sec:
		if not player.drawn: return false
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return player.drawn

var _rec := false
var _seen: Array = []

func _physics_process(_d: float) -> void:
	if _rec and player != null and player._move_id != "":
		if _seen.is_empty() or _seen[-1] != player._move_id: _seen.append(player._move_id)

func _combat() -> void:
	print("\n-- combat --")
	await open_ground()
	if player.weapon != "katana": await tap(KEY_1)
	if player.drawn: await tap(KEY_X)
	await _wait(0.8)
	var e = await dummy(Vector3(0, 0, -2.1))
	player.rotation.y = PI
	var hp0: float = e.hp
	# attack from the saya = quick draw + first cut
	await click()
	var drew := await _until(func(): return player.drawn, 0.6)
	check("LMB from sheathed quick-draws", drew)
	check("... and cuts", await _until(func(): return player._move_id == "k_a", 0.6), player._move_id)
	check("light cut damages", await _until(func(): return e.hp < hp0, 0.8), "hp %.0f -> %.0f" % [hp0, e.hp])
	await _wait(0.6)
	# three-hit chain with buffered clicks
	fresh(e)
	_seen = []
	_rec = true
	for i in 6:
		await click()
		await _wait(0.24)
	await _wait(1.2)
	_rec = false
	var seen: Array = _seen.duplicate()
	check("light chain k_a > k_b > k_diag > k_c", seen.slice(0, 4) == ["k_a", "k_b", "k_diag", "k_c"], str(seen))
	await _wait(1.0)
	await click(MOUSE_BUTTON_RIGHT)
	check("RMB heavy", await _until(func(): return player._move_id == "k_heavy", 0.4), player._move_id)
	await shot("heavy")
	await _until(func(): return player.state != Player.S.ATTACK, 2.0)
	fresh(e)
	await tap(KEY_V)
	check("V kick", await _until(func(): return player._move_id == "kick", 0.4), player._move_id)
	check("kick hits posture hard", await _until(func(): return e.posture >= 25.0, 1.0), "posture=%.0f" % e.posture)
	await shot("kick")
	await _until(func(): return player.state != Player.S.ATTACK, 1.5)
	await tap(KEY_G)
	check("G punch", await _until(func(): return player._move_id in ["jab", "cross", "hook"], 0.4), player._move_id)
	await _until(func(): return player.state != Player.S.ATTACK, 1.5)
	# guard + deflect
	key(KEY_Q, true)
	check("Q guards", await _until(func(): return player.state == Player.S.BLOCK, 0.3))
	check("deflect window at guard start", player.is_perfect_deflect())
	await _wait(0.4)
	check("block pose layered", player.rig.layer.influence > 0.6, "layer=%.2f" % player.rig.layer.influence)
	await shot("block")
	var hpp := player.hp
	player.take_hit({"damage": 30.0, "posture": 10.0, "source": e})
	check("block soaks most damage", player.hp > hpp - 8.0, "hp %.0f -> %.0f" % [hpp, player.hp])
	key(KEY_Q, false)
	await _wait(0.3)
	# perfect deflect -> riposte
	fresh(e)
	key(KEY_Q, true)
	await _until(func(): return player.state == Player.S.BLOCK, 0.3)
	player.take_hit({"damage": 30.0, "posture": 10.0, "source": e})
	check("hit inside the window is a perfect deflect", player._riposte_t > 0.0, "riposte_t=%.2f" % player._riposte_t)
	var rp0: float = e.posture
	await click()
	check("attack after a deflect = riposte", await _until(func(): return player._move_id == "k_riposte", 0.4), player._move_id)
	check("riposte breaks posture hard", await _until(func(): return e.posture >= rp0 + 30.0, 1.0), "posture %.0f -> %.0f" % [rp0, e.posture])
	key(KEY_Q, false)
	await _until(func(): return player.state != Player.S.ATTACK, 1.5)
	await _wait(0.4)
	# plunging cut: jump, attack in the air, the cut lands with the feet
	fresh(e)
	var ph0: float = e.hp
	await tap(KEY_SPACE)
	await _wait(0.18)
	await click()
	check("attack in the air = plunging cut", await _until(func(): return player._move_id == "k_air", 0.4), player._move_id)
	check("plunging cut lands", await _until(func(): return player.is_on_floor() and player._plunge_landed, 1.5))
	check("plunging cut damages", await _until(func(): return e.hp < ph0, 1.0), "hp %.0f -> %.0f" % [ph0, e.hp])
	await _until(func(): return player.state != Player.S.ATTACK, 2.0)
	await _wait(0.3)
	# other weapons' moves
	for w in [[KEY_2, "nodachi", "n_a", "n_spin"], [KEY_3, "yari", "y_a", "y_sweep"], [KEY_4, "fists", "jab", "lunge_punch"]]:
		await tap(int(w[0]))
		await _until(func(): return player.drawn and player._carry == 0, 1.5)
		fresh(e)
		# this loop checks move mapping, not stamina: start each weapon rested
		player._set_stamina(player.max_stamina)
		player.winded = false
		var h1: float = e.hp
		await click()
		check("%s light = %s" % [w[1], w[2]], await _until(func(): return player._move_id == String(w[2]), 0.5), player._move_id)
		check("%s light damages" % w[1], await _until(func(): return e.hp < h1, 1.2), "hp=%.0f" % e.hp)
		await _until(func(): return player.state != Player.S.ATTACK, 2.0)
		await _wait(0.3)
		await click(MOUSE_BUTTON_RIGHT)
		check("%s heavy = %s" % [w[1], w[3]], await _until(func(): return player._move_id == String(w[3]), 0.5), player._move_id)
		await _wait(0.5)
		await shot("heavy_" + String(w[1]))
		await _until(func(): return player.state != Player.S.ATTACK, 2.5)
	await tap(KEY_1)
	await _until(func(): return player.drawn and player._carry == 0, 1.5)
	# lock-on strafe
	e.hp = e.max_hp
	await tap(KEY_TAB)
	check("Tab locks on", await _until(func(): return player.locked_target() == e, 0.5))
	key(KEY_D, true)
	await _wait(0.8)
	check("locked strafe clip", player.rig.current() in ["K_Strafe_L", "K_Strafe_R"], player.rig.current())
	await shot("strafe")
	await tap(KEY_CTRL)
	check("locked dodge is a sidestep", await _until(func(): return player.rig.current() in ["K_Dodge_L", "K_Dodge_R"], 0.3), player.rig.current())
	key(KEY_D, false)
	await _until(func(): return player.state in [Player.S.IDLE, Player.S.MOVE], 1.5)
	await tap(KEY_CTRL)
	check("no-stick dodge is a backstep", await _until(func(): return player.rig.current() == "K_Dodge_B", 0.3), player.rig.current())
	await _until(func(): return player.state in [Player.S.IDLE, Player.S.MOVE], 1.5)
	await tap(KEY_TAB)
	check("Tab unlocks", await _until(func(): return player.locked_target() == null, 0.5))
	# deathblow
	e.set_physics_process(true)
	e.max_hp = 58.0
	e.hp = 58.0
	e.take_hit({"damage": 1.0, "posture": 999.0, "source": player})
	await _wait(0.1)
	var to: Vector3 = e.global_position - player.global_position
	player.global_position = e.global_position - to.normalized() * 1.8
	await _wait(0.1)
	check("posture break offers a deathblow", player.deathblow_available() == e)
	await tap(KEY_E)
	check("E deathblow", await _until(func(): return player.state == Player.S.DEATHBLOW, 0.3), "state=%d" % player.state)
	check("deathblow kills", await _until(func(): return e.is_dead, 1.0))
	await _until(func(): return player.state == Player.S.IDLE, 2.0)

func _swim() -> void:
	print("\n-- swim --")
	var t := world.terrain
	var lk: Dictionary = world.data.get("lake", {"x": 900, "z": 1370, "r": 175})
	# a deep spot: walk the lake's radius out from its centre until 2.5 m+
	var spot := Vector3.ZERO
	for i in 60:
		var a := TAU * float(i) / 60.0
		for r in [20.0, 40.0, 60.0, 80.0]:
			var c := Vector3(float(lk["x"]) + cos(a) * r, 0, float(lk["z"]) + sin(a) * r)
			if t.water_depth_at(c.x, c.z) > 2.5:
				spot = c
				break
		if spot != Vector3.ZERO: break
	check("found deep lake water", spot != Vector3.ZERO, str(spot))
	if spot == Vector3.ZERO: return
	if not player.drawn and player.weapon != "fists": await tap(KEY_1)
	await _until(func(): return player.drawn and player._carry == 0, 1.5)
	player.global_position = Vector3(spot.x, t.water_level + 0.5, spot.z)
	player.velocity = Vector3.ZERO
	check("falls in and swims", await _until(func(): return player.state == Player.S.SWIM, 2.0), "state=%d" % player.state)
	check("blade sheathed in the water", not player.drawn)
	await _wait(1.5)
	var fy: float = player.global_position.y
	check("floats (feet ~1.2 m under)", absf(fy - (t.water_level - 1.2)) < 0.3, "y=%.2f wl=%.2f" % [fy, t.water_level])
	check("does not sink to the bed", fy > t.sample_height(spot.x, spot.z) + 0.6)
	check("treading-water clip", player.rig.current() == "Swim_Idle", player.rig.current())
	key(KEY_W, true)
	await _wait(1.6)
	var sw: float = await avg_speed(player, 0.8)
	check("swims forward", sw > 1.6 and sw < 2.8, "%.2f m/s" % sw)
	check("stroke clip", player.rig.current() == "Swim_Fwd", player.rig.current())
	var st0: float = player.stamina
	key(KEY_SHIFT, true)
	await _wait(1.2)
	var sf: float = await avg_speed(player, 0.6)
	check("fast stroke is faster", sf > sw + 0.5, "%.2f m/s" % sf)
	check("fast stroke costs stamina", player.stamina < st0 - 5.0, "%.0f -> %.0f" % [st0, player.stamina])
	key(KEY_SHIFT, false)
	key(KEY_W, false)
	await click()
	await _wait(0.3)
	check("no attacks while swimming", player.state == Player.S.SWIM, "state=%d" % player.state)
	# back on land
	await open_ground()
	check("out of the water: on foot", await _until(func(): return player.state in [Player.S.IDLE, Player.S.MOVE], 1.0), "state=%d" % player.state)
	check("swim lift eased off", await _until(func(): return absf(player.rig.position.y) < 0.01, 1.0), "%.2f" % player.rig.position.y)

func _horse() -> void:
	print("\n-- horse --")
	await open_ground()
	if player.drawn: await tap(KEY_X)
	await _wait(0.6)
	# send the horse away, then whistle
	var away := player.global_position + Vector3(30, 0, 10)
	away.y = world.terrain.sample_height(away.x, away.z) + 0.2
	horse.global_position = away
	await _wait(0.3)
	await tap(KEY_H)
	check("H calls the horse", await _until(func(): return horse.mode == Horse.H.CALLED, 0.5), "mode=%d" % horse.mode)
	var came := await _until(func(): return horse.global_position.distance_to(player.global_position) < 4.0 and horse.mode == Horse.H.IDLE, 14.0)
	check("horse arrives and stops", came, "d=%.1f mode=%d" % [horse.global_position.distance_to(player.global_position), horse.mode])
	# stand at the flank
	var side := horse.global_position + horse.global_transform.basis.x * 1.6
	side.y = world.terrain.sample_height(side.x, side.z) + 0.1
	player.global_position = side
	await _wait(0.3)
	check("mount prompt shown", world.current_prompt().begins_with("Mount"), world.current_prompt())
	await tap(KEY_E)
	check("E mounts", await _until(func(): return player.state == Player.S.MOUNTING, 0.3), "state=%d" % player.state)
	check("seated", await _until(func(): return player.state == Player.S.MOUNTED, 1.2))
	check("horse knows its rider", horse.rider == player and horse.mode == Horse.H.RIDDEN)
	await _wait(0.4)
	var seat := horse.seat_transform().origin
	check("rider on the saddle", player.global_position.distance_to(seat) < 1.2, "d=%.2f" % player.global_position.distance_to(seat))
	await shot("mounted_idle")
	key(KEY_W, true)
	await _wait(2.6)
	var cs := await avg_speed(horse, 0.5)
	check("W canters (~7 m/s)", cs > 5.5 and cs < 8.5, "v=%.2f" % cs)
	check("rider follows the horse", player.global_position.distance_to(horse.seat_transform().origin) < 1.2)
	await shot("canter")
	key(KEY_SHIFT, true)
	var tr := ""
	var tt := 0.0
	var walls := 0
	while tt < 3.0:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()
		if horse.is_on_wall():
			walls += 1
			if walls == 1:
				var col := horse.get_last_slide_collision()
				var cn = col.get_collider() if col != null else null
				tr += " WALL@%s n=%s by=%s(%s)" % [str(horse.global_position), str(horse.get_wall_normal()), str(cn.name) if cn != null else "?", cn.get_class() if cn != null else "?"]
		if fmod(tt, 0.25) < get_physics_process_delta_time(): tr += " %.2f:%.1f" % [tt, horse._speed]
	if OS.get_cmdline_user_args().has("dbg"): print("  DBG gallop trace walls=%d%s ts=%.2f" % [walls, tr, Engine.time_scale])
	var gs := await avg_speed(horse, 0.5)
	check("Shift gallops (>12 m/s)", gs > 12.0, "v=%.2f" % gs)
	if gs <= 12.0:
		print("  DBG horse _speed=%.2f vel=%s sprint=%s fwd_held=%s pos=%s floor=%s walk=%s" % [horse._speed, str(horse.velocity), str(Input.is_action_pressed("sprint")), str(Input.is_action_pressed("move_forward")), str(horse.global_position), str(horse.is_on_floor()), str(player.walk_mode)])
	await shot("gallop")
	await tap(KEY_SPACE)
	check("Space jumps the horse", await _until(func(): return not horse.is_on_floor(), 0.5))
	check("horse lands", await _until(func(): return horse.is_on_floor(), 2.5))
	await click()
	check("mounted cut", await _until(func(): return player._move_id in ["ride_a", "ride_b"], 0.8), player._move_id)
	check("katana drawn for the cut", await _until(func(): return player.drawn, 0.8))
	await _wait(0.15)
	await shot("mounted_cut")
	key(KEY_SHIFT, false)
	key(KEY_W, false)
	# steering: turn the camera, horse should follow
	await _wait(0.2)
	key(KEY_S, true)
	await _wait(2.5)
	check("S brakes", hspeed(horse) < 2.0, "v=%.2f" % hspeed(horse))
	key(KEY_S, false)
	await _until(func(): return hspeed(horse) < 0.5, 3.0)
	await tap(KEY_E)
	check("E dismounts", await _until(func(): return player.state == Player.S.IDLE and not player.is_mounted(), 1.5), "state=%d" % player.state)
	check("collision back on", not player.body_shape.disabled and player.collision_layer == 2)
	check("feet on the ground", await _until(func(): return player.is_on_floor(), 1.5))
	check("horse idle after dismount", horse.rider == null and horse.mode == Horse.H.IDLE)
	await shot("dismounted")

func _travel() -> void:
	print("\n-- fast travel --")
	await open_ground()
	var ok0: bool = world.fast_travel("castle")
	check("cannot travel to an unvisited zone", not ok0)
	Game.visited_zones.append("village")
	var ok1: bool = world.fast_travel("village")
	check("fast travel to a visited zone", ok1)
	await _wait(0.5)
	var z: Dictionary = world.data["zones"]["village"]
	var d := Vector2(player.global_position.x - float(z["x"]), player.global_position.z - float(z["z"])).length()
	check("arrived at the village", d < 30.0, "d=%.1f" % d)
	check("horse travelled too", horse.global_position.distance_to(player.global_position) < 8.0,
		"d=%.1f" % horse.global_position.distance_to(player.global_position))
	check("standing on ground", await _until(func(): return player.is_on_floor(), 2.0))
	await shot("travel_village")

func _menu() -> void:
	print("\n-- pause / controls --")
	await tap(KEY_ESCAPE)
	await _wait(0.1)
	check("Esc pauses", await _until(func(): return get_tree().paused and world.hud.is_paused(), 0.5))
	var pm = world.hud._pause_menu
	check("pause menu visible", pm != null and pm.visible)
	await shot("pause")
	# rebind kick to B through the Controls screen
	pm._arm_rebind("kick", 0)
	await tap(KEY_B)
	check("controls screen captures a key", String(Game.binds_for("kick")[0]) == Game.slot_str(Game.K, KEY_B),
		str(Game.binds_for("kick")))
	check("rebinding persists in settings", Game.settings.has("binds"))
	await tap(KEY_ESCAPE)
	check("Esc resumes", await _until(func(): return not get_tree().paused and not world.hud.is_paused(), 0.5))
	await _wait(0.3)
	await tap(KEY_B)
	check("new kick key works in game", await _until(func(): return player._move_id == "kick", 0.4), player._move_id)
	await _until(func(): return player.state != Player.S.ATTACK, 1.5)
	Game.reset_keybinds()
	await tap(KEY_V)
	check("defaults restored", await _until(func(): return player._move_id == "kick", 0.4), player._move_id)
	await _until(func(): return player.state != Player.S.ATTACK, 1.5)
	# real mouse clicks through the GUI (v12 bug: an invisible touch layer ate them)
	await tap(KEY_ESCAPE)
	await _wait(0.1)
	check("paused for click test", get_tree().paused)
	var btns := {}
	for b in pm.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree(): btns[(b as Button).text] = b
	check("menu has Controls + Resume buttons", btns.has("Controls") and btns.has("Resume"), str(btns.keys()))
	if btns.has("Controls"):
		await click_at(btns["Controls"])
		check("click opens Controls", pm._controls_panel.visible)
		if pm._controls_panel.visible: await tap(KEY_ESCAPE)
	if btns.has("Resume"):
		check("still paused before the Resume click", get_tree().paused)
		await click_at(btns["Resume"])
		check("click on Resume resumes", await _until(func(): return not get_tree().paused, 0.5))
	# pause/resume twice more: the old bug left the game stuck paused
	for i in 2:
		await tap(KEY_ESCAPE)
		await _wait(0.1)
		var p1 := get_tree().paused
		await tap(KEY_ESCAPE)
		await _wait(0.1)
		check("pause cycle %d" % (i + 1), p1 and not get_tree().paused)

func _summary() -> void:
	release_all()
	print("\n=== PLAYER QA: %d passed, %d failed (%.1f s) ===" % [pass_n, fail_n, (Time.get_ticks_msec() - _t0) / 1000.0])
	for f in fails: print("   - ", f)
	get_tree().quit(1 if fail_n > 0 else 0)
