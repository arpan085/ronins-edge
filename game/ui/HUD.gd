extends CanvasLayer
## Cinematic feudal-Japan HUD: ink panels, gold rules, vermillion accents.

const GOLD := Color(0.78, 0.66, 0.36)
const INK := Color(0.055, 0.06, 0.075, 0.72)
const INK_SOLID := Color(0.05, 0.055, 0.07, 0.92)
const VERMILION := Color(0.72, 0.16, 0.12)
const PARCHMENT := Color(0.90, 0.86, 0.76)
const SPIRIT := Color(0.45, 0.78, 0.95)

var world: World
var player: Player
var _paint: Painter
var _toast_box: VBoxContainer
var _obj_label: Label
var _quest_title: Label
var _zone_label: Label
var _prompt_label: Label
var _stance_label: Label
var _notice_label: Label
var _time_label: Label
var _pause_btn: Button
var _db_prompt: Label
var _minimap: ImageTexture
var _mm_size := 120
var _dmg_flash := 0.0
var _deflect_flash := 0.0
var _hit_flash := 0.0
var _zone_banner := 0.0
var _zone_text := ""
var _toasts: Array = []
var _paused := false
var _pause_menu: Node

class Painter extends Control:
	var hud: CanvasLayer
	func _draw() -> void:
		if hud != null: hud.draw_all(self)

func _ready() -> void:
	layer = 10
	_paint = Painter.new()
	_paint.hud = self
	_paint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_paint)
	_build_labels()
	_build_minimap_texture()
	Game.notice.connect(_on_notice)
	Quests.objective_toast.connect(_on_toast)
	Game.zone_changed.connect(_on_zone)

func bind(w: World) -> void:
	world = w
	player = w.player
	if player != null:
		player.lock_changed.connect(func(t): if w.camera != null: w.camera.set_lock(t))
	w.prompt_changed.connect(func(t): _prompt_label.text = t)
	if player != null:
		player.died.connect(func(): _toast("You have fallen", VERMILION))

func _build_labels() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_obj_label = _mk_label(root, Vector2(24, 118), 17, PARCHMENT)
	_quest_title = _mk_label(root, Vector2(24, 96), 15, GOLD)
	_zone_label = _mk_label(root, Vector2(24, 24), 20, PARCHMENT)
	_prompt_label = _mk_label(root, Vector2(0, 0), 18, PARCHMENT)
	_stance_label = _mk_label(root, Vector2(0, 0), 17, GOLD)
	_time_label = _mk_label(root, Vector2(0, 0), 15, PARCHMENT)
	_notice_label = _mk_label(root, Vector2(0, 0), 19, GOLD)
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_db_prompt = _mk_label(root, Vector2(0, 0), 20, Color(1.0, 0.88, 0.45))
	_db_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_toast_box = VBoxContainer.new()
	_toast_box.position = Vector2(24, 150)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast_box)

	_pause_btn = Button.new()
	_pause_btn.text = "❚❚"
	_pause_btn.custom_minimum_size = Vector2(52, 46)
	_pause_btn.anchor_left = 1.0
	_pause_btn.anchor_right = 1.0
	_pause_btn.offset_left = -64
	_pause_btn.offset_right = -12
	_pause_btn.offset_top = 14
	_pause_btn.offset_bottom = 60
	_pause_btn.add_theme_color_override("font_color", PARCHMENT)
	_pause_btn.pressed.connect(func(): toggle_pause())
	root.add_child(_pause_btn)

	var fps := Label.new()
	fps.name = "Fps"
	fps.position = Vector2(24, 560)
	fps.add_theme_font_size_override("font_size", 14)
	fps.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	fps.visible = false
	root.add_child(fps)
	Perf.overlay = fps

func _mk_label(parent: Control, pos: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _build_minimap_texture() -> void:
	var t := Terrain.new()
	t._load_heightmap()
	if not t.loaded:
		t.free(); return
	var img := Image.create(481, 481, false, Image.FORMAT_RGB8)
	var splat: Image = null
	if ResourceLoader.exists("res://assets/terrain/splat.png"):
		var st := load("res://assets/terrain/splat.png") as Texture2D
		if st: splat = st.get_image()
	for z in 481:
		for x in 481:
			var h := t.heights[z * 481 + x]
			var c := Color(0.30, 0.36, 0.22).lerp(Color(0.55, 0.55, 0.50), clampf(h / 22.0, 0.0, 1.0))
			if h <= t.water_level + 0.1: c = Color(0.10, 0.20, 0.28)
			if splat != null:
				var s := splat.get_pixel(x, z)
				if s.r > 0.35: c = c.lerp(Color(0.42, 0.34, 0.22), clampf(s.r, 0.0, 1.0) * 0.8)
			img.set_pixel(x, z, c)
	_minimap = ImageTexture.create_from_image(img)
	t.free()

func _process(delta: float) -> void:
	if player == null: return
	_dmg_flash = maxf(0.0, _dmg_flash - delta * 1.8)
	_deflect_flash = maxf(0.0, _deflect_flash - delta * 2.4)
	_hit_flash = maxf(0.0, _hit_flash - delta * 3.0)
	_zone_banner = maxf(0.0, _zone_banner - delta)
	_obj_label.text = Quests.current_objective_text()
	_quest_title.text = "◆ " + Quests.current_title()
	var zt: String = String(Game.ZONE_TITLE.get(Game.zone, Game.zone))
	_zone_label.text = "❖ " + zt
	if world != null:
		var t: float = world.time_of_day
		_time_label.text = "%02d:%02d" % [int(t), int((t - floor(t)) * 60.0)]
		var dbt := player.deathblow_available()
		_db_prompt.text = "DEATHBLOW — press Interact" if dbt != null else ""
	_prompt_label.text = world.current_prompt()
	_stance_label.text = "STANCE  %s" % String(Game.stance_info()["name"]).to_upper()
	_paint.queue_redraw()

func _on_notice(text: String, kind: String) -> void:
	match kind:
		"zone": _zone_banner = 3.2; _zone_text = text
		"death", "quest", "reward", "checkpoint", "focus", "warn": _toast(text, _notice_color(kind))

func _notice_color(kind: String) -> Color:
	match kind:
		"death", "warn": return VERMILION
		"quest", "reward": return GOLD
		"focus": return SPIRIT
	return PARCHMENT

func _on_toast(text: String) -> void:
	_toast(text, PARCHMENT)

func _toast(text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	_toast_box.add_child(l)
	_toasts.append(l)
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func():
		_toasts.erase(l)
		if is_instance_valid(l): l.queue_free())
	while _toasts.size() > 4:
		var old: Label = _toasts.pop_front()
		if is_instance_valid(old): old.queue_free()

func _on_zone(z: String) -> void:
	_zone_banner = 3.4
	_zone_text = "%s — %s" % [Game.ZONE_TITLE.get(z, z), ""]

func damage_flash(v: float) -> void:
	_dmg_flash = minf(1.0, _dmg_flash + 0.4 + v / 60.0)

func deflect_flash() -> void:
	_deflect_flash = 1.0

func flash_hit() -> void:
	_hit_flash = 0.8

func notify_posture_break(enemy) -> void:
	_toast("Posture broken", GOLD)

func toggle_pause() -> void:
	_paused = not _paused
	if _pause_menu == null:
		_pause_menu = load("res://ui/PauseMenu.gd").new()
		add_child(_pause_menu)
	_pause_menu.visible = _paused
	get_tree().paused = _paused
	Audio.play_ui()

# ---------------------------------------------------------------- drawing
func draw_all(c: Control) -> void:
	var sz := c.get_viewport_rect().size
	_draw_bars(c, sz)
	_draw_enemy_bars(c, sz)
	_draw_minimap(c, sz)
	_draw_vignette(c, sz)
	_draw_stance(c, sz)
	_draw_banner(c, sz)
	_layout(sz)

func _layout(sz: Vector2) -> void:
	_prompt_label.position = Vector2(sz.x * 0.5 - 160, sz.y - 168)
	_db_prompt.position = Vector2(sz.x * 0.5 - 220, sz.y - 208)
	_stance_label.position = Vector2(sz.x - 210, sz.y - 96)
	_time_label.position = Vector2(sz.x - 96, 22)
	_notice_label.position = Vector2(sz.x * 0.5 - 260, 74)
	_notice_label.size = Vector2(520, 30)

func _panel(c: Control, r: Rect2, col: Color) -> void:
	c.draw_rect(r, col, true)
	c.draw_rect(r, GOLD * Color(1, 1, 1, 0.5), false, 1.0)

func _draw_bars(c: Control, sz: Vector2) -> void:
	if player == null: return
	var r := Rect2(24, 48, 286, 20)
	_panel(c, r.grow(4.0), INK)
	var hp := clampf(player.hp_ratio(), 0.0, 1.0)
	c.draw_rect(Rect2(r.position + Vector2(2, 2), Vector2((r.size.x - 4) * hp, r.size.y - 4)),
		Color(0.62, 0.13, 0.11).lerp(Color(0.85, 0.35, 0.20), hp * 0.4), true)
	# posture
	var pr := Rect2(24, 76, 286, 10)
	_panel(c, pr.grow(3.0), INK)
	var po := clampf(player.posture / player.max_posture, 0.0, 1.0)
	c.draw_rect(Rect2(pr.position + Vector2(2, 2), Vector2((pr.size.x - 4) * po, pr.size.y - 4)),
		Color(0.85, 0.72, 0.30), true)
	for i in range(1, 5):
		var x := pr.position.x + pr.size.x * (float(i) / 5.0)
		c.draw_line(Vector2(x, pr.position.y), Vector2(x, pr.position.y + pr.size.y), Color(0, 0, 0, 0.55), 1.0)
	# focus
	for i in 6:
		var p := Vector2(26 + i * 34, 100)
		var filled := (player.focus / player.max_focus) > float(i) / 6.0
		c.draw_rect(Rect2(p, Vector2(28, 8)), SPIRIT if filled else Color(0.2, 0.25, 0.3, 0.8), true)
		c.draw_rect(Rect2(p, Vector2(28, 8)), GOLD * Color(1, 1, 1, 0.5), false, 1.0)

func _draw_enemy_bars(c: Control, sz: Vector2) -> void:
	if player == null: return
	var t := player.locked_target()
	if t == null or not is_instance_valid(t): return
	var w := 340.0
	var x := sz.x * 0.5 - w * 0.5
	var r := Rect2(x, sz.y - 268, w, 14)
	_panel(c, r.grow(4.0), INK)
	var hp := clampf(t.hp_ratio(), 0.0, 1.0)
	c.draw_rect(Rect2(r.position + Vector2(2, 2), Vector2((r.size.x - 4) * hp, r.size.y - 4)), Color(0.66, 0.14, 0.12), true)
	var pr := Rect2(x, sz.y - 250, w, 8)
	_panel(c, pr.grow(3.0), INK)
	var po := clampf(t.posture_ratio(), 0.0, 1.0)
	c.draw_rect(Rect2(pr.position + Vector2(2, 2), Vector2((pr.size.x - 4) * po, pr.size.y - 4)),
		Color(0.95, 0.55, 0.15) if not t.posture_broken else Color(0.4, 0.9, 1.0), true)
	c.draw_string(ThemeDB.fallback_font, Vector2(x + 2, sz.y - 278),
		"%s%s" % [t.display_name(), "  ◆ BROKEN" if t.posture_broken else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, PARCHMENT)

func _draw_minimap(c: Control, sz: Vector2) -> void:
	if _minimap == null or player == null: return
	var center := Vector2(sz.x - 96, 150)
	var radius := float(_mm_size) * 0.5
	c.draw_circle(center, radius + 5.0, INK_SOLID)
	c.draw_arc(center, radius + 4.0, 0.0, TAU, 48, GOLD, 2.0)
	# terrain region around the player, rotated to camera yaw
	var span := 220.0
	var px := player.global_position.x
	var pz := player.global_position.z
	var u0 := clampf((px - span * 0.5) / 480.0, 0.0, 1.0)
	var v0 := clampf((pz - span * 0.5) / 480.0, 0.0, 1.0)
	var u1 := clampf((px + span * 0.5) / 480.0, 0.0, 1.0)
	var v1 := clampf((pz + span * 0.5) / 480.0, 0.0, 1.0)
	var region := Rect2(Vector2(u0 * 481.0, v0 * 481.0), Vector2((u1 - u0) * 481.0, (v1 - v0) * 481.0))
	var yaw := 0.0
	if world != null and world.camera != null: yaw = world.camera.get_yaw()
	c.draw_set_transform(center, -yaw, Vector2.ONE)
	c.draw_texture_rect_region(_minimap, Rect2(Vector2(-radius, -radius), Vector2(radius * 2, radius * 2)), region)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# markers
	if world != null:
		for e in world.enemies:
			if not is_instance_valid(e) or e.is_dead: continue
			var d: Vector2 = Vector2(e.global_position.x - px, e.global_position.z - pz)
			if d.length() > span * 0.5: continue
			var p := center + d.rotated(-yaw) * (radius / (span * 0.5))
			c.draw_circle(p, 3.2, Color(0.95, 0.25, 0.2))
	# player arrow
	c.draw_circle(center, 4.0, Color(0.98, 0.95, 0.85))
	var fwd := Vector2(0, -1).rotated(-player.rotation.y + yaw)
	c.draw_line(center, center + fwd * 10.0, GOLD, 2.0)
	c.draw_string(ThemeDB.fallback_font, center + Vector2(-radius, radius + 20),
		Game.ZONE_TITLE.get(Game.zone, Game.zone), HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 14, PARCHMENT)

func _draw_stance(c: Control, sz: Vector2) -> void:
	var r := Rect2(sz.x - 220, sz.y - 108, 196, 68)
	_panel(c, r, INK)
	var keys := Game.unlocked_stances
	var i := 0
	for k in keys:
		var p := r.position + Vector2(14 + i * 44, 14)
		var active := k == Game.stance
		c.draw_rect(Rect2(p, Vector2(36, 36)), (VERMILION if active else Color(0.14, 0.15, 0.18, 0.9)), true)
		c.draw_rect(Rect2(p, Vector2(36, 36)), GOLD, false, 1.0)
		c.draw_string(ThemeDB.fallback_font, p + Vector2(6, 25), String(Game.STANCE_INFO[k]["name"]).substr(0, 2).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, PARCHMENT if active else Color(0.6, 0.6, 0.65))
		i += 1

func _draw_banner(c: Control, sz: Vector2) -> void:
	if _zone_banner <= 0.0: return
	var a := clampf(_zone_banner / 1.2, 0.0, 1.0)
	var y := sz.y * 0.26
	var w := 620.0
	var x := sz.x * 0.5 - w * 0.5
	c.draw_rect(Rect2(x, y, w, 62), Color(0.03, 0.03, 0.04, 0.55 * a), true)
	c.draw_line(Vector2(x, y), Vector2(x + w, y), GOLD * Color(1, 1, 1, a), 1.5)
	c.draw_line(Vector2(x, y + 62), Vector2(x + w, y + 62), GOLD * Color(1, 1, 1, a), 1.5)
	c.draw_string(ThemeDB.fallback_font, Vector2(x, y + 40), _zone_text,
		HORIZONTAL_ALIGNMENT_CENTER, w, 26, PARCHMENT * Color(1, 1, 1, a))

func _draw_vignette(c: Control, sz: Vector2) -> void:
	if _dmg_flash > 0.01:
		var col := Color(0.75, 0.06, 0.05, 0.30 * _dmg_flash)
		c.draw_rect(Rect2(Vector2.ZERO, sz), col, true)
	if _deflect_flash > 0.01:
		c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.85, 0.95, 1.0, 0.10 * _deflect_flash), true)
	if player != null and player.hp_ratio() < 0.3:
		var pulse := 0.18 + 0.12 * sin(Time.get_ticks_msec() / 320.0)
		c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.5, 0.0, 0.0, pulse * 0.35), true)
