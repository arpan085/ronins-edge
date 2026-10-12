extends SceneTree
## Builds ui/theme.tres (project-wide UI theme, v13): Noto Sans UI font,
## rounded dark translucent buttons with a gold edge, vermilion pressed state,
## slim sliders. Run: godot --headless --path . -s tools/make_theme.gd

const GOLD := Color(0.89, 0.75, 0.46)
const PARCH := Color(0.95, 0.92, 0.86)
const VERM := Color(0.78, 0.20, 0.15)

func _sb(bg: Color, border: Color, bw: int, radius: int, mx := 14.0, my := 7.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = mx
	s.content_margin_right = mx
	s.content_margin_top = my
	s.content_margin_bottom = my
	s.anti_aliasing = true
	s.corner_detail = 6
	return s

func _init() -> void:
	var t := Theme.new()
	var font: Font = load("res://assets/fonts/UI-SemiBold.ttf")
	t.default_font = font
	t.default_font_size = 16
	for cls in ["Button", "OptionButton", "MenuButton", "CheckBox", "CheckButton"]:
		t.set_stylebox("normal", cls, _sb(Color(0.06, 0.065, 0.08, 0.86), Color(GOLD, 0.28), 1, 7))
		t.set_stylebox("hover", cls, _sb(Color(0.11, 0.105, 0.10, 0.92), Color(GOLD, 0.85), 1, 7))
		t.set_stylebox("pressed", cls, _sb(Color(VERM, 0.9), Color(GOLD, 0.9), 1, 7))
		t.set_stylebox("hover_pressed", cls, _sb(Color(VERM.lightened(0.1), 0.92), Color(GOLD, 1.0), 1, 7))
		t.set_stylebox("focus", cls, _sb(Color(0, 0, 0, 0), Color(GOLD, 0.9), 2, 7))
		t.set_stylebox("disabled", cls, _sb(Color(0.05, 0.05, 0.06, 0.6), Color(1, 1, 1, 0.08), 1, 7))
		t.set_color("font_color", cls, PARCH)
		t.set_color("font_hover_color", cls, Color(1.0, 0.95, 0.82))
		t.set_color("font_pressed_color", cls, Color(1, 1, 1))
		t.set_color("font_hover_pressed_color", cls, Color(1, 1, 1))
		t.set_color("font_focus_color", cls, Color(1.0, 0.95, 0.82))
		t.set_color("font_disabled_color", cls, Color(0.55, 0.55, 0.55))
	# check boxes read as rows, not buttons
	for cls in ["CheckBox", "CheckButton"]:
		t.set_stylebox("normal", cls, _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6, 6.0, 4.0))
		t.set_stylebox("hover", cls, _sb(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 6, 6.0, 4.0))
		t.set_stylebox("pressed", cls, _sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6, 6.0, 4.0))
		t.set_stylebox("hover_pressed", cls, _sb(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 6, 6.0, 4.0))
	t.set_color("font_color", "Label", PARCH)
	t.set_stylebox("panel", "PanelContainer", _sb(Color(0.035, 0.04, 0.05, 0.92), Color(GOLD, 0.3), 1, 10, 16.0, 12.0))
	t.set_stylebox("panel", "Panel", _sb(Color(0.035, 0.04, 0.05, 0.92), Color(GOLD, 0.3), 1, 10))
	t.set_stylebox("panel", "PopupMenu", _sb(Color(0.05, 0.055, 0.065, 0.98), Color(GOLD, 0.4), 1, 8, 6.0, 6.0))
	t.set_stylebox("hover", "PopupMenu", _sb(Color(VERM, 0.85), Color(0, 0, 0, 0), 0, 5, 6.0, 3.0))
	t.set_color("font_color", "PopupMenu", PARCH)
	t.set_color("font_hover_color", "PopupMenu", Color(1, 1, 1))
	t.set_stylebox("panel", "TooltipPanel", _sb(Color(0.05, 0.055, 0.065, 0.96), Color(GOLD, 0.4), 1, 6, 8.0, 4.0))
	# sliders: a slim track, gold fill
	var track := _sb(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 3, 0.0, 3.0)
	var fill := _sb(Color(GOLD, 0.9), Color(0, 0, 0, 0), 0, 3, 0.0, 3.0)
	for cls in ["HSlider", "VSlider"]:
		t.set_stylebox("slider", cls, track)
		t.set_stylebox("grabber_area", cls, fill)
		t.set_stylebox("grabber_area_highlight", cls, fill)
	t.set_stylebox("panel", "TabContainer", _sb(Color(0.035, 0.04, 0.05, 0.92), Color(GOLD, 0.3), 1, 8))
	t.set_stylebox("normal", "LineEdit", _sb(Color(0.06, 0.065, 0.08, 0.9), Color(GOLD, 0.3), 1, 6, 10.0, 6.0))
	t.set_stylebox("focus", "LineEdit", _sb(Color(0, 0, 0, 0), Color(GOLD, 0.9), 2, 6))
	var err := ResourceSaver.save(t, "res://ui/theme.tres")
	print("THEME_SAVED ", err)
	quit(0 if err == OK else 1)
