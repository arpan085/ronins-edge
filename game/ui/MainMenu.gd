extends Control
## v0.23 title screen: a living ink painting at dawn (shaders/title_bg.gdshader),
## Kaito and his horse on the ridge, drifting petals, a sword-stroke title reveal,
## "press any key", then a flat, keyboard-friendly menu. Returning from the game
## skips the reveal.

const GOLD := Color(0.78, 0.66, 0.36)
const PARCHMENT := Color(0.92, 0.88, 0.78)
const VERMILION := Color(0.76, 0.17, 0.12)
const VERSION := "v0.23"

var _t := 0.0
var _rt := -1.0                 ## reveal clock (-1: reveal finished)
var _state := "reveal"          ## reveal -> press -> menu
var _menu_t := 0.0
var _par := Vector2.ZERO
var _cues := {}
var _bg: ColorRect
var _mat: ShaderMaterial
var _rider: TextureRect
var _petals: CPUParticles2D
var _title: Control
var _slash: ColorRect
var _clip: Control
var _name: Label
var _edge: TextureRect
var _seal: PanelContainer
var _seal_lbl: Label
var _tag: Label
var _press: Label
var _menu: VBoxContainer
var _items: Array = []          ## [{b, line, mark, w, row, text}]
var _info: Label
var _ver: Label
var _flash: ColorRect
var _black: ColorRect
var _black_want := 0.0
var _confirm_t := 0.0
var _leaving := false
var f_title: Font
var f_semi: Font
var f_reg: Font
var f_kanji: Font

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	f_title = _font("res://assets/fonts/Title.ttf")
	f_semi = _font("res://assets/fonts/UI-SemiBold.ttf")
	f_reg = _font("res://assets/fonts/UI-Regular.ttf")
	f_kanji = _font("res://assets/fonts/Kanji.ttf")
	_bg = ColorRect.new()
	_bg.color = Color(0.05, 0.055, 0.07)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://shaders/title_bg.gdshader"):
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/title_bg.gdshader")
		_bg.material = _mat
	add_child(_bg)
	_rider = TextureRect.new()
	_rider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rider.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists("res://assets/ui/title_rider.png"):
		_rider.texture = load("res://assets/ui/title_rider.png")
	add_child(_rider)
	_petals = _make_petals()
	add_child(_petals)
	_build_title()
	_press = _label(f_semi, 15, PARCHMENT, 4)
	_press.text = _spaced("PRESS ANY KEY")
	_press.modulate.a = 0.0
	add_child(_press)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 4)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu)
	_build_menu()
	_info = _label(f_reg, 12, Color(0.80, 0.78, 0.74, 0.75), 3)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_info)
	_ver = _label(f_semi, 12, Color(0.85, 0.80, 0.70, 0.6), 3)
	_ver.text = VERSION
	_ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_ver)
	_flash = ColorRect.new()
	_flash.color = Color(1, 0.98, 0.94, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 1)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_refresh_info()
	get_viewport().size_changed.connect(_layout)
	visibility_changed.connect(_on_visible)
	_layout()
	Audio.play_music("menu")
	if DisplayServer.get_name() == "headless": _finish_reveal(true)
	else: _rt = 0.0

# ------------------------------------------------------------------ build
func _font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f = load(path)
		if f is Font: return f
	return ThemeDB.fallback_font

func _label(font: Font, size: int, col: Color, outline := 0) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func _spaced(s: String) -> String:
	var out := ""
	for i in s.length():
		out += s[i]
		if i < s.length() - 1: out += " "
	return out

func _make_petals() -> CPUParticles2D:
	var img := Image.create(24, 14, false, Image.FORMAT_RGBA8)
	for y in 14:
		for x in 24:
			var u := (x - 11.5) / 11.5
			var v := (y - 6.5) / 6.5
			var d := u * u + v * v * (1.0 + 0.6 * maxf(0.0, -u))
			var a := clampf((1.0 - d) * 3.0, 0.0, 1.0)
			var tint := lerpf(1.0, 0.86, clampf(u * 0.5 + 0.5, 0.0, 1.0))
			img.set_pixel(x, y, Color(1.0, 0.86 * tint + 0.1, 0.9 * tint + 0.05, a))
	var p := CPUParticles2D.new()
	p.texture = ImageTexture.create_from_image(img)
	p.amount = 34
	p.lifetime = 16.0
	p.preprocess = 16.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2(-1.0, 0.35)
	p.spread = 18.0
	p.initial_velocity_min = 28.0
	p.initial_velocity_max = 70.0
	p.gravity = Vector2(-6.0, 9.0)
	p.angular_velocity_min = -80.0
	p.angular_velocity_max = 80.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.95
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.08, 0.85, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 0.92, 0.94, 0.85), Color(1, 0.9, 0.92, 0.75), Color(1, 1, 1, 0)])
	p.color_ramp = g
	return p

func _build_title() -> void:
	_title = Control.new()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_slash = ColorRect.new()
	_slash.color = Color(1.0, 0.97, 0.9, 1.0)
	_slash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_child(_slash)
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_child(_clip)
	_name = _label(f_title, 84, PARCHMENT, 10)
	_name.text = "RONIN'S  EDGE"
	_clip.add_child(_name)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	g.colors = PackedColorArray([Color(1, 0.95, 0.85, 0.0), Color(1, 0.95, 0.85, 0.55), Color(1, 1, 1, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 8
	_edge = TextureRect.new()
	_edge.texture = gt
	_edge.stretch_mode = TextureRect.STRETCH_SCALE
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_child(_edge)
	_seal = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = VERMILION
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	_seal.add_theme_stylebox_override("panel", sb)
	_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seal_lbl = _label(f_kanji, 22, Color(1, 0.97, 0.92))
	_seal_lbl.text = "浪人\nの刃"
	_seal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seal.add_child(_seal_lbl)
	_title.add_child(_seal)
	_tag = _label(f_semi, 15, GOLD, 4)
	_tag.text = _spaced("A TALE OF KIYOMIZU PROVINCE")
	_title.add_child(_tag)

func _build_menu() -> void:
	for c in _menu.get_children(): c.queue_free()
	_items.clear()
	if Game.has_save(): _add("Continue", _continue)
	_add("New Game", _new_game)
	_add("Settings", _settings)
	_add("Quit", func(): get_tree().quit())

func _add(text: String, cb: Callable) -> Button:
	var row := Control.new()
	row.custom_minimum_size = Vector2(360, 44)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.position = Vector2(22, 0)
	b.size = Vector2(320, 40)
	b.add_theme_font_override("font", f_title)
	b.add_theme_font_size_override("font_size", 24)
	for k in ["font_color", "font_pressed_color"]:
		b.add_theme_color_override(k, Color(PARCHMENT, 0.72))
	for k in ["font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, Color(1.0, 0.95, 0.84))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	b.add_theme_constant_override("outline_size", 6)
	var empty := StyleBoxEmpty.new()
	for k in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(k, empty)
	var line := ColorRect.new()
	line.color = VERMILION
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.position = Vector2(22, 38)
	line.size = Vector2(0, 2)
	var mark := _label(f_title, 18, VERMILION, 4)
	mark.text = "\u2014"
	mark.position = Vector2(0, 8)
	mark.modulate.a = 0.0
	row.add_child(line)
	row.add_child(mark)
	row.add_child(b)
	var it := {"b": b, "line": line, "mark": mark, "w": 0.0, "row": row, "text": text}
	b.mouse_entered.connect(func(): if _state == "menu": b.grab_focus())
	b.focus_entered.connect(func(): if _state == "menu" and _menu_t > 0.3: Audio.play_ui("select"))
	b.pressed.connect(func():
		if _state != "menu" or _leaving: return
		Audio.play_ui("confirm")
		cb.call())
	_menu.add_child(row)
	_items.append(it)
	return b

# ------------------------------------------------------------------ layout
func _layout() -> void:
	var sz := get_viewport_rect().size
	if sz.x < 10.0: return
	var k := sz.y / 720.0
	_bg.position = Vector2.ZERO
	_bg.size = sz
	if _mat != null: _mat.set_shader_parameter("res", sz)
	_flash.size = sz
	_black.size = sz
	var rh := sz.y * 0.30
	_rider.size = Vector2(rh * 1.25, rh)
	_rider.position = Vector2(sz.x * 0.835 - _rider.size.x * 0.5, sz.y * 0.735 - rh * 0.985)
	_petals.position = Vector2(sz.x * 0.72, -40.0)
	_petals.emission_rect_extents = Vector2(sz.x * 0.45, 30.0)
	var lx := sz.x * 0.075
	_title.position = Vector2.ZERO
	_title.size = sz
	_name.add_theme_font_size_override("font_size", int(80.0 * k))
	var tw := _name.get_combined_minimum_size().x
	var th := 104.0 * k
	var ty := sz.y * 0.17
	_clip.position = Vector2(lx, ty)
	_name.position = Vector2.ZERO
	_name.size = Vector2(tw, th)
	_seal_lbl.add_theme_font_size_override("font_size", int(20.0 * k))
	_seal.position = Vector2(lx + tw + 12.0 * k, ty + 16.0 * k)
	_tag.add_theme_font_size_override("font_size", int(14.0 * k))
	_tag.position = Vector2(lx + 4.0 * k, ty + th + 2.0 * k)
	_tag.size = Vector2(sz.x * 0.6, 24.0 * k)
	_slash.position = Vector2(0, ty + th * 0.52)
	_slash.size = Vector2(sz.x, maxf(2.0, 3.0 * k))
	_edge.size = Vector2(60.0 * k, th)
	_press.add_theme_font_size_override("font_size", int(15.0 * k))
	_press.position = Vector2(lx + 4.0 * k, sz.y * 0.56)
	_press.size = Vector2(sz.x * 0.5, 30.0 * k)
	_menu.position = Vector2(lx - 22.0 * k, sz.y * 0.44)
	for it in _items:
		var row: Control = it["row"]
		row.custom_minimum_size = Vector2(380.0 * k, 46.0 * k)
		var b: Button = it["b"]
		b.add_theme_font_size_override("font_size", int(25.0 * k))
		b.size = Vector2(330.0 * k, 42.0 * k)
		(it["line"] as ColorRect).position = Vector2(26.0 * k, 39.0 * k)
		var m: Label = it["mark"]
		m.add_theme_font_size_override("font_size", int(18.0 * k))
		m.position = Vector2(0, 9.0 * k)
	_info.add_theme_font_size_override("font_size", int(12.0 * k))
	_info.position = Vector2(lx, sz.y - 70.0 * k)
	_info.size = Vector2(sz.x * 0.62, 64.0 * k)
	_ver.add_theme_font_size_override("font_size", int(12.0 * k))
	_ver.position = Vector2(sz.x - 220.0 * k, sz.y - 30.0 * k)
	_ver.size = Vector2(200.0 * k, 20.0 * k)
	_apply_title()

func _refresh_info() -> void:
	var q := String(Perf.preset()["name"])
	var last := ""
	if Game.has_save():
		last = "  ·  save found (%s, %d mastery)" % [Game.ZONE_TITLE.get(Game.zone, Game.zone), Game.mastery_points]
	var L := func(a: String) -> String: return Game.bind_label(a)
	_info.text = ("Graphics: %s  ·  %s%s\n" % [q, "touch controls enabled" if (OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()) else "desktop input", last]) \
		+ "WASD move · %s sprint · %s walk · %s jump · %s roll · %s light · %s heavy · %s kick · %s punch · %s guard · %s draw/sheathe · 1-4 weapons · %s call horse · %s mount · %s lock · Esc pause (rebind in Pause > Controls)" % [
		L.call("sprint"), L.call("walk"), L.call("jump"), L.call("dodge"), L.call("attack"), L.call("heavy"), L.call("kick"),
		L.call("punch"), L.call("block"), L.call("sheathe"), L.call("call_horse"), L.call("interact"), L.call("lock_on")]

func _on_visible() -> void:
	if not visible: return
	# back from the game: no reveal, fresh buttons (a save may exist now)
	_leaving = false
	_black_want = 0.0
	_build_menu()
	_refresh_info()
	_layout()
	_finish_reveal(true)

# ------------------------------------------------------------------ reveal
func _cue(name: String, at: float) -> bool:
	if _rt >= at and not _cues.has(name):
		_cues[name] = true
		return true
	return false

func _finish_reveal(to_menu: bool) -> void:
	_rt = -1.0
	_black.color.a = 0.0
	_flash.color.a = 0.0
	if to_menu: _open_menu(true)
	else: _state = "press"
	_apply_title()

func _open_menu(instant := false) -> void:
	_state = "menu"
	_menu_t = 2.0 if instant else 0.0
	if not instant: Audio.play_sfx("whoosh_big", null, 1.3, -14.0)
	if not _items.is_empty(): (_items[0]["b"] as Button).grab_focus()

## the reveal state at the current reveal clock (or fully shown)
func _apply_title() -> void:
	if _name == null: return
	var tt := _rt if _rt >= 0.0 else 99.0
	var a := clampf((tt - 0.4) / 2.2, 0.0, 1.0)
	if _mat != null: _mat.set_shader_parameter("fade", 0.25 + 0.75 * a * a * (3.0 - 2.0 * a))
	_rider.modulate.a = clampf((tt - 0.9) / 1.6, 0.0, 1.0)
	var r := tt - 2.1                ## the title reveal starts with the slash
	var sz := get_viewport_rect().size
	var sl := clampf(r / 0.2, 0.0, 1.0)
	_slash.size.x = sz.x * sl
	_slash.modulate = Color(1, 1, 1, clampf(1.0 - (r - 0.2) / 0.5, 0.0, 1.0) if r >= 0.0 else 0.0)
	var rv := clampf((r - 0.1) / 1.2, 0.0, 1.0)
	rv = 1.0 - pow(1.0 - rv, 3.0)
	var full := _name.size.x
	_clip.size = Vector2(full * rv + 2.0, _name.size.y)
	_edge.position = Vector2(_clip.position.x + full * rv - _edge.size.x * 0.7, _clip.position.y)
	_edge.modulate = Color(1, 1, 1, (1.0 - rv) * 1.4 if rv > 0.0 else 0.0)
	var st := clampf((r - 1.0) / 0.22, 0.0, 1.0)
	_seal.pivot_offset = _seal.size * 0.5
	_seal.scale = Vector2.ONE * lerpf(1.8, 1.0, st)
	_seal.modulate = Color(1, 1, 1, st)
	_tag.modulate = Color(1, 1, 1, clampf((r - 1.4) / 0.8, 0.0, 1.0))

func _process(delta: float) -> void:
	if not visible: return
	_t += delta
	var sz := get_viewport_rect().size
	var mp := get_viewport().get_mouse_position()
	var want := Vector2.ZERO
	if sz.x > 0.0 and mp.x >= 0.0 and mp.y >= 0.0 and mp.x <= sz.x and mp.y <= sz.y:
		want = (mp / sz - Vector2(0.5, 0.5)) * 2.0
	_par = _par.lerp(want, clampf(delta * 1.5, 0.0, 1.0))
	if _mat != null:
		_mat.set_shader_parameter("t", _t)
		_mat.set_shader_parameter("par", _par)
	var rh := sz.y * 0.30
	_rider.position = Vector2(sz.x * (0.835 - _par.x * 0.03) - rh * 1.25 * 0.5, sz.y * 0.735 - rh * 0.985)
	if _rt >= 0.0:
		_rt += delta
		_black.color.a = clampf(1.0 - _rt / 1.6, 0.0, 1.0)
		if _cue("riser", 0.15): Audio.play_sfx("riser", null, 1.0, -10.0)
		if _cue("slash", 2.1):
			Audio.play_sfx("swing_heavy", null, 1.0, -4.0)
			Audio.play_sfx("sword_ring", null, 1.0, -6.0)
			_flash.color.a = 0.45
		if _cue("seal", 3.1): Audio.play_sfx("taiko", null, 0.9, -3.0)
		if _rt > 4.4: _finish_reveal(false)
		_apply_title()
	else:
		_black.color.a = move_toward(_black.color.a, _black_want, delta * 2.2)
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 1.4)
	if _state == "press":
		_press.modulate.a = move_toward(_press.modulate.a, 0.45 + 0.4 * sin(_t * 2.6), delta * 2.0)
	else:
		_press.modulate.a = move_toward(_press.modulate.a, 0.0, delta * 4.0)
	if _state == "menu": _menu_t += delta
	var i := 0
	var k := sz.y / 720.0
	for it in _items:
		var b: Button = it["b"]
		var row: Control = it["row"]
		var appear := clampf((_menu_t - 0.08 * i) / 0.35, 0.0, 1.0) if _state == "menu" else 0.0
		appear = 1.0 - pow(1.0 - appear, 3.0)
		row.modulate.a = appear
		b.position.x = 22.0 * k + (1.0 - appear) * -24.0
		var on := b.has_focus() and _state == "menu"
		var tw: float = b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
		it["w"] = lerpf(float(it["w"]), tw if on else 0.0, clampf(delta * 12.0, 0.0, 1.0))
		(it["line"] as ColorRect).size = Vector2(float(it["w"]), maxf(2.0, 2.0 * k))
		var m: Label = it["mark"]
		m.modulate.a = move_toward(m.modulate.a, 1.0 if on else 0.0, delta * 6.0)
		i += 1
	_info.modulate.a = move_toward(_info.modulate.a, 1.0 if _state == "menu" else 0.0, delta * 2.0)
	if _confirm_t > 0.0:
		_confirm_t -= delta
		if _confirm_t <= 0.0: _set_new_game_text("New Game")

func _input(event: InputEvent) -> void:
	if not visible or _leaving: return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)
	if not pressed: return
	if _state == "reveal":
		_finish_reveal(false)
		get_viewport().set_input_as_handled()
	elif _state == "press":
		Audio.play_ui("confirm")
		_open_menu()
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ actions
func _set_new_game_text(s: String) -> void:
	for it in _items:
		if String(it["text"]) == "New Game": (it["b"] as Button).text = s

func _new_game() -> void:
	if Game.has_save() and _confirm_t <= 0.0:
		# a new journey erases the old save: ask once
		_confirm_t = 3.0
		_set_new_game_text("New Game  \u00B7  erase save?")
		return
	Game.reset_run()
	Game.delete_save()
	_leave(func(): get_parent().start_world(false))

func _continue() -> void:
	Game.load_game()
	_leave(func(): get_parent().start_world(true))

func _leave(then: Callable) -> void:
	_leaving = true
	_black_want = 1.0
	Audio.play_sfx("whoosh_big", null, 0.9, -10.0)
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(then)

func _settings() -> void:
	var pm = load("res://ui/PauseMenu.gd").new()
	add_child(pm)
	pm.visible = true
