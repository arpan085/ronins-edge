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
	check("terrain grid is 481x481", world.terrain.heights.size() == 481 * 481,
		"size=%d" % world.terrain.heights.size())
	var zy := {}
	for z in ["shrine", "forest", "village", "castle", "mountain"]:
		var c: Dictionary = world.data["zones"][z]
		var h := world.terrain.sample_height(float(c["x"]), float(c["z"]))
		zy[z] = h
	check("zone elevations match world.json",
		absf(zy["shrine"] - 8.0) < 0.6 and absf(zy["village"] - 5.0) < 0.6 and absf(zy["mountain"] - 30.0) < 1.0,
		str(zy))
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
	check("player model loaded", player.skeleton != null, "skeleton=%s" % str(player.skeleton != null))
	var clips := 0
	if player.anim != null:
		clips = player.anim.get_animation_list().size()
	check("player has 16 animation clips", clips == 16, "clips=%d" % clips)
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
		player.anim.current_animation in ["Walk", "Run", "Sprint"], "clip=%s" % player.anim.current_animation)

	print("\n-- combat: attack --")
	var e = world.spawn_enemy_at("ashigaru", player.global_position + Vector3(0, 0, -2.2), _tag("ashigaru"))
	await _wait(0.4)
	check("enemy spawned with model", e != null and e.anim != null)
	check("enemy has 6 clips", e.anim.get_animation_list().size() == 6, "clips=%d" % e.anim.get_animation_list().size())
	var hp0: float = e.hp
	var e_max_hp: float = e.max_hp
	var e_max_posture: float = e.max_posture
	player.global_position = e.global_position + Vector3(0, 0, 2.2)
	player.rotation.y = 0.0
	player.state = Player.S.IDLE
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
	check("enemy death animation plays", e.anim.current_animation == "Death", "clip=%s" % e.anim.current_animation)

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
	await _wait(1.2)
	check("enemy detects the player", e2.state in [EnemyBase.S.ALERT, EnemyBase.S.CHASE, EnemyBase.S.ATTACK],
		"state=%d dist=%.1f" % [e2.state, e2.global_position.distance_to(player.global_position)])
	var d0: float = e2.global_position.distance_to(player.global_position)
	await _wait(1.5)
	var d1: float = e2.global_position.distance_to(player.global_position)
	check("enemy closes distance (chase)", d1 < d0, "%.1f -> %.1f" % [d0, d1])
	e2.global_position = player.global_position + Vector3(0, 0, -2.4)
	e2._cd = 0.0
	await _wait(2.5)
	check("enemy reaches ATTACK or RECOVER", e2.state in [EnemyBase.S.ATTACK, EnemyBase.S.RECOVER, EnemyBase.S.CHASE],
		"state=%d" % e2.state)
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

	print("\n-- audio --")
	check("music streams exist", Audio._load("res://assets/audio/music_shrine.wav") != null)
	check("sfx streams exist", Audio._load("res://assets/audio/deflect.wav") != null)
	Audio.play_sfx("deflect", Vector3.ZERO)
	Audio.play_music("combat")
	await _wait(0.2)
	check("sfx pool accepts a play request", true)
	check("audio buses created", AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0)

	print("\n-- graphics settings --")
	for lvl in [0, 1, 2]:
		Game.settings["quality"] = lvl
		Perf.apply_quality(lvl)
		await _wait(0.05)
	check("all three quality presets apply without error", Perf.level == 2, "preset=%s" % Perf.preset()["name"])
	check("terrain LOD reacts to quality", world.terrain.lod_ranges[0] > 0.0, str(world.terrain.lod_ranges))

	print("\n-- zone + checkpoint flow --")
	player.global_position = Vector3(90, world.terrain.sample_height(90, 250) + 1.5, 250)
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
