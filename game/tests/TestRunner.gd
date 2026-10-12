extends Node
## Headless test harness: builds the real world and exercises the real systems.
## Run:  godot --headless --path . res://tests/TestRunner.tscn

var world: World
var player: Player
var pass_count := 0
var fail_count := 0
var results: Array = []
var _t0 := 0
var _run_tag := str(randi() % 1000000)

func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	print("=== RONIN'S EDGE — headless test run ===")
	await get_tree().process_frame
	world = World.new()
	world.name = "World"
	add_child(world)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player = world.player
	await _suite()
	_summary()

func _tag(base: String) -> String:
	return "test_%s_%s" % [_run_tag, base]

func check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		pass_count += 1
		print("  PASS  %s %s" % [name, detail])
	else:
		fail_count += 1
		print("  FAIL  %s %s" % [name, detail])
	results.append({"name": name, "ok": cond, "detail": detail})

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _suite() -> void:
	print("\n-- world --")
	check("world built", world.loaded)
	check("terrain heightmap loaded", world.terrain != null and world.terrain.loaded)
	check("terrain grid matches its size", world.terrain.heights.size() == world.terrain.grid * world.terrain.grid,
		"size=%d grid=%d" % [world.terrain.heights.size(), world.terrain.grid])
	var zy := {}
	var zbad := []
	for z in ["shrine", "forest", "village", "castle", "mountain"]:
		var c: Dictionary = world.data["zones"][z]
		var h := world.terrain.sample_height(float(c["x"]), float(c["z"]))
		zy[z] = h
		if absf(h - float(c.get("y", h))) > 1.0: zbad.append(z)
	check("zone elevations match world.json", zbad.is_empty(), str(zy) + (" off: " + str(zbad) if not zbad.is_empty() else ""))
	check("village is above the water line", zy["village"] > world.terrain.water_level + 1.0,
		"village=%.2f water=%.2f" % [zy["village"], world.terrain.water_level])
	check("props placed", world.get_child_count() > 20, "children=%d" % world.get_child_count())
	check("markers registered", world.markers.size() >= 10, "markers=%d" % world.markers.size())
	check("spawn table built", world.spawn_table.size() >= 20, "spawns=%d" % world.spawn_table.size())
	check("camera exists", world.camera != null and world.camera.cam() != null)
	check("day/night runs", world.time_of_day >= 0.0 and world.time_of_day < 24.0,
		"time=%.2f" % world.time_of_day)

	print("\n-- player --")
	check("player spawned", player != null)
	check("player model loaded", player.rig != null and player.rig.ok and player.rig.skeleton != null)
	var clips := 0
	if player.rig != null and player.rig.anim != null:
		clips = player.rig.anim.get_animation_list().size()
	check("player animation library loaded (100+ clips)", clips >= 100, "clips=%d" % clips)
	check("katana trail bound to hand bone", player.trail != null)
	# gravity / grounding
	player.global_position = Vector3(240, world.terrain.sample_height(240, 268) + 2.0, 268)
	await _wait(1.0)
	check("player settles on the terrain", player.is_on_floor(),
		"y=%.2f terrain=%.2f" % [player.global_position.y, world.terrain.sample_height(player.global_position.x, player.global_position.z)])
	var y0 := player.global_position
	Input.action_press("move_forward")
	await _wait(0.8)
	Input.action_release("move_forward")
	var moved := player.global_position.distance_to(y0)
	check("player moves when input is held", moved > 1.5, "moved=%.2f m" % moved)
	check("movement animation switches away from Idle",
		player.rig.current() in ["Walk", "Jog_Fwd", "Sprint", "K_Walk_Back", "K_Strafe_L", "K_Strafe_R"], "clip=%s" % player.rig.current())

	print("\n-- combat: attack --")
	var e = world.spawn_enemy_at("ashigaru", player.global_position + Vector3(0, 0, -2.2), _tag("ashigaru"))
	await _wait(0.4)
	check("enemy spawned with model", e != null and e.anim != null)
	check("enemy has its animation set", e.anim.get_animation_list().size() >= 6, "clips=%d" % e.anim.get_animation_list().size())
	var hp0: float = e.hp
	var e_max_hp: float = e.max_hp
	var e_max_posture: float = e.max_posture
	player.global_position = e.global_position + Vector3(0, 0, 2.2)
	player.rotation.y = 0.0
	player.state = Player.S.IDLE
	player.select_weapon("katana")
	player._set_drawn(true)
	player._face_now(e.global_position - player.global_position)
	player._start_attack("light1")
	await _wait(0.6)
	check("light attack damages the enemy", e.hp < hp0, "hp %.1f -> %.1f" % [hp0, e.hp])
	var post0: float = e.posture
	check("light attack adds posture", post0 > 0.0, "posture=%.1f" % post0)

	print("\n-- combat: perfect deflect --")
	e.hp = e.max_hp
	e.posture = 0.0
	player.hp = player.max_hp
	player.posture = 0.0
	player.focus = 0.0
	player._begin_block()
	check("deflect window opens on block press", player.is_perfect_deflect())
	var hp_before := player.hp
	player.take_hit({"damage": 20.0, "posture": 20.0, "source": e})
	check("perfect deflect takes no health", absf(player.hp - hp_before) < 0.01, "hp=%.1f" % player.hp)
	check("perfect deflect grants focus", player.focus > 0.0, "focus=%.1f" % player.focus)
	check("perfect deflect adds enemy posture", e.posture > 0.0, "enemy posture=%.1f" % e.posture)

	print("\n-- combat: block and dodge --")
	player.state = Player.S.IDLE
	player._blocking = false
	player.hp = player.max_hp
	player.state = Player.S.BLOCK
	player._blocking = true
	player._deflect_t = 0.0
	player.take_hit({"damage": 40.0, "posture": 20.0, "source": e})
	check("blocking reduces damage to 22%", absf(player.hp - (player.max_hp - 8.8)) < 0.2, "hp=%.1f" % player.hp)
	player.state = Player.S.IDLE
	player.hp = player.max_hp
	player._start_dodge()
	await _wait(0.12)
	check("dodge i-frames are active early", player.has_iframes(), "t=%.2f" % player._state_t)
	player.take_hit({"damage": 30.0, "posture": 10.0, "source": e})
	check("i-frames prevent all damage", absf(player.hp - player.max_hp) < 0.01, "hp=%.1f" % player.hp)
	await _wait(0.8)
	check("dodge ends and returns to locomotion", player.state in [Player.S.IDLE, Player.S.MOVE], "state=%d" % player.state)

	print("\n-- combat: posture break, stagger, deathblow --")
	e.posture = e.max_posture - 1.0
	e.take_hit({"damage": 1.0, "posture": 10.0, "source": player})
	check("posture break triggers STAGGER", e.posture_broken and e.state == EnemyBase.S.STAGGER, "state=%d" % e.state)
	player.global_position = e.global_position + Vector3(0, 0, 1.6)
	check("deathblow prompt becomes available", player.deathblow_available() == e)
	player._start_deathblow(e)
	await _wait(0.2)
	check("deathblow kills the enemy", e.is_dead, "hp=%.1f" % e.hp)
	await _wait(0.2)
	var dstate: String = e.driver.rig.loco_state() if e.driver != null and e.driver.rig != null else ""
	check("enemy death animation plays", e.state == EnemyBase.S.DEAD and dstate.begins_with("Death"), "state=%s" % dstate)

	print("\n-- enemy AI --")
	player.state = Player.S.IDLE
	var base := Vector3(240, 0, 268)
	base.y = world.terrain.sample_height(base.x, base.z) + 1.2
	player.global_position = base
	var epos := base + Vector3(0, 0, -14.0)
	epos.y = world.terrain.sample_height(epos.x, epos.z) + 0.1
	var e2 = world.spawn_enemy_at("ashigaru", epos, _tag("ai"))
	await _wait(0.1)
	check("test enemy placed at range", absf(e2.global_position.distance_to(player.global_position) - 14.0) < 1.5,
		"dist=%.1f" % e2.global_position.distance_to(player.global_position))
	e2.state = EnemyBase.S.IDLE
	e2.in_combat = false
	# v0.16 sight builds awareness over time: a sentry looking our way
	var to_p: Vector3 = player.global_position - e2.global_position
	e2.rotation.y = atan2(to_p.x, to_p.z)
	e2.set("_want_yaw", e2.rotation.y)
	e2.post_yaw = e2.rotation.y
	var waited := 0.0
	while waited < 5.0 and not e2.state in [EnemyBase.S.ALERT, EnemyBase.S.CHASE, EnemyBase.S.ATTACK, EnemyBase.S.COMBAT_READY]:
		await _wait(0.1)
		waited += 0.1
	check("enemy detects the player", e2.state in [EnemyBase.S.ALERT, EnemyBase.S.CHASE, EnemyBase.S.ATTACK, EnemyBase.S.COMBAT_READY],
		"state=%d dist=%.1f after %.1f s" % [e2.state, e2.global_position.distance_to(player.global_position), waited])
	var d0: float = e2.global_position.distance_to(player.global_position)
	await _wait(1.5)
	var d1: float = e2.global_position.distance_to(player.global_position)
	check("enemy closes distance (chase)", d1 < d0, "%.1f -> %.1f" % [d0, d1])
	e2.global_position = player.global_position + Vector3(0, 0, -2.4)
	e2._cd = 0.0
	# v0.18: watch the whole window; a full swing-recover-ready cycle is ~2 s,
	# so a single sample at 2.5 s could land between two attacks
	var seen := {}
	for _i in 25:
		await _wait(0.1)
		seen[e2.state] = true
	check("enemy reaches ATTACK or RECOVER", seen.has(EnemyBase.S.ATTACK) or seen.has(EnemyBase.S.RECOVER),
		"seen=%s" % str(seen.keys()))
	check("enemy telegraphs before hitting (windup >= 0.4s)", e2.windup >= 0.4, "windup=%.2f" % e2.windup)

	print("\n-- enemy variety --")
	var a = world.spawn_enemy_at("archer", player.global_position + Vector3(0, 0, -12.0), _tag("archer"))
	var c = world.spawn_enemy_at("captain", player.global_position + Vector3(0, 0, -4.0), _tag("captain"))
	await _wait(0.3)
	check("archer has ranged attack range", a.attack_range >= 10.0, "range=%.1f" % a.attack_range)
	check("captain is tougher than ashigaru", c.max_hp > e_max_hp and c.max_posture > e_max_posture,
		"captain hp=%.0f posture=%.0f vs ashigaru hp=%.0f posture=%.0f" % [c.max_hp, c.max_posture, e_max_hp, e_max_posture])
	check("archer and captain use different models", a.anim != null and c.anim != null)
	var kinds := {}
	for en in world.enemies: kinds[en.kind] = true
	check("three enemy kinds alive", kinds.size() >= 3, str(kinds.keys()))
	# v0.19 facial hair: every style grows a skinned shell out of the face
	var fh_ok := true
	var fh_info := []
	var head_src: Node = (load(UBCDriver.CHAR_PATH) as PackedScene).instantiate()
	for st in FacialHair.SHAPE.keys():
		var fm := FacialHair.grow(head_src, st, Color(0.1, 0.08, 0.07))
		var tris := 0
		if fm != null and fm.mesh != null:
			var fa := fm.mesh.surface_get_arrays(0)
			tris = (fa[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			if fa[Mesh.ARRAY_BONES] == null or fm.skin == null: tris = -1
		fh_info.append("%s:%d" % [st, tris])
		if tris < 20 or tris > 4000: fh_ok = false
	head_src.free()
	check("each facial hair style grows a skinned shell (20-4000 tris)", fh_ok, " ".join(fh_info))
	# v0.20 wet characters: soak, then dry back to exactly the dry values
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.5, 0.4, 0.3); wm.roughness = 0.9
	CharWet.track(wm, "cloth")
	var lv0 := CharWet.level
	CharWet.set_level(1.0)
	var soaked := wm.albedo_color.r < 0.35 and wm.roughness < 0.75
	var wcopy := CharWet.dry_copy(wm)
	CharWet.set_level(0.0)
	var dried := is_equal_approx(wm.albedo_color.r, 0.5) and is_equal_approx(wm.roughness, 0.9)
	check("rain soaks character cloth and it dries back exactly", soaked and dried and is_equal_approx(wcopy.albedo_color.r, 0.5),
		"tracked=%d" % CharWet.count())
	world.set_weather("storm", true)
	await _wait(0.2)
	var storm_lv := CharWet.level
	world.set_weather("clear", true)
	await _wait(0.2)
	check("a storm soaks the characters, clear weather dries them", storm_lv > 0.9 and CharWet.level < 0.05,
		"storm=%.2f clear=%.2f" % [storm_lv, CharWet.level])
	CharWet.set_level(lv0)
	# v0.21 breath: puffs in the snow, none at a clear noon (a standalone body:
	# a live enemy may be despawned by the world while the test waits)
	var bh := Node3D.new()
	world.add_child(bh)
	bh.global_position = player.global_position + Vector3(2.0, 0, -3.0)
	var bdrv := UBCDriver.new()
	bh.add_child(bdrv)
	var bf: BreathFX = bdrv.breath if bdrv.build(bh, "", "ashigaru", false) else null
	var p_snow := -1
	var p_noon := -1
	if bf != null:
		world.set_weather("snow", true)
		bf.anatomy.exertion = 1.0
		var b0: int = bf.puffs
		await _wait(4.0)
		p_snow = bf.puffs - b0
		world.set_time_of_day(12.0)
		world.set_weather("clear", true)
		await _wait(0.1)
		var b1: int = bf.puffs
		await _wait(3.0)
		p_noon = bf.puffs - b1
	bh.queue_free()
	check("breath shows in the snow, not at a clear noon", p_snow >= 1 and p_noon == 0,
		"snow=%d noon=%d cold=%.2f" % [p_snow, p_noon, BreathFX.cold])

	# v0.22 ground contact: the UAL clips stand on the ground (anim/GroundFix)
	# and the foot IK plants both feet across a 20 deg slope
	var gm: Node3D = (load("res://assets/char/Ronin.glb") as PackedScene).instantiate()
	world.add_child(gm)
	gm.global_position = Vector3(0, 400, 0)
	var gsk: Skeleton3D = gm.find_children("*", "Skeleton3D", true, false)[0]
	var gap := AnimationPlayer.new(); gm.add_child(gap)
	var glib: AnimationLibrary = load("res://assets/anim/ronin_anims.res")
	GroundFix.apply(glib, gsk)
	gap.add_animation_library("", glib)
	gap.root_node = gap.get_path_to(gsk.get_parent())
	var lows := {}
	for gc in ["Idle", "Walk", "Jog_Fwd", "Sprint"]:
		lows[gc] = _clip_low(gap, gsk, gc)
	gm.queue_free()
	var on_ground := true
	for gc in lows: on_ground = on_ground and lows[gc] > -0.02 and lows[gc] < 0.025
	check("idle, walk, jog and sprint keep the feet on the ground", on_ground,
		"lowest contact (m): %s" % str(lows))
	var sh := Node3D.new()
	world.add_child(sh)
	sh.global_position = Vector3(0, 400, 0)
	var th := deg_to_rad(20.0)
	var sb := StaticBody3D.new(); sh.add_child(sb)
	var scs := CollisionShape3D.new(); var sbx := BoxShape3D.new(); sbx.size = Vector3(8, 1, 8)
	scs.shape = sbx; sb.add_child(scs)
	sb.rotation = Vector3(0, 0, th)
	sb.position = Vector3(0.5 * sin(th), -0.5 * cos(th), 0)
	var sbody := Node3D.new(); sh.add_child(sbody)
	var sdrv := UBCDriver.new(); sbody.add_child(sdrv)
	var g_on := {}
	var g_off := {}
	if sdrv.build(sbody, "", "ashigaru", false) and sdrv.foot_ik != null:
		var post := [{}]
		sdrv.foot_ik.modification_processed.connect(func(): post[0] = sdrv.ankle_gaps())
		await _wait(1.2)
		g_on = post[0]
		sdrv.foot_ik.active = false
		await _wait(0.3)
		g_off = sdrv.ankle_gaps()
	sh.queue_free()
	var planted: bool = not g_on.is_empty() and absf(g_on["L"]) < 0.03 and absf(g_on["R"]) < 0.03 \
		and not g_off.is_empty() and maxf(absf(g_off["L"]), absf(g_off["R"])) > 0.05
	check("foot IK plants both feet across a 20 deg slope", planted,
		"with IK %s, without %s" % [str(g_on), str(g_off)])

	print("\n-- combat spacing --")
	EnemyBase.attackers = 0
	var tokens := 0
	for i in 5:
		var en = world.spawn_enemy_at("ashigaru", player.global_position + Vector3(float(i) - 2.0, 0, -3.0), _tag("tok%d" % i))
		if en._take_token(): tokens += 1
	check("only %d enemies may attack at once" % EnemyBase.MAX_ATTACKERS, tokens == EnemyBase.MAX_ATTACKERS,
		"tokens=%d" % tokens)
	EnemyBase.attackers = 0

	print("\n-- quests --")
	Quests.reset_all()
	var q := Quests.start_next()
	check("first quest starts", q == "ronin", "quest=%s" % q)
	check("quest objective text is exposed", Quests.current_objective_text() != "")
	Quests.progress("deflect", "", 3)
	Quests.progress("kill", "shrine", 3)
	check("quest completes when objectives are met", Quests.done.has("ronin"), str(Quests.done.keys()))
	check("quest completion grants mastery", Game.mastery_points >= 3, "mastery=%d" % Game.mastery_points)
	var q2 := Quests.start_next()
	check("next quest chains on", q2 == "forest", "quest=%s" % q2)
	Quests.progress("kill", "forest", 5)
	Quests.progress("reach", "forest_marker", 1)
	check("kill + reach objectives complete the forest quest", Quests.done.has("forest"))

	print("\n-- save / load --")
	Game.hp = 61.5
	Game.zone = "village"
	Game.checkpoint = {"zone": "village", "pos": Vector3(390, 5, 235)}
	Game.mastery_points = 7
	Game.settings["quality"] = 1
	check("save writes a file", Game.save_game())
	Game.hp = 1.0; Game.zone = "shrine"; Game.mastery_points = 0
	check("load restores state", Game.load_game() and absf(Game.hp - 61.5) < 0.01 and Game.zone == "village",
		"hp=%.1f zone=%s" % [Game.hp, Game.zone])
	check("quest progress round-trips", Game.load_game() and Quests.done.has("forest"))
	# v0.16 techniques and smoke bombs are saved with the rest
	Skills.reset()
	Skills.unlocked = ["s_silent", "s_assassin"] as Array[String]
	Game.smoke = 1
	check("save writes techniques", Game.save_game())
	Skills.reset(); Game.smoke = 3
	check("techniques and smoke bombs round-trip", Game.load_game() and Skills.has("s_assassin") and Skills.has("s_silent") and Game.smoke == 1,
		"skills=%s smoke=%d" % [str(Skills.unlocked), Game.smoke])
	check("a technique tree with 12 entries", Skills.TREE.size() == 12 and Skills.total_cost() == 27, "n=%d cost=%d" % [Skills.TREE.size(), Skills.total_cost()])
	for act in ["crouch", "smoke", "skills"]:
		check("input action '%s' is bound" % act, InputMap.has_action(act) and not InputMap.action_get_events(act).is_empty())
	Skills.reset(); Game.smoke = Game.smoke_max

	print("\n-- audio --")
	check("music streams exist", Audio._load("res://assets/audio/music/shrine.ogg") != null)
	check("sfx sets found", Audio.has_sound("clash") and Audio.has_sound("hoof_dirt") and Audio.has_sound("footstep_grass"))
	Audio.play_sfx("deflect", Vector3.ZERO)
	Audio.play_music("combat")
	await _wait(0.2)
	check("sfx pool accepts a play request", true)
	check("audio buses created", AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0)
	check("master bus is limited and the music ducks under hits (v0.22 mix)",
		AudioServer.get_bus_effect_count(0) >= 2 and AudioServer.get_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1) is AudioEffectLimiter
		and AudioServer.get_bus_effect(AudioServer.get_bus_index("Music"), 0) is AudioEffectCompressor)

	print("\n-- graphics settings --")
	for lvl in [0, 1, 2]:
		Game.settings["quality"] = lvl
		Perf.apply_quality(lvl)
		await _wait(0.05)
	check("all three quality presets apply without error", Perf.level == 2, "preset=%s" % Perf.preset()["name"])
	check("terrain LOD distances set", float(world.terrain.lod_dist[0]) > 0.0, str(world.terrain.lod_dist))

	print("\n-- zone + checkpoint flow --")
	var fz: Dictionary = world.data["zones"]["forest"]
	player.global_position = Vector3(float(fz["x"]), world.terrain.sample_height(float(fz["x"]), float(fz["z"])) + 1.5, float(fz["z"]))
	await _wait(0.8)
	check("walking into a zone updates the current zone", Game.zone == "forest", "zone=%s" % Game.zone)
	check("checkpoint saved on zone entry", Game.checkpoint["zone"] != "", str(Game.checkpoint["zone"]))

	print("\n-- damage / death / respawn --")
	player.hp = 5.0
	player.take_hit({"damage": 50.0, "posture": 10.0, "source": null})
	check("lethal damage kills the player", player.hp <= 0.0 and player.state == Player.S.DEAD, "hp=%.1f" % player.hp)
	world.respawn()
	await _wait(0.3)
	check("respawn restores health and state", player.hp > 0.0 and player.state != Player.S.DEAD,
		"hp=%.1f state=%d" % [player.hp, player.state])

	print("\n-- performance sample (software renderer, no GPU in this sandbox) --")
	await _wait(1.5)
	print("  fps=%.1f  frame=%.1f ms  draws=%d  prims=%d  nodes=%d" % [
		Perf.metrics.get("fps", 0.0), Perf.metrics.get("frame_ms", 0.0),
		Perf.metrics.get("draw_calls", 0), Perf.metrics.get("primitives", 0),
		Perf.metrics.get("objects", 0)])

func _summary() -> void:
	var ms := Time.get_ticks_msec() - _t0
	print("\n=== RESULT: %d passed, %d failed  (%.1f s) ===" % [pass_count, fail_count, ms / 1000.0])
	if fail_count > 0:
		print("failed tests:")
		for r in results:
			if not r["ok"]: print("   - %s %s" % [r["name"], r["detail"]])
	var f := FileAccess.open("user://test_results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"passed": pass_count, "failed": fail_count, "results": results}, "  "))
		f.close()
	get_tree().quit(1 if fail_count > 0 else 0)


## v0.22: lowest point of either foot (heel or ball) over a clip, metres above
## the ground plane of the model (negative = sunk into the ground)
func _clip_low(ap: AnimationPlayer, sk: Skeleton3D, clip: String) -> float:
	if not ap.has_animation(clip): return -9.0
	var a := ap.get_animation(clip)
	ap.play(clip)
	var fl := sk.find_bone("foot_l"); var fr := sk.find_bone("foot_r")
	var bl := sk.find_bone("ball_l"); var br := sk.find_bone("ball_r")
	var ah := sk.get_bone_global_rest(fl).origin.y
	var bh := sk.get_bone_global_rest(bl).origin.y
	var lo := 9.0
	for i in 24:
		ap.seek(a.length * float(i) / 24.0, true)
		for pr in [[fl, bl], [fr, br]]:
			lo = minf(lo, minf(sk.get_bone_global_pose(pr[0]).origin.y - ah, sk.get_bone_global_pose(pr[1]).origin.y - bh))
	return lo
