extends SceneTree
## Prints animal GLB structure: anims, lengths, root-motion range, mesh AABB.
func _init() -> void:
	for n in ["doe", "stag", "fox", "boar", "wolf"]:
		var ps: PackedScene = load("res://assets/animals/%s.glb" % n)
		var root: Node = ps.instantiate()
		print("== ", n, " root=", root.get_class())
		var aps := root.find_children("*", "AnimationPlayer", true, false)
		for ap in aps:
			var a: AnimationPlayer = ap
			print("  AP path=", root.get_path_to(a), " root_node=", a.root_node)
			for an in a.get_animation_list():
				var anim: Animation = a.get_animation(an)
				var info := "    %-8s len=%.2f tracks=%d loop=%d" % [an, anim.length, anim.get_track_count(), anim.loop_mode]
				# position tracks: report the biggest horizontal travel
				var best := 0.0
				var bp := ""
				for t in anim.get_track_count():
					if anim.track_get_type(t) != Animation.TYPE_POSITION_3D: continue
					var kc := anim.track_get_key_count(t)
					if kc < 2: continue
					var p0: Vector3 = anim.track_get_key_value(t, 0)
					var p1: Vector3 = anim.track_get_key_value(t, kc - 1)
					var mn := p0
					var mx := p0
					for k in kc:
						var p: Vector3 = anim.track_get_key_value(t, k)
						mn = mn.min(p); mx = mx.max(p)
					var span := (mx - mn).length()
					if span > best:
						best = span
						bp = "%s d0-1=%s range=%s..%s" % [anim.track_get_path(t), str((p1 - p0).snapped(Vector3.ONE * 0.01)), str(mn.snapped(Vector3.ONE * 0.01)), str(mx.snapped(Vector3.ONE * 0.01))]
				print(info, "  maxpos ", bp)
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var m: MeshInstance3D = mi
			print("  mesh ", root.get_path_to(m), " aabb=", m.mesh.get_aabb() if m.mesh else null, " xform=", m.transform.origin, " skin=", m.skin != null)
		for sk in root.find_children("*", "Skeleton3D", true, false):
			var s: Skeleton3D = sk
			print("  skel ", root.get_path_to(s), " bones=", s.get_bone_count(), " b0=", s.get_bone_name(0), " scale=", s.transform.basis.get_scale())
		root.free()
	quit()
