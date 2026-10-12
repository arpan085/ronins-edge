class_name WorldMap
extends Control
## v0.15 full-screen world map (M by default, the MAP button on touch).
##
## Opens over a paused game. The painted terrain map is the same bake the HUD
## radar uses (tools/bake_minimap.py), shown north-up with every province, the
## shrines and checkpoints you can rest at, caves, waterfalls and landmarks,
## your horse and the current objective. Drag or WASD to pan, the wheel / Q E
## or a pinch to zoom, C to centre on yourself; click a province you have
## already visited to fast-travel there. M or Esc closes it.

const GOLD := Color(0.89, 0.75, 0.46)
const PARCHMENT := Color(0.96, 0.93, 0.87)
const MUTED := Color(0.74, 0.72, 0.68)
const INK := Color(0.03, 0.035, 0.045, 0.86)
const VERMILION := Color(0.84, 0.20, 0.15)
const HORSE_COL := Color(0.83, 0.64, 0.40)
const WATER_COL := Color(0.55, 0.78, 0.95)
const ZONE_KANJI := {"shrine": "桜神社", "forest": "竹林", "village": "川村", "castle": "城跡",
	"mountain": "峠", "bamboo": "竹林", "grassland": "草原", "farmland": "田畑", "ruins": "遺跡",
	"lake": "湖畔"}
const ZOOM_MIN := 1.0
const ZOOM_MAX := 8.0

var hud: CanvasLayer
var world
var _tex: Texture2D
var _world_size := 1536.0
var _zoom := 2.0          # 1 = the whole world fits the frame
var _center := Vector2(768, 768)
var _frame := Rect2()
var _k := 1.0
var _drag_from := Vector2.ZERO
var _drag_center := Vector2.ZERO
var _dragging := false
var _drag_moved := 0.0
var _touches := {}        # index -> position (pinch zoom)
var _pinch_d := 0.0
var _hover := ""
var _selected := ""
var _travel_rect := Rect2()
var _close_rect := Rect2()
var _zoom_in_rect := Rect2()
var _zoom_out_rect := Rect2()
var _t := 0.0
var _opened_at := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	if ResourceLoader.exists("res://assets/terrain/minimap.png"):
		_tex = load("res://assets/terrain/minimap.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func is_open() -> bool:
	return visible

func open() -> void:
	if visible: return
	world = Game.world_ref
	if world != null:
		_world_size = float(world.data.get("size", 1536.0)) if typeof(world.data) == TYPE_DICTIONARY else 1536.0
		if world.player != null:
			var p: Vector3 = world.player.global_position
			_center = Vector2(p.x, p.z)
	_zoom = 2.2
	_selected = ""
	_hover = ""
	_clamp_view()
	visible = true
	_opened_at = Engine.get_process_frames()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.play_sfx("map_open", null, 1.0, -4.0)
	queue_redraw()

func close() -> void:
	if not visible: return
	visible = false
	_dragging = false
	_touches.clear()
	get_tree().paused = false
	if not OS.has_feature("mobile") and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Audio.play_sfx("map_open", null, 0.8, -8.0)

# ---------------------------------------------------------------- view maths
func _span() -> float:
	return _world_size / _zoom

func _to_screen(w: Vector2) -> Vector2:
	var s := _frame.size.x / _span()
	return _frame.get_center() + (w - _center) * s

func _to_world(p: Vector2) -> Vector2:
	var s := _frame.size.x / _span()
	return _center + (p - _frame.get_center()) / s

func _clamp_view() -> void:
	_zoom = clampf(_zoom, ZOOM_MIN, ZOOM_MAX)
	var half := _span() * 0.5
	_center.x = clampf(_center.x, half, _world_size - half)
	_center.y = clampf(_center.y, half, _world_size - half)

func _zoom_at(screen_p: Vector2, factor: float) -> void:
	var before := _to_world(screen_p)
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	var after := _to_world(screen_p)
	_center += before - after
	_clamp_view()
	queue_redraw()

func _layout() -> void:
	var sz := get_viewport_rect().size
	_k = clampf(sz.y / 720.0, 0.75, 2.2)
	var legend_w := 250.0 * _k if sz.x > sz.y * 1.25 else 0.0
	var side := minf(sz.y - 120.0 * _k, sz.x - legend_w - 90.0 * _k)
	side = maxf(side, 200.0)
	var x0 := (sz.x - legend_w - side) * 0.5
	if legend_w > 0.0: x0 = maxf(40.0 * _k, (sz.x - side - legend_w - 30.0 * _k) * 0.5)
	_frame = Rect2(Vector2(x0, (sz.y - side) * 0.5 + 18.0 * _k), Vector2(side, side))

# ---------------------------------------------------------------- input
func _process(delta: float) -> void:
	if not visible: return
	_t += delta
	# closing on the same press that opened it would flicker shut
	if Engine.get_process_frames() > _opened_at + 1:
		if Input.is_action_just_pressed("map") or Input.is_action_just_pressed("pause"):
			close()
			return
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if v.length() > 0.05:
		_center += v * _span() * 0.6 * delta
		_clamp_view()
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_EQUAL) or Input.is_physical_key_pressed(KEY_KP_ADD):
		_zoom_at(_frame.get_center(), 1.0 + 1.6 * delta)
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_MINUS) or Input.is_physical_key_pressed(KEY_KP_SUBTRACT):
		_zoom_at(_frame.get_center(), 1.0 / (1.0 + 1.6 * delta))
	queue_redraw()

func _gui_input(ev: InputEvent) -> void:
	if not visible: return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.18)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / 1.18)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_moved = 0.0
				_drag_from = mb.position
				_drag_center = _center
			else:
				if _dragging and _drag_moved < 8.0: _click(mb.position)
				_dragging = false
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_selected = ""
		accept_event()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _dragging:
			_drag_moved = maxf(_drag_moved, mm.position.distance_to(_drag_from))
			var s := _frame.size.x / _span()
			_center = _drag_center - (mm.position - _drag_from) / s
			_clamp_view()
		_hover = _zone_at(mm.position)
		accept_event()
	elif ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
			if _touches.size() == 1:
				_dragging = true
				_drag_moved = 0.0
				_drag_from = st.position
				_drag_center = _center
			elif _touches.size() == 2:
				var pts: Array = _touches.values()
				_pinch_d = (pts[0] as Vector2).distance_to(pts[1])
				_dragging = false
		else:
			if _touches.size() == 1 and _dragging and _drag_moved < 14.0: _click(st.position)
			_touches.erase(st.index)
			_dragging = false
		accept_event()
	elif ev is InputEventScreenDrag:
		var sd := ev as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			var pts: Array = _touches.values()
			var d := (pts[0] as Vector2).distance_to(pts[1])
			if _pinch_d > 1.0 and d > 1.0:
				_zoom_at(((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5, d / _pinch_d)
			_pinch_d = d
		elif _dragging:
			_drag_moved = maxf(_drag_moved, sd.position.distance_to(_drag_from))
			var s := _frame.size.x / _span()
			_center = _drag_center - (sd.position - _drag_from) / s
			_clamp_view()
		accept_event()
	elif ev is InputEventMagnifyGesture:
		var mg := ev as InputEventMagnifyGesture
		_zoom_at(mg.position, mg.factor)
		accept_event()
	elif ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo:
		var key := ev as InputEventKey
		if key.physical_keycode == KEY_C or key.physical_keycode == KEY_SPACE:
			_center_on_player()
			accept_event()
		elif key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_KP_ENTER:
			if _selected != "": _travel(_selected)
			accept_event()

func _center_on_player() -> void:
	if world != null and world.player != null:
		var p: Vector3 = world.player.global_position
		_center = Vector2(p.x, p.z)
		_clamp_view()
		queue_redraw()

func _click(p: Vector2) -> void:
	if _close_rect.has_point(p):
		close(); return
	if _zoom_in_rect.has_point(p):
		_zoom_at(_frame.get_center(), 1.4); return
	if _zoom_out_rect.has_point(p):
		_zoom_at(_frame.get_center(), 1.0 / 1.4); return
	if _selected != "" and _travel_rect.has_point(p):
		_travel(_selected); return
	var z := _zone_at(p)
	_selected = z
	if z != "": Audio.play_ui()
	queue_redraw()

func _travel(zone: String) -> void:
	if world == null or not world.has_method("fast_travel"): return
	if not Game.visited_zones.has(zone):
		Game.notice.emit("You have not been to %s yet" % Game.ZONE_TITLE.get(zone, zone), "warn")
		return
	# fast_travel warps the player; it runs unpaused so physics settles
	close()
	world.fast_travel(zone)

func _zones() -> Dictionary:
	if world == null or typeof(world.data) != TYPE_DICTIONARY: return {}
	return world.data.get("zones", {})

func _zone_at(p: Vector2) -> String:
	var best := ""
	var bd := 22.0 * _k
	var zs := _zones()
	for z in zs.keys():
		var sp := _to_screen(Vector2(float(zs[z]["x"]), float(zs[z]["z"])))
		var d := sp.distance_to(p)
		if d < bd:
			bd = d
			best = String(z)
	return best

# ---------------------------------------------------------------- drawing
func _draw() -> void:
	if not visible: return
	_layout()
	var sz := get_viewport_rect().size
	var k := _k
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.012, 0.014, 0.02, 0.86))
	var f_title: Font = hud.f_title if hud != null else ThemeDB.fallback_font
	var f_semi: Font = hud.f_semi if hud != null else ThemeDB.fallback_font
	var f_bold: Font = hud.f_bold if hud != null else ThemeDB.fallback_font
	var f_reg: Font = hud.f_reg if hud != null else ThemeDB.fallback_font
	# title
	var ty := _frame.position.y - 22.0 * k
	_txt(f_title, Vector2(_frame.position.x, ty), "地図", int(26.0 * k), GOLD, 4)
	_txt(f_bold, Vector2(_frame.position.x + 62.0 * k, ty - 3.0 * k), "MAP OF THE PROVINCE", int(13.0 * k), PARCHMENT, 3)
	# frame + map
	draw_rect(_frame.grow(7.0 * k), Color(0, 0, 0, 0.55))
	draw_rect(_frame.grow(3.0 * k), Color(0.07, 0.065, 0.06))
	if _tex != null:
		var ts := _tex.get_size()
		var half := _span() * 0.5
		var src := Rect2((_center - Vector2(half, half)) / _world_size * ts, Vector2(_span(), _span()) / _world_size * ts)
		draw_texture_rect_region(_tex, _frame, src, Color(1, 1, 1, 1))
	else:
		draw_rect(_frame, Color(0.22, 0.27, 0.18))
	# soft parchment wash so markers and labels pop off the painted terrain
	draw_rect(_frame, Color(0.05, 0.04, 0.02, 0.10))
	draw_rect(_frame.grow(3.0 * k), GOLD * Color(1, 1, 1, 0.75), false, 1.5 * k)
	draw_rect(_frame.grow(7.5 * k), GOLD * Color(1, 1, 1, 0.25), false, 1.0 * k)
	_corner_ornaments(_frame.grow(7.5 * k), k)

	# everything below is clipped to the frame by hand (cheap and no extra nodes)
	_draw_grid(k, f_reg)
	_draw_features(k)
	_draw_checkpoints(k)
	_draw_zones(k, f_title, f_semi)
	_draw_objective(k, f_semi)
	_draw_horse(k)
	_draw_player(k)
	_draw_compass(k, f_bold)
	_draw_scale(k, f_semi)
	_draw_buttons(k, f_bold)
	_draw_selection(k, f_title, f_semi, f_bold)
	_draw_legend(k, f_bold, f_semi, sz)

func _inside(p: Vector2, margin := 0.0) -> bool:
	return _frame.grow(-margin).has_point(p)

func _txt(font: Font, pos: Vector2, s: String, size: int, col: Color, outline := 0, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	if s == "": return
	if outline > 0:
		draw_string_outline(font, pos, s, align, width, size, outline, Color(0, 0, 0, 0.6 * col.a))
	draw_string(font, pos, s, align, width, size, col)

func _ctxt(font: Font, center: Vector2, s: String, size: int, col: Color, outline := 0) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var asc := font.get_ascent(size)
	var desc := font.get_descent(size)
	_txt(font, Vector2(center.x - w * 0.5, center.y + (asc - desc) * 0.5), s, size, col, outline)

func _corner_ornaments(r: Rect2, k: float) -> void:
	var L := 18.0 * k
	var w := 2.0 * k
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if c.x < r.get_center().x else -1.0
		var sy := 1.0 if c.y < r.get_center().y else -1.0
		draw_line(c, c + Vector2(L * sx, 0), GOLD, w)
		draw_line(c, c + Vector2(0, L * sy), GOLD, w)
		draw_circle(c, 3.0 * k, GOLD)

func _draw_grid(k: float, f: Font) -> void:
	# a faint survey grid every 256 m, labelled like an old map's margins
	var step := 256.0 if _zoom < 3.0 else 128.0
	var col := Color(0.0, 0.0, 0.0, 0.16)
	var x := 0.0
	var i := 0
	while x <= _world_size + 0.1:
		var a := _to_screen(Vector2(x, 0))
		if a.x > _frame.position.x + 1.0 and a.x < _frame.end.x - 1.0:
			draw_line(Vector2(a.x, _frame.position.y), Vector2(a.x, _frame.end.y), col, 1.0)
		x += step
		i += 1
	var z := 0.0
	while z <= _world_size + 0.1:
		var b := _to_screen(Vector2(0, z))
		if b.y > _frame.position.y + 1.0 and b.y < _frame.end.y - 1.0:
			draw_line(Vector2(_frame.position.x, b.y), Vector2(_frame.end.x, b.y), col, 1.0)
		z += step

func _features() -> Dictionary:
	if world == null or typeof(world.data) != TYPE_DICTIONARY: return {}
	return world.data

func _draw_features(k: float) -> void:
	var d := _features()
	for wf in d.get("waterfalls", []):
		var p := _to_screen(Vector2(float(wf["x"]), float(wf["z"])))
		if not _inside(p, 4.0): continue
		_icon_waterfall(p, k)
	for cv in d.get("caves", []):
		var p := _to_screen(Vector2(float(cv["x"]), float(cv["z"])))
		if not _inside(p, 4.0): continue
		_icon_cave(p, k)
	for lm in d.get("landmarks", []):
		var p := _to_screen(Vector2(float(lm["x"]), float(lm["z"])))
		if not _inside(p, 4.0): continue
		match String(lm.get("kind", "")):
			"torii": _icon_torii(p, 6.5 * k, VERMILION)
			"castle_keep": _icon_castle(p, k)
			"shrine_hall": pass
			"cedar": _icon_cedar(p, k)

func _icon_waterfall(p: Vector2, k: float) -> void:
	draw_circle(p, 6.0 * k, Color(0, 0, 0, 0.45))
	draw_circle(p, 4.6 * k, Color(0.16, 0.30, 0.42))
	for i in 3:
		var x := (float(i) - 1.0) * 2.0 * k
		draw_line(p + Vector2(x, -2.6 * k), p + Vector2(x, 2.6 * k), WATER_COL, 1.2 * k)

func _icon_cave(p: Vector2, k: float) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var a := PI + PI * float(i) / 12.0
		pts.append(p + Vector2(cos(a), sin(a)) * 6.5 * k + Vector2(0, 3.0 * k))
	draw_colored_polygon(pts, Color(0.10, 0.09, 0.08, 0.92))
	draw_polyline(pts, Color(0.80, 0.74, 0.62, 0.9), 1.2 * k)
	draw_line(p + Vector2(-6.5 * k, 3.0 * k), p + Vector2(6.5 * k, 3.0 * k), Color(0.80, 0.74, 0.62, 0.9), 1.2 * k)

func _icon_torii(p: Vector2, r: float, col: Color) -> void:
	var w := maxf(1.4, r * 0.28)
	draw_line(p + Vector2(-r * 1.15, -r * 0.62), p + Vector2(r * 1.15, -r * 0.62), Color(0, 0, 0, 0.6), w * 2.2)
	draw_line(p + Vector2(-r * 0.62, -r * 0.6), p + Vector2(-r * 0.62, r * 0.9), Color(0, 0, 0, 0.6), w * 2.0)
	draw_line(p + Vector2(r * 0.62, -r * 0.6), p + Vector2(r * 0.62, r * 0.9), Color(0, 0, 0, 0.6), w * 2.0)
	draw_line(p + Vector2(-r * 1.15, -r * 0.62), p + Vector2(r * 1.15, -r * 0.62), col, w * 1.3)
	draw_line(p + Vector2(-r * 0.85, -r * 0.2), p + Vector2(r * 0.85, -r * 0.2), col, w)
	draw_line(p + Vector2(-r * 0.62, -r * 0.6), p + Vector2(-r * 0.62, r * 0.9), col, w)
	draw_line(p + Vector2(r * 0.62, -r * 0.6), p + Vector2(r * 0.62, r * 0.9), col, w)

func _icon_castle(p: Vector2, k: float) -> void:
	var pts := PackedVector2Array([p + Vector2(-7, 6) * k, p + Vector2(-7, -1) * k, p + Vector2(-4, -1) * k,
		p + Vector2(-4, -5) * k, p + Vector2(0, -8) * k, p + Vector2(4, -5) * k, p + Vector2(4, -1) * k,
		p + Vector2(7, -1) * k, p + Vector2(7, 6) * k])
	var o := PackedVector2Array()
	for q in pts: o.append(p + (q - p) * 1.25)
	draw_colored_polygon(o, Color(0, 0, 0, 0.6))
	draw_colored_polygon(pts, Color(0.86, 0.84, 0.78))

func _icon_cedar(p: Vector2, k: float) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -6) * k, p + Vector2(4, 3) * k, p + Vector2(-4, 3) * k])
	draw_colored_polygon(pts, Color(0.09, 0.20, 0.11, 0.9))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0.75, 0.85, 0.65, 0.7), 1.0 * k)

func _draw_checkpoints(k: float) -> void:
	if world == null: return
	for c in world.get("checkpoints"):
		var pos: Vector3 = c["pos"]
		var p := _to_screen(Vector2(pos.x, pos.z))
		if not _inside(p, 4.0): continue
		var lit := bool(c.get("used", false))
		# a stone lantern: lit ones are the places you can rest
		draw_circle(p, 5.2 * k, Color(0, 0, 0, 0.55))
		draw_circle(p, 3.8 * k, Color(1.0, 0.72, 0.32) if lit else Color(0.45, 0.43, 0.40))
		if lit: draw_circle(p, 7.5 * k + sin(_t * 3.0) * 0.8 * k, Color(1.0, 0.7, 0.3, 0.16))

func _draw_zones(k: float, f_title: Font, f_semi: Font) -> void:
	var zs := _zones()
	var kanji: Dictionary = ZONE_KANJI
	for z in zs.keys():
		var zid := String(z)
		var p := _to_screen(Vector2(float(zs[z]["x"]), float(zs[z]["z"])))
		if not _inside(p, 10.0 * k): continue
		var visited := Game.visited_zones.has(zid)
		var hot := zid == _hover or zid == _selected
		var col := PARCHMENT if visited else MUTED * Color(1, 1, 1, 0.85)
		if visited:
			# visited provinces are fast-travel points: a gold torii seal
			draw_circle(p, 11.0 * k, Color(0, 0, 0, 0.55))
			draw_circle(p, 9.0 * k, Color(0.12, 0.09, 0.06, 0.95))
			draw_arc(p, 9.0 * k, 0.0, TAU, 28, GOLD, 1.4 * k, true)
			_icon_torii(p + Vector2(0, 0.5 * k), 4.6 * k, GOLD)
		else:
			draw_circle(p, 8.0 * k, Color(0, 0, 0, 0.45))
			draw_circle(p, 6.5 * k, Color(0.16, 0.15, 0.14, 0.9))
			_ctxt(f_semi, p, "?", int(10.0 * k), MUTED)
		if hot: draw_arc(p, 14.0 * k, 0.0, TAU, 32, GOLD, 2.0 * k, true)
		var title := String(Game.ZONE_TITLE.get(zid, zid))
		var kj := String(kanji.get(zid, ""))
		var main_zone := Game.ZONE_ORDER.has(zid)
		var fs := int((15.0 if main_zone else 12.5) * k)
		_ctxt(f_title, p + Vector2(0, -21.0 * k), title, fs, col, 4)
		if kj != "" and _zoom > 1.6:
			_ctxt(f_title, p + Vector2(0, -21.0 * k - fs * 1.05), kj, int(fs * 0.8), GOLD * Color(1, 1, 1, 0.8), 3)

func _draw_objective(k: float, f_semi: Font) -> void:
	if world == null or not world.has_method("objective_position"): return
	var op = world.objective_position()
	if op == null: return
	var ov: Vector3 = op
	var p := _to_screen(Vector2(ov.x, ov.z))
	var r := 7.0 * k
	if not _inside(p, 8.0 * k):
		# pinned to the frame edge, pointing the way
		var c := _frame.get_center()
		var d := p - c
		var hw := _frame.size.x * 0.5 - 14.0 * k
		var s := hw / maxf(absf(d.x), absf(d.y))
		p = c + d * minf(s, 1.0)
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	draw_arc(p, r * (1.8 + pulse * 0.7), 0.0, TAU, 32, GOLD * Color(1, 1, 1, 0.55 * (1.0 - pulse) + 0.15), 1.6 * k, true)
	var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
	var o := r + 2.0 * k
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -o), p + Vector2(o, 0), p + Vector2(0, o), p + Vector2(-o, 0)]), Color(0, 0, 0, 0.6))
	draw_colored_polygon(pts, GOLD)

func _draw_horse(k: float) -> void:
	if world == null or world.horse == null or not is_instance_valid(world.horse): return
	if world.player != null and world.player.has_method("is_mounted") and world.player.is_mounted(): return
	var hp: Vector3 = world.horse.global_position
	var p := _to_screen(Vector2(hp.x, hp.z))
	if not _inside(p, 4.0): return
	draw_circle(p, 6.5 * k, Color(0, 0, 0, 0.6))
	draw_circle(p, 5.0 * k, HORSE_COL)
	# horseshoe
	draw_arc(p + Vector2(0, 0.6 * k), 2.6 * k, PI * 0.15, PI * 1.85, 12, Color(0.15, 0.10, 0.06), 1.4 * k, true)

func _draw_player(k: float) -> void:
	if world == null or world.player == null: return
	var pl: Node3D = world.player
	var pp: Vector3 = pl.global_position
	var p := _to_screen(Vector2(pp.x, pp.z))
	if not _inside(p, 2.0): return
	# camera view cone
	if world.camera != null and world.camera.has_method("get_yaw"):
		var yaw: float = world.camera.get_yaw()
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var L := 46.0 * k
		var a := fwd.rotated(-0.5) * L
		var b := fwd.rotated(0.5) * L
		draw_colored_polygon(PackedVector2Array([p, p + a, p + b]), Color(1, 1, 1, 0.10))
	var f3 := pl.global_transform.basis.z
	var fd := Vector2(f3.x, f3.z)
	fd = fd.normalized() if fd.length() > 0.01 else Vector2(0, -1)
	var side := Vector2(-fd.y, fd.x)
	var s := 1.25 * k
	var tri := PackedVector2Array([p + fd * 9.0 * s, p - fd * 6.0 * s + side * 6.5 * s, p - fd * 3.0 * s, p - fd * 6.0 * s - side * 6.5 * s])
	var tri_o := PackedVector2Array([p + fd * 11.5 * s, p - fd * 7.8 * s + side * 8.3 * s, p - fd * 4.2 * s, p - fd * 7.8 * s - side * 8.3 * s])
	draw_circle(p, 13.0 * k + sin(_t * 2.5) * 1.5 * k, Color(1, 1, 1, 0.10))
	draw_colored_polygon(tri_o, Color(0, 0, 0, 0.7))
	draw_colored_polygon(tri, Color(1, 0.98, 0.92))

func _draw_compass(k: float, f_bold: Font) -> void:
	var c := Vector2(_frame.end.x - 34.0 * k, _frame.position.y + 38.0 * k)
	draw_circle(c, 20.0 * k, Color(0.03, 0.035, 0.045, 0.72))
	draw_arc(c, 20.0 * k, 0.0, TAU, 32, GOLD * Color(1, 1, 1, 0.7), 1.2 * k, true)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -15) * k, c + Vector2(4, 0) * k, c + Vector2(-4, 0) * k]), VERMILION)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, 15) * k, c + Vector2(4, 0) * k, c + Vector2(-4, 0) * k]), PARCHMENT * Color(1, 1, 1, 0.7))
	_ctxt(f_bold, c + Vector2(0, -27.0 * k), "N", int(11.0 * k), GOLD, 3)

func _draw_scale(k: float, f_semi: Font) -> void:
	# a scale bar of a round length about a sixth of the frame
	var mpp := _span() / _frame.size.x
	var target := _frame.size.x / 6.0 * mpp
	var nice := 50.0
	for v in [50.0, 100.0, 200.0, 250.0, 500.0]:
		if v <= target: nice = v
	var L := nice / mpp
	var a := Vector2(_frame.position.x + 18.0 * k, _frame.end.y - 18.0 * k)
	draw_rect(Rect2(a - Vector2(6, 18) * k, Vector2(L + 12.0 * k, 26.0 * k)), Color(0.03, 0.035, 0.045, 0.6))
	draw_line(a, a + Vector2(L, 0), PARCHMENT, 2.0 * k)
	draw_line(a + Vector2(0, -4 * k), a + Vector2(0, 2 * k), PARCHMENT, 2.0 * k)
	draw_line(a + Vector2(L, -4 * k), a + Vector2(L, 2 * k), PARCHMENT, 2.0 * k)
	_txt(f_semi, a + Vector2(2.0 * k, -6.0 * k), "%d m" % int(nice), int(11.0 * k), PARCHMENT, 3)

func _draw_buttons(k: float, f_bold: Font) -> void:
	var r := 17.0 * k
	var x := _frame.end.x - 34.0 * k
	var y := _frame.end.y - 34.0 * k
	_zoom_out_rect = Rect2(Vector2(x - r, y - r), Vector2(r, r) * 2.0)
	_zoom_in_rect = Rect2(Vector2(x - r, y - r - 2.4 * r), Vector2(r, r) * 2.0)
	for pair in [[_zoom_in_rect, "+"], [_zoom_out_rect, "−"]]:
		var rc: Rect2 = pair[0]
		draw_circle(rc.get_center(), r, Color(0.03, 0.035, 0.045, 0.78))
		draw_arc(rc.get_center(), r, 0.0, TAU, 28, GOLD * Color(1, 1, 1, 0.7), 1.2 * k, true)
		_ctxt(f_bold, rc.get_center() + Vector2(0, -1.0 * k), String(pair[1]), int(18.0 * k), PARCHMENT)
	# close
	var cr := 18.0 * k
	var cc := Vector2(_frame.end.x + 7.5 * k, _frame.position.y - 30.0 * k)
	_close_rect = Rect2(cc - Vector2(cr, cr), Vector2(cr, cr) * 2.0)
	draw_circle(cc, cr, Color(0.03, 0.035, 0.045, 0.85))
	draw_arc(cc, cr, 0.0, TAU, 28, GOLD * Color(1, 1, 1, 0.8), 1.2 * k, true)
	var q := 6.0 * k
	draw_line(cc + Vector2(-q, -q), cc + Vector2(q, q), PARCHMENT, 2.0 * k)
	draw_line(cc + Vector2(q, -q), cc + Vector2(-q, q), PARCHMENT, 2.0 * k)

func _draw_selection(k: float, f_title: Font, f_semi: Font, f_bold: Font) -> void:
	_travel_rect = Rect2()
	if _selected == "": return
	var zs := _zones()
	if not zs.has(_selected): return
	var p := _to_screen(Vector2(float(zs[_selected]["x"]), float(zs[_selected]["z"])))
	var w := 230.0 * k
	var h := 92.0 * k
	var box := Rect2(p + Vector2(-w * 0.5, 18.0 * k), Vector2(w, h))
	# keep the card on the map
	box.position.x = clampf(box.position.x, _frame.position.x + 6.0 * k, _frame.end.x - w - 6.0 * k)
	if box.end.y > _frame.end.y - 6.0 * k: box.position.y = p.y - 18.0 * k - h - 26.0 * k
	draw_rect(box.grow(2.0 * k), Color(0, 0, 0, 0.5))
	draw_rect(box, Color(0.03, 0.035, 0.045, 0.92))
	draw_rect(box, GOLD * Color(1, 1, 1, 0.6), false, 1.0 * k)
	var title := String(Game.ZONE_TITLE.get(_selected, _selected))
	_txt(f_title, box.position + Vector2(12, 24) * k, title, int(16.0 * k), PARCHMENT, 0)
	_txt(f_semi, box.position + Vector2(12, 43) * k, Game._zone_hint(_selected).capitalize(), int(11.5 * k), MUTED, 0)
	var visited := Game.visited_zones.has(_selected)
	var here := Game.zone == _selected
	var dist := -1.0
	if world != null and world.player != null:
		var pp: Vector3 = world.player.global_position
		dist = Vector2(pp.x, pp.z).distance_to(Vector2(float(zs[_selected]["x"]), float(zs[_selected]["z"])))
	var info := ""
	if dist >= 0.0: info = ("%d m away" % int(dist)) if dist < 1000.0 else ("%.1f km away" % (dist / 1000.0))
	if not visited:
		_txt(f_semi, box.position + Vector2(12, 74) * k, "Undiscovered  ·  " + info, int(11.5 * k), MUTED, 0)
	elif here:
		_txt(f_semi, box.position + Vector2(12, 74) * k, "You are here", int(11.5 * k), GOLD, 0)
	else:
		_txt(f_semi, box.position + Vector2(12, 74) * k, info, int(11.5 * k), MUTED, 0)
		var br := Rect2(box.end - Vector2(98, 34) * k, Vector2(88, 26) * k)
		_travel_rect = br
		draw_rect(br, VERMILION * Color(1, 1, 1, 0.9))
		draw_rect(br, GOLD, false, 1.0 * k)
		_ctxt(f_bold, br.get_center(), "TRAVEL", int(11.5 * k), PARCHMENT)

func _draw_legend(k: float, f_bold: Font, f_semi: Font, sz: Vector2) -> void:
	if sz.x <= sz.y * 1.25: return
	var x := _frame.end.x + 34.0 * k
	var y := _frame.position.y + 6.0 * k
	var fs := int(12.0 * k)
	_txt(f_bold, Vector2(x, y + 12.0 * k), "LEGEND", int(12.0 * k), GOLD, 3)
	y += 30.0 * k
	var rows := [
		["player", "You"], ["horse", "Your horse"], ["objective", "Objective"],
		["visited", "Province (fast travel)"], ["unknown", "Undiscovered province"],
		["lantern", "Checkpoint — rest here"], ["torii", "Shrine gate"], ["castle", "Castle keep"],
		["cave", "Cave"], ["waterfall", "Waterfall"], ["cedar", "Sacred cedar"],
	]
	for r in rows:
		var ic := Vector2(x + 10.0 * k, y)
		match String(r[0]):
			"player":
				draw_colored_polygon(PackedVector2Array([ic + Vector2(0, -8) * k, ic + Vector2(6, 6) * k, ic + Vector2(0, 3) * k, ic + Vector2(-6, 6) * k]), Color(1, 0.98, 0.92))
			"horse":
				draw_circle(ic, 5.0 * k, HORSE_COL)
			"objective":
				draw_colored_polygon(PackedVector2Array([ic + Vector2(0, -6) * k, ic + Vector2(6, 0) * k, ic + Vector2(0, 6) * k, ic + Vector2(-6, 0) * k]), GOLD)
			"visited":
				draw_circle(ic, 8.0 * k, Color(0.12, 0.09, 0.06, 0.95))
				draw_arc(ic, 8.0 * k, 0.0, TAU, 24, GOLD, 1.2 * k, true)
				_icon_torii(ic, 4.0 * k, GOLD)
			"unknown":
				draw_circle(ic, 6.5 * k, Color(0.16, 0.15, 0.14, 0.9))
				_ctxt(f_semi, ic, "?", int(10.0 * k), MUTED)
			"lantern":
				draw_circle(ic, 4.0 * k, Color(1.0, 0.72, 0.32))
			"torii": _icon_torii(ic, 6.0 * k, VERMILION)
			"castle": _icon_castle(ic, k)
			"cave": _icon_cave(ic, k)
			"waterfall": _icon_waterfall(ic, k)
			"cedar": _icon_cedar(ic, k)
		_txt(f_semi, Vector2(x + 28.0 * k, y + 4.5 * k), String(r[1]), fs, PARCHMENT, 0)
		y += 25.0 * k
	y += 14.0 * k
	_txt(f_bold, Vector2(x, y), "CONTROLS", int(12.0 * k), GOLD, 3)
	y += 22.0 * k
	var tips := ["Drag / WASD — pan", "Wheel / Q E — zoom", "C — centre on you",
		"Click a province — details", "Travel from visited ones", "%s / Esc — close" % Game.bind_label("map")]
	if OS.has_feature("mobile"):
		tips = ["Drag — pan", "Pinch — zoom", "Tap a province — details", "Travel from visited ones"]
	for t in tips:
		_txt(f_semi, Vector2(x, y), t, int(11.5 * k), MUTED, 0)
		y += 19.0 * k
	# the objective, in words
	y += 12.0 * k
	_txt(f_bold, Vector2(x, y), "CURRENT OBJECTIVE", int(12.0 * k), GOLD, 3)
	y += 22.0 * k
	draw_multiline_string(f_semi, Vector2(x, y), Quests.current_objective_text(), HORIZONTAL_ALIGNMENT_LEFT,
		sz.x - x - 24.0 * k, int(12.0 * k), 3, PARCHMENT)
