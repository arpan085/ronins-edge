class_name Story
extends Node
## v0.14 story mode.
##
##   * New Game opens with a prologue: letterboxed fly-over of the province
##     (castle, Hanamura, the forest road, the Sakura Shrine) under narrative
##     cards, landing behind Kaito. Enter/click = next card, Esc = skip.
##   * The six quests are the six chapters. Each opens with a title card and
##     a few spoken lines, has lines for arriving in its zone, and lines for its
##     completion; the next chapter starts when those have been said.
##   * Felling Kuroda ends the story with an epilogue; free roam continues.
##
## The story owns the quest chain: zone markers no longer start quests, so
## there is always exactly one chapter active.

const CHAPTERS := {
	"ronin": {"num": "第一章", "label": "Chapter I", "title": "The Path of the Ronin", "kanji": "浪人の道",
		"start": [
			["Genjo", "Kaito. Eleven winters since you last climbed these steps, and you come back with ash on your sleeves."],
			["Kaito", "Lord Asano is dead. Kuroda holds the castle."],
			["Genjo", "Then your blade has work to do. But anger swings wide. Show me you can still turn a blow aside."],
		],
		"done": [
			["Genjo", "Good. The steel still listens to you."],
			["Genjo", "Kuroda's bandits hold the forest road to the east. Every road to the castle runs through them."],
		]},
	"forest": {"num": "第二章", "label": "Chapter II", "title": "Bamboo and Ash", "kanji": "竹と灰",
		"start": [
			["Kaito", "Smoke above the trees. They burn the groves so no one can hide in them."],
		],
		"arrive": [
			["Kaito", "Their camp will be near the old forest shrine. The lanterns there were lit for travellers once."],
		],
		"done": [
			["Kaito", "A letter, sealed with Kuroda's crest..."],
			["Letter", "\"Hanamura has not paid. Take the rice, then burn what is left.\""],
			["Kaito", "Hanamura. The river village. I may already be too late."],
		]},
	"village": {"num": "第三章", "label": "Chapter III", "title": "Hanamura Burns", "kanji": "炎の村",
		"start": [
			["Kaito", "Hanamura lies to the south, where the river bends."],
		],
		"arrive": [
			["Elder Ume", "Ronin! They came at dawn. They are emptying the rice stores!"],
			["Kaito", "Stay behind the well. I will deal with them."],
		],
		"done": [
			["Elder Ume", "You saved what is left of us. Look, they hid this in the well."],
			["Elder Ume", "A plan of the castle. The east gate was never repaired after the siege."],
			["Kaito", "Then that is where I go in."],
		]},
	"castle": {"num": "第四章", "label": "Chapter IV", "title": "The Ruined Gate", "kanji": "城門",
		"start": [
			["Kaito", "North, to the castle. The gate my lord built, and Kuroda's men stand on it as if it were theirs."],
		],
		"done": [
			["Defender", "The beacons... light the beacons on the pass! The mountain garrison will come!"],
			["Kaito", "If those fires burn, an army comes down the mountain. I must reach the pass first."],
		]},
	"mountain": {"num": "第五章", "label": "Chapter V", "title": "Beacons on the Pass", "kanji": "峠の烽火",
		"start": [
			["Kaito", "The pass is far to the west. Before nightfall, then."],
		],
		"arrive": [
			["Kaito", "Archers on the ridge, guarding the beacon tower."],
		],
		"done": [
			["Kaito", "The beacons stay dark. No help will come for him now."],
			["Kaito", "Kuroda. It ends at the keep."],
		]},
	"duel": {"num": "終章", "label": "Final Chapter", "title": "The Final Duel", "kanji": "決闘",
		"start": [
			["Kaito", "Back to the castle. No more soldiers stand between us."],
		],
		"arrive": [
			["Kuroda", "So the old instructor comes home. You taught me every cut I know, Kaito."],
			["Kaito", "Then you know how this ends."],
			["Kuroda", "I know you are old. Draw."],
		],
		"done": []},
}

const INTRO := [
	{"shot": "castle", "text": "Kiyomizu Province, in the last years of the warring states."},
	{"shot": "castle_keep", "text": "When Lord Asano died, his captain did not mourn him. Kuroda Masanori took the castle, burned the peace treaty, and turned his lord's soldiers into raiders."},
	{"shot": "village", "text": "Villages burn. The roads belong to bandits. The samurai who would not kneel are dead, or ronin."},
	{"shot": "forest", "text": "Kaito taught the Asano clan the sword. He was far away the night the castle fell."},
	{"shot": "shrine", "text": "Now he climbs back to the Sakura Shrine, where he first learned the blade, to finish what his lord could not."},
]

const EPILOGUE := [
	{"shot": "keep", "text": "Kuroda Masanori fell before the keep he had stolen. That night the castle bells rang for the first time since the fall."},
	{"shot": "keep", "text": "The raiders scattered into the mountains. Hanamura rebuilt its storehouses before the rains."},
	{"shot": "shrine_far", "text": "Kaito laid his lord's sword before the shrine, and kept his own."},
	{"shot": "shrine_far", "text": "完\n\nThank you for playing Ronin's Edge.\nThe provinces are yours to roam."},
]

const ARRIVE_M := 75.0

var world: World
var ui: CanvasLayer
var cinematic := false

var _lines: Array = []
var _line_on := false
var _line_t := 0.0
var _line_hold := 0.0
var _delay := 0.0
var _after: Callable = Callable()
var _after_delay := 0.0
var _arrived := {}
var _poll := 0.0

var _seq: Array = []
var _seq_i := -1
var _step_t := 0.0
var _step_dur := 0.0
var _shot := {}
var _shot_name := ""
var _shot_t := 0.0
var _shot_dur := 1.0
var _cam: Camera3D
var _on_end: Callable = Callable()
var _closing := -1.0

func setup(w: World) -> void:
	world = w
	ui = load("res://ui/StoryUI.gd").new()
	ui.name = "StoryUI"
	add_child(ui)
	ui.advance.connect(_on_advance)
	ui.skip.connect(_on_skip)
	Quests.quest_started.connect(_on_quest_started)
	Quests.quest_completed.connect(_on_quest_completed)

func _exit_tree() -> void:
	if Quests.quest_started.is_connected(_on_quest_started):
		Quests.quest_started.disconnect(_on_quest_started)
	if Quests.quest_completed.is_connected(_on_quest_completed):
		Quests.quest_completed.disconnect(_on_quest_completed)
	Game.cinematic = false

# ------------------------------------------------------------------ entry
## New game: prologue, then chapter one.
func play_intro() -> void:
	_start_cinematic(INTRO, func(): _begin_story())

## New game without the prologue (test harnesses, headless runs).
func begin() -> void:
	_begin_story()

## Continue: re-announce the chapter in progress, or start the next one.
func resume() -> void:
	var cur := Quests.current_id()
	if cur == "":
		Quests.start_next()
		return
	if CHAPTERS.has(cur):
		var ch: Dictionary = CHAPTERS[cur]
		ui.show_chapter(String(ch["num"]), String(ch["label"]), String(ch["title"]), String(ch["kanji"]), 4.5)

func _begin_story() -> void:
	if Quests.current_id() == "":
		Quests.start_next()

# ------------------------------------------------------------------ quests
func _on_quest_started(id: String) -> void:
	if not CHAPTERS.has(id): return
	var ch: Dictionary = CHAPTERS[id]
	ui.show_chapter(String(ch["num"]), String(ch["label"]), String(ch["title"]), String(ch["kanji"]))
	Audio.play_sfx("quest", null, 0.8, -4.0)
	_queue(ch.get("start", []), 2.6)
	if id == "duel" and Game.boss_defeated:
		# Kuroda already fell during the castle assault: the duel is decided
		_arrived[id] = true
		Quests.progress.call_deferred("boss", "captain", 1)

func _on_quest_completed(id: String) -> void:
	if not CHAPTERS.has(id): return
	var ch: Dictionary = CHAPTERS[id]
	_queue(ch.get("done", []), 1.4)
	if id == "duel":
		_after = func(): play_epilogue()
		_after_delay = 2.5
	else:
		_after = func():
			if Quests.current_id() == "": Quests.start_next()
		_after_delay = 1.6

func play_epilogue() -> void:
	_start_cinematic(EPILOGUE, Callable())

# ------------------------------------------------------------------ lines
func _queue(lines: Array, delay: float) -> void:
	if lines.is_empty(): return
	if _lines.is_empty() and not _line_on:
		_delay = maxf(_delay, delay)
	for l in lines: _lines.append(l)

func _next_line() -> void:
	if _lines.is_empty():
		_line_on = false
		ui.hide_dialogue()
		return
	var l: Array = _lines.pop_front()
	var text := String(l[1])
	ui.say(String(l[0]), text)
	_line_on = true
	_line_t = 0.0
	# typing time + ~17 characters a second of reading, never under 2.6 s
	_line_hold = maxf(2.6, float(text.length()) / 48.0 + 1.4 + float(text.length()) / 17.0)

func busy() -> bool:
	return _line_on or not _lines.is_empty() or cinematic

func _on_advance() -> void:
	if cinematic:
		if _closing >= 0.0: return
		_next_step(true)
		return
	if _line_on:
		if not ui.line_typed(): ui.finish_typing()
		else: _next_line()

func _on_skip() -> void:
	if cinematic and _closing < 0.0:
		ui.hide_card()
		ui.set_black(1.0)
		_finish_cinematic()

# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	if world == null or not world.loaded: return
	if cinematic:
		_tick_cinematic(delta)
		return
	if _delay > 0.0:
		_delay -= delta
	elif _line_on:
		_line_t += delta
		if _line_t >= _line_hold: _next_line()
	elif not _lines.is_empty():
		_next_line()
	elif _after.is_valid():
		_after_delay -= delta
		if _after_delay <= 0.0:
			var cb := _after
			_after = Callable()
			cb.call()
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.5
		_check_arrival()

func _check_arrival() -> void:
	var cur := Quests.current_id()
	if cur == "" or _arrived.has(cur) or not CHAPTERS.has(cur): return
	var lines: Array = CHAPTERS[cur].get("arrive", [])
	if lines.is_empty():
		_arrived[cur] = true
		return
	var zn := String(Quests.DEFS[cur].get("zone", ""))
	var zs: Dictionary = world.data.get("zones", {})
	if not zs.has(zn) or world.player == null: return
	var z: Dictionary = zs[zn]
	var pp := world.player.global_position
	if Vector2(pp.x - float(z["x"]), pp.z - float(z["z"])).length() < ARRIVE_M:
		_arrived[cur] = true
		_queue(lines, 0.3)

# ------------------------------------------------------------------ cinematic
func _start_cinematic(seq: Array, on_end: Callable) -> void:
	if world == null or world.player == null:
		if on_end.is_valid(): on_end.call()
		return
	cinematic = true
	Game.cinematic = true
	_set_player_lock(true)
	_lines.clear()
	_line_on = false
	ui.hide_dialogue()
	ui.hide_chapter()
	ui.set_cinematic(true)
	ui.set_black(1.0)
	ui.fade_to(0.0, 1.4)
	if world.hud != null: world.hud.visible = false
	if world.touch != null: world.touch.visible = false
	_cam = Camera3D.new()
	_cam.name = "CineCam"
	_cam.fov = 50.0
	_cam.near = 0.2
	_cam.far = 8000.0
	world.add_child(_cam)
	_cam.current = true
	_seq = seq
	_seq_i = -1
	_shot_name = ""
	_on_end = on_end
	_closing = -1.0
	_next_step(false)

func _step_len(i: int) -> float:
	var text := String(_seq[i]["text"])
	return clampf(3.4 + float(text.length()) * 0.05, 4.8, 10.0)

func _next_step(by_player: bool) -> void:
	_seq_i += 1
	if _seq_i >= _seq.size():
		_closing = 0.0
		ui.hide_card()
		ui.fade_to(1.0, 0.7)
		return
	var st: Dictionary = _seq[_seq_i]
	_step_t = 0.0
	_step_dur = _step_len(_seq_i)
	var sn := String(st["shot"])
	if sn != _shot_name:
		var tot := 0.0
		for j in range(_seq_i, _seq.size()):
			if String(_seq[j]["shot"]) != sn: break
			tot += _step_len(j)
		_shot = _make_shot(sn)
		_shot_name = sn
		_shot_t = 0.0
		_shot_dur = tot + 0.8
		if _seq_i > 0:
			# cut: dip from black
			ui.set_black(1.0)
			ui.fade_to(0.0, 0.7)
	ui.show_card(String(st["text"]))
	_update_cam()

func _tick_cinematic(delta: float) -> void:
	_shot_t += delta
	_update_cam()
	if _closing >= 0.0:
		_closing += delta
		if _closing > 0.8 or ui.is_black(): _finish_cinematic()
		return
	_step_t += delta
	var last := _seq_i >= _seq.size() - 1
	var cut_next := last or String(_seq[_seq_i + 1]["shot"]) != _shot_name
	if _step_t > _step_dur - 0.7: ui.hide_card()
	if cut_next and _step_t > _step_dur - 0.5 and not last: ui.fade_to(1.0, 0.45)
	if _step_t >= _step_dur: _next_step(false)

func _finish_cinematic() -> void:
	if not cinematic: return
	cinematic = false
	_closing = -1.0
	_seq = []
	ui.set_cinematic(false)
	ui.hide_card()
	# hand the view back to the follow camera, already behind Kaito
	if world.camera != null:
		var pc: PlayerCamera = world.camera
		var bz := world.player.global_transform.basis.z
		pc.yaw = atan2(-bz.x, -bz.z)
		pc.snap()
		if pc.cam() != null: pc.cam().current = true
	if _cam != null:
		_cam.queue_free()
		_cam = null
	if world.hud != null: world.hud.visible = true
	if world.touch != null: world.touch.visible = true
	ui.set_black(1.0)
	ui.fade_to(0.0, 0.9)
	Game.cinematic = false
	_set_player_lock(false)
	var cb := _on_end
	_on_end = Callable()
	if cb.is_valid(): cb.call()

func _set_player_lock(on: bool) -> void:
	if world.player != null and "cinematic" in world.player:
		world.player.set("cinematic", on)

func _update_cam() -> void:
	if _cam == null or _shot.is_empty(): return
	var k := clampf(_shot_t / maxf(_shot_dur, 0.1), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	var p: Vector3 = (_shot["from"] as Vector3).lerp(_shot["to"], k)
	var l: Vector3 = (_shot["look_from"] as Vector3).lerp(_shot["look_to"], k)
	var fv = _shot.get("fov", null)
	if fv is Vector2: _cam.fov = lerpf((fv as Vector2).x, (fv as Vector2).y, k)
	else: _cam.fov = 50.0
	var t: Terrain = world.terrain
	if t != null and t.loaded:
		p.y = maxf(p.y, t.sample_height(p.x, p.z) + float(_shot.get("clear", 6.0)))
	if (l - p).length() < 0.01: return
	var up := Vector3.UP
	if absf((l - p).normalized().dot(up)) > 0.98: up = Vector3.FORWARD
	_cam.look_at_from_position(p, l, up)

func _zone(n: String) -> Vector3:
	var zs: Dictionary = world.data.get("zones", {})
	var z: Dictionary = zs.get(n, {"x": 700.0, "z": 700.0})
	var x := float(z["x"])
	var zz := float(z["z"])
	var h := 0.0
	if world.terrain != null and world.terrain.loaded: h = world.terrain.sample_height(x, zz)
	return Vector3(x, h, zz)

## v0.14b: the first cut flew every shot 40-120 m up, which read as a
## diorama and showed the map edge. Shots now sit near the ground or just
## over the canopy and are framed from the south, with the morning sun behind
## the lens: a telephoto of the castle on its plateau, a low angle on the keep
## from inside the bailey, Hanamura from the river meadow, the canopy towards
## the shrine hill, and a crane down onto Kaito at the foot of the torii.
## Paths were checked against the heightmap and the tree list so no ridge or
## crown stands in the line; tests/StoryShots has a stills mode for framing.
## Optional "fov" is a Vector2(start, end) in degrees.
func _make_shot(n: String) -> Dictionary:
	var pp: Vector3 = world.player.global_position
	match n:
		"castle":
			# ~170 m west-south-west, level with the plateau over a gap in the
			# forest (from the south the trees hide everything but the roof),
			# side-lit by the morning sun, slowly closing in on a long lens
			var c := _zone("castle")
			return {"from": c + Vector3(-164.4, -6.0, 59.9), "to": c + Vector3(-158.2, 0.7, 39.4),
				"look_from": c + Vector3(0, 20, 0), "look_to": c + Vector3(0, 18, 0),
				"clear": 16.0, "fov": Vector2(34.0, 31.0)}
		"castle_keep":
			# inside the walls, head height plus a little, drifting round the keep
			var c := _zone("castle")
			return {"from": c + Vector3(23, 5.5, 39.8), "to": c + Vector3(9.1, 5.5, 43.0),
				"look_from": c + Vector3(0, 18, 0), "look_to": c + Vector3(0, 19.5, 0),
				"clear": 4.0, "fov": Vector2(64.0, 62.0)}
		"village":
			var v := _zone("village")
			return {"from": v + Vector3(-70, 22, 110), "to": v + Vector3(-48, 17, 80),
				"look_from": v + Vector3(0, 4, 0), "look_to": v + Vector3(4, 3, -4),
				"clear": 10.0, "fov": Vector2(48.0, 46.0)}
		"forest":
			# skimming the canopy towards the shrine hill
			var f := _zone("forest")
			var s := _zone("shrine")
			return {"from": f + Vector3(70, 32, 90), "to": f + Vector3(-40, 34, -20),
				"look_from": f + Vector3(-60, 8, -50), "look_to": s + Vector3(0, 12, 0),
				"clear": 30.0, "fov": Vector2(50.0, 46.0)}
		"shrine":
			# crane down from behind onto Kaito, ending where the follow camera sits
			var pc: PlayerCamera = world.camera
			var fwd := world.player.global_transform.basis.z
			fwd = Vector3(fwd.x, 0, fwd.z).normalized()
			var yaw := atan2(-fwd.x, -fwd.z)
			var pitch: float = pc.pitch if pc != null else -0.22
			var dist: float = pc.distance if pc != null else 4.6
			var pivot := pp + Vector3(0, 1.45, 0)
			var end := pivot + Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3(0, 0, dist)
			var game_fov := clampf(float(Game.settings.get("fov", 60.0)), 45.0, 85.0)
			return {"from": pp - fwd * 60.0 + Vector3(18, 22, 0), "to": end,
				"look_from": pp + Vector3(0, 6, 0), "look_to": pivot + (pivot - end).normalized() * 6.0,
				"clear": 1.2, "fov": Vector2(50.0, game_fov)}
		"keep":
			# epilogue: the keep from the south, over the gate, in full sun,
			# rising and drawing back
			var c2 := _zone("castle")
			return {"from": c2 + Vector3(17.4, 5.9, 98.5), "to": c2 + Vector3(18.8, 10.5, 106.4),
				"look_from": c2 + Vector3(0, 17, 0), "look_to": c2 + Vector3(0, 19, 0),
				"clear": 8.0, "fov": Vector2(44.0, 46.0)}
		"shrine_far":
			var s2 := _zone("shrine")
			return {"from": s2 + Vector3(60, 30, 80), "to": s2 + Vector3(110, 55, 140),
				"look_from": s2 + Vector3(0, 6, 0), "look_to": s2 + Vector3(0, 10, 0), "clear": 15.0}
	return {"from": pp + Vector3(10, 10, 10), "to": pp + Vector3(8, 8, 12),
		"look_from": pp, "look_to": pp, "clear": 4.0}
