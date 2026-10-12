extends SceneTree
func _init() -> void:
	var sc: PackedScene = load("res://assets/models/Kaito_Ronin.glb")
	var n: Node = sc.instantiate()
	var skel: Skeleton3D = null
	var mi: MeshInstance3D = null
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is Skeleton3D: skel = c
		if c is MeshInstance3D: mi = c
		for ch in c.get_children(): stack.append(ch)
	for b in ["hips", "foot.L", "toe.L", "foot.R", "toe.R"]:
		var i: int = skel.find_bone(b)
		if i >= 0:
			print("BONE %-8s global_rest_y=%.4f" % [b, skel.get_bone_global_rest(i).origin.y])
	var aabb: AABB = mi.mesh.get_aabb()
	print("MESH aabb pos=", aabb.position, " size=", aabb.size)
	# lowest vertex of each surface, to find the sole
	var lo := 999.0
	for s in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var slo := 999.0
		for v in verts: slo = minf(slo, v.y)
		lo = minf(lo, slo)
		if slo < 0.12: print("SURF %d lowest_y=%.4f verts=%d" % [s, slo, verts.size()])
	print("LOWEST_VERTEX_Y %.4f" % lo)
	quit()
