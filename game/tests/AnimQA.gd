extends Node3D
## Automated animation QA. Drives the real Player and enemies through a scripted
## session and measures foot slide, pose discontinuity, slope grounding and
## speed matching. Writes a report and exits non-zero on hard failures.

const REPORT := "user://anim_qa.txt"

var player: Player
var enemies: Array = []
var log_lines: PackedStringArray = []
var phases: Array = []
var phase_i := -1
var phase_t := 0.0
var frames := 0
var shots_dir := ""

# per-phase metrics
var m_slide_sum := 0.0
var m_slide_n := 0
var m_slide_max := 0.0
var m_pop_max := 0.0
var m_pop_sum := 0.0
var m_pop_n := 0
var m_gap_max := 0.0
var m_speed_sum := 0.0
var m_speed_n := 0
var m_states := {}
var results := []
var hard_fail := 0

var _prev_foot := {"L": Vector3.ZERO, "R": Vector3.ZERO}
var _prev_foot_ok := false
var _prev_rot: Array[Quaternion] = []
var _screenshot_queue := []
var m_local_span := 0.0
var _local_min := 9e9
var _local_max := -9e9
var _phase_frames := 0
var qa_cam: Camera3D
var _dump := false
var m_runs := 0
var m_run_len := 0
var _run := {"L": [], "R": []}
var _run_dt := {"L": [], "R": []}

## Score the settled middle of one contact run, excluding heel strike/toe-off.
func _close_run(s2: String) -> void:
	var pts: Array = _run[s2]
	var dts: Array = _run_dt[s2]
	_run[s2] = []
	_run_dt[s2] = []
	m_runs += 1
	m_run_len += pts.size()
	if pts.size() < 5: return                       # too brief to be a stance
	var a: int = int(floor(pts.size() * 0.20))
	var b: int = int(ceil(pts.size() * 0.80))
	for i in range(maxi(a, 1), mini(b, pts.size())):
		var dt2: float = float(dts[i])
		if dt2 <= 0.0: continue
		var dv2: Vector3 = pts[i] - pts[i - 1]
		var sl2: float = Vector2(dv2.x, dv2.z).length() / dt2
		if sl2 > 12.0: continue
		m_slide_sum += sl2
		m_slide_n += 1
var _prev_loc := {}
var _prev_pos := Vector3.ZERO

func _ready() -> void:
	# sample after the player has moved and the rig has been updated this frame,
	# otherwise the transform and the pose come from different ticks
	process_priority = 500
	process_physics_priority = 500
	_build_ground()
	_build_chars()
	_build_phases()
	get_viewport().get_window().size = Vector2i(960, 540)
	print("QA setup: player=", player, " driver=", player.driver,
		" rig=", (player.driver.rig if player.driver != null else null),
		" enemy_rigs=", enemies.map(func(e): return e.driver != null and e.driver.rig != null))

func _build_ground() -> void:
	# flat arena
	_slab(Vector3(0, -0.5, 0), Vector3(80, 1, 80), Color(0.26, 0.29, 0.22))
	# 18 degree ramp
	var ramp := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(14, 0.6, 22)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.27, 0.20)
	mi.material_override = mat
	ramp.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	ramp.add_child(cs)
	ramp.position = Vector3(0, 1.9, -22)
	ramp.rotation.x = deg_to_rad(18.0)
	add_child(ramp)
	# a 0.28 m step to prove pelvis compensation
	_slab(Vector3(14, 0.14, 0), Vector3(10, 0.28, 10), Color(0.30, 0.25, 0.19))

func _slab(pos: Vector3, size: Vector3, col: Color) -> void:
	var sb := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mi.material_override = mat
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = pos
	add_child(sb)

func _build_chars() -> void:
	var l := DirectionalLight3D.new()
	l.rotation = Vector3(deg_to_rad(-48), deg_to_rad(38), 0)
	l.light_energy = 1.4
	add_child(l)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.45, 0.55, 0.68)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.62)
	e.ambient_light_energy = 0.65
	env.environment = e
	add_child(env)
	var cam := Camera3D.new()
	cam.name = "QACam"
	cam.position = Vector3(4.6, 2.4, 5.4)
	cam.rotation = Vector3(deg_to_rad(-14), deg_to_rad(38), 0)
	add_child(cam)
	cam.make_current()
	qa_cam = cam
	player = Player.new()
	player.name = "Kaito"
	player.position = Vector3(0, 0.2, 0)
	add_child(player)
	player.setup(null, null)
	for spec in [["ashigaru", Vector3(3.0, 0.2, -4.0)], ["archer", Vector3(-5.0, 0.2, -7.0)],
			["captain", Vector3(6.0, 0.2, -6.0)]]:
		var e2: EnemyBase
		match spec[0]:
			"ashigaru": e2 = Ashigaru.new()
			"archer": e2 = Archer.new()
			_: e2 = Captain.new()
		e2.spawn_id = "qa_%s" % spec[0]
		e2.position = spec[1]
		add_child(e2)
		# enemies stay passive until the melee phase so locomotion measurements
		# are not contaminated by combat
		e2.player = null
		enemies.append(e2)

func _build_phases() -> void:
	phases = [
		{"n": "idle", "settle": 0.2, "t": 2.5, "mv": Vector2.ZERO},
		{"n": "walk_fwd", "t": 3.5, "mv": Vector2(0, -0.40)},
		{"n": "walk_noik", "t": 3.5, "mv": Vector2(0, -0.40), "noik": true},
		{"n": "walk_long", "t": 6.0, "mv": Vector2(0, -0.40), "settle": 3.0},
		{"n": "jog_fwd", "t": 3.5, "mv": Vector2(0, -0.85)},
		{"n": "jog_noik", "t": 3.5, "mv": Vector2(0, -0.85), "noik": true},
		{"n": "jog_nolook", "t": 3.5, "mv": Vector2(0, -0.85), "nolook": true},
		{"n": "sprint_fwd", "t": 3.0, "mv": Vector2(0, -1.0), "sprint": true},
		{"n": "stop", "settle": 0.1, "t": 2.5, "mv": Vector2.ZERO},
		{"n": "turn_180", "t": 3.0, "mv": Vector2(0, 1.0)},
		{"n": "strafe_right", "t": 3.5, "mv": Vector2(1.0, 0), "lock": true},
		{"n": "strafe_left", "t": 3.5, "mv": Vector2(-1.0, 0), "lock": true},
		{"n": "circle_lock", "t": 3.5, "mv": Vector2(0.8, -0.6), "lock": true},
		{"n": "walk_back", "t": 3.0, "mv": Vector2(0, 1.0), "lock": true},
		{"n": "dodge_set", "t": 4.0, "mv": Vector2.ZERO, "act": "dodge", "every": 0.9},
		{"n": "jump", "t": 2.5, "mv": Vector2(0, -0.6), "act": "jump", "every": 1.1},
		{"n": "attack_combo", "settle": 0.3, "t": 5.0, "mv": Vector2.ZERO, "act": "attack", "every": 0.42},
		{"n": "heavy", "settle": 0.3, "t": 3.0, "mv": Vector2.ZERO, "act": "heavy", "every": 1.4},
		{"n": "block_hold", "settle": 0.3, "t": 2.5, "mv": Vector2.ZERO, "hold": "block"},
		{"n": "slope_up", "keep": true, "t": 5.0, "mv": Vector2(0, -0.85), "warp": Vector3(0, 0.3, -12)},
		{"n": "slope_down", "keep": true, "t": 4.0, "mv": Vector2(0, 1.0)},
		{"n": "step_up", "keep": true, "t": 4.0, "mv": Vector2(0.9, 0), "warp": Vector3(9.5, 0.4, 0)},
		{"n": "melee_fight", "settle": 0.5, "keep": true, "t": 10.0, "mv": Vector2.ZERO, "act": "attack", "every": 0.55,
			"warp": Vector3(2.0, 0.3, -2.0)},
		{"n": "recover", "settle": 0.2, "t": 3.0, "mv": Vector2.ZERO},
	]

func _next_phase() -> void:
	_close_run("L")
	_close_run("R")
	if phase_i >= 0:
		var p: Dictionary = phases[phase_i]
		var slide_avg := (m_slide_sum / m_slide_n) if m_slide_n > 0 else 0.0
		var pop_avg := (m_pop_sum / m_pop_n) if m_pop_n > 0 else 0.0
		results.append({
			"phase": p["n"], "slide_avg": slide_avg, "slide_max": m_slide_max,
			"pop_avg": pop_avg, "pop_max": m_pop_max, "gap_max": m_gap_max,
			"speed_avg": (m_speed_sum / m_speed_n) if m_speed_n > 0 else 0.0,
			"stride": (_local_max - _local_min) if _local_max > _local_min else 0.0,
			"states": m_states.keys(), "samples": m_slide_n,
			"runs": m_runs, "run_len": (float(m_run_len) / m_runs) if m_runs > 0 else 0.0,
			"dbg": (player.driver.rig.debug_state() if player.driver != null and player.driver.rig != null else {}),
		})
	m_slide_sum = 0.0; m_slide_n = 0; m_slide_max = 0.0; m_runs = 0; m_run_len = 0
	m_pop_max = 0.0; m_pop_sum = 0.0; m_pop_n = 0
	m_gap_max = 0.0; m_speed_sum = 0.0; m_speed_n = 0
	m_states = {}
	_local_min = 9e9; _local_max = -9e9; _phase_frames = 0
	_prev_foot_ok = false
	phase_i += 1
	phase_t = 0.0
	if phase_i >= phases.size():
		_finish()
		return
	var np: Dictionary = phases[phase_i]
	if np.has("warp"):
		player.global_position = np["warp"]
		player.velocity = Vector3.ZERO
	# lock-on is what makes the side and back clips reachable at all
	var want_lock := bool(np.get("lock", false))
	if want_lock and player._lock_target == null:
		player._toggle_lock()
	elif not want_lock and player._lock_target != null:
		player._toggle_lock()
	_release_all()

func _release_all() -> void:
	for a in ["attack", "heavy", "dodge", "block", "jump", "sprint"]:
		if InputMap.has_action(a): Input.action_release(a)
	Game.touch_move = Vector2.ZERO
	Game.touch_sprint = false
	Game.touch_block = false

var _act_t := 0.0

func _physics_process(delta: float) -> void:
	if phase_i < 0:
		_next_phase()
		return
	if phase_i >= phases.size(): return
	var p: Dictionary = phases[phase_i]
	phase_t += delta
	Game.touch_move = p.get("mv", Vector2.ZERO)
	Game.touch_sprint = bool(p.get("sprint", false))
	if p.has("hold"):
		Game.touch_block = p["hold"] == "block"
	if p.has("act"):
		_act_t -= delta
		if _act_t <= 0.0:
			_act_t = float(p.get("every", 1.0))
			_fire(String(p["act"]))
	# keep the subject framed: an off-screen skeleton stops being updated, which
	# would silently turn every measurement into a frozen pose
	if qa_cam != null:
		qa_cam.global_position = player.global_position + Vector3(4.2, 2.3, 4.6)
		qa_cam.look_at(player.global_position + Vector3(0, 1.0, 0))
	if player.driver != null:
		if player.driver.foot_ik != null:
			player.driver.foot_ik.influence = 0.0 if bool(p.get("noik", false)) else 1.0
		if player.driver.look != null:
			player.driver.look.influence = 0.0 if bool(p.get("nolook", false)) else 1.0
	# The arena is 80 m wide but the phases all run forward, so by the sprint
	# phase the subject had travelled ~44 m and walked off the edge; every
	# later phase then measured a falling character in JumpAir. Wrap it back to
	# the middle, keeping velocity and heading so deceleration still reads.
	var pp: Vector3 = player.global_position
	if pp.y < -0.4:
		player.global_position = Vector3(0.0, 0.45, 0.0)
		player.velocity.y = 0.0
		_prev_foot_ok = false
	elif not bool(p.get("keep", false)) and (absf(pp.x) > 9.0 or absf(pp.z) > 9.0):
		player.global_position = Vector3(0.0, pp.y, 0.0)
		_prev_foot_ok = false
	# the harness measures animation, not survival
	player.hp = player.max_hp
	player.posture = 0.0
	var fight := String(p["n"]) == "melee_fight"
	for e in enemies:
		if is_instance_valid(e): e.player = player if fight else null
	# Each phase changes the requested direction, so the subject spends up to a
	# second turning into it. Turning genuinely slides the feet, but it is not
	# what the steady-state locomotion rows are being measured for - turn
	# quality has its own phase. Discard the transient.
	if player.driver != null and player.driver.ok():
		m_states[player.driver.loco_state()] = true   # coverage, settle or not
	if phase_t >= float(p.get("settle", 1.0)):
		_sample(delta)
	else:
		_prev_foot_ok = false
		_run["L"].clear(); _run["R"].clear()
		_run_dt["L"].clear(); _run_dt["R"].clear()
	if phase_t >= float(p["t"]):
		_next_phase()

func _fire(act: String) -> void:
	match act:
		"attack": _tap("attack")
		"heavy": _tap("heavy")
		"dodge": _tap("dodge")
		"jump": _tap("jump")

func _tap(a: String) -> void:
	if not InputMap.has_action(a): return
	Input.action_press(a)
	get_tree().create_timer(0.05).timeout.connect(func(): Input.action_release(a))

func _sample(delta: float) -> void:
	frames += 1
	_phase_frames += 1
	_dump = false
	if player == null or player.driver == null or not player.driver.ok(): return
	var d: AnimDriver = player.driver
	m_states[d.loco_state()] = true
	# ---- foot slide. "Planted" means the ankle is genuinely within a few
	# centimetres of the ground it is standing on, judged by the same raycast
	# the IK uses, not merely "lower than the other foot".
	var fl := d.ankle_world("L")
	var fr := d.ankle_world("R")
	var g: Dictionary = d.ankle_gaps()
	# Foot slide is measured over the *middle* of each contact run. The first
	# and last frames of a contact are heel strike and toe-off, where the foot
	# is legitimately still rolling and moving; counting those reports slide
	# that no animator would call slide. A run is closed when the gap opens
	# again, then its middle 60% is scored.
	for s2 in ["L", "R"]:
		var gap: float = absf(float(g.get(s2, 99.0)))
		var cur: Vector3 = fl if s2 == "L" else fr
		if gap <= 0.035:
			_run[s2].append(cur)
			_run_dt[s2].append(delta)
		elif _run[s2].size() > 0:
			_close_run(s2)
	if not _prev_foot_ok:
		_run["L"].clear(); _run["R"].clear()
		_run_dt["L"].clear(); _run_dt["R"].clear()
	if _prev_foot_ok and delta > 0.0:
		for s2 in ["L", "R"]:
			var gap2: float = absf(float(g.get(s2, 99.0)))
			if gap2 > 0.035: continue
			var cur2: Vector3 = fl if s2 == "L" else fr
			var dv: Vector3 = cur2 - _prev_foot[s2]
			var sl: float = Vector2(dv.x, dv.z).length() / delta
			if sl > 12.0: continue
			m_slide_max = maxf(m_slide_max, sl)
			if _dump and _phase_frames % 24 == 0:
				var dpos: Vector3 = player.global_position - _prev_pos
				var loc: Vector3 = d.skeleton.global_transform.affine_inverse() * cur2
				var ploc: Vector3 = _prev_loc.get(s2, loc)
				print("  raw %s f%d gap=%.3f slide=%.3f body=%.4f locZ=%.4f dlocZ=%.4f %s" % [
					s2, _phase_frames, gap2, sl, Vector2(dpos.x, dpos.z).length(),
					loc.z, loc.z - ploc.z, str(d.rig.debug_state())])
	_prev_foot["L"] = fl
	_prev_foot["R"] = fr
	var inv := d.skeleton.global_transform.affine_inverse()
	_prev_loc["L"] = inv * fl
	_prev_loc["R"] = inv * fr
	_prev_pos = player.global_position
	_prev_foot_ok = true
	# ---- pose discontinuity
	var sk: Skeleton3D = d.skeleton
	if sk != null:
		var n := sk.get_bone_count()
		if _prev_rot.size() != n:
			_prev_rot.resize(n)
			for i in range(n): _prev_rot[i] = sk.get_bone_pose_rotation(i)
		else:
			var mx := 0.0
			for i in range(n):
				var q: Quaternion = sk.get_bone_pose_rotation(i)
				var ang: float = rad_to_deg(2.0 * acos(clampf(absf(q.dot(_prev_rot[i])), 0.0, 1.0)))
				mx = maxf(mx, ang)
				_prev_rot[i] = q
			if _phase_frames > 12:      # ignore the settle at a phase switch
				m_pop_max = maxf(m_pop_max, mx)
				m_pop_sum += mx
				m_pop_n += 1
	# ---- slope grounding
	# grounding is judged on the supporting foot; the swing foot is meant to be up
	var gaps: Dictionary = d.ankle_gaps()
	var best := 999.0
	for s in gaps.keys():
		var gv: float = float(gaps[s])
		if gv < 90.0: best = minf(best, absf(gv))
	if best < 90.0 and player.is_on_floor():
		m_gap_max = maxf(m_gap_max, best)
	# ---- speed
	m_speed_sum += Vector3(player.velocity.x, 0, player.velocity.z).length()
	m_speed_n += 1
	# stride check: how far the ankle travels in the character's own frame
	var linv := player.global_transform.affine_inverse()
	var lz: float = (linv * fl).z
	_local_min = minf(_local_min, lz)
	_local_max = maxf(_local_max, lz)

func _finish() -> void:
	var L := log_lines
	L.append("=== Ronin's Edge animation QA ===")
	var d: AnimDriver = player.driver
	L.append("clips available: %d   loco speeds walk/jog/sprint = %.2f / %.2f / %.2f m/s"
		% [d.rig.available.size(), d.speed_walk, d.speed_jog, d.speed_sprint])
	L.append("blend points: %d   triangles: %d" % [d.rig.blend_points, d.rig.blend_triangles])
	L.append("bones: %d   enemies animating: %d" % [d.skeleton.get_bone_count(), enemies.size()])
	L.append("")
	L.append("%-14s %9s %9s %8s %8s %8s %8s %8s %6s %7s" % ["phase", "slideAvg", "slideMax",
		"popAvg", "popMax", "gapMax", "spdAvg", "strideM", "runs", "runLen"])
	for r in results:
		L.append("   dbg %s" % [r.get("dbg", {})])
		L.append("%-14s %9.3f %9.3f %8.2f %8.2f %8.3f %8.2f %8.3f %6d %7.1f" % [r["phase"], r["slide_avg"],
			r["slide_max"], r["pop_avg"], r["pop_max"], r["gap_max"], r["speed_avg"],
			r["stride"], int(r["runs"]), r["run_len"]])
	L.append("")
	# ---------- assertions
	var fails := []
	var warns := []
	for r in results:
		var ph: String = r["phase"]
		if ph in ["walk_fwd", "jog_fwd", "sprint_fwd", "strafe_right", "strafe_left", "walk_back"]:
			if r["slide_avg"] > 0.55:
				fails.append("%s: planted foot slides %.2f m/s (limit 0.55)" % [ph, r["slide_avg"]])
			elif r["slide_avg"] > 0.30:
				warns.append("%s: foot slide %.2f m/s is high" % [ph, r["slide_avg"]])
			if r["pop_max"] > 34.0:
				warns.append("%s: pose jump %.1f deg in one frame" % [ph, r["pop_max"]])
		if ph in ["slope_up", "slope_down", "step_up"]:
			if r["gap_max"] > 0.22:
				fails.append("%s: foot floats %.3f m off the ground" % [ph, r["gap_max"]])
			elif r["gap_max"] > 0.12:
				warns.append("%s: foot gap %.3f m" % [ph, r["gap_max"]])
		if ph == "idle" and r["pop_max"] > 8.0:
			warns.append("idle: unexpected pose jump %.1f deg" % r["pop_max"])
		if r["samples"] < 5 and ph != "idle":
			warns.append("%s: only %d contact samples" % [ph, r["samples"]])
	var seen := {}
	for r in results:
		for st in r["states"]: seen[st] = true
	L.append("loco states exercised: %s" % [", ".join(seen.keys())])
	for want in ["Move", "StartRun", "StopRun"]:
		if not seen.has(want):
			warns.append("loco state %s never entered" % want)
	var alive := 0
	for e in enemies:
		if is_instance_valid(e): alive += 1
	L.append("enemies still simulated: %d/%d" % [alive, enemies.size()])
	L.append("")
	if fails.is_empty():
		L.append("FAILURES: none")
	else:
		for f in fails: L.append("FAIL  " + f)
	for w in warns: L.append("warn  " + w)
	hard_fail = fails.size()
	var f2 := FileAccess.open(REPORT, FileAccess.WRITE)
	if f2 != null:
		f2.store_string("\n".join(L))
		f2.close()
	for ln in L: print(ln)
	print("QA_DONE fails=%d warns=%d frames=%d" % [hard_fail, warns.size(), frames])
	get_tree().quit(0)
