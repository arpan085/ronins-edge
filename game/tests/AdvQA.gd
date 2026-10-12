extends Node
## v0.16 "advanced" QA on the real Main.tscn (run headless):
##  camps   spawn table: seven camps, no stacking, dry ground, routes, one boss
##  sense   sight cone, crouch, night, tall-grass cover, hearing, Silent Step
##  alarm   a shout pulls in the camp, others come to look
##  stealth assassination (+skill gate), chain, witnesses
##  smoke   blinds, loses pursuers, hides you, enables assassination
##  ai      guard / unblockable / kicks / behind, posture regen, perilous thrust
##          vs block & perfect deflect & Mikiri, sweep vs jump & block, feints,
##          spacing slots
##  skills  fox pounce, Shadow Step, Iaijutsu, Steady Hand, Unbroken,
##          Mending, Spirit Blade Mastery, skill rules + save, techniques UI,
##          kill XP, captains-are-not-bosses
## Prints "ADVQA" lines and "ADVQA_DONE fails=N".

var main: Node
var world: World
var player: Player
var terrain: Terrain
var fails := 0
var passes := 0
var lines: Array[String] = []
var spot := Vector3.ZERO
var face := Vector3.FORWARD
var steer_to := Vector3.INF
var steer_mag := 0.0
var _n := 0

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
	player = world.player
	terrain = world.terrain
	_log("start player=%s enemies=%d spawns=%d" % [player.global_position, world.enemies.size(), world.spawn_table.size()])
	if _on("camps"): _test_camps()
	if _on("camp_runtime"): await _test_camp_runtime()
	# isolate the rest: no camps, no animals, clear midday
	world.spawn_table.clear()
	_clear_enemies()
	world.wild.set("_target", 0)
	world.wild.set("_pack_cd", 1.0e9)
	for a in world.wild.animals().duplicate(): world.wild._remove(a)
	world.set_weather("clear", true)
	world.set_time_of_day(11.0)
	spot = _find_open(player.global_position)
	world.warp_to(spot)
	await _wait(1.5)
	spot = player.global_position
	face = await _open_dir(26.0)
	_log("test ground %s face=%s biome=%s" % [spot.snapped(Vector3.ONE * 0.1), face.snapped(Vector3.ONE * 0.01), terrain.biome_at(spot.x, spot.z)])
	if _on("sight"): await _test_sight()
	if _on("night"): await _test_night()
	if _on("cover"): _test_cover()
	if _on("hearing"): await _test_hearing()
	if _on("alarm"): await _test_alarm()
	if _on("assassination"): await _test_assassination()
	if _on("chain"): await _test_chain()
	if _on("witness"): await _test_witness()
	if _on("smoke"): await _test_smoke()
	if _on("guard"): await _test_guard()
	if _on("posture_regen"): await _test_posture_regen()
	if _on("perilous_thrust"): await _test_perilous_thrust()
	if _on("mikiri"): await _test_mikiri()
	if _on("perilous_sweep"): await _test_perilous_sweep()
	if _on("feint"): await _test_feint()
	if _on("slots"): await _test_slots()
	if _on("fox"): await _test_fox()
	if _on("shadow_step"): await _test_shadow_step()
	if _on("iai"): await _test_iai()
	if _on("passives"): await _test_passives()
	if _on("blade_mastery"): await _test_blade_mastery()
	if _on("skill_rules"): _test_skill_rules()
	if _on("ui"): await _test_ui()
	if _on("kill_xp"): await _test_kill_xp()
	_log("SUMMARY pass=%d fails=%d" % [passes, fails])
	print("\n".join(lines))
	print("ADVQA_DONE fails=%d" % fails)
	get_tree().quit()

# ------------------------------------------------------------------ helpers
## ADVQA_ONLY=night,smoke runs just those tests (the set-up always runs)
func _on(t: String) -> bool:
	var only := OS.get_environment("ADVQA_ONLY")
	return only == "" or t in only.split(",")

func _log(s: String) -> void:
	print("ADVQA " + s)
	lines.append(s)

func _check(ok: bool, what: String) -> void:
	if ok: passes += 1
	else: fails += 1
	_log(("PASS " if ok else "FAIL ") + what)

func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, true).timeout

func _frames(n: int) -> void:
	for i in n: await get_tree().physics_frame

func _press(a: String, hold := 0.08) -> void:
	Input.action_press(a)
	await get_tree().create_timer(hold, true, true).timeout
	Input.action_release(a)

func _clear_enemies() -> void:
	for e in world.enemies:
		if is_instance_valid(e): e.queue_free()
	world.enemies.clear()
	world.get("_live_ids").clear()
	EnemyBase.attackers = 0

func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, terrain.sample_height(p.x, p.z), p.z)

func _yaw_of(dir: Vector3) -> float:
	return atan2(dir.x, dir.z)

## A clean slate for each case: healthy, standing, no techniques, no foes.
func _reset(skills: Array = []) -> void:
	_clear_enemies()
	await _frames(2)
	steer_to = Vector3.INF
	Game.touch_move = Vector2.ZERO
	for a in ["block", "sprint", "attack", "dodge", "interact", "smoke", "crouch", "jump"]:
		Input.action_release(a)
	Engine.time_scale = 1.0
	player.revive()
	player.walk_mode = false
	player.set("_lock_target", null)
	Skills.reset()
	for id in skills:
		if not Skills.has(String(id)): Skills.unlocked.append(String(id))
	Game.stance = "stone"
	player.stance = "stone"
	Game.set_smoke(Game.smoke_max)
	player.global_position = _ground(spot) + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	player.rotation.y = _yaw_of(face)
	world.set_time_of_day(11.0)
	await _frames(3)

func _enemy(kind: String, pos: Vector3, look: Vector3, group := "") -> EnemyBase:
	_n += 1
	var e: EnemyBase = world.spawn_enemy_at(kind, _ground(pos), "qa_%s_%d" % [kind, _n])
	var y := _yaw_of(look)
	e.rotation.y = y
	e.post_yaw = y
	e.set("_want_yaw", y)
	e.set("_look_t", 999.0)
	e.set("_t", -100.0)
	e.route = []
	e.group = group
	return e

func _fight(e: EnemyBase) -> void:
	e._begin_alert(false)
	e.set("_alert_t", 99.0)
	e.state = EnemyBase.S.COMBAT_READY

## time until the soldier is fully aware (or the timeout)
func _time_to_alert(e: EnemyBase, timeout: float) -> float:
	var t := 0.0
	while t < timeout:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not is_instance_valid(e): return timeout
		if e.awareness >= 1.0 or e.in_combat: return t
	return timeout

func _find_open(c: Vector3) -> Vector3:
	for ring in range(0, 40):
		var r := 30.0 + ring * 25.0
		for k in 16:
			var ang := TAU * k / 16.0 + ring * 0.37
			var x := c.x + sin(ang) * r
			var z := c.z + cos(ang) * r
			if not world.wild._ground_ok(x, z): continue
			var b := terrain.biome_at(x, z)
			if not b in ["grassland", "farmland"]: continue
			var ok := true
			for j in 8:
				var a2 := TAU * j / 8.0
				for rr in [10.0, 26.0]:
					var xx: float = x + sin(a2) * rr
					var zz: float = z + cos(a2) * rr
					if not world.wild._ground_ok(xx, zz) or terrain.slope_at(xx, zz) > 12.0: ok = false
			if ok: return Vector3(x, terrain.sample_height(x, z), z)
	return c

func _open_dir(reach: float) -> Vector3:
	var space := player.get_world_3d().direct_space_state
	var base := player.global_position
	for k in 24:
		var ang := TAU * k / 24.0
		var dv := Vector3(sin(ang), 0.0, cos(ang))
		var free := true
		for h in [0.6, 1.4]:
			var from: Vector3 = base + Vector3(0, h, 0)
			var q := PhysicsRayQueryParameters3D.create(from, from + dv * reach, 1)
			q.exclude = [player.get_rid()]
			if not space.intersect_ray(q).is_empty(): free = false
			var q2 := PhysicsRayQueryParameters3D.create(from - dv * 8.0, from, 1)
			q2.exclude = [player.get_rid()]
			if not space.intersect_ray(q2).is_empty(): free = false
		if free: return dv
	return Vector3.FORWARD

func _physics_process(_dt: float) -> void:
	if player == null: return
	if steer_to == Vector3.INF:
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

func _stop() -> void:
	steer_to = Vector3.INF
	Game.touch_move = Vector2.ZERO

# ------------------------------------------------------------------ camps
func _test_camps() -> void:
	var tbl: Array = world.spawn_table
	var zones := {}
	var ids := {}
	var dup := false
	var bad_pos := 0
	var bosses := 0
	var boss_ok := false
	var routes_ok := true
	for s in tbl:
		var id := String(s["id"])
		if ids.has(id): dup = true
		ids[id] = true
		var p: Vector3 = s["pos"]
		if bool(s.get("boss", false)):
			bosses += 1
			boss_ok = String(s["kind"]) == "captain" and id == "boss_captain"
			continue
		var z := String(s["zone"])
		if not zones.has(z): zones[z] = []
		zones[z].append(p)
		if not world._spot_ok(p.x, p.z): bad_pos += 1
		if String(s.get("role", "")) == "patrol" and (s.get("route", []) as Array).size() < 3: routes_ok = false
	_check(zones.size() == 7, "seven camps (%s)" % ", ".join(zones.keys()))
	_check(not dup, "spawn ids unique (%d)" % ids.size())
	_check(bosses == 1 and boss_ok and bool(tbl[-1].get("boss", false)), "exactly one boss, Kuroda, last in the table")
	_check(bad_pos == 0, "every post on dry walkable ground in bounds (bad=%d)" % bad_pos)
	_check(routes_ok, "every patroller has a route of 3+ waypoints")
	var stacked := 0
	var narrow := 0
	for z in zones.keys():
		var ps: Array = zones[z]
		var spread := 0.0
		for i in ps.size():
			for j in range(i + 1, ps.size()):
				var d: float = (ps[i] as Vector3).distance_to(ps[j])
				spread = maxf(spread, d)
				if d < 1.5: stacked += 1
		if spread < 8.0: narrow += 1
		_log("camp %-8s n=%d spread=%.1f m centre=%s" % [z, ps.size(), spread, str(world.camps[z]["center"].snapped(Vector3.ONE))])
	_check(stacked <= 1, "no stacked soldiers (pairs < 1.5 m: %d)" % stacked)
	_check(narrow == 0, "every camp spreads over 8 m+ (the v0.15 diagonal-line bug)")
	var forest := 0
	for s in tbl:
		if String(s["zone"]) == "forest" and not bool(s.get("boss", false)): forest += 1
	_check(forest == 6, "forest keeps its 6 soldiers for the 5-kill quest (%d)" % forest)

func _test_camp_runtime() -> void:
	var c: Vector3 = world.camps["forest"]["center"]
	var away := c + Vector3(34, 0, 0)
	world.warp_to(away)
	await _wait(3.0)
	var camp: Array = []
	for e in world.enemies:
		if is_instance_valid(e) and String(e.zone) == "forest": camp.append(e)
	_check(camp.size() >= 5, "forest camp spawns when you come near (%d)" % camp.size())
	var walker: EnemyBase = null
	var start := Vector3.ZERO
	for e in camp:
		if not (e.route as Array).is_empty():
			walker = e
			start = e.global_position
			break
	var sentry_ok := true
	for e in camp:
		if (e.route as Array).is_empty() and absf(angle_difference(e.rotation.y, e.post_yaw)) > 1.4: sentry_ok = false
	_check(sentry_ok, "sentries face out from their posts")
	_check(walker != null, "a patroller is out")
	if walker != null:
		await _wait(9.0)
		var moved := walker.global_position.distance_to(start)
		_check(moved > 3.0, "the patrol walks its route (%.1f m in 9 s, state=%s)" % [moved, EnemyBase.S.keys()[walker.state]])
		_check(not walker.in_combat, "and does not notice you 30 m off")
	var g := ""
	for e in camp: g = String(e.group)
	_check(g == "forest_camp", "camp soldiers share an alert group (%s)" % g)

# ------------------------------------------------------------------ perception
func _test_sight() -> void:
	await _reset()
	var e := _enemy("ashigaru", spot + face * 9.0, -face)
	await _frames(4)
	var t_stand := await _time_to_alert(e, 8.0)
	await _reset()
	player.set_crouch(true)
	await _frames(2)
	var e2 := _enemy("ashigaru", spot + face * 9.0, -face)
	await _frames(4)
	var t_crouch := await _time_to_alert(e2, 8.0)
	_log("sight 9 m: standing %.2f s, crouched %.2f s" % [t_stand, t_crouch])
	_check(t_stand < 3.0, "seen standing in the open at 9 m (%.2f s)" % t_stand)
	_check(t_crouch > t_stand * 1.3, "crouching takes longer to notice (%.2f vs %.2f s)" % [t_crouch, t_stand])
	# behind his back, crouched, 4 m: not noticed
	await _reset()
	player.set_crouch(true)
	var e3 := _enemy("ashigaru", spot + face * 4.0, face)
	await _wait(3.0)
	_check(e3.awareness < EnemyBase.SUSPECT and not e3.in_combat, "crouched behind his back at 4 m: unseen (aw=%.2f)" % e3.awareness)
	# Silent Step: noticed later
	await _reset(["s_silent"])
	player.set_crouch(true)
	var e4 := _enemy("ashigaru", spot + face * 9.0, -face)
	await _frames(4)
	var t_silent := await _time_to_alert(e4, 8.0)
	_check(t_silent > t_crouch * 1.25, "Silent Step: 40%% slower to notice (%.2f vs %.2f s)" % [t_silent, t_crouch])

func _test_night() -> void:
	await _reset()
	var e := _enemy("ashigaru", spot + face * 9.0, -face)
	await _frames(4)
	var t_day := await _time_to_alert(e, 8.0)
	await _reset()
	world.set_time_of_day(0.5)
	await _frames(4)
	var e2 := _enemy("ashigaru", spot + face * 9.0, -face)
	await _frames(4)
	var t_night := await _time_to_alert(e2, 10.0)
	var ll: float = world.daynight.daylight()
	_check(t_night > t_day * 1.3, "night halves their sight (day %.2f s, night %.2f s, daylight=%.2f)" % [t_day, t_night, ll])
	world.set_time_of_day(11.0)

func _test_cover() -> void:
	# densest tall grass near the test ground
	var best := Vector3.INF
	var bg := 0.0
	for ring in range(1, 60):
		for k in 24:
			var a := TAU * float(k) / 24.0
			var x := spot.x + cos(a) * float(ring) * 12.0
			var z := spot.z + sin(a) * float(ring) * 12.0
			if x < 20.0 or z < 20.0 or x > 1510.0 or z > 1510.0: continue
			if terrain.biome_at(x, z) != "tallgrass": continue
			var g := terrain.grass_density_at(x, z)
			if g > bg:
				bg = g
				best = Vector3(x, 0, z)
		if bg > 0.7: break
	if best == Vector3.INF:
		_check(false, "found tall grass to hide in")
		return
	var keep := player.global_position
	player.global_position = _ground(best) + Vector3(0, 0.05, 0)
	player.set_crouch(true)
	player.set("_cover", player._cover_here())
	var cv: float = player.cover()
	var vis: float = player.stealth_visibility()
	player.set_crouch(false)
	var vis_up: float = player.stealth_visibility()
	_log("tall grass at %s density %.2f: cover %.2f vis crouched %.2f standing %.2f" % [best.snapped(Vector3.ONE), bg, cv, vis, vis_up])
	_check(cv > 0.5 and vis < 0.25 and vis_up >= 0.6, "crouched in tall grass you are nearly invisible")
	player.global_position = keep

func _test_hearing() -> void:
	await _reset()
	var e := _enemy("ashigaru", spot + face * 6.0, face)     # back to you
	await _frames(3)
	player.set_crouch(true)
	var side := Vector3(face.z, 0, -face.x)
	steer_to = spot + side * 12.0
	steer_mag = 1.0
	await _wait(0.8)
	var nr_crouch: float = player.noise_radius()
	await _wait(1.2)
	var aw_quiet := e.awareness
	_stop()
	await _reset()
	var e2 := _enemy("ashigaru", spot + face * 6.0, face)
	await _frames(3)
	Input.action_press("sprint")
	steer_to = spot + side * 14.0
	steer_mag = 1.0
	await _wait(0.8)
	var nr_sprint: float = player.noise_radius()
	await _wait(1.0)
	Input.action_release("sprint")
	_stop()
	var heard := e2.state == EnemyBase.S.INVESTIGATE or e2.awareness >= EnemyBase.SUSPECT or e2.in_combat
	_log("noise: crouch-walk %.1f m (aw %.2f), sprint %.1f m (aw %.2f state %s)" % [nr_crouch, aw_quiet, nr_sprint, e2.awareness, EnemyBase.S.keys()[e2.state]])
	_check(nr_crouch < 2.0 and nr_sprint > 10.0, "crouch-walking is quiet, sprinting is loud")
	_check(aw_quiet < EnemyBase.SUSPECT, "crouch-walking past his back is not heard")
	_check(heard, "sprinting past his back is heard: he turns to look")
	Skills.unlocked.append("s_silent")
	_check(player.noise_radius() <= nr_sprint * 0.6 or player.noise_radius() < 0.5, "Silent Step halves the noise")

func _test_alarm() -> void:
	await _reset()
	var c := spot + face * 30.0
	var side := Vector3(face.z, 0, -face.x)
	var e1 := _enemy("ashigaru", c, face, "qa_camp")
	var e2 := _enemy("ashigaru", c + side * 8.0, face, "qa_camp")
	var e3 := _enemy("archer", c + side * 26.0, face, "qa_camp")
	var e4 := _enemy("ashigaru", c - side * 18.0, face, "other")
	var e5 := _enemy("ashigaru", c + face * 60.0, face, "far")
	await _frames(3)
	e1._begin_alert()
	await _wait(0.4)
	_check(e2.in_combat and e3.in_combat, "the alarm pulls in the whole camp (8 m and 26 m)")
	_check(not e4.in_combat and (e4.state == EnemyBase.S.INVESTIGATE or e4.awareness >= 0.5), "another camp 18 m off comes to look (state %s)" % EnemyBase.S.keys()[e4.state])
	_check(not e5.in_combat and e5.awareness < 0.1, "60 m away nobody hears it")

# ------------------------------------------------------------------ stealth kills
func _behind(e: EnemyBase, d: float) -> Vector3:
	var back: Vector3 = -e.global_transform.basis.z
	back.y = 0.0
	return e.global_position + back.normalized() * d

func _test_assassination() -> void:
	await _reset()
	var e := _enemy("ashigaru", spot + face * 3.0, face)
	await _frames(3)
	player.global_position = _ground(_behind(e, 1.8)) + Vector3(0, 0.05, 0)
	player.set_crouch(true)
	await _frames(6)
	_check(player.assassination_target() == null, "no assassination without the technique")
	await _reset(["s_silent", "s_assassin"])
	var e2 := _enemy("ashigaru", spot + face * 3.0, face)
	await _frames(3)
	player.global_position = _ground(_behind(e2, 1.8)) + Vector3(0, 0.05, 0)
	player.set_crouch(true)
	await _frames(6)
	var tgt := player.assassination_target()
	_check(tgt == e2, "crouched behind an unaware soldier: ASSASSINATE is offered")
	var xp0 := Game.xp
	await _press("interact")
	var t := 0.0
	while t < 2.0 and not e2.is_dead:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check(e2.is_dead, "interact kills him in one stroke (%.2f s)" % t)
	_check(Game.xp >= xp0 + 1, "an assassination earns mastery (+%d)" % (Game.xp - xp0))
	await _wait(1.2)
	_check(player.state != Player.S.ASSASSIN and player.crouching, "back in control, still crouched (state %d)" % player.state)
	# a soldier who is fighting you cannot be assassinated
	var e3 := _enemy("ashigaru", player.global_position + face * 1.8, -face)
	_fight(e3)
	e3.set("_cd", 999.0)
	await _frames(3)
	_check(player.assassination_target() == null, "not on a soldier already fighting you")

func _test_chain() -> void:
	for with_chain in [false, true]:
		var sk := ["s_silent", "s_assassin"]
		if with_chain: sk.append("s_chain")
		await _reset(sk)
		var e1 := _enemy("ashigaru", spot + face * 3.0, face)
		var e2 := _enemy("ashigaru", spot + face * 3.0 + face * 5.5, face)
		e2.guard_chance = 0.0
		await _frames(3)
		player.global_position = _ground(_behind(e1, 1.8)) + Vector3(0, 0.05, 0)
		player.set_crouch(true)
		await _frames(6)
		await _press("interact")
		await _wait(0.5)
		await _press("attack")
		await _wait(1.6)
		if with_chain:
			_check(e1.is_dead and e2.is_dead, "Chain Assassination: a second soldier 5.5 m on dies too")
		else:
			_check(e1.is_dead and not e2.is_dead, "without the technique only the first dies")

func _test_witness() -> void:
	await _reset(["s_silent", "s_assassin"])
	var v := _enemy("ashigaru", spot + face * 3.0, face)
	var w := _enemy("ashigaru", spot + face * 3.0 + face * 6.0, -face)   # looking at the victim's front
	await _frames(3)
	player.global_position = _ground(_behind(v, 1.8)) + Vector3(0, 0.05, 0)
	player.set_crouch(true)
	await _frames(6)
	# the witness can see Kaito too; give the kill a fair chance first
	w.awareness = 0.0
	await _press("interact")
	await _wait(0.8)
	_check(v.is_dead, "victim dies")
	_check(w.in_combat or w.awareness >= 0.6, "a soldier watching it happen raises the alarm (aw %.2f)" % w.awareness)

func _test_smoke() -> void:
	await _reset()
	var sb := get_tree().get_nodes_in_group("smoke_cloud").size()
	await _press("smoke")
	await _wait(0.8)
	_check(get_tree().get_nodes_in_group("smoke_cloud").size() == sb and Game.smoke == Game.smoke_max, "no smoke bomb without the technique")
	await _reset(["s_silent", "s_assassin", "s_smoke"])
	var near := _enemy("ashigaru", spot + face * 2.4, -face)
	var far := _enemy("ashigaru", spot + face * 12.0, -face)
	_fight(near); _fight(far)
	near.set("_cd", 999.0); far.set("_cd", 999.0)
	await _frames(3)
	await _press("smoke")
	await _wait(0.7)
	_check(Game.smoke == Game.smoke_max - 1, "a bomb is used (%d left)" % Game.smoke)
	_check(near.is_blind(), "the soldier inside the cloud is blinded")
	_check(not far.in_combat and far.state == EnemyBase.S.INVESTIGATE, "the one outside loses you and searches (state %s)" % EnemyBase.S.keys()[far.state])
	_check(player.in_smoke() and player.stealth_visibility() == 0.0, "you cannot be seen inside it")
	var tgt := player.assassination_target()
	_check(tgt == near, "a blinded soldier can be assassinated (state %s, %.2f m, dy %.2f, can %s)" % [Player.S.keys()[player.state], near.global_position.distance_to(player.global_position), near.global_position.y - player.global_position.y, near.can_be_assassinated(player)])
	await _press("interact")
	await _wait(1.0)
	_check(near.is_dead, "assassinated in the smoke")
	await _wait(8.5)
	_check(get_tree().get_nodes_in_group("smoke_cloud").is_empty(), "the cloud clears and frees itself")

# ------------------------------------------------------------------ enemy combat AI
func _hit_info(extra := {}) -> Dictionary:
	var d := {"damage": 1.0, "posture": 1.0, "heavy": false, "source": player}
	for k in extra.keys(): d[k] = extra[k]
	return d

func _count_blocks(e: EnemyBase, n: int, extra := {}) -> int:
	var b := 0
	for i in n:
		var hp0 := e.hp
		e.state = EnemyBase.S.COMBAT_READY
		e.take_hit(_hit_info(extra))
		if e.hp >= hp0: b += 1
		e.set("_pressure", 0.0)
		e.set("_hitstop_t", 0.0)
	return b

func _test_guard() -> void:
	await _reset()
	var e := _enemy("ashigaru", spot + face * 2.0, -face)
	_fight(e)
	e.set("_cd", 999.0)
	e.max_hp = 999.0; e.hp = 999.0
	await _frames(3)
	var plain := _count_blocks(e, 40)
	var unbl := _count_blocks(e, 20, {"unblockable": true})
	var kicks := _count_blocks(e, 20, {"kick": true})
	e.rotation.y = _yaw_of(face)          # turn his back
	var behind := _count_blocks(e, 20)
	_log("guard: plain %d/40 unblockable %d/20 kick %d/20 behind %d/20" % [plain, unbl, kicks, behind])
	_check(plain >= 5 and plain <= 24, "soldiers block some cuts (%d/40 at 30%%)" % plain)
	_check(unbl == 0 and kicks == 0 and behind == 0, "never an unblockable cut, a kick, or a cut from behind")

func _test_posture_regen() -> void:
	await _reset()
	var e := _enemy("ashigaru", spot + face * 5.0, -face)
	_fight(e)
	e.set("_cd", 999.0)
	e.posture = 40.0
	e.set("_posture_idle", 0.0)
	await _wait(1.0)
	var p1 := e.posture
	await _wait(2.5)
	var p2 := e.posture
	_check(p1 >= 39.0 and p2 < p1 - 6.0, "enemy posture holds a moment, then drains (%.1f -> %.1f)" % [p1, p2])

func _start_attack(e: EnemyBase) -> void:
	EnemyBase.attackers = 0
	e.state = EnemyBase.S.COMBAT_READY
	e._take_token()
	e._begin_attack()

## waits until the attack is about to land (windup_left < lead) or it ends
func _until_windup(e: EnemyBase, lead: float) -> bool:
	var t := 0.0
	while t < 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if e.state != EnemyBase.S.ATTACK: return false
		var wl: float = e.windup_left()
		if wl >= 0.0 and wl < lead: return true
	return false

func _perilous_foe(kind: String) -> EnemyBase:
	var e := _enemy("ashigaru", spot + face * 2.2, -face)
	_fight(e)
	e.set("_cd", 999.0)
	e.guard_chance = 0.0
	e.delay_chance = 0.0
	e.feint_chance = 0.0
	e.perilous_thrust = 1.0 if kind == "thrust" else 0.0
	e.perilous_sweep = 1.0 if kind == "sweep" else 0.0
	return e

func _test_perilous_thrust() -> void:
	# held guard: the thrust goes straight through
	await _reset()
	await _press("sheathe")
	await _wait(1.0)
	var e := _perilous_foe("thrust")
	await _frames(3)
	Input.action_press("block")
	await _wait(0.6)
	var hp0 := player.hp
	_start_attack(e)
	var per := e.perilous_kind()
	await _wait(1.6)
	Input.action_release("block")
	var lost := hp0 - player.hp
	_check(per == "thrust", "forced perilous thrust is flagged 危 (%s)" % per)
	_check(lost > 10.0, "a perilous thrust ignores a held guard (-%.0f hp)" % lost)
	# perfect deflect: it does stop the thrust
	await _reset()
	var e2 := _perilous_foe("thrust")
	await _frames(3)
	var hp1 := player.hp
	var p0 := e2.posture
	_start_attack(e2)
	var ok := await _until_windup(e2, 0.11)
	Input.action_press("block")
	await _wait(0.5)
	Input.action_release("block")
	_check(ok and player.hp >= hp1 - 0.5 and e2.posture >= p0 + 25.0, "a perfect deflect stops it and costs him posture (hp -%.0f, posture +%.0f)" % [hp1 - player.hp, e2.posture - p0])

func _test_mikiri() -> void:
	await _reset(["b_deflect", "b_posture", "b_mikiri"])
	var e := _perilous_foe("thrust")
	await _frames(3)
	var hp0 := player.hp
	_start_attack(e)
	var t := 0.0
	while t < 2.0 and e.perilous_progress() < 0.5:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	steer_to = e.global_position
	steer_mag = 1.0
	await _frames(2)
	await _press("dodge", 0.05)
	_stop()
	await _wait(0.4)
	_check(e.posture >= e.max_posture * 0.5 or e.posture_broken, "Mikiri: dodging into the thrust breaks half his posture (%.0f/%.0f)" % [e.posture, e.max_posture])
	_check(player.hp >= hp0 - 0.5, "and you take nothing")
	await _wait(0.35)
	_check(player.riposte_ready(), "and the riposte is ready (state %s)" % Player.S.keys()[player.state])
	await _press("attack", 0.05)
	await _frames(2)
	_check(String(player.get("_move_id")).ends_with("riposte"), "a light attack becomes the riposte (%s)" % String(player.get("_move_id")))

func _test_perilous_sweep() -> void:
	await _reset()
	var e := _perilous_foe("sweep")
	await _frames(3)
	var hp0 := player.hp
	_start_attack(e)
	var per := e.perilous_kind()
	var ok := await _until_windup(e, 0.16)
	await _press("jump", 0.05)
	await _wait(1.2)
	_check(per == "sweep" and ok and player.hp >= hp0 - 0.5, "jumping a perilous sweep: no damage (-%.0f)" % (hp0 - player.hp))
	await _reset()
	var e2 := _perilous_foe("sweep")
	await _frames(3)
	Input.action_press("block")
	await _wait(0.6)
	var hp1 := player.hp
	_start_attack(e2)
	await _wait(1.6)
	Input.action_release("block")
	_check(hp1 - player.hp > 10.0, "a perilous sweep goes through a guard (-%.0f)" % (hp1 - player.hp))

func _test_feint() -> void:
	await _reset()
	var e := _enemy("ashigaru", spot + face * 2.4, -face)
	_fight(e)
	e.set("_cd", 999.0)
	e.guard_chance = 0.0
	e.delay_chance = 0.0
	e.perilous_thrust = 0.0
	e.perilous_sweep = 0.0
	e.feint_chance = 1.0
	await _frames(3)
	var hp0 := player.hp
	_start_attack(e)
	var t := 0.0
	var last_t := 0.0
	var resets := 0
	var hit_at := -1.0
	while t < 3.5:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var et := float(e.get("_t"))
		if e.state == EnemyBase.S.ATTACK and et < last_t - 0.05: resets += 1
		last_t = et
		if hit_at < 0.0 and player.hp < hp0 - 0.5: hit_at = t
	_check(resets >= 1 and hit_at > e.windup * 1.5, "a feint: the blade stops and comes again (restarts %d, hit at %.2f s vs windup %.2f)" % [resets, hit_at, e.windup])

func _test_slots() -> void:
	await _reset()
	var side := Vector3(face.z, 0, -face.x)
	var es: Array = []
	for i in 3:
		var e := _enemy("ashigaru", spot + face * 4.5 + side * (float(i) - 1.0) * 1.2, -face)
		_fight(e)
		e.set("_cd", 999.0)
		es.append(e)
	await _wait(6.0)
	var angs: Array = []
	for e in es:
		var d: Vector3 = (e as EnemyBase).global_position - player.global_position
		angs.append(atan2(d.x, d.z))
	var mind := PI
	for i in angs.size():
		for j in range(i + 1, angs.size()):
			mind = minf(mind, absf(angle_difference(float(angs[i]), float(angs[j]))))
	_check(rad_to_deg(mind) > 40.0, "three soldiers spread round you instead of queueing (closest pair %.0f°)" % rad_to_deg(mind))

# ------------------------------------------------------------------ techniques
func _test_fox() -> void:
	await _reset(["p_fox"])
	await _frames(4)
	var fox = world.get("fox")
	_check(fox != null and is_instance_valid(fox), "Fox Spirit: the fox appears")
	if fox == null: return
	var e := _enemy("ashigaru", spot + face * 4.0, -face)
	_fight(e)
	e.set("_cd", 999.0)
	var t := 0.0
	var distracted := false
	while t < 8.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if float(e.get("_distract_t")) > 0.0: distracted = true
		if distracted and int(fox.pounces) >= 1: break
	_check(int(fox.pounces) >= 1 and distracted, "in a fight it pounces and the soldier turns on it (%.1f s)" % t)
	Skills.reset()
	await _frames(4)
	_check(world.get("fox") == null, "and leaves when the technique is gone")

func _test_shadow_step() -> void:
	await _reset(["p_fox", "p_mend", "p_step"])
	await _press("sheathe")
	await _wait(1.0)
	var e := _enemy("ashigaru", spot + face * 2.2, -face)
	_fight(e)
	e.set("_cd", 999.0)
	e.guard_chance = 0.0
	e.delay_chance = 0.0
	e.feint_chance = 0.0
	e.perilous_thrust = 0.0
	e.perilous_sweep = 0.0
	e.max_hp = 400.0; e.hp = 400.0
	await _frames(3)
	var hp0 := player.hp
	_start_attack(e)
	var ok := await _until_windup(e, 0.1)
	await _press("dodge", 0.05)
	await _wait(0.12)
	var ready := player.shadow_step_ready()
	var ehp := e.hp
	await _press("attack", 0.05)
	await _wait(1.3)
	var rel: Vector3 = player.global_position - e.global_position
	var efwd: Vector3 = e.global_transform.basis.z
	_check(ok and player.hp >= hp0 - 0.5 and ready, "a dodged blow opens SHADOW STEP")
	_check(rel.dot(efwd) < 0.0 or ehp - e.hp > 30.0, "attack: you appear behind him (dot %.2f)" % rel.dot(efwd))
	_check(ehp - e.hp > 30.0, "and the strike lands hard (-%.0f)" % (ehp - e.hp))

func _test_iai() -> void:
	var dmg := {}
	for with_iai in [false, true]:
		var sk := ["b_deflect", "b_posture", "b_iai"] if with_iai else []
		await _reset(sk)
		if player.drawn:
			await _press("sheathe")
			await _wait(1.1)
		var e := _enemy("ashigaru", spot + face * 1.7, -face)
		_fight(e)
		e.set("_cd", 999.0)
		e.guard_chance = 0.0
		e.max_hp = 400.0; e.hp = 400.0
		await _frames(3)
		var h0 := e.hp
		await _press("attack", 0.05)
		await _wait(1.4)
		dmg[with_iai] = h0 - e.hp
	_log("first cut from the sheath: plain %.1f, Iaijutsu %.1f" % [float(dmg[false]), float(dmg[true])])
	_check(float(dmg[true]) > float(dmg[false]) * 1.6 and float(dmg[false]) > 0.0, "Iaijutsu: the draw-cut hits 1.8x")

func _test_passives() -> void:
	await _reset()
	player._begin_block()
	var w0 := float(player.get("_deflect_t"))
	player.state = Player.S.IDLE
	await _reset(["b_deflect"])
	player._begin_block()
	var w1 := float(player.get("_deflect_t"))
	player.state = Player.S.IDLE
	_check(absf(w1 - w0 * 1.2) < 0.005, "Steady Hand: deflect window %.3f -> %.3f s" % [w0, w1])
	var rates := []
	for sk in [[], ["b_deflect", "b_posture"]]:
		await _reset(sk)
		player.posture = 60.0
		player.set("_posture_idle", 1.0)
		await _wait(0.2)
		var a := player.posture
		await _wait(1.0)
		rates.append(a - player.posture)
	_check(float(rates[1]) > float(rates[0]) * 1.2, "Unbroken: posture recovers faster (%.1f vs %.1f /s)" % [float(rates[1]), float(rates[0])])
	await _reset(["p_fox", "p_mend"])
	player.hp = 50.0
	player._perfect_deflect({"source": null}, player.global_position + face)
	var after_deflect := player.hp
	var e := _enemy("ashigaru", spot + face * 2.0, -face)
	await _frames(2)
	e.execute(player)
	await _frames(2)
	_check(absf(after_deflect - 53.0) < 0.01 and absf(player.hp - 59.0) < 0.6, "Spirit Mending: deflect +3, kill +6 (%.1f, %.1f)" % [after_deflect, player.hp])

func _test_blade_mastery() -> void:
	var lens := []
	var landed := []
	for sk in [[], ["p_fox", "p_mend", "p_blade"]]:
		await _reset(sk)
		player.focus = player.max_focus
		player._activate_focus()
		lens.append(float(player.get("_spirit_blade_t")))
		Engine.time_scale = 1.0
		player.set("_slowmo_t", 0.0)
		var e := _enemy("ashigaru", spot + face * 1.6, -face)
		_fight(e)
		e.set("_cd", 999.0)
		e.guard_chance = 1.0
		e.max_hp = 999.0; e.hp = 999.0
		await _frames(3)
		var n := 0
		for i in 6:
			var h0 := e.hp
			e.state = EnemyBase.S.COMBAT_READY
			e.set("_pressure", 0.0)
			player.set("_hit_ids", {})
			player._hit_scan(Player.MOVES["k_a"])
			if e.hp < h0: n += 1
			player.set("_hitstop_t", 0.0)
		landed.append(n)
	_check(float(lens[0]) == 10.0 and float(lens[1]) == 15.0, "Spirit Blade Mastery: 15 s instead of 10")
	_check(int(landed[1]) == 6 and int(landed[0]) < 6, "and its cuts pass any guard (%d/6 vs %d/6 without)" % [int(landed[1]), int(landed[0])])

func _test_skill_rules() -> void:
	Skills.reset()
	Game.mastery_points = 0
	_check(not Skills.unlock("b_deflect"), "no points: nothing to learn")
	Game.mastery_points = 2
	_check(not Skills.unlock("b_posture"), "tier 2 needs its tier 1 first")
	_check(Skills.unlock("b_deflect") and Game.mastery_points == 1, "learning spends points (1 left)")
	_check(not Skills.unlock("b_posture"), "and 2-point techniques need 2")
	Game.mastery_points = 10
	_check(Skills.unlock("b_posture") and Skills.unlock("b_mikiri") and Game.mastery_points == 5, "the fork opens after the trunk")
	_check(Skills.total_cost() == 27, "all twelve techniques cost 27 points (%d)" % Skills.total_cost())
	Skills.deserialize(["b_mikiri", "s_chain", "p_fox"])
	_check(Skills.unlocked == ["p_fox"], "a save with missing prerequisites is cleaned up (%s)" % str(Skills.unlocked))
	Skills.deserialize(["b_deflect", "b_posture", "b_iai", "nonsense"])
	var blob: Array = Skills.serialize()
	Skills.reset()
	Skills.deserialize(blob)
	_check(Skills.has("b_iai") and Skills.unlocked.size() == 3, "serialize/deserialize round trip")
	Skills.reset()

func _test_ui() -> void:
	await _reset()
	var hud = world.hud
	Game.mastery_points = 3
	hud.open_skills()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(hud.is_skills_open() and get_tree().paused, "U opens the techniques screen over a paused game")
	var m = hud.get("_skills")
	var before := String(m.selected)
	m.move_selection(Vector2.RIGHT)
	var after := String(m.selected)
	_check(before != after, "arrows move the selection (%s -> %s)" % [before, after])
	m.selected = "s_silent"
	await get_tree().process_frame
	_check(Skills.state_of("s_silent") == "available", "a 1-point technique shows as learnable with 3 points")
	m.close()
	await get_tree().process_frame
	_check(not hud.is_skills_open() and not get_tree().paused, "closes and unpauses")
	Game.mastery_points = 0

func _test_kill_xp() -> void:
	await _reset()
	var xp0 := Game.xp
	var s := {"id": "qa_xp_soldier", "kind": "ashigaru", "zone": "shrine", "pos": _ground(spot + face * 4.0), "boss": false}
	var e: EnemyBase = world._spawn_enemy(s)
	var c: EnemyBase = world._spawn_enemy({"id": "qa_xp_captain", "kind": "captain", "zone": "castle", "pos": _ground(spot + face * 6.0), "boss": false})
	await _frames(3)
	_check(not c.is_boss and c.display_name() == "Captain", "a castle captain is not Kuroda (%s)" % c.display_name())
	var bd := Game.boss_defeated
	e.execute(player)
	c.execute(player)
	await _frames(3)
	_check(Game.xp == xp0 + 4, "kills earn mastery: soldier 1 + captain 3 (+%d)" % (Game.xp - xp0))
	_check(Game.boss_defeated == bd, "killing an ordinary captain does not end the story")
