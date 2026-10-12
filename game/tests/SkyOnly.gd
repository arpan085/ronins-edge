extends Node3D
## Sky preview with no world load: fast iteration on shaders/sky.gdshader.
## v0.17: drives the sky through the real DayNight (exposure, twilight, the CPU
## atmosphere twin), and puts a grey ball on a grass-coloured disc in front of
## the camera so the ambient light the sky produces is visible too. Writes to
## user://sky. Optional: only=name,name  w= h=

func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with(key + "="): return s.substr(key.length() + 1)
	return def

func _ready() -> void:
	get_viewport().get_window().size = Vector2i(int(_arg("w", "640")), int(_arg("h", "360")))
	DirAccess.make_dir_recursive_absolute("user://sky")
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/sky.gdshader")
	mat.set_shader_parameter("octaves", int(_arg("oct", "5")))
	RenderingServer.global_shader_parameter_set("cloud_time", 11.0)
	var sky := Sky.new()
	sky.sky_material = mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_white = 4.0
	e.glow_enabled = true
	e.glow_intensity = 0.42
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 1.45
	e.glow_hdr_scale = 1.8
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.10
	e.adjustment_contrast = 1.05
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.62, 0.80)
	add_child(moon)
	var dn := DayNight.new()
	add_child(dn)
	dn.setup(sun, moon, e, mat)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	ball.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.5, 0.5, 0.5)
	ball.material_override = bm
	add_child(ball)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.22, 0.28, 0.12)
	ground.material_override = gm
	add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 72.0
	add_child(cam)
	cam.make_current()
	if mat.shader == null:
		print("SKY FAIL shader did not load"); get_tree().quit(); return
	var cases := [
		{"n": "noon", "h": 12.0, "cover": 0.32, "storm": 0.0, "turb": 1.25, "look": "away", "pitch": 18.0},
		{"n": "morning", "h": 8.0, "cover": 0.32, "storm": 0.0, "turb": 1.25, "look": "sun", "pitch": 10.0},
		{"n": "golden", "h": 17.35, "cover": 0.32, "storm": 0.0, "turb": 1.25, "look": "sun", "pitch": 6.0},
		{"n": "golden_away", "h": 17.35, "cover": 0.32, "storm": 0.0, "turb": 1.25, "look": "away", "pitch": 8.0},
		{"n": "sunset", "h": 17.9, "cover": 0.42, "storm": 0.0, "turb": 1.25, "look": "sun", "pitch": 6.0},
		{"n": "dusk", "h": 19.2, "cover": 0.36, "storm": 0.0, "turb": 1.25, "look": "sun", "pitch": 8.0},
		{"n": "cloudy", "h": 13.0, "cover": 0.62, "storm": 0.0, "turb": 1.41, "look": "away", "pitch": 12.0},
		{"n": "storm", "h": 15.0, "cover": 0.98, "storm": 1.0, "turb": 2.0, "look": "sun", "pitch": 8.0},
		{"n": "mist", "h": 6.6, "cover": 0.54, "storm": 0.0, "turb": 2.3, "look": "sun", "pitch": 6.0},
		{"n": "night", "h": 23.0, "cover": 0.30, "storm": 0.0, "turb": 1.25, "look": "moon", "pitch": 22.0},
	]
	var only := _arg("only", "")
	for c in cases:
		if only != "" and not (only.split(",") as Array).has(str(c["n"])): continue
		dn.turbidity = float(c["turb"])
		RenderingServer.global_shader_parameter_set("cloud_cover", float(c["cover"]))
		RenderingServer.global_shader_parameter_set("cloud_storm", float(c["storm"]))
		dn.set_hour(float(c["h"]))
		var az := deg_to_rad(-110.0 + (float(c["h"]) / 24.0) * 300.0)
		var yaw := az + PI
		if str(c["look"]) == "away": yaw = az
		elif str(c["look"]) == "moon":
			var md: Vector3 = Basis.from_euler(moon.rotation).z
			yaw = atan2(md.x, md.z) + PI
		cam.rotation = Vector3(deg_to_rad(float(c["pitch"])), yaw, 0.0)
		var fwd := -cam.global_transform.basis.z
		var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
		cam.position = Vector3(0, 1.6, 0)
		ball.position = cam.position + flat * 6.0 + Vector3(0, -0.9, 0)
		ground.position = Vector3(0, -0.05, 0)
		for i in 5:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://sky/%s.png" % str(c["n"]))
		print("SKY shot ", c["n"], " sx=", snappedf(dn.sky_exposure, 0.01), " art=", snappedf(dn.art_mix, 0.01),
			" e=", snappedf(dn.sky_elevation(), 0.01), " zen=", dn.sky_zenith, " hor=", dn.sky_horizon)
	print("SKY DONE")
	get_tree().quit()
