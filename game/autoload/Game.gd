extends Node
## Global game state, settings, save/load and scene flow.

signal state_changed
signal notice(text: String, kind: String)
signal zone_changed(zone: String)
signal difficulty_changed

const SAVE_PATH := "user://ronin_save.json"
const ZONE_ORDER := ["shrine", "forest", "village", "castle", "mountain"]
const ZONE_TITLE := {
	"shrine": "Sakura Shrine", "forest": "Bamboo Forest", "village": "River Village",
	"castle": "Castle Ruins", "mountain": "Mountain Pass"
}
const STANCES := ["stone", "water", "wind", "moon"]
const STANCE_INFO := {
	"stone": {"name": "Stone", "desc": "Balanced. +posture damage", "dmg": 1.0, "spd": 1.0, "posture": 1.15},
	"water": {"name": "Water", "desc": "Fast combos, lower damage", "dmg": 0.82, "spd": 1.35, "posture": 0.9},
	"wind":  {"name": "Wind", "desc": "Heavy breaks, slow", "dmg": 1.28, "spd": 0.8, "posture": 1.35},
	"moon":  {"name": "Moon", "desc": "Parry focus, deflect bonus", "dmg": 0.95, "spd": 1.1, "posture": 1.0},
}

var hp := 100.0
var max_hp := 100.0
var posture := 0.0
var max_posture := 100.0
var focus := 0.0
var max_focus := 100.0
var stance := "stone"
var unlocked_stances: Array[String] = ["stone", "water", "wind", "moon"]
var mastery_points := 0
var xp := 0
var zone := "shrine"
var checkpoint := {"zone": "shrine", "pos": Vector3.ZERO}
var defeated := {}          # enemy instance id -> true (so they stay dead)
var boss_defeated := false
var tutorial_done := false
var play_time := 0.0
var in_combat := false

var settings := {
	"quality": 2,            # 0 low, 1 medium, 2 high
	"touch_scale": 1.0,
	"camera_sens": 1.0,
	"joystick_size": 1.0,
	"invert_y": false,
	"haptics": true,
	"shake": 1.0,
	"music": 0.7,
	"sfx": 0.9,
	"show_fps": false,
	"left_handed": false,
}

var player_ref: Node3D = null
var world_ref: Node3D = null
## written by TouchControls, read by Player so touch and keyboard share one path
var touch_move := Vector2.ZERO
var touch_sprint := false
var touch_block := false

func _ready() -> void:
	_setup_input()
	load_settings()
	load_game()
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if world_ref != null:
		play_time += delta

# ---------------------------------------------------------------- input map
func _setup_input() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"attack": [KEY_J], "heavy": [KEY_K], "dodge": [KEY_SPACE],
		"block": [KEY_L], "lock_on": [KEY_TAB], "stance": [KEY_Q],
		"interact": [KEY_F], "special": [KEY_R], "pause": [KEY_ESCAPE],
		"sprint": [KEY_SHIFT], "debug": [KEY_F3], "ui_restart": [KEY_F5],
	}
	for action in keys.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	# mouse buttons for dev
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", mb)
	var mb2 := InputEventMouseButton.new()
	mb2.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("block", mb2)

# ---------------------------------------------------------------- player state
func reset_run() -> void:
	hp = max_hp; posture = 0.0; focus = 0.0; stance = "stone"
	mastery_points = 0; xp = 0; zone = "shrine"; boss_defeated = false
	defeated = {}; tutorial_done = false; play_time = 0.0
	checkpoint = {"zone": "shrine", "pos": Vector3.ZERO}
	Quests.reset_all()
	emit_signal("state_changed")

func spend_posture(v: float) -> void:
	posture = clampf(posture + v, 0.0, max_posture)
	emit_signal("state_changed")

func add_focus(v: float) -> void:
	focus = clampf(focus + v, 0.0, max_focus)
	emit_signal("state_changed")

func damage_player(v: float) -> void:
	hp = clampf(hp - v, 0.0, max_hp)
	emit_signal("state_changed")

func heal_player(v: float) -> void:
	hp = clampf(hp + v, 0.0, max_hp)
	emit_signal("state_changed")

func add_xp(v: int) -> void:
	xp += v
	mastery_points += v
	emit_signal("state_changed")

func set_zone(z: String) -> void:
	if z == zone: return
	zone = z
	Audio.play_music(z)
	emit_signal("zone_changed", z)
	notice.emit("%s — %s" % [ZONE_TITLE.get(z, z), _zone_hint(z)], "zone")

func _zone_hint(z: String) -> String:
	match z:
		"shrine": return "the path begins"
		"forest": return "bamboo whispers"
		"village": return "the people need you"
		"castle": return "ruins of a fallen lord"
		"mountain": return "the final duel awaits"
	return ""

func stance_info() -> Dictionary:
	return STANCE_INFO.get(stance, STANCE_INFO["stone"])

func cycle_stance(dir: int = 1) -> void:
	var avail := unlocked_stances
	if avail.is_empty(): return
	var i := avail.find(stance)
	if i < 0: i = 0
	stance = avail[(i + dir + avail.size()) % avail.size()]
	notice.emit("Stance: %s" % STANCE_INFO[stance]["name"], "stance")
	emit_signal("state_changed")

func mark_defeated(id: String) -> void:
	defeated[id] = true

func is_defeated(id: String) -> bool:
	return defeated.get(id, false)

# ---------------------------------------------------------------- save / load
func save_game() -> bool:
	var data := {
		"hp": hp, "posture": posture, "focus": focus, "stance": stance,
		"mastery": mastery_points, "xp": xp, "zone": zone,
		"checkpoint": {"zone": checkpoint["zone"], "pos": _v3_to_a(checkpoint["pos"])},
		"defeated": defeated, "boss_defeated": boss_defeated,
		"tutorial_done": tutorial_done, "play_time": play_time,
		"quests": Quests.serialize(),
		"settings": settings,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("save failed: %s" % FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH): return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null: return false
	var txt := f.get_as_text(); f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY: return false
	hp = float(parsed.get("hp", 100.0))
	posture = float(parsed.get("posture", 0.0))
	focus = float(parsed.get("focus", 0.0))
	stance = String(parsed.get("stance", "stone"))
	mastery_points = int(parsed.get("mastery", 0))
	xp = int(parsed.get("xp", 0))
	zone = String(parsed.get("zone", "shrine"))
	boss_defeated = bool(parsed.get("boss_defeated", false))
	tutorial_done = bool(parsed.get("tutorial_done", false))
	play_time = float(parsed.get("play_time", 0.0))
	var cp: Dictionary = parsed.get("checkpoint", {})
	checkpoint = {"zone": String(cp.get("zone", "shrine")), "pos": _a_to_v3(cp.get("pos", [0, 0, 0]))}
	defeated = parsed.get("defeated", {})
	if parsed.has("settings"):
		for k in parsed["settings"].keys():
			settings[k] = parsed["settings"][k]
	Quests.deserialize(parsed.get("quests", {}))
	return true

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func save_settings() -> void:
	var f := FileAccess.open("user://ronin_settings.json", FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(settings, "  ")); f.close()
	Perf.apply_quality(int(settings["quality"]))

func load_settings() -> void:
	if not FileAccess.file_exists("user://ronin_settings.json"): return
	var f := FileAccess.open("user://ronin_settings.json", FileAccess.READ)
	if f == null: return
	var parsed = JSON.parse_string(f.get_as_text()); f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		for k in parsed.keys(): settings[k] = parsed[k]

func set_checkpoint(z: String, pos: Vector3) -> void:
	checkpoint = {"zone": z, "pos": pos}
	notice.emit("Checkpoint reached", "checkpoint")

func _v3_to_a(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func _a_to_v3(a) -> Vector3:
	if typeof(a) == TYPE_ARRAY and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
