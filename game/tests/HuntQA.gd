extends Node
## v0.15 hunting QA on the real Main.tscn.
##  A  walk (walk toggle) up behind a grazing doe: it must let you reach
##     striking range, and a sneak attack must kill it in one cut
##  B  harvest the carcass with interact: health and a gourd charge come back
##  C  run at a grazing doe: it must bolt well out of reach
##  D  walk at a doe that is looking your way: it must spot you far out
##  E  a boar charges and bites; a sidestep makes it miss; it can be killed
##  F  a night wolf pack turns up, circles, bites one at a time, and leaves at
##     dawn
## Prints "HUNTQA" lines and a summary, then quits.

var main: Node
var world: Node
var wild: Wildlife
var player: Node3D
var terrain: Terrain
var steer_to := Vector3.INF
var steer_mag := 0.0
var face_only := false
var fails := 0
var lines: Array[String] = []
var spot := Vector3.ZERO

func _ready() -> void:
	process_priority = 900
	process_physics_priority = 900
	get_viewport().get_window().size = Vector2i(480, 270)
	Perf.apply_quality(0)
	await get_tree().create_timer(1.0).timeout
	main = get_parent().get_node_or_null("Main")
	main.start_world(false)
	await get_tree().create_timer(3.0).timeout
	world = main.get("world")
	if world == null:
		for n in get_tree().root.get_children():
			var w = n.find_child("World", true, false)
			if w != null: world = w
	player = world.player
	wild = world.wild
	terrain = world.terrain
	_log("start  player=%s wild=%s animals=%d" % [player.global_position, wild != null, wild.animals().size()])
	# isolate the test: no new herds, no wolves until we ask for them
	wild.set("_target", 0)
	wild.set("_pack_cd", 1.0e9)
	_clear()
	spot = _find_open(player.global_position)
	_log("open ground at %s biome=%s" % [spot, terrain.biome_at(spot.x, spot.z)])
	world.warp_to(spot)
	world.set_time_of_day(10.0)
	await _wait(2.0)
	await _test_stealth()
	await _test_harvest()
	await _test_run_spook()
	await _test_seen()
	await _test_boar()
	await _test_wolves()
	await _measure_models()
	_log("SUMMARY fails=%d" % fails)
	print("\n".join(lines))
	print("HUNTQA_DONE fails=%d" % fails)
	get_tree().quit()

# ------------------------------------------------------------------ helpers
func _log(s: String) -> void:
	print("HUNTQA " + s)
	lines.append(s)

func _check(ok: bool, what: String) -> void:
	if not ok: fails += 1
	_log(("PASS " if ok else "FAIL ") + what)

func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, true).timeout

func _clear() -> void:
	for a in wild.animals().duplicate():
		wild._remove(a)

func _find_open(c: Vector3) -> Vector3:
	var best := c
	for ring in range(0, 40):
		var r := 30.0 + ring * 25.0
		for k in 16:
			var ang := TAU * k / 16.0 + ring * 0.37
			var x := c.x + sin(ang) * r
			var z := c.z + cos(ang) * r
			if not wild._ground_ok(x, z): continue
			var b := terrain.biome_at(x, z)
			if not b in ["grassland", "farmland", "tallgrass"]: continue
			var ok := true
			for j in 8:
				var a2 := TAU * j / 8.0
				for rr in [12.0, 30.0]:
					var xx: float = x + sin(a2) * rr
					var zz: float = z + cos(a2) * rr
					if not wild._ground_ok(xx, zz) or terrain.slope_at(xx, zz) > 0.25: ok = false
			if ok:
				return Vector3(x, terrain.sample_height(x, z), z)
	return best

## back to the open test ground, facing a direction with nothing solid in the
## way for `reach` metres (trunks, boulders and fences block the capsule)
func _prep(reach := 40.0) -> Vector3:
	steer_to = Vector3.INF
	Game.touch_move = Vector2.ZERO
	world.warp_to(spot)
	await _wait(1.0)
	var space := player.get_world_3d().direct_space_state
	var base := player.global_position
	for k in 24:
		var ang := TAU * k / 24.0
		var dv := Vector3(sin(ang), 0.0, cos(ang))
		var side := Vector3(dv.z, 0.0, -dv.x)
		var free := true
		for h in [0.35, 1.0]:
			for o in [-0.45, 0.0, 0.45]:
				var from: Vector3 = base + Vector3(0, h, 0) + side * o
				var q := PhysicsRayQueryParameters3D.create(from, from + dv * reach, 1)
				q.exclude = [player.get_rid()]
				if not space.intersect_ray(q).is_empty(): free = false
		# and the ground must stay walkable all the way
		for i in range(4, int(reach), 4):
			var p := base + dv * float(i)
			if not wild._ground_ok(p.x, p.z): free = false
		if free: return dv
	_log("WARN no clear direction from %s" % base)
	return _cam_fwd()

func _cam_fwd() -> Vector3:
	var yaw: float = player.camera.get_yaw()
	return Vector3(-sin(yaw), 0.0, -cos(yaw))

func _spawn(sp: String, pos: Vector3, face: Vector3, st: int) -> WildAnimal:
	pos.y = terrain.sample_height(pos.x, pos.z)
	var a: WildAnimal = wild._spawn(sp, pos)
	a.heading = atan2(face.x, face.z)
	a.set("_goal", a.heading)
	a.rotation.y = a.heading
	a._enter(st)
	a.set("_dur", 999.0)
	return a

func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()

func _physics_process(_dt: float) -> void:
	if player == null: return
	if steer_to == Vector3.INF:
		Game.touch_move = Vector2.ZERO
		return
	var w := steer_to - player.global_position
	w.y = 0.0
	if w.length() < 0.05:
		Game.touch_move = Vector2.ZERO
		return
	w = w.normalized()
	var yaw: float = player.camera.get_yaw()
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	Game.touch_move = Vector2(w.dot(right), -w.dot(fwd)) * steer_mag

func _press(a: String, hold := 0.08) -> void:
	Input.action_press(a)
	await get_tree().create_timer(hold, true, true).timeout
	Input.action_release(a)

func _ensure_drawn() -> void:
	if bool(player.call("is_sheathed")):
		await _press("sheathe")
		await _wait(1.2)

func _pstate() -> String:
	return "player state=%d mounted=%s hp=%.0f pos=%s drawn=%s cin=%s" % [int(player.get("state")),
		str(player.call("is_mounted")), float(player.get("hp")), str(player.global_position),
		str(not bool(player.call("is_sheathed"))), str(Game.cinematic)]

func _state_name(a: WildAnimal) -> String:
	return WildAnimal.S.keys()[a.state]

# ------------------------------------------------------------------ A
func _test_stealth() -> void:
	_log("_test_stealth: " + _pstate())
	_clear()
	await _ensure_drawn()
	var f: Vector3 = await _prep(20.0)
	var pp := player.global_position
	var doe := _spawn("doe", pp + f * 16.0, f, WildAnimal.S.GRAZE)
	await _wait(0.5)
	player.set("walk_mode", true)
	steer_to = doe.global_position
	steer_mag = 1.0
	var t := 0.0
	var first_alert := -1.0
	var struck := false
	var min_d := 999.0
	while t < 20.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not is_instance_valid(doe): break
		var dd := _flat(doe.global_position - player.global_position)
		min_d = minf(min_d, dd)
		steer_to = doe.global_position
		if first_alert < 0.0 and doe.state != WildAnimal.S.GRAZE:
			first_alert = dd
			_log("A doe reacts (%s) at %.2f m  pv=%.2f" % [_state_name(doe), dd, float(wild.get("_pv"))])
		if doe.is_dead or doe.state == WildAnimal.S.FLEE: break
		if dd < 2.4 and not struck:
			struck = true
			steer_mag = 0.25
			_log("A in range at %.2f m, state=%s alert=%.2f" % [dd, _state_name(doe), float(doe.get("_alert"))])
			_press("attack")
			for i in 50:
				await get_tree().physics_frame
				if doe.is_dead: break
			break
	steer_to = Vector3.INF
	player.set("walk_mode", false)
	_log("A end: state=%s hp=%.1f dead=%s min_d=%.2f" % [_state_name(doe), doe.hp, doe.is_dead, min_d])
	_check(struck, "A walking from behind reaches striking range (closest %.2f m)" % min_d)
	_check(doe.is_dead, "A one sneak cut kills the doe")
	await _wait(1.5)

# ------------------------------------------------------------------ B
func _test_harvest() -> void:
	_log("_test_harvest: " + _pstate())
	var c := wild.carcass_near(player.global_position, 4.0)
	_check(c != null, "B carcass found next to the player")
	if c == null: return
	# stand on it
	steer_to = c.global_position
	steer_mag = 0.4
	for i in 120:
		await get_tree().physics_frame
		if _flat(c.global_position - player.global_position) < 1.6: break
	steer_to = Vector3.INF
	await _wait(0.4)
	player.set("hp", 40.0)
	Game.set_gourd(0)
	var hp0: float = player.get("hp")
	await _press("interact", 0.1)
	await _wait(0.6)
	var hp1: float = player.get("hp")
	_log("B hp %.1f -> %.1f gourd %d harvested=%s" % [hp0, hp1, Game.gourd, c.harvested])
	_check(c.harvested and hp1 >= hp0 + 30.0 and Game.gourd >= 1, "B harvest heals and refills a gourd charge")
	await _wait(2.2)
	_check(not is_instance_valid(c) or c.despawn or not wild.animals().has(c), "B harvested carcass sinks away")
	player.set("hp", 100.0)

# ------------------------------------------------------------------ C
func _test_run_spook() -> void:
	_log("_test_run_spook: " + _pstate())
	_clear()
	var f: Vector3 = await _prep(46.0)
	var doe := _spawn("doe", player.global_position + f * 32.0, f, WildAnimal.S.GRAZE)
	await _wait(0.5)
	steer_to = doe.global_position
	steer_mag = 1.0
	var t := 0.0
	var bolt_d := -1.0
	while t < 12.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		steer_to = doe.global_position
		if doe.state == WildAnimal.S.FLEE:
			bolt_d = _flat(doe.global_position - player.global_position)
			break
	steer_to = Vector3.INF
	_log("C dbg paused=%s touch=%s vel=%s mi=%s phys=%s cin=%s hitstop=%.2f buf=%s" % [get_tree().paused, Game.touch_move,
		player.velocity, player.call("_move_input"), player.is_physics_processing(), player.get("cinematic"),
		float(player.get("_hitstop_t")), str(player.get("_buf"))])
	_log("C running approach: doe bolts at %.2f m (pv %.2f)" % [bolt_d, float(wild.get("_pv"))])
	_check(bolt_d > 5.5, "C a running approach spooks a grazing doe out of reach")
	# it really runs: distance grows
	var d0 := _flat(doe.global_position - player.global_position)
	await _wait(2.0)
	var d1 := _flat(doe.global_position - player.global_position)
	_log("C flee distance %.1f -> %.1f m, speed %.1f, anim %s x%.2f" % [d0, d1, doe.speed, doe.get("_clip"), doe.get("_ap").speed_scale if doe.get("_ap") != null else 0.0])
	_check(d1 > d0 + 10.0, "C the doe runs off")

# ------------------------------------------------------------------ D
func _test_seen() -> void:
	_log("_test_seen: " + _pstate())
	_clear()
	var f: Vector3 = await _prep(26.0)
	var doe := _spawn("doe", player.global_position + f * 24.0, -f, WildAnimal.S.LOOK)
	await _wait(0.3)
	player.set("walk_mode", true)
	steer_to = doe.global_position
	steer_mag = 1.0
	var t := 0.0
	var alert_d := -1.0
	var bolt_d := -1.0
	while t < 20.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var dd := _flat(doe.global_position - player.global_position)
		if alert_d < 0.0 and doe.state == WildAnimal.S.ALERT: alert_d = dd
		if doe.state == WildAnimal.S.FLEE:
			bolt_d = dd
			break
	steer_to = Vector3.INF
	player.set("walk_mode", false)
	_log("D doe facing you: alert at %.2f m, bolts at %.2f m" % [alert_d, bolt_d])
	_check(bolt_d > 4.0, "D a doe looking your way spots a walking approach")
	# freezing in the alert ring lets it settle: new doe, stop at the alert
	_clear()
	f = await _prep(22.0)
	doe = _spawn("doe", player.global_position + f * 20.0, -f, WildAnimal.S.LOOK)
	player.set("walk_mode", true)
	steer_to = doe.global_position
	steer_mag = 1.0
	t = 0.0
	while t < 15.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if doe.state == WildAnimal.S.ALERT or doe.state == WildAnimal.S.FLEE: break
	steer_to = Vector3.INF
	player.set("walk_mode", false)
	var st0 := _state_name(doe)
	await _wait(6.0)
	_log("D froze at %.2f m when it looked up (%s): after 6 s state=%s alert=%.2f" % [
		_flat(doe.global_position - player.global_position), st0, _state_name(doe), float(doe.get("_alert"))])
	_check(st0 == "ALERT" and doe.state != WildAnimal.S.FLEE, "D freezing when it looks up lets it settle")

# ------------------------------------------------------------------ E
func _test_boar() -> void:
	_log("_test_boar: " + _pstate())
	_clear()
	player.set("hp", 100.0)
	var f: Vector3 = await _prep(14.0)
	var boar := _spawn("boar", player.global_position + f * 9.0, -f, WildAnimal.S.GRAZE)
	await _wait(0.3)
	# walk in until it notices
	player.set("walk_mode", true)
	steer_to = boar.global_position
	steer_mag = 1.0
	var t := 0.0
	var notice_d := -1.0
	while t < 10.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if boar.state == WildAnimal.S.ALERT:
			notice_d = _flat(boar.global_position - player.global_position)
			break
	steer_to = Vector3.INF
	player.set("walk_mode", false)
	_log("E boar notices at %.2f m" % notice_d)
	# stand and take the first charge
	var hp0: float = player.get("hp")
	t = 0.0
	var states := {}
	while t < 6.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		states[_state_name(boar)] = true
		if float(player.get("hp")) < hp0: break
	var hp1: float = player.get("hp")
	_log("E boar states %s; player hp %.1f -> %.1f" % [str(states.keys()), hp0, hp1])
	_check(states.has("CHARGE") and hp1 < hp0, "E a boar charges and gores a player who stands still")
	# next pass: sidestep when it is close
	await _wait(0.2)
	hp0 = player.get("hp")
	t = 0.0
	var dodged := false
	var passes := 0
	var last := boar.state
	var trace := ""
	var tr_t := 0.0
	while t < 10.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		tr_t -= get_physics_process_delta_time()
		if tr_t <= 0.0:
			tr_t = 0.1
			trace += "%s%.1f%s " % [_state_name(boar).substr(0, 2), _flat(boar.global_position - player.global_position), "*" if int(player.get("state")) == 4 else ""]
		if boar.state != last and boar.state == WildAnimal.S.CHARGE: passes += 1
		last = boar.state
		var dd := _flat(boar.global_position - player.global_position)
		if boar.state == WildAnimal.S.CHARGE and dd < 6.0 and not dodged:
			dodged = true
			var side := Vector3(sin(boar.heading + PI * 0.5), 0, cos(boar.heading + PI * 0.5))
			steer_to = player.global_position + side * 6.0
			steer_mag = 1.0
			await get_tree().physics_frame
			await get_tree().physics_frame
			_press("dodge")
		if dodged and (boar.state == WildAnimal.S.RECOVER or boar.state == WildAnimal.S.WALK):
			break
	steer_to = Vector3.INF
	var hp2: float = player.get("hp")
	_log("E sidestep pass: hp %.1f -> %.1f (boar %s)  trace: %s" % [hp0, hp2, _state_name(boar), trace])
	_check(hp2 >= hp0, "E dodging sideways out of the charge line avoids the hit")
	# fight it the way it is meant to be fought: sidestep the charge, cut it
	# while it skids round
	player.set("hp", 100.0)
	t = 0.0
	var cut_t := 0.0
	var dodge_t := 0.0
	var hp_b0 := boar.hp
	var bites := 0
	var hp_last: float = player.get("hp")
	var windows := 0
	var was_rec := false
	while t < 45.0 and not boar.is_dead and boar.state != WildAnimal.S.FLEE:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		cut_t -= dt
		dodge_t -= dt
		var dd := _flat(boar.global_position - player.global_position)
		var rec := boar.state == WildAnimal.S.RECOVER
		if rec and not was_rec: windows += 1
		was_rec = rec
		if boar.state == WildAnimal.S.CHARGE and dd < 6.0 and dodge_t <= 0.0:
			dodge_t = 1.2
			var side := Vector3(sin(boar.heading + PI * 0.5), 0, cos(boar.heading + PI * 0.5))
			steer_to = player.global_position + side * 6.0
			steer_mag = 1.0
			await get_tree().physics_frame
			await get_tree().physics_frame
			_press("dodge")
		elif rec or boar.state == WildAnimal.S.ALERT:
			if dd < 2.6 and cut_t <= 0.0:
				cut_t = 0.42
				steer_to = boar.global_position
				steer_mag = 0.3
				_press("attack")
			elif dd >= 2.6 and dodge_t <= 0.4:
				steer_to = boar.global_position
				steer_mag = 1.0
		elif boar.state == WildAnimal.S.WALK or boar.state == WildAnimal.S.GRAZE or boar.state == WildAnimal.S.IDLE:
			steer_to = boar.global_position
			steer_mag = 1.0
		var php: float = player.get("hp")
		if php < hp_last - 0.5: bites += 1
		hp_last = php
		if php < 30.0:
			player.set("hp", 100.0)
			hp_last = 100.0
	steer_to = Vector3.INF
	_log("E boar fight: %.1f s, openings %d, boar hp %.0f -> %.0f (%s), bites taken %d" % [
		t, windows, hp_b0, boar.hp, _state_name(boar), bites])
	_check(boar.hp < hp_b0, "E cuts land while it skids round")
	_check(boar.is_dead or boar.state == WildAnimal.S.FLEE, "E the boar can be cut down or driven off")
	# a dead boar rolls over (it has no death clip)
	if not boar.is_dead:
		boar.take_hit({"damage": 999.0, "source": player})
	await _wait(1.0)
	var piv: Node3D = boar.get("_pivot")
	_log("E dead boar roll %.2f rad" % piv.rotation.z)
	_check(absf(piv.rotation.z) > 1.2, "E the dead boar rolls onto its side")
	await _wait(0.5)

# ------------------------------------------------------------------ F
func _test_wolves() -> void:
	_log("_test_wolves: " + _pstate())
	_clear()
	player.set("hp", 100.0)
	await _prep(10.0)
	world.set_time_of_day(23.0)
	await _wait(1.0)
	_check(wild.is_night(), "F it is night")
	wild.set("_pack_cd", 0.0)
	var t := 0.0
	var wolves: Array = []
	while t < 5.0 and wolves.is_empty():
		await _wait(0.25)
		t += 0.25
		for a in wild.animals():
			if a.is_predator(): wolves.append(a)
	_check(wolves.size() >= 2, "F a pack of %d wolves arrives" % wolves.size())
	if wolves.is_empty(): return
	_log("F pack spawned %.1f m away" % _flat(wolves[0].global_position - player.global_position))
	var hp0: float = player.get("hp")
	t = 0.0
	var closest := 999.0
	var max_attackers := 0
	var bites := 0
	var hp_last := hp0
	while t < 40.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var att := 0
		for w in wolves:
			if not is_instance_valid(w): continue
			closest = minf(closest, _flat(w.global_position - player.global_position))
			if w.state == WildAnimal.S.ATTACK or w.state == WildAnimal.S.CHARGE: att += 1
		max_attackers = maxi(max_attackers, att)
		var hp: float = player.get("hp")
		if hp < hp_last - 0.5: bites += 1
		hp_last = hp
		if bites >= 2: break
		if hp < 30.0:
			player.set("hp", 100.0)
			hp_last = 100.0
	_log("F after %.1f s: closest %.1f m, bites %d, max attackers at once %d" % [t, closest, bites, max_attackers])
	_check(bites >= 1, "F the wolves close in and bite")
	_check(max_attackers <= 1, "F wolves attack one at a time")
	# fight back a while
	t = 0.0
	var cut_t := 0.0
	var kills0: int = wild.kills
	while t < 30.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		cut_t -= dt
		var near_w: WildAnimal = null
		var nd := 999.0
		for w in wolves:
			if not is_instance_valid(w) or w.is_dead: continue
			var dd := _flat(w.global_position - player.global_position)
			if dd < nd:
				nd = dd
				near_w = w
		if near_w == null: break
		if nd < 3.2 and cut_t <= 0.0:
			cut_t = 0.5
			steer_to = near_w.global_position
			steer_mag = 0.3
			_press("attack")
		elif nd >= 3.2:
			steer_to = Vector3.INF
		if float(player.get("hp")) < 30.0: player.set("hp", 100.0)
		if wild.kills > kills0: break
	steer_to = Vector3.INF
	_log("F fight: kills %d (after %.1f s)" % [wild.kills - kills0, t])
	_check(wild.kills > kills0, "F a wolf can be killed")
	# dawn: the rest leave
	world.set_time_of_day(8.0)
	await _wait(6.0)
	var fleeing := 0
	var alive := 0
	for w in wolves:
		if not is_instance_valid(w) or w.is_dead: continue
		alive += 1
		if w.state == WildAnimal.S.FLEE: fleeing += 1
	_log("F dawn: %d alive, %d fleeing" % [alive, fleeing])
	_check(alive == fleeing, "F wolves leave at dawn")

# ------------------------------------------------------------------ sizes
## CPU-skins every mesh of the animal in its current pose and reports the
## real extent relative to the animal's origin (which sits on the ground).
func _skinned_box(a: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n in a.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree(): continue
		var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		var skin: Skin = mi.skin
		var xf: Array[Transform3D] = []
		if skel != null and skin != null:
			for bi in skin.get_bind_count():
				var bone := skin.get_bind_bone(bi)
				if bone < 0: bone = skel.find_bone(skin.get_bind_name(bi))
				xf.append(skel.global_transform * skel.get_bone_global_pose(bone) * skin.get_bind_pose(bi))
		for si in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones = arr[Mesh.ARRAY_BONES]
			var wts = arr[Mesh.ARRAY_WEIGHTS]
			var nb := 0
			if xf.size() > 0 and bones != null and verts.size() > 0: nb = bones.size() / verts.size()
			for vi in verts.size():
				var p := Vector3.ZERO
				if nb > 0:
					var wsum := 0.0
					for k in nb:
						var w: float = wts[vi * nb + k]
						if w <= 0.0: continue
						p += (xf[bones[vi * nb + k]] * verts[vi]) * w
						wsum += w
					if wsum > 0.0: p /= wsum
				else:
					p = mi.global_transform * verts[vi]
				p -= a.global_position
				if first:
					box = AABB(p, Vector3.ZERO)
					first = false
				else:
					box = box.expand(p)
	return box

func _measure_models() -> void:
	_clear()
	await _prep(14.0)
	var base := player.global_position + _cam_fwd() * 10.0
	for sp in ["doe", "stag", "fox", "boar", "wolf"]:
		for st in [WildAnimal.S.IDLE, WildAnimal.S.FLEE]:
			var a := _spawn(sp, base, Vector3(1, 0, 0), st)
			a.set("_goal", a.heading)
			for i in 8: await get_tree().process_frame
			var b := _skinned_box(a)
			_log("SIZE %-5s %-4s ground %+.2f m  top %.2f m  nose-tail %.2f m  width %.2f m" % [sp,
				"idle" if st == WildAnimal.S.IDLE else "run", b.position.y, b.end.y, b.size.x, b.size.z])
			wild._remove(a)
