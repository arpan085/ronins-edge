extends Node3D

func _ready() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	if main.has_method("start_world"):
		main.call("start_world", false)
	for i in 30:
		await get_tree().process_frame
	var world: Node = main.get_node_or_null("World")
	if world == null:
		for c in main.get_children():
			if c.get_script() != null and c.name.to_lower().contains("world"): world = c
	print("--- tree (big meshes) ---")
	_walk(main, 0)
	var pos := Vector3(1180, 12.09, 1120)
	if world != null and world.has_method("warp_to"):
		world.call("warp_to", pos)
		for i in 20: await get_tree().process_frame
	# raycast straight down from above the village
	var space := get_world_3d().direct_space_state
	for off in [Vector3(0,0,0), Vector3(20,0,20), Vector3(-30,0,10)]:
		var from: Vector3 = pos + (off as Vector3) + Vector3(0, 40, 0)
		var to: Vector3 = pos + (off as Vector3) - Vector3(0, 40, 0)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		var r := space.intersect_ray(q)
		print("ray ", off, " -> ", r.get("position", "MISS"), " collider=", (r.get("collider") as Node).name if r.has("collider") else "-")
	get_tree().quit()

func _walk(n: Node, d: int) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var ab := mi.get_aabb()
		if ab.size.x > 60.0 or ab.size.z > 60.0:
			var matn := "-"
			if mi.material_override != null: matn = mi.material_override.get_class() + "/" + str((mi.material_override as ShaderMaterial).shader.resource_path if mi.material_override is ShaderMaterial else "")
			elif mi.mesh != null and mi.mesh.get_surface_count() > 0 and mi.mesh.surface_get_material(0) != null: matn = "surf:" + mi.mesh.surface_get_material(0).get_class()
			print("  ".repeat(d), mi.name, " aabb=", ab.position.snapped(Vector3.ONE), " size=", ab.size.snapped(Vector3.ONE), " vis=", mi.visible, " mat=", matn, " layers=", mi.layers)
	for c in n.get_children(): _walk(c, d + 1)
