shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D base_tex : hint_default_white, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float sway = 0.0;
uniform float sway_speed = 1.0;
uniform float sway_height = 1.0;
uniform float wind_dir = 0.7;

void vertex() {
	// sway grows with height above the instance origin
	float h = max(VERTEX.y, 0.0) / max(sway_height, 0.001);
	float w = clamp(h, 0.0, 1.6);
	float ph = TIME * sway_speed + (MODEL_MATRIX[3].x + MODEL_MATRIX[3].z) * 0.35;
	float s = sin(ph) * 0.6 + sin(ph * 2.3) * 0.4;
	VERTEX.x += s * sway * w * wind_dir;
	VERTEX.z += s * sway * w * (1.0 - wind_dir);
}

void fragment() {
	vec2 uv = UV * 2.0;
	vec3 c = texture(base_tex, uv).rgb * tint.rgb;
	ALBEDO = c;
	ROUGHNESS = 0.82;
	METALLIC = 0.0;
	SPECULAR = 0.15;
}
