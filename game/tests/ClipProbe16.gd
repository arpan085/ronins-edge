extends SceneTree
## v0.16 probe: lengths/loops of new clips and the ground speed of crouch walks.
func _init() -> void:
	var rig = load("res://player/PlayerRig.gd").new()
	root.add_child(rig)
	await process_frame
	if not rig.ok: rig.build()
	var anim: AnimationPlayer = rig.anim
	var skel: Skeleton3D = rig.skeleton
	var names := ["Walk", "Crouch_Idle", "Crouch_Fwd", "K_Crouch", "K_Sneak", "K_Throw", "OverhandThrow", "K_1H_Stab", "K_2H_Stab", "Sword_Dash", "K_Kick"]
	var fl := -1
	var fr := -1
	for b in ["foot_l", "foot.L", "Foot_L", "LeftFoot", "mixamorig_LeftFoot"]:
		if skel.find_bone(b) >= 0: fl = skel.find_bone(b)
	for b in ["foot_r", "foot.R", "Foot_R", "RightFoot", "mixamorig_RightFoot"]:
		if skel.find_bone(b) >= 0: fr = skel.find_bone(b)
	print("FEET ", fl, " ", fr)
	for c in names:
		if not anim.has_animation(c):
			print("CLIP %s MISSING" % c)
			continue
		var a: Animation = anim.get_animation(c)
		var line := "CLIP %-14s len=%.3f loop=%d" % [c, a.length, a.loop_mode]
		if fl >= 0 and (c in ["Walk", "Crouch_Fwd", "K_Sneak"]):
			anim.play(c)
			var zmin := 1e9
			var zmax := -1e9
			var hy := []
			var n := 60
			for i in n + 1:
				anim.seek(a.length * float(i) / float(n), true)
				var p: Vector3 = skel.get_bone_global_pose(fl).origin
				zmin = minf(zmin, p.z); zmax = maxf(zmax, p.z)
			var hips := skel.find_bone("pelvis")
			var hipy := 0.0
			if hips >= 0: hipy = skel.get_bone_global_pose(hips).origin.y
			line += " footZrange=%.3f est_speed=%.2f pelvis_y=%.2f" % [zmax - zmin, 2.0 * (zmax - zmin) / a.length, hipy]
		print(line)
	quit()
