extends Control
## Pause menu with settings, save and quit.

var _quality: OptionButton
var _sens: HSlider
var _touch: HSlider
var _music: HSlider
var _sfx: HSlider
var _haptics: CheckBox
var _fps: CheckBox
var _invert: CheckBox
var _edit_touch: CheckBox

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func _panel(title: String, pos: Vector2, size: Vector2) -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.045, 0.055, 0.96)
	bg.position = pos
	bg.size = size
	add_child(bg)
	var border := ColorRect.new()
	border.color = Color(0.78, 0.66, 0.36, 0.8)
	border.position = pos
	border.size = Vector2(size.x, 2)
	add_child(border)
	var t := Label.new()
	t.text = title
	t.position = pos + Vector2(20, 12)
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color(0.78, 0.66, 0.36))
	add_child(t)
	var box := VBoxContainer.new()
	box.position = pos + Vector2(20, 52)
	box.custom_minimum_size = Vector2(size.x - 40, size.y - 70)
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	return box

func _row(box: VBoxContainer, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	box.add_child(h)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(170, 0)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.88, 0.86, 0.80))
	h.add_child(l)
	return h

func _button(box: VBoxContainer, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 40)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(cb)
	box.add_child(b)
	return b

func _build() -> void:
	var sz := Vector2(1280, 720)
	var left := _panel("RONIN'S EDGE", Vector2(sz.x * 0.5 - 340, 60), Vector2(320, 560))
	_button(left, "Resume", func(): _resume())
	_button(left, "Save Game", func():
		Game.save_game()
		Audio.play_ui())
	_button(left, "Restart Checkpoint", func():
		_resume()
		if Game.world_ref != null: Game.world_ref.respawn())
	_button(left, "Quit to Menu", func():
		get_tree().paused = false
		Game.save_game()
		get_tree().change_scene_to_file("res://main/Main.tscn"))
	var right := _panel("SETTINGS", Vector2(sz.x * 0.5 + 20, 60), Vector2(340, 560))
	var r := _row(right, "Graphics")
	_quality = OptionButton.new()
	_quality.add_item("Low", 0); _quality.add_item("Medium", 1); _quality.add_item("High", 2)
	_quality.selected = int(Game.settings.get("quality", 2))
	_quality.item_selected.connect(func(i):
		Game.settings["quality"] = i
		Game.save_settings()
		Audio.play_ui())
	r.add_child(_quality)
	var r2 := _row(right, "Camera sensitivity")
	_sens = _slider(r2, 0.3, 2.5, float(Game.settings.get("camera_sens", 1.0)))
	_sens.value_changed.connect(func(v): Game.settings["camera_sens"] = v; Game.save_settings())
	var r3 := _row(right, "Touch button size")
	_touch = _slider(r3, 0.8, 1.5, float(Game.settings.get("touch_scale", 1.0)))
	_touch.value_changed.connect(func(v): Game.settings["touch_scale"] = v; Game.save_settings())
	var r4 := _row(right, "Music")
	_music = _slider(r4, 0.0, 1.0, float(Game.settings.get("music", 0.7)))
	_music.value_changed.connect(func(v): Game.settings["music"] = v; Audio.apply_volumes(); Game.save_settings())
	var r5 := _row(right, "Sound effects")
	_sfx = _slider(r5, 0.0, 1.0, float(Game.settings.get("sfx", 0.9)))
	_sfx.value_changed.connect(func(v): Game.settings["sfx"] = v; Audio.apply_volumes(); Game.save_settings())
	var r6 := _row(right, "Screen shake")
	var sh := _slider(r6, 0.0, 1.5, float(Game.settings.get("shake", 1.0)))
	sh.value_changed.connect(func(v): Game.settings["shake"] = v; Game.save_settings())
	var r7 := _row(right, "Haptics")
	_haptics = CheckBox.new(); _haptics.button_pressed = bool(Game.settings.get("haptics", true))
	_haptics.toggled.connect(func(v): Game.settings["haptics"] = v; Game.save_settings())
	r7.add_child(_haptics)
	var r8 := _row(right, "Invert Y")
	_invert = CheckBox.new(); _invert.button_pressed = bool(Game.settings.get("invert_y", false))
	_invert.toggled.connect(func(v): Game.settings["invert_y"] = v; Game.save_settings())
	r8.add_child(_invert)
	var r9 := _row(right, "Show FPS / stats")
	_fps = CheckBox.new(); _fps.button_pressed = bool(Game.settings.get("show_fps", false))
	_fps.toggled.connect(func(v):
		Game.settings["show_fps"] = v
		if Perf.overlay != null: Perf.overlay.visible = v
		Game.save_settings())
	r9.add_child(_fps)
	var r10 := _row(right, "Customise touch layout")
	_edit_touch = CheckBox.new()
	_edit_touch.toggled.connect(func(v):
		var t = get_tree().get_first_node_in_group("touch_layer")
		if t != null: t.set_edit_mode(v)
		if not v:
			var t2 = get_tree().get_first_node_in_group("touch_layer")
			if t2 != null: t2.save_layout())
	r10.add_child(_edit_touch)
	_button(right, "Back to Game", func(): _resume())

func _slider(row: HBoxContainer, lo: float, hi: float, val: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo; s.max_value = hi; s.step = 0.05
	s.value = val
	s.custom_minimum_size = Vector2(140, 24)
	row.add_child(s)
	return s

func _resume() -> void:
	get_tree().paused = false
	visible = false
	var h = get_parent()
	if h != null and h.has_method("toggle_pause"): h._paused = false
