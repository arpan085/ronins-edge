extends Node
## Global game state, settings, save/load and scene flow.

signal state_changed
signal notice(text: String, kind: String)
signal zone_changed(zone: String)
signal difficulty_changed
signal gourd_changed(charges: int, max_charges: int)   ## v0.15 healing gourd
signal smoke_changed(charges: int, max_charges: int)   ## v0.16 smoke bombs
signal mastery_gained(points: int)                       ## v0.16

const SAVE_PATH := "user://ronin_save.json"
const ZONE_ORDER := ["shrine", "forest", "village", "castle", "mountain"]
const ZONE_TITLE := {
	"shrine": "Sakura Shrine", "forest": "Bamboo Forest", "village": "River Village",
	"castle": "Castle Ruins", "mountain": "Mountain Pass",
	"bamboo": "Bamboo Grove", "grassland": "Grasslands", "farmland": "Farmland",
	"ruins": "Old Ruins", "lake": "Lake Shore"
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
## v0.15 healing: the gourd holds a few drinks of medicine (B by default).
## Refilled by resting at a checkpoint or shrine, by medicinal herbs and by
## the meat of hunted animals.
var gourd := 3
var gourd_max := 3
var smoke := 3               ## v0.16 smoke bombs (Shinobi Arts), refilled with the gourd
var smoke_max := 3
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
var cinematic := false      ## v0.14: a story cinematic owns camera and input
var visited_zones: Array = ["shrine"]   ## fast-travel destinations

var settings := {
	"quality": 2,            # 0 low, 1 medium, 2 high
	"touch_scale": 1.0,
	"camera_sens": 1.0,
	"fov": 60.0,
	"joystick_size": 1.0,
	"invert_y": false,
	"haptics": true,
	"shake": 1.0,
	"master": 1.0,
	"music": 0.7,
	"sfx": 0.9,
	"ambience": 0.8,
	"show_fps": false,
	"film_fx": true,         # v0.17 vignette, grain and colour grade
	"left_handed": false,
	"binds": {},           # action -> [slot0, slot1] overrides ("k:<code>", "m:<button>", "")
	"last_weapon": "katana",
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
	apply_keybinds()          # saved rebinds only exist after load_settings()
	load_game()
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if world_ref != null:
		play_time += delta
	# debounce: a dragged slider writes the file once, half a second after it stops
	if _settings_dirty:
		_settings_t += delta
		if _settings_t > 0.5:
			flush_settings()

# ---------------------------------------------------------------- input map
func _setup_input() -> void:
	apply_keybinds()

## Every rebindable action, in the order the Controls screen lists them.  Each
## action has two slots.  A slot is "k:<physical keycode>", "m:<mouse button>"
## or "" (empty).  Defaults live in BIND_INFO, the player's changes in
## settings["binds"].  Esc always pauses (FIXED_ACTIONS) so nobody can lock
## themselves out of the menu.
const BIND_ORDER := [
	"move_forward", "move_back", "move_left", "move_right",
	"sprint", "walk", "crouch", "jump", "dodge",
	"attack", "heavy", "kick", "punch", "block", "sheathe",
	"weapon_1", "weapon_2", "weapon_3", "weapon_4", "weapon_next", "weapon_prev",
	"lock_on", "special", "stance", "interact", "call_horse", "heal", "smoke", "map", "skills",
]
const BIND_GROUPS := {"move_forward": "Movement", "attack": "Combat", "weapon_1": "Weapons", "lock_on": "Other"}
const K := 0
const M := 1
const BIND_INFO := {
	"move_forward": {"label": "Move forward", "def": [[K, KEY_W], [K, KEY_UP]]},
	"move_back":    {"label": "Move back", "def": [[K, KEY_S], [K, KEY_DOWN]]},
	"move_left":    {"label": "Move left", "def": [[K, KEY_A], [K, KEY_LEFT]]},
	"move_right":   {"label": "Move right", "def": [[K, KEY_D], [K, KEY_RIGHT]]},
	"sprint":       {"label": "Sprint (hold)", "def": [[K, KEY_SHIFT]]},
	"walk":         {"label": "Walk / run toggle", "def": [[K, KEY_Z]]},
	"jump":         {"label": "Jump", "def": [[K, KEY_SPACE]]},
	"crouch":       {"label": "Crouch / sneak (toggle)", "def": [[K, KEY_C]]},
	"dodge":        {"label": "Dodge / roll", "def": [[K, KEY_CTRL]]},
	"attack":       {"label": "Light attack", "def": [[M, MOUSE_BUTTON_LEFT], [K, KEY_J]]},
	"heavy":        {"label": "Heavy attack", "def": [[M, MOUSE_BUTTON_RIGHT], [K, KEY_K]]},
	"kick":         {"label": "Kick", "def": [[K, KEY_V]]},
	"punch":        {"label": "Punch combo", "def": [[K, KEY_G]]},
	"block":        {"label": "Guard / deflect (hold)", "def": [[K, KEY_Q], [K, KEY_L]]},
	"sheathe":      {"label": "Draw / sheathe", "def": [[K, KEY_X]]},
	"weapon_1":     {"label": "Katana", "def": [[K, KEY_1]]},
	"weapon_2":     {"label": "Nodachi", "def": [[K, KEY_2]]},
	"weapon_3":     {"label": "Yari (spear)", "def": [[K, KEY_3]]},
	"weapon_4":     {"label": "Fists", "def": [[K, KEY_4]]},
	"weapon_next":  {"label": "Next weapon", "def": [[M, MOUSE_BUTTON_WHEEL_DOWN], [K, KEY_BRACKETRIGHT]]},
	"weapon_prev":  {"label": "Previous weapon", "def": [[M, MOUSE_BUTTON_WHEEL_UP], [K, KEY_BRACKETLEFT]]},
	"lock_on":      {"label": "Lock on", "def": [[K, KEY_TAB], [M, MOUSE_BUTTON_MIDDLE]]},
	"special":      {"label": "Spirit Blade (focus)", "def": [[K, KEY_R]]},
	"stance":       {"label": "Change stance", "def": [[K, KEY_T]]},
	"interact":     {"label": "Interact / mount / deathblow", "def": [[K, KEY_E], [K, KEY_F]]},
	"call_horse":   {"label": "Call horse", "def": [[K, KEY_H]]},
	"heal":         {"label": "Drink from gourd (heal)", "def": [[K, KEY_B]]},
	"smoke":        {"label": "Smoke bomb", "def": [[K, KEY_Y], [M, MOUSE_BUTTON_XBUTTON1]]},
	"map":          {"label": "Open map", "def": [[K, KEY_M]]},
	"skills":       {"label": "Techniques (skill tree)", "def": [[K, KEY_U]]},
}
## Actions the player cannot rebind because the build depends on them.
const FIXED_ACTIONS := {"pause": [KEY_ESCAPE, KEY_P], "debug": [KEY_F3], "ui_restart": [KEY_F5]}

static func slot_str(kind: int, code: int) -> String:
	return ("k:%d" if kind == K else "m:%d") % code

func _binds() -> Dictionary:
	if not settings.has("binds") or typeof(settings["binds"]) != TYPE_DICTIONARY:
		settings["binds"] = {}
	return settings["binds"]

## The two slots of an action (strings, "" when empty).
func binds_for(action: String) -> Array:
	var ov := _binds()
	if ov.has(action):
		var a = ov[action]
		if typeof(a) == TYPE_ARRAY and a.size() == 2: return [String(a[0]), String(a[1])]
	var out := ["", ""]
	if BIND_INFO.has(action):
		var d: Array = BIND_INFO[action]["def"]
		for i in mini(2, d.size()): out[i] = slot_str(int(d[i][0]), int(d[i][1]))
	return out

static func slot_label(s: String) -> String:
	if s == "": return "\u2014"
	var c := int(s.substr(2))
	if s.begins_with("m:"):
		match c:
			MOUSE_BUTTON_LEFT: return "Left Mouse"
			MOUSE_BUTTON_RIGHT: return "Right Mouse"
			MOUSE_BUTTON_MIDDLE: return "Middle Mouse"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
			MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
		return "Mouse %d" % c
	return OS.get_keycode_string(c)

## Short text for prompts: the first bound slot of an action.
func bind_label(action: String) -> String:
	if FIXED_ACTIONS.has(action): return OS.get_keycode_string(int(FIXED_ACTIONS[action][0]))
	for s in binds_for(action):
		if s != "": return slot_label(s)
	return "\u2014"

func key_label(action: String) -> String:
	return bind_label(action)

## Put `s` on one slot of an action.  Whatever else held that input loses it, so
## two actions can never fight over one key.  Returns the action that lost it.
func set_bind(action: String, slot: int, s: String) -> String:
	var ov := _binds()
	var stolen := ""
	if s != "":
		for a in BIND_ORDER:
			var cur := binds_for(a)
			for i in 2:
				if cur[i] == s and not (a == action and i == slot):
					cur[i] = ""
					ov[a] = cur
					stolen = a
	var mine := binds_for(action)
	mine[slot] = s
	ov[action] = mine
	apply_keybinds()
	save_settings()
	return stolen

## Old single-key API kept for callers that still use it.
func set_keybind(action: String, keycode: int) -> void:
	set_bind(action, 0, slot_str(K, keycode))

func reset_keybinds() -> void:
	settings["binds"] = {}
	apply_keybinds()
	save_settings()

static func event_for(s: String) -> InputEvent:
	if s.length() < 3: return null
	var c := int(s.substr(2))
	if s.begins_with("k:"):
		var ev := InputEventKey.new()
		ev.physical_keycode = c as Key
		return ev
	var mb := InputEventMouseButton.new()
	mb.button_index = c as MouseButton
	return mb

## Rebuild the whole InputMap from BIND_INFO plus the saved overrides, so there
## is exactly one code path that decides what a key does.
func apply_keybinds() -> void:
	_migrate_binds()
	for action in BIND_ORDER:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		for s in binds_for(action):
			var ev := event_for(String(s))
			if ev != null: InputMap.action_add_event(action, ev)
	for action2 in FIXED_ACTIONS.keys():
		if not InputMap.has_action(action2):
			InputMap.add_action(action2, 0.2)
		InputMap.action_erase_events(action2)
		for k2 in FIXED_ACTIONS[action2]:
			var ev2 := InputEventKey.new()
			ev2.physical_keycode = int(k2) as Key
			InputMap.action_add_event(action2, ev2)

## v0.16: C moved from dodge's second slot to the new crouch action. A saved
## v0.15 layout still lists C under dodge; free it so one key is not both.
func _migrate_binds() -> void:
	var ov := _binds()
	if ov.has("crouch") or not ov.has("dodge"): return
	var a = ov["dodge"]
	if typeof(a) != TYPE_ARRAY or a.size() != 2: return
	var c := slot_str(K, KEY_C)
	for i in 2:
		if String(a[i]) == c: a[i] = ""
	ov["dodge"] = a

# ---------------------------------------------------------------- player state
func reset_run() -> void:
	hp = max_hp; posture = 0.0; focus = 0.0; stance = "stone"
	mastery_points = 0; xp = 0; zone = "shrine"; boss_defeated = false
	defeated = {}; tutorial_done = false; play_time = 0.0
	checkpoint = {"zone": "shrine", "pos": Vector3.ZERO}
	visited_zones = ["shrine"]
	gourd = gourd_max
	smoke = smoke_max
	Skills.reset()
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
	# v0.15: the player node owns the live hp. Writing only Game.hp (what this
	# used to do) left the bar where it was, so "restored health" restored nothing.
	if player_ref != null and is_instance_valid(player_ref) and player_ref.has_method("heal"):
		player_ref.heal(v)
	else:
		hp = clampf(hp + v, 0.0, max_hp)
	emit_signal("state_changed")

func add_xp(v: int) -> void:
	if v <= 0: return
	xp += v
	mastery_points += v
	emit_signal("state_changed")
	mastery_gained.emit(v)

func set_zone(z: String) -> void:
	if not visited_zones.has(z):
		visited_zones.append(z)
		if zone != "": Audio.play_sfx("discover", null, 1.0, 0.0)
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
		"bamboo": return "tall stalks, narrow paths"
		"grassland": return "open ground for riding"
		"farmland": return "rice fields and quiet farms"
		"ruins": return "stones older than the castle"
		"lake": return "still water"
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
		"hp": hp, "posture": posture, "focus": focus, "stance": stance, "gourd": gourd,
		"mastery": mastery_points, "xp": xp, "zone": zone, "visited": visited_zones,
		"skills": Skills.serialize(), "smoke": smoke,
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
	gourd = clampi(int(parsed.get("gourd", gourd_max)), 0, gourd_max)
	posture = float(parsed.get("posture", 0.0))
	focus = float(parsed.get("focus", 0.0))
	stance = String(parsed.get("stance", "stone"))
	mastery_points = int(parsed.get("mastery", 0))
	smoke = clampi(int(parsed.get("smoke", smoke_max)), 0, smoke_max)
	Skills.deserialize(parsed.get("skills", []))
	xp = int(parsed.get("xp", 0))
	zone = String(parsed.get("zone", "shrine"))
	visited_zones = []
	for vz in parsed.get("visited", ["shrine", zone]):
		if not visited_zones.has(String(vz)): visited_zones.append(String(vz))
	if not visited_zones.has(zone): visited_zones.append(zone)
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

## v0.15: writing the file no longer re-applies graphics quality. Sliders call
## this on every tick; the quality menu applies its own change once.
func save_settings() -> void:
	_settings_dirty = true

var _settings_dirty := false
var _settings_t := 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if _settings_dirty: flush_settings()

func flush_settings() -> void:
	_settings_dirty = false
	_settings_t = 0.0
	var f := FileAccess.open("user://ronin_settings.json", FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(settings, "  ")); f.close()

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


## v0.15 healing helpers -------------------------------------------------------
func set_gourd(n: int) -> void:
	var v := clampi(n, 0, gourd_max)
	if v == gourd: return
	gourd = v
	gourd_changed.emit(gourd, gourd_max)

func refill_gourd(n: int = 99) -> int:
	var before := gourd
	set_gourd(gourd + n)
	# smoke bombs are restocked wherever the gourd is (rest, respawn, caches)
	if n >= gourd_max: set_smoke(smoke_max)
	return gourd - before

func set_smoke(n: int) -> void:
	var v := clampi(n, 0, smoke_max)
	if v == smoke: return
	smoke = v
	smoke_changed.emit(smoke, smoke_max)
