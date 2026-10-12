extends Node3D
## Minimal water rig: a green bed, a water quad 0.35 m above it, a grazing
## camera. Renders the shader's intermediate terms so a wash-out can be
## attributed instead of guessed at. This is how the depth-buffer read was
## caught returning zero.

var cam: Camera3D
var mat: ShaderMaterial
var modes := ["final", "behind", "depthbuf", "opacity", "foam", "fresnel",
			  "rawdepth", "invdepth", "surfz", "shore"]
var idx := 0
var t := 0.0

func _ready() -> void:
	get_viewport().get_window().size = Vector2i(520, 380)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.45, 0.60, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.7, 0.85)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, 40.0, 0.0)
	key.light_energy = 1.6
	add_child(key)
	var bed := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	bed.mesh = pm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.22, 0.34, 0.16)
	bm.roughness = 0.95
	bed.material_override = bm
	add_child(bed)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(-7, 0.35, -7), Vector3(7, 0.35, -7),
				Vector3(7, 0.35, 7), Vector3(-7, 0.35, 7)]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[i])
		st.set_uv2(Vector2(0, 1))
		st.set_color(Color(0.3125, 0, 0, 1))
		st.add_vertex(pts[i])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("ripple_n", load("res://assets/textures/metal_n.png"))
	mat.set_shader_parameter("ssr_steps", 12)
	mat.set_shader_parameter("refract_strength", 0.045)
	mat.set_shader_parameter("clarity", 2.60)
	mi.material_override = mat
	add_child(mi)
	cam = Camera3D.new()
	cam.fov = 48.0
	add_child(cam)
	cam.global_position = Vector3(0.0, 1.4, 9.0)
	cam.look_at(Vector3(0.0, 0.35, -3.0))
	print("WPROBE adapter=", RenderingServer.get_video_adapter_name(),
		" method=", ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	_set_mode()

func _set_mode() -> void:
	mat.set_shader_parameter("debug_mode", idx)
	t = 0.0

func _process(delta: float) -> void:
	if idx >= modes.size(): return
	t += delta
	if t < 0.5: return
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://wprobe")
	img.save_png("user://wprobe/%d_%s.png" % [idx, modes[idx]])
	print("WPROBE ", modes[idx])
	idx += 1
	if idx >= modes.size():
		print("WPROBE_DONE")
		get_tree().quit()
		return
	_set_mode()
