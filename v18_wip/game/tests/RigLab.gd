extends Node3D
## Contact-sheet lab for the player rig.
##   --clips "Sword_Regular_A:0:0.43:6,Idle:0:0:1"  (clip:t0:t1:n)
##   --cams side,front  --weapon katana  --drawn 1  --dist 4 --height 0.95 --w 330 --h 440
##   --out /tmp/rig
## Writes <out>_<clip>_<cam>_<i>.png
var args := {}
func _ready() -> void:
	var ua := OS.get_cmdline_user_args()
	var i := 0
	while i < ua.size():
		if ua[i].begins_with("--") and i + 1 < ua.size():
			args[ua[i].substr(2)] = ua[i + 1]; i += 2
		else: i += 1
	get_window().size = Vector2i(int(args.get("w", 330)), int(args.get("h", 440)))
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-40), deg_to_rad(30), 0); light.light_energy = 1.5
	add_child(light)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.32, 0.36, 0.42)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8); e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e; add_child(env)
	var fl := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(30, 30); fl.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.25, 0.27, 0.25); fl.material_override = fm; add_child(fl)
	var rig := PlayerRig.new(); add_child(rig)
	rig.build()
	rig.set_weapon(String(args.get("weapon", "katana")), int(args.get("drawn", 0)) == 1)
	if args.has("grip"):
		rig.anatomy.grip_l = float(args["grip"]); rig.anatomy.grip_r = float(args["grip"])
	if args.has("exert"): rig.anatomy.exertion = float(args["exert"])
	if args.has("noanat"): rig.anatomy.active = false
	if args.has("gpos"):
		var g := String(args["gpos"]).split(",")
		rig.grip_pos = Vector3(float(g[0]), float(g[1]), float(g[2])); rig.refresh_weapons()
	var cam := Camera3D.new(); add_child(cam); cam.fov = 30
	var d := float(args.get("dist", 4.0)); var hh := float(args.get("height", 0.95))
	var target := Vector3(float(args.get("cx", 0.0)), hh, float(args.get("cz", 0.0)))
	var cams: PackedStringArray = String(args.get("cams", "side")).split(",", false)
	var base := String(args.get("out", "/tmp/rig"))
	for spec in String(args.get("clips", "Idle:0:0:1")).split(",", false):
		var p := spec.split(":")
		var clip := p[0]; var t0 := float(p[1]); var t1 := float(p[2]); var n := int(p[3])
		if not rig.has_clip(clip): push_error("no clip " + clip); continue
		rig.anim.play(clip)
		rig.anim.pause()
		for k in n:
			var t := t0 if n <= 1 else lerpf(t0, t1, float(k) / float(n - 1))
			rig.anim.seek(t, true)
			rig.anim.advance(0.0)
			rig.skeleton.force_update_all_bone_transforms()
			for mode in cams:
				match mode:
					"front": cam.position = target + Vector3(0, 0.2, d)
					"back": cam.position = target + Vector3(0, 0.2, -d)
					"side": cam.position = target + Vector3(d, 0.2, 0)
					"lside": cam.position = target + Vector3(-d, 0.2, 0)
					"top": cam.position = target + Vector3(0.01, d, 0.01)
					"q": cam.position = target + Vector3(d * 0.6, 0.5, d * 0.8)
					"bq": cam.position = target + Vector3(d * 0.6, 0.6, -d * 0.8)
					_: cam.position = target + Vector3(d * 0.6, 0.5, d * 0.8)
				cam.look_at(target)
				if args.has("saya"): rig.update_saya_hand(1.0, true)
				await get_tree().process_frame
				if args.has("saya"): rig.update_saya_hand(1.0, true)
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s_%s_%s_%02d.png" % [base, clip, mode, k])
	print("done")
	get_tree().quit()
