extends CanvasLayer
## Mobile touch layer: virtual joystick, action buttons, customisable layout.
## Buttons drive the same Input actions as the keyboard, so gameplay code is shared.

const DEFAULT_LAYOUT := {
	"attack":   {"frac": Vector2(0.898, 0.822), "r": 54.0, "label": "ATK",  "action": "attack",   "hold": false},
	"heavy":    {"frac": Vector2(0.795, 0.878), "r": 44.0, "label": "HVY",  "action": "heavy",    "hold": false},
	"dodge":    {"frac": Vector2(0.930, 0.640), "r": 44.0, "label": "DODGE","action": "dodge",    "hold": false},
	"block":    {"frac": Vector2(0.815, 0.700), "r": 46.0, "label": "BLK",  "action": "block",    "hold": true},
	"lock":     {"frac": Vector2(0.712, 0.640), "r": 36.0, "label": "LOCK", "action": "lock_on",  "hold": false},
	"stance":   {"frac": Vector2(0.884, 0.480), "r": 38.0, "label": "STNC", "action": "stance",   "hold": false},
	"special":  {"frac": Vector2(0.762, 0.500), "r": 36.0, "label": "SPRT", "action": "special",  "hold": false},
	"interact": {"frac": Vector2(0.966, 0.470), "r": 34.0, "label": "USE",  "action": "interact", "hold": false},
	"sprint":   {"frac": Vector2(0.190, 0.800), "r": 34.0, "label": "SPRN", "special": "sprint",  "hold": true},
}
const STICK_FRAC := Vector2(0.128, 0.760)
const STICK_R := 84.0

var world: World
var layout := {}
var edit_mode := false
var enabled := true
var _stick_active := -1
var _stick_center := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _touch_owner := {}      # touch index -> button id
var _pressed := {}
var _scale := 1.0
var _control: Control

class Layer extends Control:
	var tc: CanvasLayer
	func _draw() -> void:
		if tc != null: tc.draw_all(self)

func _ready() -> void:
	layer = 11
	add_to_group("touch_layer")
	layout = {}
	for k in DEFAULT_LAYOUT.keys():
		layout[k] = DEFAULT_LAYOUT[k].duplicate()
	if Game.settings.has("touch_layout"):
		var saved: Dictionary = Game.settings["touch_layout"]
		for k in saved.keys():
			if layout.has(k):
				layout[k]["frac"] = Vector2(float(saved[k][0]), float(saved[k][1]))
	_control = Layer.new()
	_control.tc = self
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_control)
	_scale = float(Game.settings.get("touch_scale", 1.0))
	_update_visibility()

func bind(w: World) -> void:
	world = w

func _update_visibility() -> void:
	enabled = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() or bool(Game.settings.get("force_touch", false))

func set_edit_mode(on: bool) -> void:
	edit_mode = on
	if _control != null: _control.queue_redraw()

func save_layout() -> void:
	var out := {}
	for k in layout.keys():
		var f: Vector2 = layout[k]["frac"]
		out[k] = [f.x, f.y]
	Game.settings["touch_layout"] = out
	Game.save_settings()

func _btn_pos(id: String, sz: Vector2) -> Vector2:
	var f: Vector2 = layout[id]["frac"]
	return Vector2(f.x * sz.x, f.y * sz.y)

func _btn_radius(id: String) -> float:
	return float(layout[id]["r"]) * _scale

func _stick_pos(sz: Vector2) -> Vector2:
	return Vector2(STICK_FRAC.x * sz.x, STICK_FRAC.y * sz.y)

# ---------------------------------------------------------------- input
func _input(event: InputEvent) -> void:
	if not enabled or get_tree().paused: return
	var sz := _control.get_viewport_rect().size
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed: _touch_down(e.index, e.position, sz)
		else: _touch_up(e.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touch_drag(d.index, d.position, sz)

func _touch_down(index: int, pos: Vector2, sz: Vector2) -> void:
	if edit_mode:
		for id in layout.keys():
			if pos.distance_to(_btn_pos(id, sz)) <= _btn_radius(id) + 16.0:
				_touch_owner[index] = "EDIT:" + id
				return
		return
	var sc := _stick_pos(sz)
	if pos.distance_to(sc) <= STICK_R * _scale * 1.35:
		_stick_active = index
		_stick_center = pos
		_stick_vec = Vector2.ZERO
		Game.touch_move = Vector2.ZERO
		return
	for id in layout.keys():
		if pos.distance_to(_btn_pos(id, sz)) <= _btn_radius(id) * 1.12:
			_touch_owner[index] = id
			_press(id)
			return

func _touch_drag(index: int, pos: Vector2, sz: Vector2) -> void:
	if edit_mode:
		var owner: String = String(_touch_owner.get(index, ""))
		if owner.begins_with("EDIT:"):
			var id := owner.substr(5)
			layout[id]["frac"] = Vector2(clampf(pos.x / sz.x, 0.03, 0.97), clampf(pos.y / sz.y, 0.05, 0.97))
			_control.queue_redraw()
		return
	if index == _stick_active:
		var d := pos - _stick_center
		var maxr := STICK_R * _scale * 0.75
		if d.length() > maxr: d = d.normalized() * maxr
		_stick_vec = d / maxr
		if _stick_vec.length() < 0.16: _stick_vec = Vector2.ZERO
		Game.touch_move = _stick_vec
		return
	# sliding off a button cancels it (prevents accidental holds)
	var id: String = String(_touch_owner.get(index, ""))
	if id != "":
		var p := _btn_pos(id, sz)
		if pos.distance_to(p) > _btn_radius(String(id)) * 1.9:
			_release(String(id))
			_touch_owner.erase(index)

func _touch_up(index: int) -> void:
	if index == _stick_active:
		_stick_active = -1
		_stick_vec = Vector2.ZERO
		Game.touch_move = Vector2.ZERO
		return
	var id: String = String(_touch_owner.get(index, ""))
	if id != "" and not id.begins_with("EDIT:"):
		_release(id)
	_touch_owner.erase(index)

func _press(id: String) -> void:
	if _pressed.get(id, false): return
	_pressed[id] = true
	var b: Dictionary = layout[id]
	if b.has("action"):
		Input.action_press(String(b["action"]))
	if b.get("special", "") == "sprint":
		Game.touch_sprint = true
	if id == "block":
		Game.touch_block = true
	Audio.play_ui()
	_control.queue_redraw()

func _release(id: String) -> void:
	if not _pressed.get(id, false): return
	_pressed[id] = false
	var b: Dictionary = layout[id]
	if b.has("action"):
		Input.action_release(String(b["action"]))
	if b.get("special", "") == "sprint":
		Game.touch_sprint = false
	if id == "block":
		Game.touch_block = false
	_control.queue_redraw()

func release_all() -> void:
	for id in _pressed.keys():
		if _pressed[id]: _release(String(id))
	_stick_active = -1
	_stick_vec = Vector2.ZERO
	Game.touch_move = Vector2.ZERO
	Game.touch_sprint = false
	Game.touch_block = false

# ---------------------------------------------------------------- drawing
func draw_all(c: Control) -> void:
	if not enabled: return
	var sz := c.get_viewport_rect().size
	# joystick
	var sc := _stick_pos(sz)
	c.draw_circle(sc, STICK_R * _scale, Color(0.05, 0.06, 0.08, 0.42))
	c.draw_arc(sc, STICK_R * _scale, 0.0, TAU, 40, Color(0.78, 0.66, 0.36, 0.75), 2.0)
	var knob := sc + _stick_vec * STICK_R * _scale * 0.75
	c.draw_circle(knob, STICK_R * _scale * 0.34, Color(0.85, 0.82, 0.74, 0.55))
	c.draw_arc(knob, STICK_R * _scale * 0.34, 0.0, TAU, 24, Color(0.78, 0.66, 0.36, 0.9), 2.0)
	for id in layout.keys():
		var p := _btn_pos(id, sz)
		var r := _btn_radius(id)
		var on: bool = _pressed.get(id, false)
		var base := Color(0.10, 0.11, 0.14, 0.55 if not on else 0.85)
		c.draw_circle(p, r, base)
		c.draw_arc(p, r, 0.0, TAU, 28, Color(0.80, 0.68, 0.38, 0.95 if on else 0.6), 2.0)
		if on: c.draw_circle(p, r * 0.82, Color(0.72, 0.16, 0.12, 0.45))
		var lbl: String = String(layout[id]["label"])
		c.draw_string(ThemeDB.fallback_font, p + Vector2(-r * 0.62, 6), lbl,
			HORIZONTAL_ALIGNMENT_CENTER, r * 1.24, int(15 * _scale), Color(0.92, 0.89, 0.80))
	if edit_mode:
		c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.0, 0.0, 0.0, 0.35), true)
		c.draw_string(ThemeDB.fallback_font, Vector2(sz.x * 0.5 - 150, 46), "Drag buttons to reposition",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.9, 0.6))
