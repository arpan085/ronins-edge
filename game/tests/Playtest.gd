extends Node
## Scripted pilot for the real game scene: drives the actual Main.tscn through
## explore -> engage -> fight -> recover, records frame time, animation LOD
## behaviour and how many rigs are simulated, and screenshots along the way.
## This is the "did it actually run" check, not a synthetic rig bench.

var t := 0.0
var beat := 0
var shots := 0
var frames := 0
var ft_sum := 0.0
var ft_max := 0.0
var ft_hist := {}
var samples := []
var player: Node = null
var log_t := 0.0

var beats := [
	{"n": "spawn",      "t": 2.0, "mv": Vector2.ZERO},
	{"n": "walk_out",   "t": 2.2, "mv": Vector2(0, -0.45)},
	{"n": "sprint_out", "t": 3.3, "mv": Vector2(0, -1.0), "sprint": true},
	{"n": "turn_back",  "t": 2.2, "mv": Vector2(0.9, 0.5)},
	{"n": "seek",       "t": 4.4, "mv": Vector2(-0.6, -0.9), "sprint": true},
	{"n": "approach",   "t": 3.3, "mv": Vector2(0, -0.8)},
	{"n": "engage",     "t": 5.0, "mv": Vector2(0, -0.35), "act": "attack", "every": 0.5, "lock": true},
	{"n": "defend",     "t": 2.8, "mv": Vector2(0.7, 0), "hold": "block", "lock": true},
	{"n": "evade",      "t": 2.8, "mv": Vector2(-0.8, 0.3), "act": "dodge", "every": 1.0},
	{"n": "finish",     "t": 4.4, "mv": Vector2(0, -0.5), "act": "heavy", "every": 1.3, "lock": true},
	{"n": "withdraw",   "t": 2.8, "mv": Vector2(0.4, 1.0)},
	{"n": "rest",       "t": 2.0, "mv": Vector2.ZERO},
]
var act_t := 0.0

func _ready() -> void:
	process_priority = 900
	process_physics_priority = 900
	get_viewport().get_window().size = Vector2i(640, 360)
	# The agent box has no GPU: everything renders through llvmpipe, so the
	# world scene is fill-rate bound. Drop resolution and quality so the
	# playtest exercises animation and AI rather than the software rasteriser.
	var pf = get_node_or_null("/root/Perf")
	if pf != null and pf.has_method("apply_quality"): pf.apply_quality(0)
	# Main boots into the title screen; drive it the way a player would.
	await get_tree().create_timer(1.0).timeout
	var main := get_parent().get_node_or_null("Main")
	if main != null and main.has_method("start_world"):
		main.start_world(false)
		print("PLAYTEST started world")
	await get_tree().create_timer(3.0).timeout
	for n in get_tree().root.get_children():
		player = n.find_child("Player", true, false)
		if player != null: break
	if player == null:
		var all := []
		_collect(get_tree().root, all)
		for n in all:
			if n.is_class("CharacterBody3D") and n.get("max_hp") != null and n.get("posture") != null:
				player = n
				break
	print("PLAYTEST player=", player, " enemies=", _rigs().size())

func _collect(n: Node, out: Array) -> void:
	if n != player and n.get("driver") != null:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)

func _rigs() -> Array:
	var out := []
	_collect(get_tree().root, out)
	return out

func _process(delta: float) -> void:
	frames += 1
	ft_sum += delta
	if frames > 90:
		ft_max = maxf(ft_max, delta)
	var ms := int(clampf(delta * 1000.0, 0.0, 200.0))
	ft_hist[ms] = int(ft_hist.get(ms, 0)) + 1

func _physics_process(delta: float) -> void:
	if beat >= beats.size(): return
	if player == null or not is_instance_valid(player):
		for n in get_tree().root.get_children():
			player = n.find_child("Player", true, false)
			if player != null: break
		if player == null: return
	var p: Dictionary = beats[beat]
	t += delta
	log_t += delta
	Game.touch_move = p.get("mv", Vector2.ZERO)
	Game.touch_sprint = bool(p.get("sprint", false))
	Game.touch_block = p.get("hold", "") == "block"
	if p.has("act"):
		act_t -= delta
		if act_t <= 0.0:
			act_t = float(p.get("every", 1.0))
			var a := String(p["act"])
			if InputMap.has_action(a):
				Input.action_press(a)
				get_tree().create_timer(0.06).timeout.connect(func(): Input.action_release(a))
	if bool(p.get("lock", false)) and player != null and InputMap.has_action("lock_on"):
		if not _locked:
			_locked = true
			Input.action_press("lock_on")
			get_tree().create_timer(0.06).timeout.connect(func(): Input.action_release("lock_on"))
	if log_t > 1.0:
		log_t = 0.0
		_snapshot(String(p["n"]))
	if t >= float(p["t"]):
		print("beat done: ", p["n"], " enemies=", _rigs().size())
		_shoot(String(p["n"]))
		t = 0.0
		_locked = false
		beat += 1
		Game.touch_move = Vector2.ZERO
		Game.touch_block = false
		Game.touch_sprint = false
		if beat >= beats.size():
			_report()

var _locked := false

func _snapshot(label: String) -> void:
	var rigs := _rigs()
	var vis := 0
	var lods := {}
	var sk_upd := 0
	for e in rigs:
		var d = e.get("driver")
		if d == null: continue
		var l = d.get("lod")
		if l != null:
			var tier: String = ["NEAR", "MED", "FAR", "CULL"][clampi(int(l.get("level")), 0, 3)]
			lods[tier] = int(lods.get(tier, 0)) + 1
		if d.has_method("ok") and d.ok():
			sk_upd += 1
		var sk = d.get("skeleton")
		if sk != null and sk.is_visible_in_tree(): vis += 1
	samples.append({"beat": label, "enemies": rigs.size(), "visible": vis,
		"rigs_ok": sk_upd, "lod": lods,
		"fps": Engine.get_frames_per_second(),
		"draw": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"prims": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"hp": (player.get("hp") if player != null else -1)})

func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://play_%02d_%s.png" % [shots, name])
	shots += 1

func _report() -> void:
	var L := []
	L.append("")
	L.append("=============== PLAYTEST (real Main.tscn) ===============")
	L.append("%-12s %8s %8s %8s %7s %9s %10s %s" % ["beat", "enemies", "visible",
		"rigsOK", "fps", "draws", "prims", "lod"])
	for s in samples:
		L.append("%-12s %8d %8d %8d %7d %9d %10d %s" % [s["beat"], s["enemies"],
			s["visible"], s["rigs_ok"], s["fps"], s["draw"], s["prims"], str(s["lod"])])
	var keys := ft_hist.keys()
	keys.sort()
	var tot := 0
	for k in keys: tot += int(ft_hist[k])
	var acc := 0
	var p50 := 0
	var p95 := 0
	var p99 := 0
	for k in keys:
		acc += int(ft_hist[k])
		if p50 == 0 and acc >= tot * 0.50: p50 = int(k)
		if p95 == 0 and acc >= tot * 0.95: p95 = int(k)
		if p99 == 0 and acc >= tot * 0.99: p99 = int(k)
	L.append("")
	L.append("frames=%d  mean=%.1f ms  p50=%d ms  p95=%d ms  p99=%d ms  worst(after warmup)=%.1f ms" % [
		frames, (ft_sum / maxf(frames, 1)) * 1000.0, p50, p95, p99, ft_max * 1000.0])
	L.append("PLAYTEST_DONE shots=%d" % shots)
	print("\n".join(L))
	get_tree().quit()
