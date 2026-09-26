extends Node
## Boot: title screen -> loading -> world. Owns pause/debug keys.

var menu: Control
var world: World
var loading: Control
var _loading_bar: ProgressBar
var _loading_label: Label

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_menu()

func _show_menu() -> void:
	if world != null:
		world.queue_free()
		world = null
	if menu == null:
		menu = load("res://ui/MainMenu.gd").new()
		menu.name = "MainMenu"
		add_child(menu)
	menu.visible = true
	Audio.play_music("menu")
	Perf.apply_quality(int(Game.settings.get("quality", 2)))

func _loading_screen() -> void:
	loading = Control.new()
	loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.045, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.add_child(bg)
	_loading_label = Label.new()
	_loading_label.text = "RONIN'S EDGE"
	_loading_label.add_theme_font_size_override("font_size", 40)
	_loading_label.add_theme_color_override("font_color", Color(0.90, 0.86, 0.76))
	_loading_label.position = Vector2(0, 280)
	_loading_label.size = Vector2(1280, 60)
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.add_child(_loading_label)
	_loading_bar = ProgressBar.new()
	_loading_bar.min_value = 0; _loading_bar.max_value = 100; _loading_bar.value = 0
	_loading_bar.position = Vector2(1280 * 0.5 - 200, 372)
	_loading_bar.custom_minimum_size = Vector2(400, 12)
	loading.add_child(_loading_bar)
	add_child(loading)

func start_world(from_save: bool) -> void:
	if menu != null: menu.visible = false
	_loading_screen()
	await get_tree().process_frame
	_loading_bar.value = 20
	_loading_label.text = "Raising the five provinces..."
	await get_tree().process_frame
	world = World.new()
	world.name = "World"
	add_child(world)
	_loading_bar.value = 70
	_loading_label.text = "Sharpening steel..."
	await get_tree().process_frame
	await get_tree().process_frame
	if world.player != null and world.camera != null:
		world.player.setup(world, world.camera)
	_loading_bar.value = 100
	await get_tree().create_timer(0.25).timeout
	loading.queue_free()
	loading = null
	if from_save:
		Quests.start_next()
	if not from_save and world.player != null:
		Game.notice.emit("Sakura Shrine — the path begins", "zone")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if world != null and world.hud != null and world.hud.has_method("toggle_pause"):
			world.hud.toggle_pause()
	elif event.is_action_pressed("debug"):
		Game.settings["show_fps"] = not bool(Game.settings.get("show_fps", false))
		if Perf.overlay != null: Perf.overlay.visible = bool(Game.settings["show_fps"])
	elif event.is_action_pressed("ui_restart") and world != null:
		world.respawn()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
