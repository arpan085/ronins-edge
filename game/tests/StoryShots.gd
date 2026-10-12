extends Node
## v0.14 story harness: starts a new game, plays the prologue and photographs
## it at given seconds of game time, then the first chapter card and dialogue.
##   renv.sh res://tests/StoryShots.tscn -- out=/tmp/story at=1,5,12,20,28 [w=960 h=540] [epi]
## Stills mode freezes the sequence and frames named shots at a given
## progress (0..1), with that shot's card, so framing can be checked quickly:
##   renv.sh res://tests/StoryShots.tscn -- out=/tmp/story stills=castle:0,castle:1,village:0.5
## Log mode (fine headless) prints the sequence state every half second of game
## time up to `until`, optionally pressing Skip at `skip=` seconds:
##   godot --headless --path . res://tests/StoryShots.tscn -- log until=60 [skip=5] [epi]

var out := "/tmp/story"
var times: Array = [1.0, 6.0, 13.0, 20.0, 27.0, 33.0]
var stills: Array = []
var epi := false
var log_mode := false
var until := 60.0
var skip_at := -1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var w := 960
	var h := 540
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("out="): out = s.substr(4)
		elif s.begins_with("at="):
			times = []
			for t in s.substr(3).split(","): times.append(float(t))
		elif s.begins_with("stills="):
			for t in s.substr(7).split(","): stills.append(String(t))
		elif s.begins_with("w="): w = int(s.substr(2))
		elif s.begins_with("h="): h = int(s.substr(2))
		elif s == "epi": epi = true
		elif s == "log": log_mode = true
		elif s.begins_with("until="): until = float(s.substr(6))
		elif s.begins_with("skip="): skip_at = float(s.substr(5))
	DirAccess.make_dir_recursive_absolute(out)
	get_viewport().get_window().size = Vector2i(w, h)
	Game.reset_run()
	await get_tree().create_timer(0.3).timeout
	var main = get_parent().get_node("Main")
	main.start_world(false)
	var guard := 0
	while (main.world == null or not main.world.loaded or main.world.player == null) and guard < 900:
		guard += 1
		await get_tree().process_frame
	var world = main.world
	for i in 30: await get_tree().process_frame
	var st = world.story
	Quests.reset_all()
	var pp: Vector3 = world.player.global_position
	print("STORY player at ", pp.snapped(Vector3.ONE * 0.1), " boss spawn ", world.spawn_table[-1]["pos"])
	if not stills.is_empty():
		await _stills(world, st)
		print("STORY DONE")
		get_tree().quit()
		return
	if epi: st.play_epilogue()
	else: st.play_intro()
	if log_mode:
		await _log_run(world, st)
		print("STORY DONE")
		get_tree().quit()
		return
	var t0 := Time.get_ticks_msec()
	var idx := 0
	# the clock here is game time (frames are slow in software rendering)
	var gt := 0.0
	while idx < times.size():
		await get_tree().process_frame
		gt += get_process_delta_time()
		if gt >= float(times[idx]):
			await _shot("story_%02d" % idx)
			print("STORY shot ", idx, " t=", snappedf(gt, 0.1), " cine=", st.cinematic, " quest=", Quests.current_id())
			idx += 1
		if Time.get_ticks_msec() - t0 > 2400000: break
	print("STORY DONE")
	get_tree().quit()

func _stills(world, st) -> void:
	st.play_intro()
	st.set_process(false)
	var cards := {}
	for step in st.INTRO + st.EPILOGUE:
		if not cards.has(String(step["shot"])): cards[String(step["shot"])] = String(step["text"])
	for i in stills.size():
		var parts := String(stills[i]).split(":")
		var nm := parts[0]
		var k := float(parts[1]) if parts.size() > 1 else 0.5
		st._shot = st._make_shot(nm)
		st._shot_name = nm
		st._shot_dur = 10.0
		st._shot_t = k * 10.0
		st._update_cam()
		st.ui.set_black(0.0)
		st.ui.show_card(String(cards.get(nm, "")))
		for f in 10: await get_tree().process_frame
		var cam: Camera3D = get_viewport().get_camera_3d()
		var cp := cam.global_position
		var gh: float = world.terrain.sample_height(cp.x, cp.z)
		await _shot("still_%02d_%s_%s" % [i, nm, str(k).replace(".", "")])
		print("STILL ", i, " ", nm, " k=", k, " cam=", cp.snapped(Vector3.ONE * 0.1), " agl=", snappedf(cp.y - gh, 0.1), " fov=", snappedf(cam.fov, 0.1))

func _log_run(world, st) -> void:
	var gt := 0.0
	var next_log := 0.0
	var skipped := false
	var ui = st.ui
	while gt < until:
		await get_tree().process_frame
		gt += get_process_delta_time()
		if skip_at >= 0.0 and not skipped and gt >= skip_at:
			skipped = true
			print("STORYLOG t=%.1f SKIP pressed" % gt)
			st._on_skip()
		if gt >= next_log:
			next_log += 0.5
			var cam: Camera3D = get_viewport().get_camera_3d()
			print("STORYLOG t=%.1f cine=%s step=%d shot=%s card=%.2f '%s' black=%.2f chapter=%s dlg=%.2f '%s: %s' quest=%s game_cine=%s player_lock=%s cam=%s hud=%s" % [
				gt, str(st.cinematic), st._seq_i, st._shot_name, ui._card_a, String(ui._card.text).left(24),
				ui._black_a, str(ui.chapter_showing()), ui._dlg_a, ui._dlg_name.text, String(ui._dlg_text.text).left(30),
				Quests.current_id(), str(Game.cinematic), str(world.player.get("cinematic")),
				cam.name if cam != null else "none", str(world.hud.visible) if world.hud != null else "-"])

func _shot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, nm])
