extends CanvasLayer
## v0.14 story presentation: letterbox bars, a black fade, narrative cards,
## chapter title cards and a subtitle-style dialogue box. Story.gd decides what
## to show and when; this layer only draws it and reports player input.
##
## Input: Enter / Space / E / click / tap advances, Esc skips a cinematic.
## During normal play only Enter (or a tap on the box) advances dialogue, so
## Space still jumps and E still interacts.

signal advance
signal skip

const GOLD := Color(0.89, 0.75, 0.46)
const PARCHMENT := Color(0.96, 0.93, 0.87)
const MUTED := Color(0.74, 0.72, 0.68)
const VERMILION := Color(0.84, 0.20, 0.15)

var cinematic := false          ## true while the intro / epilogue owns the screen
## v0.23 prologue overlays: big centred cards, a white flash, the title reveal
## and hold-Esc-to-skip
var prologue := false
var _center: Control
var _c_kanji: Label
var _c_text: Label
var _c_t := -1.0
var _c_len := 4.0
var _flash: ColorRect
var _flash_a := 0.0
var _flash_rate := 4.0
var _title: Control
var _t_clip: Control
var _t_main: Label
var _t_edge: TextureRect
var _t_seal: PanelContainer
var _t_seal_lbl: Label
var _t_sub: Label
var _t_slash: ColorRect
var _t_t := -1.0
var _t_len := 5.0
var _hold := 0.0
var _esc_down := false
var _skip_hint_t := 0.0
var _skip_bar: ColorRect
var _skip_bar_bg: ColorRect
var f_kanji: Font

var _root: Control
var _bar_top: ColorRect
var _bar_bot: ColorRect
var _black: ColorRect
var _card: Label
var _chapter: Control
var _ch_kanji: Label
var _ch_label: Label
var _ch_title: Label
var _ch_sub: Label
var _ch_line: ColorRect
var _dlg: PanelContainer
var _dlg_name: Label
var _dlg_text: Label
var _dlg_hint: Label
var _hint: Label
var _skip_btn: Button

var _bars := 0.0                ## 0..1 letterbox amount
var _bars_want := 0.0
var _black_a := 0.0
var _black_want := 0.0
var _black_rate := 2.0
var _card_a := 0.0
var _card_want := 0.0
var _ch_t := -1.0               ## chapter card clock (-1 = hidden)
var _ch_len := 5.0
var _dlg_a := 0.0
var _dlg_want := 0.0
var _type_t := 0.0
var _type_len := 0
var f_title: Font
var f_reg: Font
var f_semi: Font

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	f_title = _font("res://assets/fonts/Title.ttf")
	f_reg = _font("res://assets/fonts/UI-Regular.ttf")
	f_semi = _font("res://assets/fonts/UI-SemiBold.ttf")
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_bar_top = _rect(Color(0, 0, 0, 1))
	_bar_bot = _rect(Color(0, 0, 0, 1))
	_card = Label.new()
	_card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.add_theme_font_override("font", f_title)
	_card.add_theme_color_override("font_color", PARCHMENT)
	_card.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_card.add_theme_constant_override("outline_size", 8)
	_card.add_theme_constant_override("line_spacing", 6)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_card)
	_build_chapter()
	_build_dialogue()
	_hint = Label.new()
	_hint.add_theme_font_override("font", f_semi)
	_hint.add_theme_color_override("font_color", MUTED)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("outline_size", 4)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.text = "Enter  next     Esc  skip"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hint)
	_skip_btn = Button.new()
	_skip_btn.text = "Skip  \u00BB"
	_skip_btn.focus_mode = Control.FOCUS_NONE
	_skip_btn.flat = true
	_skip_btn.add_theme_font_override("font", f_semi)
	_skip_btn.add_theme_color_override("font_color", PARCHMENT)
	_skip_btn.pressed.connect(func(): skip.emit())
	_root.add_child(_skip_btn)
	_build_v23()
	# the fade sits above everything else
	_black = _rect(Color(0, 0, 0, 0))
	# v0.23 text over black: title cards, the title and the skip bar sit above the fade
	for n in [_center, _title, _skip_bar_bg, _skip_bar, _skip_btn]:
		if n != null: _root.move_child(n, -1)
	_flash = _rect(Color(1, 1, 1, 0))
	_layout()
	get_viewport().size_changed.connect(_layout)
	_apply()

func _font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f = load(path)
		if f is Font: return f
	return ThemeDB.fallback_font

func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(r)
	return r

func _label(font: Font, size: int, col: Color, outline := 0) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build_chapter() -> void:
	_chapter = Control.new()
	_chapter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_chapter)
	_ch_kanji = _label(f_title, 30, GOLD, 6)
	_ch_label = _label(f_semi, 15, GOLD, 4)
	_ch_title = _label(f_title, 46, PARCHMENT, 8)
	_ch_sub = _label(f_title, 20, MUTED, 5)
	_ch_line = ColorRect.new()
	_ch_line.color = VERMILION
	_ch_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for n in [_ch_kanji, _ch_label, _ch_line, _ch_title, _ch_sub]:
		_chapter.add_child(n)

func _build_dialogue() -> void:
	_dlg = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.025, 0.035, 0.72)
	sb.border_color = GOLD * Color(1, 1, 1, 0.45)
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.anti_aliasing = true
	_dlg.add_theme_stylebox_override("panel", sb)
	_dlg.mouse_filter = Control.MOUSE_FILTER_PASS
	_dlg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			advance.emit()
		elif ev is InputEventScreenTouch and ev.pressed:
			advance.emit())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dlg.add_child(v)
	_dlg_name = _label(f_title, 18, GOLD)
	_dlg_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(_dlg_name)
	_dlg_text = _label(f_reg, 19, PARCHMENT)
	_dlg_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_dlg_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_dlg_text)
	_dlg_hint = _label(f_semi, 12, MUTED)
	_dlg_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dlg_hint.text = "Enter  \u00BB"
	v.add_child(_dlg_hint)
	_root.add_child(_dlg)

func _build_v23() -> void:
	f_kanji = _font("res://assets/fonts/Kanji.ttf")
	_center = Control.new()
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_center)
	_c_kanji = _label(f_kanji, 28, GOLD, 6)
	_c_text = _label(f_title, 34, PARCHMENT, 8)
	_c_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_c_text.add_theme_constant_override("line_spacing", 8)
	_center.add_child(_c_kanji)
	_center.add_child(_c_text)
	_title = Control.new()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_title)
	_t_slash = ColorRect.new()
	_t_slash.color = Color(1.0, 0.97, 0.9, 1.0)
	_t_slash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_child(_t_slash)
	_t_clip = Control.new()
	_t_clip.clip_contents = true
	_t_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_child(_t_clip)
	_t_main = _label(f_title, 92, PARCHMENT, 10)
	_t_main.text = "RONIN'S  EDGE"
	_t_clip.add_child(_t_main)
	# a soft ink edge that leads the reveal
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	g.colors = PackedColorArray([Color(1, 0.95, 0.85, 0.0), Color(1, 0.95, 0.85, 0.55), Color(1, 1, 1, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 8
	_t_edge = TextureRect.new()
	_t_edge.texture = gt
	_t_edge.stretch_mode = TextureRect.STRETCH_SCALE
	_t_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_child(_t_edge)
	_t_seal = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = VERMILION
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	_t_seal.add_theme_stylebox_override("panel", sb)
	_t_seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_t_seal_lbl = _label(f_kanji, 30, Color(1, 0.97, 0.92))
	_t_seal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_t_seal_lbl.text = "浪人\nの刃"
	_t_seal.add_child(_t_seal_lbl)
	_title.add_child(_t_seal)
	_t_sub = _label(f_semi, 16, GOLD, 4)
	_t_sub.text = _spaced("A TALE OF KIYOMIZU PROVINCE")
	_title.add_child(_t_sub)
	_skip_bar_bg = ColorRect.new()
	_skip_bar_bg.color = Color(1, 1, 1, 0.18)
	_skip_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_skip_bar_bg)
	_skip_bar = ColorRect.new()
	_skip_bar.color = GOLD
	_skip_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_skip_bar)

func _layout() -> void:
	var sz := _root.get_viewport_rect().size
	var k := sz.y / 720.0
	var bh := sz.y * 0.12 * _bars
	_bar_top.position = Vector2(0, 0)
	_bar_top.size = Vector2(sz.x, bh)
	_bar_bot.position = Vector2(0, sz.y - bh)
	_bar_bot.size = Vector2(sz.x, bh)
	_black.position = Vector2.ZERO
	_black.size = sz
	var cw := minf(sz.x * 0.70, 900.0 * k)
	_card.add_theme_font_size_override("font_size", int(26.0 * k))
	_card.position = Vector2((sz.x - cw) * 0.5, sz.y * 0.64)
	_card.size = Vector2(cw, sz.y * 0.20)
	_chapter.position = Vector2(0, sz.y * 0.24)
	_chapter.size = Vector2(sz.x, sz.y * 0.3)
	_ch_kanji.add_theme_font_size_override("font_size", int(30.0 * k))
	_ch_label.add_theme_font_size_override("font_size", int(15.0 * k))
	_ch_title.add_theme_font_size_override("font_size", int(46.0 * k))
	_ch_sub.add_theme_font_size_override("font_size", int(20.0 * k))
	_ch_kanji.position = Vector2(0, 0); _ch_kanji.size = Vector2(sz.x, 40.0 * k)
	_ch_label.position = Vector2(0, 42.0 * k); _ch_label.size = Vector2(sz.x, 22.0 * k)
	_ch_line.size = Vector2(160.0 * k, 2.0 * k)
	_ch_line.position = Vector2(sz.x * 0.5 - 80.0 * k, 72.0 * k)
	_ch_title.position = Vector2(0, 80.0 * k); _ch_title.size = Vector2(sz.x, 60.0 * k)
	_ch_sub.position = Vector2(0, 142.0 * k); _ch_sub.size = Vector2(sz.x, 30.0 * k)
	var dw := minf(sz.x * 0.62, 760.0 * k)
	_dlg_name.add_theme_font_size_override("font_size", int(18.0 * k))
	_dlg_text.add_theme_font_size_override("font_size", int(19.0 * k))
	_dlg_hint.add_theme_font_size_override("font_size", int(12.0 * k))
	_dlg.custom_minimum_size = Vector2(dw, 0)
	_dlg.size = Vector2(dw, 0)
	_dlg.position = Vector2((sz.x - dw) * 0.5, sz.y - 128.0 * k - _dlg.get_combined_minimum_size().y)
	if _bars > 0.01:
		_dlg.position.y = minf(_dlg.position.y, sz.y - bh - 12.0 * k - _dlg.get_combined_minimum_size().y)
	_hint.add_theme_font_size_override("font_size", int(13.0 * k))
	_hint.position = Vector2(sz.x - 330.0 * k, 14.0 * k)
	_hint.size = Vector2(300.0 * k, 20.0 * k)
	_skip_btn.add_theme_font_size_override("font_size", int(15.0 * k))
	_skip_btn.position = Vector2(sz.x - 120.0 * k, 34.0 * k)
	_skip_btn.size = Vector2(100.0 * k, 32.0 * k)
	if _center == null: return
	_flash.position = Vector2.ZERO
	_flash.size = sz
	_center.position = Vector2(0, sz.y * 0.36)
	_center.size = Vector2(sz.x, sz.y * 0.3)
	_c_kanji.add_theme_font_size_override("font_size", int(26.0 * k))
	_c_text.add_theme_font_size_override("font_size", int(30.0 * k))
	_c_kanji.position = Vector2(0, 0)
	_c_kanji.size = Vector2(sz.x, 40.0 * k)
	_c_text.position = Vector2(sz.x * 0.15, 48.0 * k)
	_c_text.size = Vector2(sz.x * 0.7, 120.0 * k)
	_title.position = Vector2.ZERO
	_title.size = sz
	_t_main.add_theme_font_size_override("font_size", int(84.0 * k))
	var tw := _t_main.get_combined_minimum_size().x
	var th := 110.0 * k
	var tx := (sz.x - tw) * 0.5
	var ty := sz.y * 0.36
	_t_clip.position = Vector2(tx, ty)
	_t_main.position = Vector2.ZERO
	_t_main.size = Vector2(tw, th)
	_t_seal_lbl.add_theme_font_size_override("font_size", int(22.0 * k))
	_t_seal.position = Vector2(tx + tw + 14.0 * k, ty + 14.0 * k)
	_t_sub.add_theme_font_size_override("font_size", int(15.0 * k))
	_t_sub.position = Vector2(0, ty + th + 4.0 * k)
	_t_sub.size = Vector2(sz.x, 26.0 * k)
	_t_slash.position = Vector2(0, ty + th * 0.52)
	_t_slash.size = Vector2(sz.x, maxf(2.0, 3.0 * k))
	_t_edge.size = Vector2(60.0 * k, th)
	_skip_bar_bg.position = Vector2(sz.x - 222.0 * k, 34.0 * k + 36.0 * k)
	_skip_bar_bg.size = Vector2(200.0 * k, maxf(2.0, 3.0 * k))
	_skip_bar.position = _skip_bar_bg.position

# ------------------------------------------------------------------ api
func letterbox(on: bool) -> void:
	_bars_want = 1.0 if on else 0.0

func fade_to(alpha: float, seconds := 0.5) -> void:
	_black_want = alpha
	_black_rate = 1.0 / maxf(seconds, 0.01)

func set_black(alpha: float) -> void:
	_black_a = alpha
	_black_want = alpha
	_apply()

func is_black() -> bool:
	return _black_a > 0.98

func show_card(text: String) -> void:
	_card.text = text
	_card_a = 0.0
	_card_want = 1.0

func hide_card() -> void:
	_card_want = 0.0

func show_chapter(kanji: String, label: String, title: String, sub: String, seconds := 5.0) -> void:
	_ch_kanji.text = kanji
	_ch_label.text = _spaced(label.to_upper())
	_ch_title.text = title
	_ch_sub.text = sub
	_ch_t = 0.0
	_ch_len = seconds

func chapter_showing() -> bool:
	return _ch_t >= 0.0

func hide_chapter() -> void:
	_ch_t = -1.0

func say(speaker: String, text: String) -> void:
	_dlg_name.text = speaker
	_dlg_text.text = text
	_dlg_text.visible_characters = 0
	_type_t = 0.0
	_type_len = text.length()
	_dlg_want = 1.0
	_layout()

func line_typed() -> bool:
	return _dlg_text.visible_characters < 0 or _dlg_text.visible_characters >= _type_len

func finish_typing() -> void:
	_dlg_text.visible_characters = -1

func hide_dialogue() -> void:
	_dlg_want = 0.0

## v0.23 a big centred card (kanji line above, text below) that fades in and out.
func center_text(kanji: String, text: String, seconds := 4.0) -> void:
	_c_kanji.text = kanji
	_c_text.text = text
	_c_t = 0.0
	_c_len = seconds

## v0.23 white flash that decays over `seconds`.
func flash(strength := 1.0, seconds := 0.25) -> void:
	_flash_a = clampf(strength, 0.0, 1.0)
	_flash_rate = 1.0 / maxf(seconds, 0.02)

## v0.23 the title: a sword-light slash, the name brushed in left to right,
## the seal stamped beside it, the line beneath; all out after `seconds`.
func title_reveal(seconds := 5.0) -> void:
	_t_t = 0.0
	_t_len = seconds
	flash(0.55, 0.35)
	_layout()

func title_showing() -> bool:
	return _t_t >= 0.0

func set_cinematic(on: bool) -> void:
	cinematic = on
	letterbox(on)

static func _spaced(s: String) -> String:
	var out := ""
	for i in s.length():
		out += s[i]
		if i < s.length() - 1: out += " "
	return out

# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	_tick_v23(delta)
	var lb := _bars
	_bars = move_toward(_bars, _bars_want, delta * 1.6)
	_black_a = move_toward(_black_a, _black_want, delta * _black_rate)
	_card_a = move_toward(_card_a, _card_want, delta * 1.8)
	_dlg_a = move_toward(_dlg_a, _dlg_want, delta * 5.0)
	if _ch_t >= 0.0:
		_ch_t += delta
		if _ch_t > _ch_len: _ch_t = -1.0
	if _dlg_want > 0.5 and not line_typed():
		_type_t += delta
		_dlg_text.visible_characters = int(_type_t * 48.0)
	if absf(lb - _bars) > 0.0001 or _dlg_a > 0.001: _layout()
	_apply()

func _tick_v23(delta: float) -> void:
	if _center == null: return
	_flash_a = maxf(0.0, _flash_a - delta * _flash_rate)
	_flash.color = Color(1, 1, 1, _flash_a)
	_flash.visible = _flash_a > 0.002
	var ca := 0.0
	if _c_t >= 0.0:
		_c_t += delta
		ca = clampf(_c_t / 1.0, 0.0, 1.0) * clampf((_c_len - _c_t) / 0.9, 0.0, 1.0)
		if _c_t > _c_len: _c_t = -1.0
	_center.modulate = Color(1, 1, 1, ca)
	_center.visible = ca > 0.001
	# title
	if _t_t >= 0.0:
		_t_t += delta
		var tt := _t_t
		var out := clampf((_t_len - tt) / 1.1, 0.0, 1.0)
		var sl := clampf(tt / 0.22, 0.0, 1.0)
		var sz := _root.get_viewport_rect().size
		_t_slash.size.x = sz.x * sl
		_t_slash.position.x = sz.x * 0.5 * (1.0 - sl)
		_t_slash.modulate = Color(1, 1, 1, clampf(1.0 - (tt - 0.22) / 0.5, 0.0, 1.0))
		var rv := clampf((tt - 0.12) / 1.25, 0.0, 1.0)
		rv = 1.0 - pow(1.0 - rv, 3.0)
		var full := _t_main.size.x
		_t_clip.size = Vector2(full * rv + 2.0, _t_main.size.y)
		_t_edge.position = Vector2(_t_clip.position.x + full * rv - _t_edge.size.x * 0.7, _t_clip.position.y)
		_t_edge.modulate = Color(1, 1, 1, (1.0 - rv) * 1.4 if rv > 0.0 else 0.0)
		var st := clampf((tt - 1.0) / 0.25, 0.0, 1.0)
		_t_seal.pivot_offset = _t_seal.size * 0.5
		_t_seal.scale = Vector2.ONE * lerpf(1.7, 1.0, st)
		_t_seal.modulate = Color(1, 1, 1, st)
		_t_sub.modulate = Color(1, 1, 1, clampf((tt - 1.5) / 0.8, 0.0, 1.0))
		_title.modulate = Color(1, 1, 1, out)
		_title.visible = true
		if tt > _t_len: _t_t = -1.0
	else:
		_title.visible = false
	# hold Esc to skip the prologue
	if prologue and _esc_down:
		_hold += delta
		if _hold >= 0.9:
			_hold = 0.0
			_esc_down = false
			skip.emit()
	else:
		_hold = maxf(0.0, _hold - delta * 3.0)
	_skip_hint_t = maxf(0.0, _skip_hint_t - delta)
	var show_bar := prologue and (_hold > 0.0 or _skip_hint_t > 0.0)
	_skip_bar_bg.visible = show_bar
	_skip_bar.visible = show_bar and _hold > 0.0
	_skip_bar.size = Vector2(_skip_bar_bg.size.x * clampf(_hold / 0.9, 0.0, 1.0), _skip_bar_bg.size.y)

func _apply() -> void:
	_black.color = Color(0, 0, 0, _black_a)
	_black.visible = _black_a > 0.001
	_bar_top.visible = _bars > 0.001
	_bar_bot.visible = _bars > 0.001
	_card.modulate = Color(1, 1, 1, _card_a)
	_card.visible = _card_a > 0.001
	var ca := 0.0
	if _ch_t >= 0.0:
		ca = clampf(_ch_t / 0.8, 0.0, 1.0) * clampf((_ch_len - _ch_t) / 1.0, 0.0, 1.0)
	_chapter.modulate = Color(1, 1, 1, ca)
	_chapter.visible = ca > 0.001
	_ch_line.size.x = 160.0 * (_root.get_viewport_rect().size.y / 720.0) * clampf(_ch_t / 1.2, 0.0, 1.0)
	_dlg.modulate = Color(1, 1, 1, _dlg_a)
	_dlg.visible = _dlg_a > 0.001
	_hint.visible = cinematic and (not prologue or _skip_hint_t > 0.0 or _hold > 0.0)
	_skip_btn.visible = cinematic
	_hint.text = "Hold Esc to skip" if prologue else "Enter  next     Esc  skip"

func _input(event: InputEvent) -> void:
	if cinematic and prologue:
		# the prologue runs to its score: no paging, Esc must be held to skip
		if event is InputEventKey and not event.echo:
			var kk: int = (event as InputEventKey).keycode
			if kk == KEY_ESCAPE:
				_esc_down = event.pressed
				get_viewport().set_input_as_handled()
			if event.pressed: _skip_hint_t = 2.5
		elif (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
			_skip_hint_t = 2.5
		return
	if cinematic:
		if event is InputEventKey and event.pressed and not event.echo:
			var kc: int = (event as InputEventKey).keycode
			if kc == KEY_ESCAPE:
				skip.emit()
				get_viewport().set_input_as_handled()
			elif kc in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_E]:
				advance.emit()
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# let the Skip button have its own click
			if _skip_btn.visible and _skip_btn.get_global_rect().has_point((event as InputEventMouseButton).position):
				return
			advance.emit()
			get_viewport().set_input_as_handled()
		elif event is InputEventScreenTouch and event.pressed:
			if _skip_btn.visible and _skip_btn.get_global_rect().has_point((event as InputEventScreenTouch).position):
				return
			advance.emit()
		return
	if _dlg_want > 0.5 and event is InputEventKey and event.pressed and not event.echo:
		var k2: int = (event as InputEventKey).keycode
		if k2 == KEY_ENTER or k2 == KEY_KP_ENTER:
			advance.emit()
			get_viewport().set_input_as_handled()
