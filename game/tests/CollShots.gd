extends Node
## Proof shots for world collision: walk the player into a building, a tree and
## a hillside and photograph where the body actually stops.

var t := 0.0
var idx := -1
var saved := 0
var player: Node = null
var world: Node = null
var terrain: Node = null
var shots: Array = []

func _ready() -> void:
	process_priority = 900
	get_viewport().get_window().size = Vector2i(1000, 620)
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
	if world == null: world = find_child("World", true, false)
	terrain = world.get("terrain")
	player = world.get("player")
	var f := FileAccess.open("res://assets/terrain/world.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	var house := Vector3.ZERO
	var tree := Vector3.ZERO
	for p in d.get("props", []):
		if String(p.get("kind", "")) == "house" and house == Vector3.ZERO:
			house = Vector3(float(p["x"]), 0, float(p["z"]))
	for tr in d.get("trees", []):
		if String(tr.get("kind", "")) == "cedar" and tree == Vector3.ZERO:
			tree = Vector3(float(tr["x"]), 0, float(tr["z"]))
		if tree != Vector3.ZERO: break
	# steepest spot we can find
	var steep := Vector3.ZERO
	var best := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 4000:
		var x := rng.randf_range(60.0, 1470.0)
		var z := rng.randf_range(60.0, 1470.0)
		var sl: float = terrain.slope_at(x, z)
		if sl > best and terrain.sample_height(x, z) > terrain.water_level + 4.0:
			best = sl; steep = Vector3(x, 0, z)
	print("COLLSHOT house=%v tree=%v steep=%v slope=%.2f" % [house, tree, steep, best])
	shots = [
		
		{"n": "04_slope_stand", "at": steep, "mv": Vector2.ZERO, "face": steep + Vector3(8, 0, 0), "t": 2.0},
		{"n": "01_house", "at": house + Vector3(9, 0, 0), "mv": Vector2(0, -1.0), "face": house, "t": 3.0},
	]
	idx = 0
	_begin()

func _begin() -> void:
	var s: Dictionary = shots[idx]
	world.warp_to(s["at"])
	var f: Vector3 = s["face"]
	var p: Vector3 = player.global_position
	player.rotation.y = atan2(f.x - p.x, f.z - p.z)
	if player.get("_want_yaw") != null: player.set("_want_yaw", player.rotation.y)
	t = 0.0

func _physics_process(delta: float) -> void:
	if idx < 0 or idx >= shots.size(): return
	var s: Dictionary = shots[idx]
	t += delta
	Game.touch_move = s.get("mv", Vector2.ZERO)
	if t < float(s["t"]): return
	Game.touch_move = Vector2.ZERO
	var img := get_viewport().get_texture().get_image()
	var dir := "user://coll"
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png("%s/%s.png" % [dir, s["n"]])
	saved += 1
	var pp: Vector3 = player.global_position
	print("COLLSHOT %s pos=%v ground=%.2f dy=%+.3f floor=%s" % [s["n"], pp,
		terrain.sample_height(pp.x, pp.z), pp.y - terrain.sample_height(pp.x, pp.z),
		str(player.is_on_floor())])
	idx += 1
	if idx >= shots.size():
		print("COLLSHOT_DONE saved=%d" % saved)
		get_tree().quit()
		return
	_begin()
