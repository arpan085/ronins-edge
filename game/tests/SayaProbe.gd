extends Node
## Where exactly does the katana sit in its own bone space, and where does the
## saya's cavity sit in its bone space? Eyeballing a render cannot answer that;
## the vertices can. Both meshes are skinned rigidly to one bone each, so the
## bind-space extents give the seating transform directly.
func _ready() -> void:
	var sc: PackedScene = load("res://assets/models/Kaito_Ronin.glb")
	var n: Node = sc.instantiate()
	add_child(n)
	var skel: Skeleton3D = null
	var mi: MeshInstance3D = null
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is Skeleton3D: skel = c
		if c is MeshInstance3D: mi = c
		for ch in c.get_children(): stack.append(ch)
	var skin: Skin = mi.skin
	var bind_to_bone := {}
	for i in skin.get_bind_count():
		var bn := skin.get_bind_name(i)
		var bi := skin.get_bind_bone(i)
		if bi < 0 and bn != "": bi = skel.find_bone(bn)
		bind_to_bone[i] = bi
	var want := {"weapon.R": skel.find_bone("weapon.R"), "scabbard": skel.find_bone("scabbard")}
	for label in want.keys():
		var bone: int = want[label]
		var inv: Transform3D = skel.get_bone_global_rest(bone).affine_inverse()
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		var cnt := 0
		for s in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			if bones.is_empty(): continue
			var per := bones.size() / maxi(verts.size(), 1)
			for v in verts.size():
				var best := -1
				var bw := 0.0
				for j in per:
					var w: float = wts[v * per + j]
					if w > bw: bw = w; best = int(bones[v * per + j])
				if best < 0: continue
				if int(bind_to_bone.get(best, -1)) != bone: continue
				var lp: Vector3 = inv * verts[v]
				lo = Vector3(minf(lo.x, lp.x), minf(lo.y, lp.y), minf(lo.z, lp.z))
				hi = Vector3(maxf(hi.x, lp.x), maxf(hi.y, lp.y), maxf(hi.z, lp.z))
				cnt += 1
		print("SAYA %-10s verts=%5d  bone-local min=(%.3f,%.3f,%.3f) max=(%.3f,%.3f,%.3f)"
			% [label, cnt, lo.x, lo.y, lo.z, hi.x, hi.y, hi.z])
	get_tree().quit()
