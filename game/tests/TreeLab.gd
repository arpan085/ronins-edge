extends Node3D
## Tree render lab (v0.14): one tree per family at LOD 0/1/2 side by side on a
## flat lawn under a sky, so tree meshes/shaders can be judged without the world.
##   renv.sh res://tests/TreeLab.tscn -- fams=pine,maple out=/tmp/tree [dist=26] [h=5]

var out := "/tmp/tree"

func _ready() -> void:
	var ua := OS.get_cmdline_user_args()
	var fams := ["pine", "cedar", "maple", "sakura", "bamboo", "young_tree", "dead_tree"]
	var dist := 30.0
	var camh := 3.0
	var size := Vector2i(900, 520)
	for a in ua:
		var s := String(a)
		if s.begins_with("fams="): fams = s.substr(5).split(",")
		elif s.begins_with("out="): out = s.substr(4)
		elif s.begins_with("dist="): dist = float(s.substr(5))
		elif s.begins_with("h="): camh = float(s.substr(2))
	get_viewport().get_window().size = size
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var ps := ProceduralSkyMaterial.new()
	ps.sky_top_color = Color(0.32, 0.50, 0.78)
	ps.sky_horizon_color = Color(0.72, 0.78, 0.84)
	ps.ground_horizon_color = Color(0.55, 0.58, 0.55)
	sky.sky_material = ps
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(-35), 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.30, 0.38, 0.20)
	fm.roughness = 1.0
	mi.material_override = fm
	add_child(mi)
	var ts := TreeSystem.new()
	add_child(ts)
	var cam := Camera3D.new()
	cam.fov = 50
	add_child(cam)
	var i := 0
	for f in fams:
		var fam := String(f)
		var base := Vector3(float(i) * 300.0, 0, 0)
		for lod in 3:
			var m: ArrayMesh = ts._mesh_for(fam, 0, lod)
			var t := MeshInstance3D.new()
			t.mesh = m
			t.position = base + Vector3((float(lod) - 1.0) * 17.0, 0, 0)
			t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(t)
		cam.position = base + Vector3(0, camh, dist)
		cam.look_at(base + Vector3(0, 5.5, 0), Vector3.UP)
		for k in 6: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s_%s.png" % [out, fam])
		print("TREELAB saved ", fam)
		i += 1
	get_tree().quit()
