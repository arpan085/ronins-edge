class_name SkillsMenu
extends Control
## v0.16 techniques screen (U, or Techniques in the pause menu). Three skill
## paths side by side, each a short trunk that forks; mastery points buy them.
## Opens over a paused game like the world map. Keyboard/pad: arrows or WASD
## move, Enter / E / Space learns, U or Esc closes. Mouse/touch: tap a
## technique to select it, tap it again (or the Learn button) to learn it.

const GOLD := Color(0.89, 0.75, 0.46)
const INK := Color(0.02, 0.025, 0.035, 0.90)
const PANEL := Color(0.035, 0.04, 0.05, 0.92)
const VERMILION := Color(0.84, 0.20, 0.15)
const PARCHMENT := Color(0.96, 0.93, 0.87)
const MUTED := Color(0.62, 0.60, 0.57)
const DIM := Color(0.36, 0.35, 0.34)
const SPIRIT := Color(0.47, 0.82, 1.0)
const PATH_COL := {"bushido": Color(0.92, 0.36, 0.26), "shinobi": Color(0.62, 0.66, 0.78), "spirit": Color(0.47, 0.82, 1.0)}

var hud: Node = null
var f_reg: Font
var f_semi: Font
var f_bold: Font
var f_title: Font
var f_kanji: Font
var selected := "b_deflect"
var _pos := {}            ## id -> node centre (screen)
var _radius := 30.0
var _close_rect := Rect2()
var _learn_rect := Rect2()
var _t := 0.0
var _opened_at := 0
var _flash := {}          ## id -> seconds left of the learned flash
var _msg := ""
var _msg_t := 0.0
var _k := 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	f_reg = _font("res://assets/fonts/UI-Regular.ttf")
	f_semi = _font("res://assets/fonts/UI-SemiBold.ttf")
	f_bold = _font("res://assets/fonts/UI-ExtraBold.ttf")
	f_title = _font("res://assets/fonts/Title.ttf")
	f_kanji = _font("res://assets/fonts/Kanji.ttf")

func _font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f = load(path)
		if f is Font: return f
	return ThemeDB.fallback_font

func is_open() -> bool:
	return visible

func open() -> void:
	if visible: return
	visible = true
	_opened_at = Engine.get_process_frames()
	# start on the first technique you could learn, else the first one
	selected = "b_deflect"
	for p in Skills.PATHS:
		for id in Skills.ids_in(p):
			if Skills.state_of(id) == "available":
				selected = id
				break
		if Skills.state_of(selected) == "available": break
	_msg = ""
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.play_sfx("map_open", null, 1.15, -4.0)
	queue_redraw()

func close() -> void:
	if not visible: return
	visible = false
	get_tree().paused = false
	if not OS.has_feature("mobile") and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Audio.play_sfx("map_open", null, 0.8, -8.0)

## Learn the selected technique (or `id`). Returns true on success.
func learn(id := "") -> bool:
	var tid := id if id != "" else selected
	var st := Skills.state_of(tid)
	if st == "owned":
		_say("Already learned")
		return false
	if st == "locked":
		var req := String(Skills.TREE[tid]["req"])
		_say("Learn %s first" % String(Skills.TREE[req]["name"]))
		Audio.play_ui("back")
		return false
	if st == "need_points":
		_say("Needs %d mastery points — you have %d" % [int(Skills.TREE[tid]["cost"]), Game.mastery_points])
		Audio.play_ui("back")
		return false
	if Skills.unlock(tid):
		_flash[tid] = 1.0
		_say("%s learned" % String(Skills.TREE[tid]["name"]))
		Game.save_game()
		return true
	return false

func _say(s: String) -> void:
	_msg = s
	_msg_t = 2.6

func _process(delta: float) -> void:
	if not visible: return
	_t += delta
	_msg_t = maxf(0.0, _msg_t - delta)
	for id in _flash.keys():
		_flash[id] = float(_flash[id]) - delta
		if float(_flash[id]) <= 0.0: _flash.erase(id)
	if Engine.get_process_frames() > _opened_at + 1:
		if Input.is_action_just_pressed("skills") or Input.is_action_just_pressed("pause"):
			close()
			return
		if Input.is_action_just_pressed("ui_cancel"):
			close()
			return
	queue_redraw()

func _input(ev: InputEvent) -> void:
	if not visible or Engine.get_process_frames() <= _opened_at + 1: return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k := (ev as InputEventKey).physical_keycode
		var dir := Vector2.ZERO
		match k:
			KEY_LEFT, KEY_A: dir = Vector2.LEFT
			KEY_RIGHT, KEY_D: dir = Vector2.RIGHT
			KEY_UP, KEY_W: dir = Vector2.UP
			KEY_DOWN, KEY_S: dir = Vector2.DOWN
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E:
				learn()
				get_viewport().set_input_as_handled()
				return
		if dir != Vector2.ZERO:
			move_selection(dir)
			get_viewport().set_input_as_handled()

## Select the nearest technique in direction dir (screen space).
func move_selection(dir: Vector2) -> void:
	if _pos.is_empty(): _layout(get_viewport_rect().size)
	var here: Vector2 = _pos.get(selected, Vector2.ZERO)
	var best := ""
	var bs := 1e9
	for id in _pos.keys():
		if id == selected: continue
		var to: Vector2 = _pos[id] - here
		if to.length() < 1.0: continue
		var along := to.normalized().dot(dir)
		if along < 0.35: continue
		var score := to.length() * (2.0 - along)
		if score < bs:
			bs = score
			best = id
	if best != "":
		selected = best
		Audio.play_ui("select")

func _gui_input(ev: InputEvent) -> void:
	if not visible: return
	var p := Vector2.INF
	var click := false
	if ev is InputEventMouseMotion:
		var hit := _node_at((ev as InputEventMouseMotion).position)
		if hit != "" and hit != selected:
			selected = hit
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		p = (ev as InputEventMouseButton).position
		click = true
	elif ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
		p = (ev as InputEventScreenTouch).position
		click = true
	if not click: return
	accept_event()
	if _close_rect.has_point(p):
		close()
		return
	if _learn_rect.has_point(p):
		learn()
		return
	var id := _node_at(p)
	if id == "": return
	if id == selected: learn()
	else:
		selected = id
		Audio.play_ui("select")

func _node_at(p: Vector2) -> String:
	for id in _pos.keys():
		if (p - Vector2(_pos[id])).length() <= _radius * 1.25: return id
	return ""

# ---------------------------------------------------------------- layout / draw
func _frame(sz: Vector2) -> Rect2:
	var w := minf(1120.0 * _k, sz.x - 40.0 * _k)
	var h := minf(640.0 * _k, sz.y - 30.0 * _k)
	return Rect2((sz - Vector2(w, h)) * 0.5, Vector2(w, h))

func _layout(sz: Vector2) -> void:
	_k = clampf(sz.y / 720.0, 0.6, 2.2)
	var fr := _frame(sz)
	_radius = 29.0 * _k
	var colw := fr.size.x / 3.0
	var y0 := fr.position.y + 194.0 * _k
	var dy := 100.0 * _k
	var fork := minf(76.0 * _k, colw * 0.26)
	for i in Skills.PATHS.size():
		var cx := fr.position.x + colw * (float(i) + 0.5)
		for id in Skills.ids_in(String(Skills.PATHS[i])):
			var slot := int(Skills.TREE[id]["slot"])
			var p := Vector2(cx, y0)
			match slot:
				1: p = Vector2(cx, y0 + dy)
				2: p = Vector2(cx - fork, y0 + dy * 2.0)
				3: p = Vector2(cx + fork, y0 + dy * 2.0)
			_pos[id] = p

func _txt(font: Font, pos: Vector2, s: String, size: int, col: Color, outline := 0, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	if outline > 0: draw_string_outline(font, pos, s, align, width, size, outline, Color(0, 0, 0, 0.6 * col.a))
	draw_string(font, pos, s, align, width, size, col)

func _ctxt(font: Font, center: Vector2, s: String, size: int, col: Color, outline := 0) -> void:
	var ts := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var asc := font.get_ascent(size)
	var desc := font.get_descent(size)
	_txt(font, Vector2(center.x - ts.x * 0.5, center.y + (asc - desc) * 0.5), s, size, col, outline)

func _spaced(font: Font, cx: float, y: float, s: String, size: int, col: Color, spacing: float) -> void:
	var total := 0.0
	var ws := []
	for ch in s:
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		ws.append(w)
		total += w + spacing
	total -= spacing
	var x := cx - total * 0.5
	var i := 0
	for ch in s:
		_txt(font, Vector2(x, y), ch, size, col)
		x += float(ws[i]) + spacing
		i += 1

func _wrap(font: Font, s: String, size: int, width: float) -> Array:
	var lines: Array = []
	var cur := ""
	for word in s.split(" "):
		var t := word if cur == "" else cur + " " + word
		if font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width and cur != "":
			lines.append(cur)
			cur = word
		else:
			cur = t
	if cur != "": lines.append(cur)
	return lines

func _box(r: Rect2, col: Color, border: Color, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = border
	sb.set_border_width_all(maxi(1, int(round(1.2 * _k))))
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	draw_style_box(sb, r)

func _draw() -> void:
	if not visible: return
	var sz := get_viewport_rect().size
	_layout(sz)
	var k := _k
	draw_rect(Rect2(Vector2.ZERO, sz), INK, true)
	var fr := _frame(sz)
	_box(fr, PANEL, GOLD * Color(1, 1, 1, 0.45), 10.0 * k)
	# title
	var ty := fr.position.y + 46.0 * k
	_ctxt(f_kanji, Vector2(fr.position.x + 52.0 * k, ty - 6.0 * k), "技", int(38.0 * k), VERMILION)
	_txt(f_title, Vector2(fr.position.x + 86.0 * k, ty + 6.0 * k), "TECHNIQUES", int(26.0 * k), PARCHMENT, 3)
	var mp := "MASTERY POINTS  %d" % Game.mastery_points
	var mw := f_bold.get_string_size(mp, HORIZONTAL_ALIGNMENT_LEFT, -1, int(15.0 * k)).x
	_txt(f_bold, Vector2(fr.end.x - 64.0 * k - mw, ty + 2.0 * k), mp, int(15.0 * k), GOLD, 3)
	# close button
	var cr := 16.0 * k
	var cc := Vector2(fr.end.x - 32.0 * k, fr.position.y + 36.0 * k)
	_close_rect = Rect2(cc - Vector2(cr, cr) * 1.3, Vector2(cr, cr) * 2.6)
	draw_circle(cc, cr, Color(0.03, 0.035, 0.045, 0.9))
	draw_arc(cc, cr, 0.0, TAU, 28, GOLD * Color(1, 1, 1, 0.8), 1.2 * k, true)
	var q := 5.5 * k
	draw_line(cc + Vector2(-q, -q), cc + Vector2(q, q), PARCHMENT, 2.0 * k)
	draw_line(cc + Vector2(q, -q), cc + Vector2(-q, q), PARCHMENT, 2.0 * k)
	draw_line(Vector2(fr.position.x + 30.0 * k, ty + 22.0 * k), Vector2(fr.end.x - 30.0 * k, ty + 22.0 * k), GOLD * Color(1, 1, 1, 0.3), 1.0 * k)
	# columns
	var colw := fr.size.x / 3.0
	for i in Skills.PATHS.size():
		var path := String(Skills.PATHS[i])
		var info: Dictionary = Skills.PATH_INFO[path]
		var cx := fr.position.x + colw * (float(i) + 0.5)
		var pc: Color = PATH_COL[path]
		if i > 0:
			var lx := fr.position.x + colw * float(i)
			draw_line(Vector2(lx, ty + 40.0 * k), Vector2(lx, fr.position.y + 446.0 * k), GOLD * Color(1, 1, 1, 0.14), 1.0 * k)
		_ctxt(f_kanji, Vector2(cx, ty + 52.0 * k), String(info["kanji"]), int(24.0 * k), pc)
		_spaced(f_bold, cx, ty + 86.0 * k, String(info["name"]).to_upper(), int(12.0 * k), PARCHMENT, 2.0 * k)
		_ctxt(f_reg, Vector2(cx, ty + 100.0 * k), String(info["blurb"]), int(12.0 * k), MUTED)
		var ids := Skills.ids_in(path)
		# links: trunk then the fork
		for id in ids:
			var req := String(Skills.TREE[id]["req"])
			if req == "": continue
			var a: Vector2 = _pos[req]
			var b: Vector2 = _pos[id]
			var lit := Skills.has(id)
			var avail := Skills.has(req)
			var col := pc if lit else (GOLD * Color(1, 1, 1, 0.55) if avail else DIM * Color(1, 1, 1, 0.6))
			var dirv := (b - a).normalized()
			draw_line(a + dirv * _radius, b - dirv * _radius, col, (2.6 if lit else 1.6) * k, true)
		for id in ids: _draw_node(id, pc)
	_draw_details(fr)

func _draw_node(id: String, pc: Color) -> void:
	var k := _k
	var p: Vector2 = _pos[id]
	var st := Skills.state_of(id)
	var r := _radius
	var sel := id == selected
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	if sel: draw_circle(p, r + 9.0 * k, GOLD * Color(1, 1, 1, 0.16 + 0.10 * pulse))
	var fill := Color(0.05, 0.055, 0.065, 0.95)
	var ring := DIM
	var kcol := DIM
	match st:
		"owned":
			fill = pc.darkened(0.55)
			ring = pc
			kcol = PARCHMENT
		"available":
			ring = GOLD.lerp(PARCHMENT, 0.3 * pulse)
			kcol = GOLD
		"need_points":
			ring = MUTED
			kcol = MUTED
	draw_circle(p, r, fill)
	draw_arc(p, r, 0.0, TAU, 48, ring, (2.6 if st == "owned" or sel else 1.6) * k, true)
	if st == "owned": draw_arc(p, r - 4.0 * k, 0.0, TAU, 48, pc * Color(1, 1, 1, 0.5), 1.0 * k, true)
	var kan := String(Skills.TREE[id]["kanji"])
	_ctxt(f_kanji, p + Vector2(0, -1.0 * k), kan, int((20.0 if kan.length() <= 2 else 15.0) * k), kcol)
	if _flash.has(id):
		var f := float(_flash[id])
		draw_arc(p, r + (1.0 - f) * 26.0 * k, 0.0, TAU, 48, GOLD * Color(1, 1, 1, f), 3.0 * k, true)
	# name + cost under the node, on a backing so the links never run through it
	var nm := String(Skills.TREE[id]["name"])
	var nw := maxf(f_semi.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, int(11.5 * k)).x, 44.0 * k) + 10.0 * k
	draw_rect(Rect2(p + Vector2(-nw * 0.5, r + 5.0 * k), Vector2(nw, 26.0 * k)), Color(0.034, 0.039, 0.049, 0.97), true)
	_ctxt(f_semi, p + Vector2(0, r + 13.0 * k), nm, int(11.5 * k), PARCHMENT if st != "locked" else MUTED, 3)
	if st != "owned":
		var cost := int(Skills.TREE[id]["cost"])
		for c in cost:
			var cp := p + Vector2((float(c) - float(cost - 1) * 0.5) * 9.0 * k, r + 26.0 * k)
			var dc := GOLD if st == "available" else DIM
			draw_colored_polygon(PackedVector2Array([cp + Vector2(0, -3.2 * k), cp + Vector2(3.2 * k, 0), cp + Vector2(0, 3.2 * k), cp + Vector2(-3.2 * k, 0)]), dc)
	else:
		_ctxt(f_bold, p + Vector2(0, r + 26.0 * k), "LEARNED", int(8.5 * k), pc, 2)

func _draw_details(fr: Rect2) -> void:
	var k := _k
	var id := selected
	if not Skills.TREE.has(id): return
	var d: Dictionary = Skills.TREE[id]
	var st := Skills.state_of(id)
	var pc: Color = PATH_COL[String(d["path"])]
	var r := Rect2(fr.position.x + 30.0 * k, fr.end.y - 170.0 * k, fr.size.x - 60.0 * k, 140.0 * k)
	_box(r, Color(0.02, 0.025, 0.03, 0.85), pc * Color(1, 1, 1, 0.5), 8.0 * k)
	_ctxt(f_kanji, r.position + Vector2(54.0 * k, 52.0 * k), String(d["kanji"]), int(34.0 * k), pc)
	var x := r.position.x + 110.0 * k
	_txt(f_title, Vector2(x, r.position.y + 36.0 * k), String(d["name"]).to_upper(), int(21.0 * k), PARCHMENT, 3)
	var path_nm := String(Skills.PATH_INFO[String(d["path"])]["name"])
	_txt(f_bold, Vector2(x, r.position.y + 56.0 * k), "%s  ·  %d POINT%s" % [path_nm.to_upper(), int(d["cost"]), "" if int(d["cost"]) == 1 else "S"],
		int(10.5 * k), GOLD * Color(1, 1, 1, 0.9), 2)
	var ly := r.position.y + 80.0 * k
	for line in _wrap(f_reg, String(d["desc"]), int(14.0 * k), r.size.x - 360.0 * k):
		_txt(f_reg, Vector2(x, ly), String(line), int(14.0 * k), PARCHMENT)
		ly += 19.0 * k
	# status / action
	var bw := 190.0 * k
	var bh := 40.0 * k
	_learn_rect = Rect2(Vector2(r.end.x - bw - 22.0 * k, r.position.y + 30.0 * k), Vector2(bw, bh))
	var label := ""
	var sub := ""
	var col := MUTED
	match st:
		"owned":
			label = "LEARNED"; col = pc
			_learn_rect = Rect2()
		"available":
			label = "LEARN"; col = GOLD
			sub = "Enter / tap again"
		"need_points":
			label = "NEED %d POINTS" % int(d["cost"]); col = MUTED
			sub = "Earn mastery: quests, kills, shrines, caches"
		"locked":
			label = "LOCKED"; col = DIM
			sub = "Requires %s" % String(Skills.TREE[String(d["req"])]["name"])
	var br := Rect2(Vector2(r.end.x - bw - 22.0 * k, r.position.y + 30.0 * k), Vector2(bw, bh))
	_box(br, Color(0.05, 0.05, 0.06, 0.9) if st != "available" else GOLD * Color(0.35, 0.3, 0.2, 0.95), col, 6.0 * k)
	_ctxt(f_bold, br.get_center(), label, int(14.0 * k), PARCHMENT if st == "available" else col)
	if sub != "":
		_ctxt(f_semi, Vector2(br.get_center().x, br.end.y + 16.0 * k), sub, int(10.5 * k), MUTED)
	# feedback line + key hints
	var hint := "Arrows / WASD select   ·   Enter learn   ·   %s / Esc close" % Game.bind_label("skills")
	if _msg_t > 0.0:
		_ctxt(f_semi, Vector2(fr.get_center().x, fr.end.y - 186.0 * k), _msg, int(14.0 * k), GOLD * Color(1, 1, 1, clampf(_msg_t, 0.0, 1.0)), 3)
	_ctxt(f_semi, Vector2(fr.get_center().x, fr.end.y - 14.0 * k), hint, int(11.0 * k), MUTED)
