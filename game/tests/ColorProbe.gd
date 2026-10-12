extends Node3D
## Does Godot 4.3 convert source_color uniform DEFAULTS (and Color params) to linear?
func _ready() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded;
uniform vec3 c_def : source_color = vec3(0.5, 0.5, 0.5);
uniform vec3 c_set : source_color = vec3(0.0);
uniform vec3 c_vec : source_color = vec3(0.0);
uniform int which = 0;
void fragment() {
	ALBEDO = which == 0 ? c_def : (which == 1 ? c_set : c_vec);
}
"""
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 5)
	add_child(cam)
	for i in 3:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("which", i)
		m.set_shader_parameter("c_set", Color(0.5, 0.5, 0.5))
		m.set_shader_parameter("c_vec", Vector3(0.5, 0.5, 0.5))
		var q := MeshInstance3D.new()
		var pm := QuadMesh.new()
		pm.size = Vector2(1.5, 3.0)
		q.mesh = pm
		q.material_override = m
		q.position = Vector3(-1.6 + i * 1.6, 0, 0)
		add_child(q)
	for f in 10:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	for i in 3:
		var x := int(w * 0.5 + (-1.6 + i * 1.6) / 5.0 * h * 0.5 / tan(deg_to_rad(37.5)))
		var c := img.get_pixel(clampi(x, 0, w - 1), h / 2)
		print("COLORPROBE ", ["default", "Color", "Vector3"][i], " -> ", c.r, " (0.5=converted-as-sRGB, 0.735=raw linear)")
	get_tree().quit()
