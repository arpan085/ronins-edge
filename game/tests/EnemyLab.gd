extends Node3D
## v0.18 contact-sheet lab for the soldiers on the shared base body.
##   --kinds ashigaru,archer,captain  --clip Attack  --at 0.4  (enemy clip names)
##   --cams front,q,side  --dist 6 --height 1.0 --w 900 --h 520 --out /tmp/en
##   v0.19: --beard moustache,beard,...  (one style per soldier)  --nogear 1
##   (no hat, banner or weapon: face close-ups)  --rise 0.02 (camera height)
##   v0.20: --wet 1.0  (soaked by rain, see anim/CharWet.gd)
##   v0.21: --cold 1 --puff 0.6 [--exert 1]  (breathe out, capture 0.6 s later)
##   --mood cold  (dim blue winter light and a snowy floor)
##   v0.22: --nofix 1  (without anim/GroundFix: feet sunk 17 cm, as before)
## Writes <out>_<cam>.png with the soldiers side by side.
var args := {}
func _ready() -> void:
	var ua := OS.get_cmdline_user_args()
	var i := 0
	while i < ua.size():
		if ua[i].begins_with("--") and i + 1 < ua.size():
			args[ua[i].substr(2)] = ua[i + 1]; i += 2
		else: i += 1
	get_window().size = Vector2i(int(args.get("w", 900)), int(args.get("h", 520)))
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-38), deg_to_rad(28), 0); light.light_energy = 1.6
	light.shadow_enabled = true
	add_child(light)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.34, 0.38, 0.44)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.76, 0.8); e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e; add_child(env)
	var fl := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(40, 40); fl.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.26, 0.27, 0.24); fl.material_override = fm; add_child(fl)
	if args.get("mood", "") == "cold":   # winter dawn: low blue light, snow underfoot
		light.light_energy = 1.05; light.light_color = Color(0.78, 0.85, 1.0)
		light.rotation = Vector3(deg_to_rad(-22), deg_to_rad(40), 0)
		e.background_color = Color(0.16, 0.19, 0.26)
		e.ambient_light_color = Color(0.55, 0.62, 0.78); e.ambient_light_energy = 0.6
		fm.albedo_color = Color(0.8, 0.82, 0.86); fm.roughness = 0.9
	var kinds: PackedStringArray = String(args.get("kinds", "ashigaru,archer,captain")).split(",", false)
	var gap := float(args.get("gap", 1.3))
	var drivers := []
	UBCDriver.vary_enabled = args.has("vary")
	if args.has("nofix"): GroundFix.enabled = false   # v0.22: the old sunk pose
	if args.has("vary"): UBCDriver.vary_seed_base = int(args["vary"])
	UBCDriver.gear_enabled = not args.has("nogear")
	var beards: PackedStringArray = String(args.get("beard", "")).split(",")
	for k in kinds.size():
		var host := Node3D.new()
		host.position = Vector3((k - (kinds.size() - 1) * 0.5) * gap, 0, 0)
		host.rotation.y = float(args.get("yaw", 0.0))
		add_child(host)
		UBCDriver.beard_force = beards[mini(k, beards.size() - 1)]
		var d := UBCDriver.new()
		host.add_child(d)
		if not d.build(host, "", kinds[k], false): push_error("build failed " + kinds[k]); continue
		drivers.append(d)
	var clip := String(args.get("clip", ""))
	var at := float(args.get("at", 0.0))
	for d in drivers:
		var ap: AnimationPlayer = d.anim_player
		var lib := clip
		if clip != "" and d.ubc.map.has(clip): lib = String(d.ubc.map[clip][0])
		elif clip != "" and UBCDriver.STATES.has(clip): lib = String(UBCDriver.STATES[clip])
		elif clip == "": lib = String((UBCDriver.KINDS.get(d.kind, {}) as Dictionary).get("_idle_combat", "Idle")) if args.has("combat") else "Idle"
		if not ap.has_animation(lib): push_error("no clip " + lib); continue
		ap.play(lib)
		ap.pause()
		ap.seek(at, true)
		ap.advance(0.0)
		if args.has("drawn") or (UBCDriver.ATTACKS.get(d.kind, {}) as Dictionary).has(clip): d._set_drawn(true)
	# --sim N: run the live driver for N frames (state / look / shoot options)
	if args.has("sim"):
		var lookp := Vector3(0, 1.4, 12)
		if args.has("look"):
			var lp := String(args["look"]).split(",")
			lookp = Vector3(float(lp[0]), float(lp[1]), float(lp[2]))
		for d in drivers:
			(d.anim_player as AnimationPlayer).play("Idle")
			if args.has("state"): d.ubc.travel(String(args["state"]))
			if args.has("drawn"): d._set_drawn(true)
			d.look_at_point(lookp)
		var nsim := int(args["sim"])
		var shoot_at := int(args.get("shoot", -1))
		for k in nsim:
			for d in drivers:
				if k == shoot_at: d.action("Shoot")
				d.tick(1.0 / 30.0, Vector3.ZERO, 0.0, false)
			await get_tree().process_frame
	if args.has("wet"): CharWet.set_level(float(args["wet"]))
	if args.has("cold"): BreathFX.cold = float(args["cold"])
	if args.has("puff"):
		for d in drivers:
			if d.breath != null:
				if args.has("exert"): d.anatomy.exertion = float(args["exert"])
				d.breath.puff()
		await get_tree().create_timer(float(args["puff"])).timeout
	var cam := Camera3D.new(); add_child(cam); cam.fov = float(args.get("fov", 30))
	var dist := float(args.get("dist", 6.0)); var hh := float(args.get("height", 1.0))
	var target := Vector3(float(args.get("cx", 0.0)), hh, 0)
	var rise := float(args.get("rise", 0.25))
	var base := String(args.get("out", "/tmp/en"))
	var times: PackedStringArray = String(args.get("times", str(at))).split(",", false)
	if args.has("sim"): times = PackedStringArray(["0"])
	for ti in times.size():
		for d in drivers:
			if args.has("sim"): break
			var ap: AnimationPlayer = d.anim_player
			if ap.current_animation != "" or ap.assigned_animation != "":
				ap.seek(float(times[ti]), true)
				ap.advance(0.0)
				(d.skeleton as Skeleton3D).force_update_all_bone_transforms()
		await get_tree().process_frame
		await get_tree().process_frame
		for mode in String(args.get("cams", "front")).split(",", false):
			match mode:
				"front": cam.position = target + Vector3(0, rise, dist)
				"back": cam.position = target + Vector3(0, rise, -dist)
				"side": cam.position = target + Vector3(dist, rise, 0)
				"q": cam.position = target + Vector3(dist * 0.55, rise * 2.4, dist * 0.83)
				"close": cam.position = target + Vector3(dist * 0.2, 0.1, dist * 0.98)
			cam.look_at(target)
			for f in 3: await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(base + "_" + mode + ("_%d" % ti if times.size() > 1 else "") + ".png")
	get_tree().quit()
