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
var _rebinding := ""
var _rebind_slot := 0
var _bind_buttons := {}      # "action:slot" -> Button
var _controls_panel: Control
var _travel_panel: Control
var _travel_box: VBoxContainer
var _bind_msg: Label
var hud: Node = null

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
	_button(left, "Fast Travel", func():
		_open_travel()
		Audio.play_ui())
	_button(left, "Techniques", func():
		_resume()
		if hud != null and hud.has_method("open_skills"): hud.open_skills())
	_button(left, "Controls", func():
		_controls_panel.visible = true
		_refresh_binds()
		Audio.play_ui())
	_button(left, "Restart Checkpoint", func():
		_resume()
		if Game.world_ref != null: Game.world_ref.respawn())
	_button(left, "Quit to Menu", func():
		get_tree().paused = false
		Game.save_game()
		get_tree().change_scene_to_file("res://main/Main.tscn"))
	var right := _panel("SETTINGS", Vector2(sz.x * 0.5 + 20, 22), Vector2(360, 680))
	var r := _row(right, "Graphics")
	_quality = OptionButton.new()
	_quality.add_item("Low", 0); _quality.add_item("Medium", 1); _quality.add_item("High", 2)
	_quality.add_item("Ultra", 3)
	_quality.selected = int(Game.settings.get("quality", 2))
	_quality.item_selected.connect(func(i):
		if int(Game.settings.get("quality", 2)) == i: return
		Game.settings["quality"] = i
		Game.save_settings()
		Audio.play_ui()
		# v0.15: applied once, here, and only when the tier really changed
		Perf.apply_quality(i))
	r.add_child(_quality)
	var r2 := _row(right, "Camera sensitivity")
	_sens = _slider(r2, 0.3, 2.5, float(Game.settings.get("camera_sens", 1.0)))
	_sens.value_changed.connect(func(v): Game.settings["camera_sens"] = v; Game.save_settings())
	var rf := _row(right, "Field of view")
	var fov := _slider(rf, 45.0, 80.0, float(Game.settings.get("fov", 60.0)))
	fov.value_changed.connect(func(v): Game.settings["fov"] = v; Game.save_settings())
	var r3 := _row(right, "Touch button size")
	_touch = _slider(r3, 0.8, 1.5, float(Game.settings.get("touch_scale", 1.0)))
	_touch.value_changed.connect(func(v): Game.settings["touch_scale"] = v; Game.save_settings())
	# v0.15: four volume sliders with a readout. The bus curve is perceptual
	# (Audio.slider_db), so 10% now sounds like a tenth, not like half.
	for vk in [["master", "Master volume", 1.0], ["music", "Music", 0.7],
			["sfx", "Sound effects", 0.9], ["ambience", "Nature / ambience", 0.8]]:
		var rv := _row(right, String(vk[1]))
		var key: String = vk[0]
		var sl := _slider(rv, 0.0, 1.0, float(Game.settings.get(key, vk[2])))
		sl.step = 0.01
		sl.custom_minimum_size = Vector2(112, 24)
		var pct := Label.new()
		pct.custom_minimum_size = Vector2(40, 0)
		pct.add_theme_font_size_override("font_size", 13)
		pct.add_theme_color_override("font_color", Color(0.78, 0.74, 0.62))
		pct.text = "%d%%" % int(round(sl.value * 100.0))
		rv.add_child(pct)
		sl.value_changed.connect(func(v):
			Game.settings[key] = v
			pct.text = "%d%%" % int(round(v * 100.0))
			Audio.apply_volumes()
			Game.save_settings())
		if key == "music": _music = sl
		elif key == "sfx": _sfx = sl
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
	var rfx := _row(right, "Film grain / vignette")
	var fx := CheckBox.new(); fx.button_pressed = bool(Game.settings.get("film_fx", true))
	fx.toggled.connect(func(v):
		Game.settings["film_fx"] = v
		Game.save_settings()
		if Game.world_ref != null and Game.world_ref.has_method("apply_post"):
			Game.world_ref.apply_post(Perf.level))
	rfx.add_child(fx)
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
	_build_controls(sz)
	_build_travel(sz)

## Key rebinding.
##
## Every action in Game.BIND_ORDER gets a row with two buttons (primary and
## secondary input).  Pressing a button arms a capture: the next key or mouse
## button becomes that slot, Game rebuilds the InputMap, and any other action
## that was on the same input loses it (the screen says which).  Esc cancels,
## Backspace/Delete clears the slot.
func _build_controls(sz: Vector2) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	add_child(root)
	_controls_panel = root
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.045, 0.985)
	bg.position = Vector2(sz.x * 0.5 - 380, 24)
	bg.size = Vector2(760, 672)
	root.add_child(bg)
	var t := Label.new()
	t.text = "CONTROLS"
	t.position = bg.position + Vector2(24, 12)
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", Color(0.78, 0.66, 0.36))
	root.add_child(t)
	_bind_msg = Label.new()
	_bind_msg.text = "Click a slot, then press a key or mouse button.  Esc cancels · Backspace clears · Esc always pauses."
	_bind_msg.position = bg.position + Vector2(24, 46)
	_bind_msg.add_theme_font_size_override("font_size", 13)
	_bind_msg.add_theme_color_override("font_color", Color(0.62, 0.60, 0.56))
	root.add_child(_bind_msg)
	var scroll := ScrollContainer.new()
	scroll.position = bg.position + Vector2(20, 72)
	scroll.size = Vector2(720, 540)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 5)
	scroll.add_child(grid)
	for action: String in Game.BIND_ORDER:
		if Game.BIND_GROUPS.has(action):
			for i in 3:
				var gl := Label.new()
				gl.text = String(Game.BIND_GROUPS[action]).to_upper() if i == 0 else ""
				gl.add_theme_font_size_override("font_size", 13)
				gl.add_theme_color_override("font_color", Color(0.78, 0.66, 0.36))
				grid.add_child(gl)
		var l := Label.new()
		l.text = str(Game.BIND_INFO[action]["label"])
		l.custom_minimum_size = Vector2(300, 0)
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", Color(0.88, 0.86, 0.80))
		grid.add_child(l)
		for slot in 2:
			var b := Button.new()
			b.custom_minimum_size = Vector2(185, 30)
			b.add_theme_font_size_override("font_size", 14)
			b.focus_mode = Control.FOCUS_NONE
			var act: String = action
			var sl: int = slot
			b.pressed.connect(func(): _arm_rebind(act, sl))
			grid.add_child(b)
			_bind_buttons["%s:%d" % [action, slot]] = b
	var foot := HBoxContainer.new()
	foot.position = bg.position + Vector2(24, 624)
	foot.add_theme_constant_override("separation", 12)
	root.add_child(foot)
	var rb := Button.new()
	rb.text = "Restore defaults"
	rb.custom_minimum_size = Vector2(190, 36)
	rb.pressed.connect(func():
		Game.reset_keybinds()
		_rebinding = ""
		_refresh_binds()
		_bind_msg.text = "Default controls restored."
		Audio.play_ui())
	foot.add_child(rb)
	var cb := Button.new()
	cb.text = "Close"
	cb.custom_minimum_size = Vector2(150, 36)
	cb.pressed.connect(func(): _close_controls())
	foot.add_child(cb)
	_refresh_binds()

func _close_controls() -> void:
	_rebinding = ""
	_refresh_binds()
	_controls_panel.visible = false
	Audio.play_ui()

func _arm_rebind(action: String, slot: int) -> void:
	_rebinding = action
	_rebind_slot = slot
	_refresh_binds()
	var key := "%s:%d" % [action, slot]
	if _bind_buttons.has(key):
		(_bind_buttons[key] as Button).text = "press a key..."
	_bind_msg.text = "Rebinding '%s' — press a key or mouse button (Esc cancels, Backspace clears)." % str(Game.BIND_INFO[action]["label"])

func _refresh_binds() -> void:
	for action in Game.BIND_ORDER:
		var cur: Array = Game.binds_for(action)
		for slot in 2:
			var key := "%s:%d" % [action, slot]
			if _bind_buttons.has(key):
				(_bind_buttons[key] as Button).text = Game.slot_label(String(cur[slot]))

func _finish_rebind(s: String) -> void:
	var target := _rebinding
	_rebinding = ""
	var stolen := Game.set_bind(target, _rebind_slot, s)
	_refresh_binds()
	if s == "":
		_bind_msg.text = "Cleared."
	elif stolen != "" and stolen != target:
		_bind_msg.text = "%s is now %s (removed from %s)." % [Game.slot_label(s), str(Game.BIND_INFO[target]["label"]), str(Game.BIND_INFO[stolen]["label"])]
	else:
		_bind_msg.text = "%s is now %s." % [Game.slot_label(s), str(Game.BIND_INFO[target]["label"])]
	Audio.play_ui()

## Esc handling lives here (this node keeps processing while the tree is paused):
## cancel a capture, close a sub-panel, or resume the game.
func _input(ev: InputEvent) -> void:
	if not visible: return
	if _rebinding != "":
		if ev is InputEventKey:
			var k := ev as InputEventKey
			if not k.pressed or k.echo: return
			get_viewport().set_input_as_handled()
			if k.physical_keycode == KEY_ESCAPE:
				_rebinding = ""
				_refresh_binds()
				_bind_msg.text = "Cancelled."
			elif k.physical_keycode == KEY_BACKSPACE or k.physical_keycode == KEY_DELETE:
				_finish_rebind("")
			else:
				_finish_rebind(Game.slot_str(Game.K, int(k.physical_keycode)))
		elif ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if not mb.pressed: return
			get_viewport().set_input_as_handled()
			_finish_rebind(Game.slot_str(Game.M, int(mb.button_index)))
		return
	if ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo \
			and ev.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if _controls_panel.visible: _close_controls()
		elif _travel_panel.visible: _travel_panel.visible = false
		else: _resume()

# ---------------------------------------------------------------- fast travel
func _build_travel(sz: Vector2) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	add_child(root)
	_travel_panel = root
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.045, 0.985)
	bg.position = Vector2(sz.x * 0.5 - 260, 90)
	bg.size = Vector2(520, 520)
	root.add_child(bg)
	var t := Label.new()
	t.text = "FAST TRAVEL"
	t.position = bg.position + Vector2(24, 14)
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", Color(0.78, 0.66, 0.36))
	root.add_child(t)
	var hint := Label.new()
	hint.text = "Ride to any province you have already visited. Your horse comes with you."
	hint.position = bg.position + Vector2(24, 50)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.62, 0.60, 0.56))
	root.add_child(hint)
	_travel_box = VBoxContainer.new()
	_travel_box.position = bg.position + Vector2(24, 86)
	_travel_box.add_theme_constant_override("separation", 8)
	root.add_child(_travel_box)
	var cb := Button.new()
	cb.text = "Close"
	cb.custom_minimum_size = Vector2(150, 36)
	cb.position = bg.position + Vector2(24, 466)
	cb.pressed.connect(func():
		_travel_panel.visible = false
		Audio.play_ui())
	root.add_child(cb)

func _open_travel() -> void:
	for c in _travel_box.get_children(): c.queue_free()
	var w = Game.world_ref
	for z: String in Game.ZONE_ORDER:
		var b := Button.new()
		b.custom_minimum_size = Vector2(472, 44)
		b.add_theme_font_size_override("font_size", 17)
		var known := Game.visited_zones.has(z)
		b.text = String(Game.ZONE_TITLE.get(z, z)) + ("" if known else "   (not discovered)")
		b.disabled = not known or w == null
		if w != null and w.has_method("zone_name") and w.zone_name() == z: b.text += "   · you are here"
		var zz := z
		b.pressed.connect(func():
			_travel_panel.visible = false
			_resume()
			if Game.world_ref != null and Game.world_ref.has_method("fast_travel"):
				Game.world_ref.fast_travel(zz))
		_travel_box.add_child(b)
	_travel_panel.visible = true

func _slider(row: HBoxContainer, lo: float, hi: float, val: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo; s.max_value = hi; s.step = 0.05
	s.value = val
	s.custom_minimum_size = Vector2(140, 24)
	row.add_child(s)
	return s

func _resume() -> void:
	_rebinding = ""
	if _controls_panel != null: _controls_panel.visible = false
	if _travel_panel != null: _travel_panel.visible = false
	var h = hud if hud != null else get_parent()
	if h != null and h.has_method("set_paused"):
		h.set_paused(false)
	else:
		get_tree().paused = false
		visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
