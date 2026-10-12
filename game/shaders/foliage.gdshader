shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Shared shader for every dressed prop family (grass, bamboo, sakura...).
// It used to sample one colour texture, set a flat roughness and stop, which
// threw away two things already paid for: the AO the mesh library bakes into
// COLOR.g, and the matching normal/roughness pairs in assets/textures.

uniform sampler2D base_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D norm_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float uv_scale = 2.0;
uniform float norm_strength : hint_range(0.0, 3.0) = 1.0;
uniform float rough_min : hint_range(0.0, 1.0) = 0.62;
uniform float rough_max : hint_range(0.0, 1.0) = 0.94;
uniform float specular_level : hint_range(0.0, 1.0) = 0.22;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.55;
// Per-instance macro variation. Every family is one mesh drawn by a MultiMesh,
// so without this a hundred identical clumps read as a hundred copies of the
// same object rather than a hundred clumps.
uniform float variation : hint_range(0.0, 1.0) = 0.16;
uniform float sway = 0.0;
uniform float sway_speed = 1.0;
uniform float sway_height = 1.0;
uniform float wind_dir = 0.7;

varying float v_var;

void vertex() {
	vec2 o = vec2(MODEL_MATRIX[3].x, MODEL_MATRIX[3].z);
	v_var = fract(sin(dot(o, vec2(12.9898, 78.233))) * 43758.5453);
	float h = max(VERTEX.y, 0.0) / max(sway_height, 0.001);
	float w = clamp(h, 0.0, 1.6);
	float ph = TIME * sway_speed + (o.x + o.y) * 0.35;
	float s = sin(ph) * 0.6 + sin(ph * 2.3) * 0.4;
	VERTEX.x += s * sway * w * wind_dir;
	VERTEX.z += s * sway * w * (1.0 - wind_dir);
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 c = texture(base_tex, uv).rgb * tint.rgb;
	c *= mix(1.0 - variation, 1.0 + variation, v_var);
	c *= vec3(1.0 + (v_var - 0.5) * variation * 0.5, 1.0,
			  1.0 - (v_var - 0.5) * variation * 0.5);
	float ao = mix(1.0 - ao_strength, 1.0, COLOR.g);
	ALBEDO = c * ao;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	float r = texture(rough_tex, uv).r;
	ROUGHNESS = clamp(mix(rough_min, rough_max, r) + (v_var - 0.5) * 0.10, 0.04, 1.0);
	METALLIC = 0.0;
	SPECULAR = specular_level;
	NORMAL_MAP = texture(norm_tex, uv).rgb;
	NORMAL_MAP_DEPTH = norm_strength;
}
