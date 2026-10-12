extends Node3D
## v0.22: how far each clip in ronin_anims.res pushes the feet into (or above)
## the ground. Prints: clip, lowest contact over the cycle (m, - = buried), and
## the share of samples with a foot within 2 cm of the ground.
func _ready() -> void:
	var m: Node3D = (load("res://assets/char/Ronin.glb") as PackedScene).instantiate()
	add_child(m)
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	var ap := AnimationPlayer.new(); m.add_child(ap)
	var lib: AnimationLibrary = load("res://assets/anim/ronin_anims.res")
	if not "--raw" in OS.get_cmdline_user_args(): GroundFix.apply(lib, sk)
	ap.add_animation_library("", lib)
	ap.root_node = ap.get_path_to(sk.get_parent())
	var fl := sk.find_bone("foot_l"); var fr := sk.find_bone("foot_r")
	var bl := sk.find_bone("ball_l"); var br := sk.find_bone("ball_r")
	var ah := sk.get_bone_global_rest(fl).origin.y
	var bh := sk.get_bone_global_rest(bl).origin.y
	var out := []
	for c in ap.get_animation_list():
		var a := ap.get_animation(c)
		ap.play(c)
		var lo := 9.0
		var hi := -9.0
		var pv_at := 1.0
		var n := 32
		for i in n:
			ap.seek(a.length * float(i) / float(n), true)
			var g := 9.0
			for pair in [[fl, bl], [fr, br]]:
				var ay: float = sk.get_bone_global_pose(pair[0]).origin.y - ah
				var by: float = sk.get_bone_global_pose(pair[1]).origin.y - bh
				g = minf(g, minf(ay, by))
			if g < lo: pv_at = sk.get_bone_global_pose(sk.find_bone("pelvis")).origin.y
			lo = minf(lo, g)
			hi = maxf(hi, g)
		out.append([lo, c, hi, a.length, 1.0 - lo / maxf(pv_at, 0.05), pv_at])
	out.sort_custom(func(x, y): return x[0] < y[0])
	for r in out:
		print("GND %-28s low=%+.3f  high=%+.3f  len=%.2f  s=%.3f pel=%.3f" % [r[1], r[0], r[2], r[3], r[4], r[5]])
	get_tree().quit()
