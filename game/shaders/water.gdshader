shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D ripple_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.035, 0.085, 0.12);
uniform vec3 shallow_color : source_color = vec3(0.10, 0.20, 0.22);
uniform float flow_speed = 0.035;
uniform float ripple_scale = 0.09;
uniform float strength = 0.55;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz;
	vec2 a = uv * ripple_scale + vec2(TIME * flow_speed, TIME * flow_speed * 0.6);
	vec2 b = uv * ripple_scale * 1.9 - vec2(TIME * flow_speed * 1.4, TIME * flow_speed * 0.4);
	vec3 n1 = texture(ripple_n, a).xyz * 2.0 - 1.0;
	vec3 n2 = texture(ripple_n, b).xyz * 2.0 - 1.0;
	vec3 nrm = normalize(vec3((n1.xy + n2.xy) * strength, 1.0));
	NORMAL_MAP = nrm;
	ALBEDO = mix(deep_color, shallow_color, clamp(nrm.y * 0.5 + 0.5, 0.0, 1.0));
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.85;
}
