extends Node
## Renders one spot repeatedly, hiding one subsystem each time, to identify
## which system draws the large pale quads seen in the world shots.

var world: Node = null
var player: Node = null
var terrain: Node = null
var t := 0.0
var idx := -1
var steps: Array = ["all", "no_foliage", "no_water", "no_ambience", "no_trees", "no_props"]

func _ready() -> void:
	process_priority = 900
	get_viewport().get_window().size = Vector2i(900, 560)
	var pf = get_node_or_null("/root/Perf")
	if pf != null and pf.has_method("apply_quality"): pf.apply_quality(1)
	var ps: PackedScene = load("res://main/Main.tscn")
	var main: Node = ps.instantiate()
	main.name = "Main"
	add_child(main)
	await get_tree().create_timer(0.8).timeout
	if main.has_method("start_world"): main.start_world(false)
	await get_tree().create_timer(4.0).timeout
	world = main.get("world")
	terrain = world.get("terrain")
	player = world.get("player")
	world.warp_to(Vector3(569.0, 0.0, 838.6))
	await get_tree().create_timer(2.5).timeout
	idx = 0
	_apply()

func _apply() -> void:
	var s: String = steps[idx]
	_show("Foliage", s != "no_foliage")
	_show("Water", s != "no_water")
	_show("Ambience", s != "no_ambience")
	_show("Petals", s != "no_ambience")
	_show("Trees", s != "no_trees")
	for c in world.get_children():
		if String(c.name).begins_with("MM_"): c.visible = s != "no_props"
	t = 0.0

func _show(n: String, v: bool) -> void:
	var nd = world.get_node_or_null(n)
	if nd != null and nd is Node3D: nd.visible = v

func _physics_process(delta: float) -> void:
	if idx < 0 or idx >= steps.size(): return
	Game.touch_move = Vector2.ZERO
	t += delta
	if t < 1.2: return
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://iso")
	img.save_png("user://iso/%d_%s.png" % [idx, steps[idx]])
	print("ISO %s" % steps[idx])
	idx += 1
	if idx >= steps.size():
		print("ISO_DONE")
		get_tree().quit()
		return
	_apply()
