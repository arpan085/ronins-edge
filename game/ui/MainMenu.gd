extends Control
## Title screen. Feudal ink-and-gold styling, no template look.

const GOLD := Color(0.78, 0.66, 0.36)
const PARCHMENT := Color(0.90, 0.86, 0.76)
const VERMILION := Color(0.72, 0.16, 0.12)

var _bg: ColorRect
var _t := 0.0
var _title: Label
var _sub: Label
var _menu: VBoxContainer
var _info: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg = ColorRect.new()
	_bg.color = Color(0.05, 0.055, 0.07)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	_title = Label.new()
	_title.text = "R O N I N ' S   E D G E"
	_title.add_theme_font_size_override("font_size", 54)
	_title.add_theme_color_override("font_color", PARCHMENT)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_title.add_theme_constant_override("outline_size", 8)
	_title.position = Vector2(0, 96)
	_title.size = Vector2(1280, 70)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)
	_sub = Label.new()
	_sub.text = "a mobile vertical slice  ·  feudal Japan  ·  five connected zones"
	_sub.add_theme_font_size_override("font_size", 16)
	_sub.add_theme_color_override("font_color", GOLD)
	_sub.position = Vector2(0, 158)
	_sub.size = Vector2(1280, 26)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_sub)
	_menu = VBoxContainer.new()
	_menu.position = Vector2(1280 * 0.5 - 150, 236)
	_menu.custom_minimum_size = Vector2(300, 300)
	_menu.add_theme_constant_override("separation", 14)
	add_child(_menu)
	_add("New Game", _new_game)
	if Game.has_save():
		_add("Continue", _continue)
	_add("Settings", _settings)
	_add("Quit", func(): get_tree().quit())
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 14)
	_info.add_theme_color_override("font_color", Color(0.68, 0.68, 0.70))
	_info.position = Vector2(0, 620)
	_info.size = Vector2(1280, 80)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_info)
	_refresh_info()
	Audio.play_music("menu")

func _refresh_info() -> void:
	var q := String(Perf.preset()["name"])
	var last := ""
	if Game.has_save():
		last = "  ·  save found (%s, %d mastery)" % [Game.ZONE_TITLE.get(Game.zone, Game.zone), Game.mastery_points]
	_info.text = "Graphics: %s  ·  %s%s\nKeyboard/mouse or touch.  WASD move · J light · K heavy · L block · Space dodge · Tab lock · Q stance · R special · F interact · Esc pause" % [
		q, "touch controls enabled" if (OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()) else "desktop input", last]

func _add(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 46)
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", PARCHMENT)
	b.add_theme_stylebox_override("normal", _style(Color(0.10, 0.11, 0.13, 0.85)))
	b.add_theme_stylebox_override("hover", _style(Color(0.20, 0.14, 0.12, 0.95)))
	b.add_theme_stylebox_override("pressed", _style(Color(0.32, 0.12, 0.10, 1.0)))
	b.pressed.connect(func():
		Audio.play_ui()
		cb.call())
	_menu.add_child(b)
	return b

func _style(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.border_color = GOLD
	s.set_border_width_all(1)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func _process(delta: float) -> void:
	_t += delta
	var g := 0.06 + 0.02 * sin(_t * 0.7)
	_bg.color = Color(g, g + 0.005, g + 0.02)

func _new_game() -> void:
	Game.reset_run()
	Game.delete_save()
	get_parent().start_world(false)

func _continue() -> void:
	Game.load_game()
	get_parent().start_world(true)

func _settings() -> void:
	var pm = load("res://ui/PauseMenu.gd").new()
	add_child(pm)
	pm.visible = true
