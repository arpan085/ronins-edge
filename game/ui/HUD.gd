extends CanvasLayer
## v13 HUD: modern and low-clutter. Soft translucent capsules, clean sans type
## (Noto Sans) and a Mincho title face with kanji for places, stances, weapons.
##   top-left       quest tracker and toasts
##   top-right      radar (terrain map, objective, enemies, horse, north), zone, time
##   bottom-left    weapon emblem with the focus ring, health with a trailing damage
##                  ghost, stamina (fades when full), horse stamina while riding
##   bottom-centre  Sekiro-style posture bar growing from the middle; prompts
##   bottom-right   stance wheel
##   over enemies   small health/posture bars in a fight; lock/boss bar top-centre
## Everything is drawn by one Control in _draw(); all sizes scale with height.

const GOLD := Color(0.89, 0.75, 0.46)
const INK := Color(0.02, 0.025, 0.035, 0.52)
const INK_SOLID := Color(0.035, 0.04, 0.05, 0.84)
const VERMILION := Color(0.84, 0.20, 0.15)
const PARCHMENT := Color(0.96, 0.93, 0.87)
const MUTED := Color(0.74, 0.72, 0.68)
const SPIRIT := Color(0.47, 0.82, 1.0)
const HP_A := Color(0.66, 0.10, 0.10)
const HP_B := Color(0.92, 0.30, 0.21)
const STAM := Color(0.96, 0.89, 0.70)
const HORSE_COL := Color(0.83, 0.64, 0.40)
const BANNER_T := 4.4

const ZONE_KANJI := {"shrine": "桜神社", "forest": "竹林", "village": "川村", "castle": "城跡",
	"mountain": "峠", "bamboo": "竹林", "grassland": "草原", "farmland": "田畑", "ruins": "遺跡",
	"lake": "湖畔"}
const STANCE_KANJI := {"stone": "岩", "water": "水", "wind": "風", "moon": "月"}
const WEAPON_KANJI := {"katana": "刀", "nodachi": "野太刀", "yari": "槍", "fists": "拳"}

var world: World
var player: Player
var f_reg: Font
var f_semi: Font
var f_bold: Font
var f_title: Font
var _paint: Painter
var _toast_box: VBoxContainer
var _pause_btn: Button
var _prompt_text := ""
var _minimap: Texture2D
var _mm_res := 256
var _mm_world := 1536.0
var _dmg_flash := 0.0
var _deflect_flash := 0.0
var _hit_flash := 0.0
var _zone_banner := 0.0
var _zone_id := ""
var _zone_title := ""
var _zone_hint := ""
var _toasts: Array = []
var _paused := false
var _pause_menu: Node
var _map: WorldMap
var _hp_ghost := 1.0
var _hp_hold := 0.0
var _hp_last := 1.0
var _heal_glow := 0.0
var _stam_alpha := 1.0
var _stam_full_t := 0.0
var _posture_show := 0.0
var _enemy_ghost := {}
var _death_t := -1.0
var _span := 130.0
var _k := 1.0
var _vignette: GradientTexture2D
var _sb := StyleBoxFlat.new()
var f_kanji: Font
var _skills: Node = null
var _peril_t := 0.0
var _mastery_pending := 0
var _mastery_t := 0.0

class Painter extends Control:
	var hud: CanvasLayer
	func _draw() -> void:
		if hud != null: hud.draw_all(self)

func _ready() -> void:
	layer = 10
	f_reg = _font("res://assets/fonts/UI-Regular.ttf")
	f_semi = _font("res://assets/fonts/UI-SemiBold.ttf")
	f_bold = _font("res://assets/fonts/UI-ExtraBold.ttf")
	f_title = _font("res://assets/fonts/Title.ttf")
	f_kanji = _font("res://assets/fonts/Kanji.ttf")
	_sb.anti_aliasing = true
	_sb.corner_detail = 8
	_build_vignette()
	_paint = Painter.new()
	_paint.hud = self
	_paint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_paint)
	_build_nodes()
	_build_minimap_texture()
	Game.notice.connect(_on_notice)
	Quests.objective_toast.connect(_on_toast)
	Game.zone_changed.connect(_on_zone)
	Game.mastery_gained.connect(_on_mastery)

func _font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f = load(path)
		if f is Font: return f
	return ThemeDB.fallback_font

func bind(w: World) -> void:
	world = w
	player = w.player
	if player != null:
		player.lock_changed.connect(func(t): if w.camera != null: w.camera.set_lock(t))
		player.died.connect(_on_player_died)
	w.prompt_changed.connect(func(t): _prompt_text = t)

func _build_vignette() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.52, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0)])
	_vignette = GradientTexture2D.new()
	_vignette.gradient = g
	_vignette.fill = GradientTexture2D.FILL_RADIAL
	_vignette.fill_from = Vector2(0.5, 0.5)
	_vignette.fill_to = Vector2(1.2, 0.5)
	_vignette.width = 256
	_vignette.height = 256

func _build_nodes() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_toast_box = VBoxContainer.new()
	_toast_box.position = Vector2(30, 112)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.add_theme_constant_override("separation", 6)
	root.add_child(_toast_box)
	_pause_btn = Button.new()
	_pause_btn.text = "II"
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_pause_btn.custom_minimum_size = Vector2(40, 40)
	_pause_btn.size = Vector2(40, 40)
	_pause_btn.add_theme_font_override("font", f_bold)
	_pause_btn.add_theme_font_size_override("font_size", 15)
	_pause_btn.add_theme_color_override("font_color", PARCHMENT)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.035, 0.045, 0.55 if st == "normal" else 0.8)
		sb.set_corner_radius_all(20)
		sb.border_color = GOLD * Color(1, 1, 1, 0.35 if st == "normal" else 0.8)
		sb.set_border_width_all(1)
		sb.anti_aliasing = true
		_pause_btn.add_theme_stylebox_override(st, sb)
	_pause_btn.tooltip_text = "Pause"
	_pause_btn.pressed.connect(func(): toggle_pause())
	root.add_child(_pause_btn)
	var fps := Label.new()
	fps.name = "Fps"
	fps.position = Vector2(30, 560)
	fps.add_theme_font_override("font", f_semi)
	fps.add_theme_font_size_override("font_size", 13)
	fps.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	fps.visible = false
	root.add_child(fps)
	Perf.overlay = fps

## The radar map is baked offline (tools/bake_minimap.py: biomes, hillshade,
## contours, roads, the river, buildings). If it is missing, a plain height
## map is baked here from the terrain data instead.
func _build_minimap_texture() -> void:
	var t := Terrain.new()
	t._load_data()
	_mm_world = t.size
	if ResourceLoader.exists("res://assets/terrain/minimap.png"):
		_minimap = load("res://assets/terrain/minimap.png")
		t.free()
		return
	if not t._load_heightmap():
		t.free(); return
	var g: int = t.grid
	var res: int = _mm_res
	var img := Image.create(res, res, false, Image.FORMAT_RGB8)
	for py in res:
		var gz: int = clampi(int(float(py) / float(res - 1) * float(g - 1)), 0, g - 1)
		for px in res:
			var gx: int = clampi(int(float(px) / float(res - 1) * float(g - 1)), 0, g - 1)
			var h: float = t.heights[gz * g + gx]
			var c := Color(0.10, 0.20, 0.27)
			if h > t.water_level:
				var a: float = clampf((h - t.water_level) / 60.0, 0.0, 1.0)
				c = Color(0.27, 0.33, 0.21).lerp(Color(0.55, 0.54, 0.50), a)
				var hx: float = t.heights[gz * g + mini(gx + 1, g - 1)]
				var hz: float = t.heights[mini(gz + 1, g - 1) * g + gx]
				var sl: float = clampf(((h - hx) + (h - hz)) * 0.10, -0.35, 0.35)
				c = c.lerp(Color(1, 1, 1) if sl > 0.0 else Color(0, 0, 0), absf(sl))
			img.set_pixel(px, py, c)
	_minimap = ImageTexture.create_from_image(img)
	t.free()

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	if player == null: return
	_dmg_flash = maxf(0.0, _dmg_flash - delta * 1.6)
	_deflect_flash = maxf(0.0, _deflect_flash - delta * 2.4)
	_hit_flash = maxf(0.0, _hit_flash - delta * 3.0)
	_heal_glow = maxf(0.0, _heal_glow - delta * 1.5)
	_zone_banner = maxf(0.0, _zone_banner - delta)
	if _death_t >= 0.0:
		_death_t += delta
		if _death_t > 3.6: _death_t = -1.0
	# health: the lost chunk lingers pale, then drains after it
	var hp := clampf(player.hp_ratio(), 0.0, 1.0)
	if hp < _hp_last - 0.0005: _hp_hold = 0.6
	elif hp > _hp_last + 0.0005: _heal_glow = 1.0
	_hp_last = hp
	if _hp_ghost < hp: _hp_ghost = hp
	elif _hp_hold > 0.0: _hp_hold -= delta
	else: _hp_ghost = move_toward(_hp_ghost, hp, delta * 0.55)
	# stamina fades back once it has been full for a moment
	var st: float = player.stamina_ratio() if player.has_method("stamina_ratio") else 1.0
	if st >= 0.999 and not bool(player.get("winded")): _stam_full_t += delta
	else: _stam_full_t = 0.0
	_stam_alpha = move_toward(_stam_alpha, 0.22 if _stam_full_t > 1.6 else 1.0, delta * 3.0)
	var pr := player.posture / maxf(player.max_posture, 1.0)
	_posture_show = move_toward(_posture_show, 1.0 if pr > 0.01 else 0.0, delta * (4.0 if pr > 0.01 else 1.5))
	if world != null: _prompt_text = world.current_prompt()
	if Input.is_action_just_pressed("map"): open_map()
	if InputMap.has_action("skills") and Input.is_action_just_pressed("skills"): open_skills()
	_peril_t = maxf(0.0, _peril_t - delta)
	if _mastery_t > 0.0:
		_mastery_t -= delta
		if _mastery_t <= 0.0 and _mastery_pending > 0:
			_toast("+%d mastery  ·  %s: techniques (%d to spend)" % [_mastery_pending, Game.bind_label("skills"), Game.mastery_points], GOLD)
			_mastery_pending = 0
	# radar zooms out at speed
	var spd := Vector2(player.velocity.x, player.velocity.z).length()
	_span = lerpf(_span, lerpf(120.0, 210.0, clampf((spd - 4.0) / 8.0, 0.0, 1.0)), clampf(delta * 1.5, 0.0, 1.0))
	var sz := _paint.get_viewport_rect().size
	_k = clampf(sz.y / 720.0, 0.75, 2.2)
	_toast_box.position = Vector2(30.0 * _k, 104.0 * _k)
	var rr := 68.0 * _k
	_pause_btn.position = Vector2(sz.x - 30.0 * _k - rr * 2.0 - 52.0 * _k, 28.0 * _k)
	_paint.queue_redraw()

func _on_notice(text: String, kind: String) -> void:
	match kind:
		"zone": pass          # the banner comes from zone_changed
		"death": pass         # the death screen says it
		"quest", "reward", "checkpoint", "focus", "warn", "tip": _toast(text, _notice_color(kind))

func _notice_color(kind: String) -> Color:
	match kind:
		"death", "warn": return Color(1.0, 0.55, 0.45)
		"quest", "reward": return GOLD
		"focus": return SPIRIT
	return PARCHMENT

func _on_toast(text: String) -> void:
	_toast(text, PARCHMENT)

func _toast(text: String, col: Color) -> void:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.025, 0.035, 0.62)
	sb.set_corner_radius_all(int(6 * _k))
	sb.border_width_left = maxi(2, int(3 * _k))
	sb.border_color = col if col != PARCHMENT else GOLD * Color(1, 1, 1, 0.7)
	sb.content_margin_left = 12 * _k
	sb.content_margin_right = 14 * _k
	sb.content_margin_top = 4 * _k
	sb.content_margin_bottom = 5 * _k
	sb.anti_aliasing = true
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", f_semi)
	l.add_theme_font_size_override("font_size", int(15 * _k))
	l.add_theme_color_override("font_color", col)
	p.add_child(l)
	p.modulate.a = 0.0
	_toast_box.add_child(p)
	_toasts.append(p)
	# bound to the toast so a toast pushed out early takes its tween with it
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(3.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func():
		_toasts.erase(p)
		if is_instance_valid(p): p.queue_free())
	while _toasts.size() > 4:
		var old: Control = _toasts.pop_front()
		if is_instance_valid(old): old.queue_free()

func _on_zone(z: String) -> void:
	_zone_banner = BANNER_T
	_zone_id = z
	_zone_title = String(Game.ZONE_TITLE.get(z, z))
	_zone_hint = Game._zone_hint(z)

func _on_player_died() -> void:
	_death_t = 0.0

func damage_flash(v: float) -> void:
	_dmg_flash = minf(1.0, _dmg_flash + 0.35 + v / 60.0)

func deflect_flash() -> void:
	_deflect_flash = 1.0

func flash_hit() -> void:
	_hit_flash = 0.8

func notify_posture_break(_enemy) -> void:
	_toast("Posture broken", GOLD)

func toggle_pause() -> void:
	set_paused(not _paused)

## One place that pauses/unpauses: the tree, the menu and the mouse cursor.
func set_paused(on: bool) -> void:
	_paused = on
	if _pause_menu == null:
		# own top layer: nothing drawn above the menu can steal its clicks
		var cl := CanvasLayer.new()
		cl.layer = 50
		cl.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(cl)
		_pause_menu = load("res://ui/PauseMenu.gd").new()
		_pause_menu.hud = self
		cl.add_child(_pause_menu)
	_pause_menu.visible = on
	get_tree().paused = on
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not OS.has_feature("mobile"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Audio.play_ui()

func is_paused() -> bool:
	return _paused

## v0.15 world map (ui/WorldMap.gd): its own layer above the HUD, pauses the
## game while it is open and closes itself on M / Esc.
func open_map() -> void:
	if get_tree().paused or _death_t >= 0.0: return
	if player != null and bool(player.get("cinematic")): return
	if _map == null:
		var cl := CanvasLayer.new()
		cl.layer = 45
		cl.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(cl)
		_map = WorldMap.new()
		_map.hud = self
		cl.add_child(_map)
	_map.open()

func is_map_open() -> bool:
	return _map != null and _map.is_open()

## v0.16 techniques screen (ui/SkillsMenu.gd), same pattern as the map.
func open_skills() -> void:
	if get_tree().paused or _death_t >= 0.0: return
	if player != null and bool(player.get("cinematic")): return
	if _skills == null:
		var cl := CanvasLayer.new()
		cl.layer = 46
		cl.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(cl)
		_skills = load("res://ui/SkillsMenu.gd").new()
		_skills.hud = self
		cl.add_child(_skills)
	_skills.open()

func is_skills_open() -> bool:
	return _skills != null and _skills.is_open()

func perilous_flash(_e) -> void:
	_peril_t = 0.9

func _on_mastery(v: int) -> void:
	_mastery_pending += v
	_mastery_t = 1.0

# ---------------------------------------------------------------- primitives
func _cap(c: Control, r: Rect2, col: Color, radius := -1.0) -> void:
	if r.size.x < 1.0 or r.size.y < 0.5 or col.a <= 0.003: return
	var rad := r.size.y * 0.5 if radius < 0.0 else radius
	_sb.bg_color = col
	_sb.set_corner_radius_all(int(round(minf(rad, r.size.x * 0.5))))
	_sb.set_border_width_all(0)
	c.draw_style_box(_sb, r)

func _text(c: Control, font: Font, pos: Vector2, s: String, size: int, col: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 4) -> void:
	if s == "" or col.a <= 0.003: return
	if outline > 0:
		c.draw_string_outline(font, pos, s, align, width, size, outline, Color(0, 0, 0, 0.5 * col.a))
	c.draw_string(font, pos, s, align, width, size, col)

## Letter-spaced line centred on cx.
func _spaced(c: Control, font: Font, cx: float, y: float, s: String, size: int, col: Color, spacing: float, outline := 4) -> void:
	var widths := []
	var total := 0.0
	for ch in s:
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		widths.append(w)
		total += w + spacing
	total -= spacing
	var x := cx - total * 0.5
	var i := 0
	for ch in s:
		_text(c, font, Vector2(x, y), ch, size, col, HORIZONTAL_ALIGNMENT_LEFT, -1.0, outline)
		x += float(widths[i]) + spacing
		i += 1

func _centered(c: Control, font: Font, center: Vector2, s: String, size: int, col: Color, outline := 0) -> void:
	var ts := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var asc := font.get_ascent(size)
	var desc := font.get_descent(size)
	_text(c, font, Vector2(center.x - ts.x * 0.5, center.y + (asc - desc) * 0.5), s, size, col, HORIZONTAL_ALIGNMENT_LEFT, -1.0, outline)

func _diamond(c: Control, p: Vector2, r: float, col: Color, outline := true) -> void:
	var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)])
	if outline:
		var o := r + 1.6 * _k
		c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -o), p + Vector2(o, 0), p + Vector2(0, o), p + Vector2(-o, 0)]), Color(0, 0, 0, 0.55 * col.a))
	c.draw_colored_polygon(pts, col)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

# ---------------------------------------------------------------- drawing
func draw_all(c: Control) -> void:
	var sz := c.get_viewport_rect().size
	_draw_vignette(c, sz)
	if player == null: return
	_draw_enemy_overhead(c, sz)
	_draw_awareness(c, sz)
	_draw_target_bar(c, sz)
	_draw_quest(c, sz)
	_draw_radar(c, sz)
	_draw_vitals(c, sz)
	_draw_posture(c, sz)
	_draw_prompts(c, sz)
	_draw_perilous(c, sz)
	_draw_stealth(c, sz)
	_draw_stance(c, sz)
	_draw_banner(c, sz)
	_draw_death(c, sz)

func _draw_vitals(c: Control, sz: Vector2) -> void:
	var k := _k
	var t := _now()
	var ec := Vector2(30.0 * k + 30.0 * k, sz.y - 70.0 * k)
	var er := 28.0 * k
	# emblem: weapon kanji, focus fills the ring around it
	c.draw_circle(ec, er + 8.0 * k, Color(0, 0, 0, 0.28))
	c.draw_circle(ec, er, INK_SOLID)
	c.draw_arc(ec, er, 0.0, TAU, 56, GOLD * Color(1, 1, 1, 0.45), 1.2 * k, true)
	var wk: String = WEAPON_KANJI.get(player.weapon, "刀")
	var drawn := player.drawn or player.weapon == "fists"
	_centered(c, f_title, ec + Vector2(0, -1.0 * k), wk, int((27.0 if wk.length() == 1 else 13.0) * k),
		PARCHMENT if drawn else MUTED, 0)
	var fr := clampf(player.focus / maxf(player.max_focus, 1.0), 0.0, 1.0)
	c.draw_arc(ec, er + 4.5 * k, 0.0, TAU, 64, Color(0.1, 0.14, 0.18, 0.7), 3.0 * k, true)
	if fr > 0.001:
		var fcol := SPIRIT
		if fr >= 1.0: fcol = SPIRIT.lerp(Color(1, 1, 1), 0.25 + 0.25 * sin(t * 5.0))
		c.draw_arc(ec, er + 4.5 * k, -PI * 0.5, -PI * 0.5 + TAU * fr, 64, fcol, 3.0 * k, true)
	var wname := String(player.weapon_name()).to_upper()
	_spaced(c, f_bold, ec.x, ec.y + er + 20.0 * k, wname, int(10.0 * k), GOLD * Color(1, 1, 1, 0.9), 1.6 * k, 3)
	# health
	var x0 := ec.x + er + 16.0 * k
	var hw := 300.0 * k * clampf(player.max_hp / 100.0, 0.6, 1.6)
	var hh := 10.0 * k
	var hy := ec.y - 12.0 * k
	var hp := clampf(player.hp_ratio(), 0.0, 1.0)
	_cap(c, Rect2(x0 - 2.0 * k, hy - 2.0 * k, hw + 4.0 * k, hh + 4.0 * k), Color(0, 0, 0, 0.42))
	_cap(c, Rect2(x0, hy, hw, hh), Color(0.16, 0.12, 0.12, 0.72))
	_cap(c, Rect2(x0, hy, hw * _hp_ghost, hh), Color(1.0, 0.86, 0.74, 0.5))
	var hcol := HP_A.lerp(HP_B, 0.3 + 0.35 * hp)
	if hp < 0.3: hcol = hcol.lerp(Color(1.0, 0.42, 0.3), 0.2 + 0.2 * sin(t * 6.0))
	if _heal_glow > 0.0: hcol = hcol.lerp(Color(1.0, 0.9, 0.7), _heal_glow * 0.5)
	_cap(c, Rect2(x0, hy, hw * hp, hh), hcol)
	_cap(c, Rect2(x0 + 3.0 * k, hy + 1.2 * k, maxf(0.0, hw * hp - 6.0 * k), hh * 0.34), Color(1, 1, 1, 0.14))
	var hp_txt := "%d" % int(ceil(player.hp))
	_text(c, f_bold, Vector2(x0, hy - 5.0 * k), hp_txt, int(13.0 * k), PARCHMENT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 3)
	var tw := f_bold.get_string_size(hp_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(13.0 * k)).x
	_text(c, f_semi, Vector2(x0 + tw + 4.0 * k, hy - 5.0 * k), "/ %d" % int(player.max_hp), int(11.0 * k), MUTED, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 3)
	_draw_gourd(c, Vector2(x0 + hw + 22.0 * k, hy + hh * 0.5 + 1.0 * k), k, t)
	if Skills.has("s_smoke"):
		_draw_smoke(c, Vector2(x0 + hw + 22.0 * k + (34.0 + float(Game.gourd_max) * 9.0) * k, hy + hh * 0.5 + 1.0 * k), k)
	# stamina
	var st: float = player.stamina_ratio() if player.has_method("stamina_ratio") else 1.0
	var winded := bool(player.get("winded"))
	var flash := float(player.get("_stamina_flash")) if "_stamina_flash" in player else 0.0
	var sw := 236.0 * k * clampf(float(player.get("max_stamina")) / 100.0 if "max_stamina" in player else 1.0, 0.6, 1.6)
	var sh := 5.0 * k
	var sy := hy + hh + 8.0 * k
	var sa := maxf(_stam_alpha, clampf(flash * 2.0, 0.0, 1.0))
	_cap(c, Rect2(x0 - 1.5 * k, sy - 1.5 * k, sw + 3.0 * k, sh + 3.0 * k), Color(0, 0, 0, 0.4 * sa))
	_cap(c, Rect2(x0, sy, sw, sh), Color(0.16, 0.15, 0.13, 0.7 * sa))
	var scol := STAM
	if winded: scol = Color(1.0, 0.45, 0.3).lerp(STAM, 0.3 + 0.3 * sin(t * 9.0))
	if flash > 0.0:
		_cap(c, Rect2(x0 - 3.0 * k, sy - 3.0 * k, sw + 6.0 * k, sh + 6.0 * k), Color(1.0, 0.35, 0.25, 0.35 * clampf(flash, 0.0, 1.0)))
	_cap(c, Rect2(x0, sy, sw * st, sh), scol * Color(1, 1, 1, sa))
	# horse stamina while riding
	if player.is_mounted() and world != null and world.horse != null and world.horse.has_method("stamina_ratio"):
		var hs: float = world.horse.stamina_ratio()
		var hy2 := sy + sh + 9.0 * k
		_text(c, f_bold, Vector2(x0, hy2 + 6.0 * k), "HORSE", int(9.0 * k), MUTED, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 2)
		var hx := x0 + 44.0 * k
		var hww := 150.0 * k
		_cap(c, Rect2(hx, hy2, hww, 5.0 * k), Color(0.16, 0.13, 0.1, 0.72))
		var hcol2 := HORSE_COL
		if bool(world.horse.get("winded")): hcol2 = Color(1.0, 0.45, 0.3).lerp(HORSE_COL, 0.35 + 0.3 * sin(t * 7.0))
		_cap(c, Rect2(hx, hy2, hww * hs, 5.0 * k), hcol2)
	# focus ready hint
	if fr >= 1.0:
		_text(c, f_bold, Vector2(x0, sy + sh + (34.0 if player.is_mounted() else 20.0) * k),
			"%s  SPIRIT BLADE READY" % Game.bind_label("special"), int(11.0 * k), SPIRIT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 3)

## v0.15 healing gourd: a little hyotan with one pip per drink and its key.
func _draw_gourd(c: Control, p: Vector2, k: float, t: float) -> void:
	var n := int(Game.gourd)
	var nmax := int(Game.gourd_max)
	var full := n > 0
	var glow := float(player.get("heal_glow")) if "heal_glow" in player else 0.0
	var body := Color(0.80, 0.58, 0.26) if full else Color(0.34, 0.30, 0.26)
	if glow > 0.0: body = body.lerp(Color(0.75, 1.0, 0.6), glow * 0.6)
	var hurt := player.hp < player.max_hp * 0.5 and full
	if hurt: body = body.lerp(Color(1.0, 0.9, 0.6), 0.25 + 0.25 * sin(t * 4.0))
	# shadow, lower bulb, waist cord, upper bulb, stopper
	c.draw_circle(p + Vector2(0, 4.0 * k), 9.0 * k, Color(0, 0, 0, 0.35))
	c.draw_circle(p + Vector2(0, 3.5 * k), 7.5 * k, body)
	c.draw_circle(p + Vector2(0, -5.5 * k), 4.6 * k, body)
	c.draw_line(p + Vector2(-4.0 * k, -1.4 * k), p + Vector2(4.0 * k, -1.4 * k), Color(0.55, 0.12, 0.10), 2.0 * k)
	c.draw_rect(Rect2(p + Vector2(-1.6 * k, -12.5 * k), Vector2(3.2 * k, 3.4 * k)), Color(0.32, 0.22, 0.14))
	c.draw_circle(p + Vector2(-2.4 * k, 1.5 * k), 1.8 * k, Color(1, 1, 1, 0.22 if full else 0.08))
	# pips
	for i in nmax:
		var q := p + Vector2(14.0 * k + float(i) * 9.0 * k, 3.0 * k)
		c.draw_circle(q, 3.2 * k, Color(0, 0, 0, 0.45))
		if i < n: c.draw_circle(q, 2.4 * k, Color(0.96, 0.82, 0.50))
		else: c.draw_arc(q, 2.4 * k, 0.0, TAU, 16, MUTED, 1.0 * k, true)
	_text(c, f_bold, p + Vector2(14.0 * k + float(nmax) * 9.0 * k + 2.0 * k, -2.0 * k),
		Game.bind_label("heal"), int(10.0 * k), PARCHMENT if full else MUTED, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 3)

## Posture: empty and hidden at rest; fills outward from the middle, yellow to red.
func _draw_posture(c: Control, sz: Vector2) -> void:
	if _posture_show < 0.02: return
	var k := _k
	var pr := clampf(player.posture / maxf(player.max_posture, 1.0), 0.0, 1.0)
	var full := 360.0 * k
	var cx := sz.x * 0.5
	var y := sz.y - 42.0 * k
	var h := 6.0 * k
	var a := _posture_show
	_cap(c, Rect2(cx - full * 0.5 - 2.0 * k, y - 2.0 * k, full + 4.0 * k, h + 4.0 * k), Color(0, 0, 0, 0.4 * a))
	_cap(c, Rect2(cx - full * 0.5, y, full, h), Color(0.14, 0.12, 0.1, 0.6 * a))
	var col := Color(1.0, 0.84, 0.38).lerp(Color(1.0, 0.55, 0.16), clampf(pr * 1.6, 0.0, 1.0))
	if pr > 0.78: col = col.lerp(Color(0.98, 0.22, 0.12), clampf((pr - 0.78) / 0.22, 0.0, 1.0))
	var w := full * pr
	_cap(c, Rect2(cx - w * 0.5, y, w, h), col * Color(1, 1, 1, a))
	_cap(c, Rect2(cx - w * 0.5 + 2.0 * k, y + 1.0 * k, maxf(0.0, w - 4.0 * k), h * 0.35), Color(1, 1, 1, 0.18 * a))
	_diamond(c, Vector2(cx, y + h * 0.5), 4.0 * k, GOLD * Color(1, 1, 1, a))

func _draw_prompts(c: Control, sz: Vector2) -> void:
	var k := _k
	if _prompt_text != "":
		var fs := int(15.0 * k)
		var ts := f_semi.get_string_size(_prompt_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var r := Rect2(sz.x * 0.5 - ts.x * 0.5 - 16.0 * k, sz.y - 104.0 * k, ts.x + 32.0 * k, 30.0 * k)
		_cap(c, r, INK, 8.0 * k)
		_text(c, f_semi, Vector2(r.position.x + 16.0 * k, r.position.y + 20.5 * k), _prompt_text, fs, PARCHMENT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 0)
	if _prompt_text == "" and player.has_method("is_swimming") and player.is_swimming():
		var sw := "Swimming  ·  hold %s for a fast stroke" % Game.bind_label("sprint")
		var fs2 := int(14.0 * k)
		var ts2 := f_semi.get_string_size(sw, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2)
		var r2 := Rect2(sz.x * 0.5 - ts2.x * 0.5 - 16.0 * k, sz.y - 104.0 * k, ts2.x + 32.0 * k, 28.0 * k)
		_cap(c, r2, INK, 8.0 * k)
		_text(c, f_semi, Vector2(r2.position.x + 16.0 * k, r2.position.y + 19.5 * k), sw, fs2, PARCHMENT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 0)
	if player.has_method("riposte_ready") and player.riposte_ready():
		var ra := 0.75 + 0.25 * sin(_now() * 9.0)
		var ry := sz.y * 0.60
		_spaced(c, f_title, sz.x * 0.5, ry, "RIPOSTE", int(20.0 * k), Color(1.0, 0.86, 0.55, ra), 5.0 * k, 4)
		_centered(c, f_semi, Vector2(sz.x * 0.5, ry + 19.0 * k), "attack now", int(13.0 * k), PARCHMENT, 3)
	var dbt := player.deathblow_available()
	if dbt != null:
		var t := _now()
		var cy := sz.y * 0.64
		var a := 0.8 + 0.2 * sin(t * 6.0)
		_spaced(c, f_title, sz.x * 0.5, cy, "DEATHBLOW", int(26.0 * k), Color(1.0, 0.82, 0.5, a), 6.0 * k, 5)
		_centered(c, f_semi, Vector2(sz.x * 0.5, cy + 22.0 * k), "press %s" % Game.bind_label("interact"), int(14.0 * k), PARCHMENT, 3)
		return
	# v0.16 assassination / chain / shadow step
	var at: Node3D = player.assassination_target() if player.has_method("assassination_target") else null
	if at != null:
		var t2 := _now()
		var chain := player.state == Player.S.ASSASSIN
		var cy2 := sz.y * 0.64
		var a2 := 0.8 + 0.2 * sin(t2 * 7.0)
		_spaced(c, f_title, sz.x * 0.5, cy2, "CHAIN" if chain else "ASSASSINATE", int(24.0 * k), Color(1.0, 0.42, 0.34, a2), 6.0 * k, 5)
		var keys := Game.bind_label("interact")
		if chain or player.crouching: keys = "%s / %s" % [Game.bind_label("interact"), Game.bind_label("attack")]
		_centered(c, f_semi, Vector2(sz.x * 0.5, cy2 + 22.0 * k), "press %s" % keys, int(14.0 * k), PARCHMENT, 3)
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var top := at.global_position + Vector3(0, 2.25, 0)
			if not cam.is_position_behind(top):
				var sp := cam.unproject_position(top)
				_diamond(c, sp, 7.0 * k * (0.9 + 0.1 * sin(t2 * 9.0)), Color(0.95, 0.25, 0.2, 0.95))
	elif player.has_method("shadow_step_ready") and player.shadow_step_ready():
		var cy3 := sz.y * 0.62
		_spaced(c, f_title, sz.x * 0.5, cy3, "SHADOW STEP", int(22.0 * k), SPIRIT, 5.0 * k, 5)
		_centered(c, f_semi, Vector2(sz.x * 0.5, cy3 + 20.0 * k), "attack now", int(13.0 * k), PARCHMENT, 3)

func _draw_quest(c: Control, sz: Vector2) -> void:
	var k := _k
	var x := 34.0 * k
	var y := 40.0 * k
	var title := Quests.current_title().to_upper()
	c.draw_line(Vector2(x - 12.0 * k, y - 12.0 * k), Vector2(x - 12.0 * k, y + 34.0 * k), GOLD * Color(1, 1, 1, 0.6), 2.0 * k)
	_text(c, f_bold, Vector2(x, y), title, int(12.0 * k), GOLD, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 3)
	_text(c, f_semi, Vector2(x, y + 24.0 * k), Quests.current_objective_text(), int(16.0 * k), PARCHMENT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 4)

func _draw_radar(c: Control, sz: Vector2) -> void:
	var k := _k
	var R := 68.0 * k
	var center := Vector2(sz.x - R - 30.0 * k, R + 30.0 * k)
	var yaw := 0.0
	if world != null and world.camera != null: yaw = world.camera.get_yaw()
	var px := player.global_position.x
	var pz := player.global_position.z
	var mscale := R / _span
	c.draw_circle(center, R + 7.0 * k, Color(0, 0, 0, 0.3))
	c.draw_circle(center, R + 1.0 * k, INK_SOLID)
	if _minimap != null:
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		var wsz := maxf(_mm_world, 1.0)
		for i in 48:
			var a := TAU * float(i) / 48.0
			var o := Vector2(cos(a), sin(a)) * R
			pts.append(center + o)
			var d := o.rotated(-yaw) / mscale
			uvs.append(Vector2((px + d.x) / wsz, (pz + d.y) / wsz))
		c.draw_colored_polygon(pts, Color(1, 1, 1, 0.93), uvs, _minimap)
	# view cone (camera forward is up)
	c.draw_colored_polygon(PackedVector2Array([center, center + Vector2(-0.62, -1.0) * R * 0.85,
		center + Vector2(0.62, -1.0) * R * 0.85]), Color(1, 1, 1, 0.07))
	c.draw_arc(center, R, 0.0, TAU, 72, Color(1, 1, 1, 0.5), 1.4 * k, true)
	c.draw_arc(center, R + 4.0 * k, 0.0, TAU, 72, GOLD * Color(1, 1, 1, 0.35), 1.0 * k, true)
	# enemies
	if world != null:
		for e in world.enemies:
			if not is_instance_valid(e) or e.is_dead: continue
			var d := Vector2(e.global_position.x - px, e.global_position.z - pz)
			if d.length() > _span * 0.97: continue
			var p := center + d.rotated(yaw) * mscale
			var hot := bool(e.in_combat)
			c.draw_circle(p, (3.4 if hot else 2.6) * k, Color(0, 0, 0, 0.5))
			c.draw_circle(p, (2.6 if hot else 1.9) * k, Color(1.0, 0.28, 0.22) if hot else Color(0.9, 0.45, 0.35, 0.8))
		# horse
		if world.horse != null and is_instance_valid(world.horse) and not player.is_mounted():
			var d := Vector2(world.horse.global_position.x - px, world.horse.global_position.z - pz)
			if d.length() > _span * 0.9: d = d.normalized() * _span * 0.9
			var p := center + d.rotated(yaw) * mscale
			c.draw_circle(p, 4.0 * k, Color(0, 0, 0, 0.55))
			c.draw_circle(p, 2.8 * k, HORSE_COL)
	# objective (pinned to the rim when it is off the map)
	var dist := -1.0
	if world != null and world.has_method("objective_position"):
		var op = world.objective_position()
		if op != null:
			var ov: Vector3 = op
			var d := Vector2(ov.x - px, ov.z - pz)
			dist = d.length()
			var s := d.rotated(yaw) * mscale
			var lim := R - 7.0 * k
			if s.length() > lim: s = s.normalized() * lim
			_diamond(c, center + s, 5.5 * k, GOLD)
	# north
	var np := center + Vector2(0, -1).rotated(yaw) * (R + 0.5 * k)
	c.draw_circle(np, 8.0 * k, INK_SOLID)
	_centered(c, f_bold, np, "N", int(10.0 * k), GOLD, 0)
	# player arrow: facing (model +Z) relative to the camera
	var f3 := player.global_transform.basis.z
	var fd := Vector2(f3.x, f3.z).normalized().rotated(yaw)
	var side := Vector2(-fd.y, fd.x)
	var tip := center + fd * 8.0 * k
	var tri := PackedVector2Array([tip, center - fd * 5.0 * k + side * 5.5 * k, center - fd * 2.5 * k, center - fd * 5.0 * k - side * 5.5 * k])
	var tri_o := PackedVector2Array([center + fd * 10.0 * k, center - fd * 6.5 * k + side * 7.0 * k, center - fd * 3.5 * k, center - fd * 6.5 * k - side * 7.0 * k])
	c.draw_colored_polygon(tri_o, Color(0, 0, 0, 0.6))
	c.draw_colored_polygon(tri, Color(1, 0.98, 0.92))
	# zone, time, objective distance
	var ly := center.y + R + 24.0 * k
	_centered(c, f_title, Vector2(center.x, ly), String(Game.ZONE_TITLE.get(Game.zone, Game.zone)), int(16.0 * k), PARCHMENT, 4)
	var info := ""
	if world != null:
		var tod: float = world.time_of_day
		info = "%02d:%02d" % [int(tod), int((tod - floor(tod)) * 60.0)]
	if dist >= 0.0:
		var dtxt := ("%d m" % int(dist)) if dist < 1000.0 else ("%.1f km" % (dist / 1000.0))
		var fs := int(12.0 * k)
		var w1 := f_semi.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var w2 := f_semi.get_string_size(dtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var total := w1 + 22.0 * k + w2
		var x := center.x - total * 0.5
		_text(c, f_semi, Vector2(x, ly + 20.0 * k), info, fs, MUTED, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 3)
		_diamond(c, Vector2(x + w1 + 11.0 * k, ly + 16.0 * k), 3.5 * k, GOLD, false)
		_text(c, f_semi, Vector2(x + w1 + 22.0 * k, ly + 20.0 * k), dtxt, fs, GOLD, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 3)
	else:
		_centered(c, f_semi, Vector2(center.x, ly + 16.0 * k), info, int(12.0 * k), MUTED, 3)

func _draw_stance(c: Control, sz: Vector2) -> void:
	var k := _k
	var keys: Array = Game.unlocked_stances
	var n := keys.size()
	if n == 0: return
	var r := 16.0 * k
	var gap := 40.0 * k
	var right := sz.x - 30.0 * k - r
	var y := sz.y - 62.0 * k
	for i in n:
		var key := String(keys[i])
		var cp := Vector2(right - float(n - 1 - i) * gap, y)
		var active := key == Game.stance
		c.draw_circle(cp, r + 3.0 * k, Color(0, 0, 0, 0.3))
		c.draw_circle(cp, r, Color(VERMILION, 0.92) if active else INK_SOLID)
		c.draw_arc(cp, r, 0.0, TAU, 40, GOLD * Color(1, 1, 1, 0.9 if active else 0.35), (1.8 if active else 1.0) * k, true)
		_centered(c, f_title, cp + Vector2(0, -0.5 * k), String(STANCE_KANJI.get(key, "?")), int(16.0 * k), PARCHMENT if active else MUTED, 0)
	var info: Dictionary = Game.stance_info()
	var label := "%s STANCE" % String(info["name"]).to_upper()
	var fs := int(10.0 * k)
	var lw := f_bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_text(c, f_bold, Vector2(right + r - lw, y + r + 18.0 * k), label, fs, GOLD, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 3)
	var hint := "%s to switch" % Game.bind_label("stance")
	var hw := f_semi.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_text(c, f_semi, Vector2(right + r - hw, y + r + 32.0 * k), hint, fs, MUTED, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 3)

func _enemy_bars(c: Control, e, x: float, y: float, w: float, h: float, a: float) -> void:
	var k := _k
	var id: int = e.get_instance_id()
	var hp := clampf(float(e.hp_ratio()), 0.0, 1.0)
	var g := float(_enemy_ghost.get(id, hp))
	g = hp if g < hp else move_toward(g, hp, get_process_delta_time() * 0.5)
	_enemy_ghost[id] = g
	_cap(c, Rect2(x - 1.5 * k, y - 1.5 * k, w + 3.0 * k, h + 3.0 * k), Color(0, 0, 0, 0.45 * a))
	_cap(c, Rect2(x, y, w, h), Color(0.15, 0.1, 0.1, 0.7 * a))
	_cap(c, Rect2(x, y, w * g, h), Color(1.0, 0.85, 0.72, 0.5 * a))
	_cap(c, Rect2(x, y, w * hp, h), Color(0.86, 0.2, 0.15, a))
	var po := clampf(float(e.posture_ratio()), 0.0, 1.0)
	var broken := bool(e.posture_broken)
	if po > 0.01 or broken:
		var ph := maxf(2.0, h * 0.6)
		var pw := w if broken else w * po
		var col := Color(0.45, 0.88, 1.0, a * (0.7 + 0.3 * sin(_now() * 10.0))) if broken \
			else Color(1.0, 0.72, 0.25).lerp(Color(1.0, 0.3, 0.12), po) * Color(1, 1, 1, a)
		_cap(c, Rect2(x + (w - pw) * 0.5, y + h + 3.0 * k, pw, ph), col)

func _draw_enemy_overhead(c: Control, _sz: Vector2) -> void:
	if world == null: return
	var cam := get_viewport().get_camera_3d()
	if cam == null: return
	var k := _k
	var locked := player.locked_target()
	for e in world.enemies:
		if not is_instance_valid(e) or e.is_dead: continue
		if e == locked or (e.is_boss and e.in_combat): continue
		var d: float = e.global_position.distance_to(player.global_position)
		if d > 28.0: continue
		if not (e.in_combat or e.hp < e.max_hp or e.posture > 1.0): continue
		var top: Vector3 = e.global_position + Vector3(0, 2.3, 0)
		if cam.is_position_behind(top): continue
		var sp := cam.unproject_position(top)
		var a := clampf((28.0 - d) / 6.0, 0.0, 1.0)
		var w := 58.0 * k
		_enemy_bars(c, e, sp.x - w * 0.5, sp.y, w, 4.0 * k, a)

func _draw_target_bar(c: Control, sz: Vector2) -> void:
	var t: Node = player.locked_target()
	if (t == null or not is_instance_valid(t)) and world != null and world.boss != null and is_instance_valid(world.boss):
		if world.boss.in_combat and not world.boss.is_dead: t = world.boss
	if t == null or not is_instance_valid(t) or bool(t.get("is_dead")): return
	var k := _k
	var boss := bool(t.get("is_boss"))
	var w := (460.0 if boss else 320.0) * k
	var x := sz.x * 0.5 - w * 0.5
	var y := 58.0 * k
	var nm := String(t.display_name())
	if boss: _spaced(c, f_title, sz.x * 0.5, y - 10.0 * k, nm.to_upper(), int(19.0 * k), PARCHMENT, 3.0 * k, 4)
	else: _centered(c, f_semi, Vector2(sz.x * 0.5, y - 16.0 * k), nm, int(14.0 * k), PARCHMENT, 3)
	_enemy_bars(c, t, x, y, w, (8.0 if boss else 6.0) * k, 1.0)
	if bool(t.get("posture_broken")):
		_spaced(c, f_bold, sz.x * 0.5, y + 34.0 * k, "POSTURE BROKEN", int(11.0 * k), SPIRIT, 2.0 * k, 3)

func _draw_banner(c: Control, sz: Vector2) -> void:
	if _zone_banner <= 0.0: return
	var k := _k
	var t := BANNER_T - _zone_banner
	var a := smoothstep(0.0, 0.7, t) * (1.0 - smoothstep(BANNER_T - 1.2, BANNER_T, t))
	var cx := sz.x * 0.5
	var cy := sz.y * 0.23
	var kan := String(ZONE_KANJI.get(_zone_id, ""))
	if kan != "":
		_centered(c, f_title, Vector2(cx, cy), kan, int(52.0 * k), Color(0.88, 0.26, 0.19, 0.92 * a), int(5.0 * k))
	_spaced(c, f_title, cx, cy + 58.0 * k, _zone_title.to_upper(), int(28.0 * k), PARCHMENT * Color(1, 1, 1, a), 7.0 * k, 5)
	var L := 180.0 * k * ease(clampf(t / 1.1, 0.0, 1.0), 0.3)
	var ly := cy + 74.0 * k
	c.draw_line(Vector2(cx - L, ly), Vector2(cx - 10.0 * k, ly), GOLD * Color(1, 1, 1, 0.8 * a), 1.2 * k, true)
	c.draw_line(Vector2(cx + 10.0 * k, ly), Vector2(cx + L, ly), GOLD * Color(1, 1, 1, 0.8 * a), 1.2 * k, true)
	_diamond(c, Vector2(cx, ly), 3.5 * k, GOLD * Color(1, 1, 1, a), false)
	if _zone_hint != "":
		_centered(c, f_reg, Vector2(cx, ly + 20.0 * k), _zone_hint, int(15.0 * k), MUTED * Color(1, 1, 1, a), 4)

func _draw_death(c: Control, sz: Vector2) -> void:
	if _death_t < 0.0: return
	var k := _k
	var t := _death_t
	var a_in := smoothstep(0.0, 0.7, t)
	var a_out := 1.0 - smoothstep(2.7, 3.5, t)
	var dark := smoothstep(0.9, 2.1, t) * a_out
	c.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, sz), false, Color(0.35, 0.0, 0.0, 0.8 * a_in * a_out))
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.88 * dark), true)
	var cy := sz.y * 0.44
	_centered(c, f_title, Vector2(sz.x * 0.5, cy), "死", int(132.0 * k), Color(0.86, 0.16, 0.12, 0.95 * a_in * a_out), int(6.0 * k))
	_spaced(c, f_semi, sz.x * 0.5, cy + 104.0 * k, "YOU HAVE FALLEN", int(18.0 * k), PARCHMENT * Color(1, 1, 1, a_in * a_out), 6.0 * k, 4)

func _draw_vignette(c: Control, sz: Vector2) -> void:
	var r := Rect2(Vector2.ZERO, sz)
	if _dmg_flash > 0.01:
		c.draw_texture_rect(_vignette, r, false, Color(0.8, 0.05, 0.04, 0.75 * _dmg_flash))
	if _deflect_flash > 0.01:
		c.draw_texture_rect(_vignette, r, false, Color(0.75, 0.9, 1.0, 0.45 * _deflect_flash))
	if player != null and player.hp_ratio() < 0.3 and _death_t < 0.0:
		var pulse := 0.5 + 0.5 * sin(_now() * 3.2)
		c.draw_texture_rect(_vignette, r, false, Color(0.5, 0.0, 0.0, (0.35 + 0.25 * pulse) * (1.0 - player.hp_ratio() / 0.3)))

# ================================================================ v0.16 stealth HUD
## Screen position for a world point; z = 1 when it is off-screen (then x,y
## are clamped to the screen edge in the right direction).
func _edge_point(cam: Camera3D, w: Vector3, sz: Vector2, inset: float) -> Vector3:
	var r := Rect2(Vector2(inset, inset), sz - Vector2(inset, inset) * 2.0)
	if not cam.is_position_behind(w):
		var sp := cam.unproject_position(w)
		if r.has_point(sp): return Vector3(sp.x, sp.y, 0.0)
	var lp: Vector3 = cam.global_transform.affine_inverse() * w
	var d := Vector2(lp.x, -lp.y)
	if lp.z > 0.0 and absf(d.y) > absf(d.x): d.y = absf(d.y)   # behind: show it low, not high
	if d.length() < 0.001: d = Vector2(0, 1)
	d = d.normalized()
	var c := sz * 0.5
	var s := minf((r.size.x * 0.5) / maxf(absf(d.x), 0.001), (r.size.y * 0.5) / maxf(absf(d.y), 0.001))
	var e := c + d * s
	return Vector3(e.x, e.y, 1.0)

func _edge_arrow(c: Control, p: Vector2, sz: Vector2, col: Color, r: float) -> void:
	var d := (p - sz * 0.5).normalized()
	var n := Vector2(-d.y, d.x)
	var tip := p + d * r * 1.1
	c.draw_colored_polygon(PackedVector2Array([tip, p - d * r * 0.3 + n * r * 0.8, p - d * r * 0.3 - n * r * 0.8]), col)

## Awareness above every soldier that is noticing you: a white arc that fills
## as he looks, an amber "?" while he searches, a red "!" when he raises the
## alarm. Off-screen ones sit on the screen edge pointing at him.
func _draw_awareness(c: Control, sz: Vector2) -> void:
	if world == null: return
	var cam := get_viewport().get_camera_3d()
	if cam == null: return
	var k := _k
	var pp := player.global_position
	for e in world.enemies:
		if not is_instance_valid(e) or e.is_dead or not e.has_method("awareness_ratio"): continue
		var d: float = e.global_position.distance_to(pp)
		if d > 48.0: continue
		var flash: float = e.alert_flash()
		var aw: float = e.awareness_ratio()
		if flash <= 0.0 and (e.in_combat or aw < 0.04): continue
		var ep := _edge_point(cam, e.global_position + Vector3(0, 2.55, 0), sz, 46.0 * k)
		var p := Vector2(ep.x, ep.y)
		var off := ep.z > 0.5
		var r := 11.0 * k
		if flash > 0.0:
			var a := clampf(flash / 0.5, 0.0, 1.0)
			var grow := 1.0 + (1.4 - flash) * 0.6
			c.draw_circle(p, r * 1.25 * grow, Color(0, 0, 0, 0.45 * a))
			c.draw_arc(p, r * 1.25 * grow, 0.0, TAU, 32, Color(1.0, 0.25, 0.18, a), 2.0 * k, true)
			_centered(c, f_title, p + Vector2(0, -1.0 * k), "!", int(22.0 * k), Color(1.0, 0.3, 0.22, a), 4)
			if off: _edge_arrow(c, p, sz, Color(1.0, 0.3, 0.22, a), r)
			continue
		var searching: bool = e.is_searching() or aw >= EnemyBase.SUSPECT
		var col := Color(1.0, 0.72, 0.25) if searching else Color(0.95, 0.94, 0.9)
		var a2 := clampf(0.45 + aw, 0.0, 1.0) * clampf((48.0 - d) / 8.0, 0.0, 1.0)
		c.draw_circle(p, r, Color(0, 0, 0, 0.45 * a2))
		c.draw_arc(p, r, 0.0, TAU, 32, Color(1, 1, 1, 0.18 * a2), 1.6 * k, true)
		c.draw_arc(p, r, -PI * 0.5, -PI * 0.5 + TAU * clampf(aw, 0.0, 1.0), 32, col * Color(1, 1, 1, a2), 2.4 * k, true)
		if searching:
			_centered(c, f_title, p + Vector2(0, -1.0 * k), "?", int(17.0 * k), col * Color(1, 1, 1, a2), 3)
		if off: _edge_arrow(c, p, sz, col * Color(1, 1, 1, a2), r * 0.8)

## 危 over a soldier winding up a perilous attack, with what answers it, and a
## red edge arrow for any attack coming from off-screen.
func _draw_perilous(c: Control, sz: Vector2) -> void:
	if world == null: return
	var cam := get_viewport().get_camera_3d()
	if cam == null: return
	var k := _k
	var t := _now()
	var pp := player.global_position
	for e in world.enemies:
		if not is_instance_valid(e) or e.is_dead or not e.in_combat: continue
		var d: float = e.global_position.distance_to(pp)
		if d > 26.0: continue
		var per: String = e.perilous_kind() if e.has_method("perilous_kind") else ""
		var winding: bool = e.state == EnemyBase.S.ATTACK and e.windup_left() > 0.0
		if per == "" and not winding: continue
		var ep := _edge_point(cam, e.global_position + Vector3(0, 2.7, 0), sz, 54.0 * k)
		var p := Vector2(ep.x, ep.y)
		var off := ep.z > 0.5
		if per != "":
			var pr: float = e.perilous_progress()
			var pulse := 0.75 + 0.25 * sin(t * 14.0)
			var R := 21.0 * k * (1.0 + 0.25 * (1.0 - pr))
			c.draw_circle(p, R, Color(0.25, 0.0, 0.0, 0.55))
			c.draw_arc(p, R, 0.0, TAU, 40, Color(1.0, 0.15, 0.1, pulse), 2.4 * k, true)
			_centered(c, f_kanji, p + Vector2(0, -1.0 * k), "危", int(26.0 * k), Color(1.0, 0.22, 0.15, pulse), 4)
			var hint := "DEFLECT"
			if per == "thrust" and Skills.has("b_mikiri"): hint = "DEFLECT · MIKIRI"
			elif per == "sweep": hint = "JUMP"
			_centered(c, f_bold, p + Vector2(0, R + 12.0 * k), hint, int(10.0 * k), Color(1.0, 0.8, 0.7, pulse), 3)
			if off: _edge_arrow(c, p, sz, Color(1.0, 0.15, 0.1, pulse), R * 0.7)
		elif off and d < 12.0:
			var a := clampf(1.0 - e.windup_left() / 0.8, 0.3, 1.0)
			_edge_arrow(c, p, sz, Color(1.0, 0.45, 0.2, a), 13.0 * k)
	# a red pulse at the screen edge on a perilous wind-up
	if _peril_t > 0.0:
		c.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, sz), false, Color(0.9, 0.05, 0.03, 0.35 * _peril_t))

## The stealth eye over the weapon emblem: open while you are seen-able,
## half-shut crouched, shut when hidden (tall grass or smoke).
func _draw_stealth(c: Control, sz: Vector2) -> void:
	if not player.has_method("is_crouching"): return
	var smoke: bool = player.in_smoke()
	if not player.crouching and not smoke: return
	var k := _k
	var p := Vector2(60.0 * k, sz.y - 70.0 * k - 28.0 * k - 30.0 * k)
	var hidden: bool = smoke or player.cover() > 0.5
	var col := SPIRIT if hidden else PARCHMENT
	var w := 13.0 * k
	var h := (2.0 if hidden else 6.5) * k
	c.draw_circle(p, 17.0 * k, Color(0, 0, 0, 0.35))
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in 13:
		var x := -w + 2.0 * w * float(i) / 12.0
		var y := h * (1.0 - (x / w) * (x / w))
		top.append(p + Vector2(x, -y))
		bot.append(p + Vector2(x, y * (0.2 if hidden else 1.0)))
	c.draw_polyline(top, col, 1.8 * k, true)
	c.draw_polyline(bot, col, 1.8 * k, true)
	if not hidden: c.draw_circle(p, 2.8 * k, col)
	var label := "IN SMOKE" if smoke else ("HIDDEN" if hidden else "CROUCHED")
	_text(c, f_bold, p + Vector2(22.0 * k, 4.0 * k), label, int(10.0 * k), col, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 3)

## Smoke bombs next to the gourd: a dark ball, one pip per bomb, its key.
func _draw_smoke(c: Control, p: Vector2, k: float) -> void:
	var n := int(Game.smoke)
	var nmax := int(Game.smoke_max)
	var full := n > 0
	c.draw_circle(p + Vector2(0, 2.0 * k), 8.5 * k, Color(0, 0, 0, 0.35))
	c.draw_circle(p + Vector2(0, 1.5 * k), 7.0 * k, Color(0.30, 0.31, 0.33) if full else Color(0.18, 0.18, 0.19))
	c.draw_line(p + Vector2(2.0 * k, -5.0 * k), p + Vector2(5.0 * k, -9.0 * k), Color(0.75, 0.6, 0.35), 1.6 * k)
	c.draw_circle(p + Vector2(-2.2 * k, -0.6 * k), 1.8 * k, Color(1, 1, 1, 0.2 if full else 0.06))
	for i in nmax:
		var q := p + Vector2(14.0 * k + float(i) * 9.0 * k, 3.0 * k)
		c.draw_circle(q, 3.2 * k, Color(0, 0, 0, 0.45))
		if i < n: c.draw_circle(q, 2.4 * k, Color(0.82, 0.84, 0.88))
		else: c.draw_arc(q, 2.4 * k, 0.0, TAU, 16, MUTED, 1.0 * k, true)
	_text(c, f_bold, p + Vector2(14.0 * k + float(nmax) * 9.0 * k + 2.0 * k, -2.0 * k),
		Game.bind_label("smoke"), int(10.0 * k), PARCHMENT if full else MUTED, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 3)
