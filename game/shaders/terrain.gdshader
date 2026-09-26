shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D splat_tex : hint_default_black, filter_linear_mipmap;
uniform sampler2D grass_tex : hint_default_white, filter_linear_mipmap;
uniform sampler2D dirt_tex  : hint_default_white, filter_linear_mipmap;
uniform sampler2D rock_tex  : hint_default_white, filter_linear_mipmap;
uniform sampler2D detail_n  : hint_normal, filter_linear_mipmap;
uniform sampler2D macro_tex : hint_default_white, filter_linear_mipmap;
uniform float world_size = 480.0;
uniform vec3 grass_tint : source_color = vec3(0.42, 0.52, 0.28);
uniform vec3 dirt_tint  : source_color = vec3(0.46, 0.38, 0.26);
uniform vec3 rock_tint  : source_color = vec3(0.55, 0.54, 0.52);
uniform float detail_scale = 22.0;
uniform float macro_scale = 0.9;
uniform float wetness = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz / world_size + 0.5;
	vec3 splat = texture(splat_tex, uv).rgb;
	float road = clamp(splat.r, 0.0, 1.0);
	float rocky = clamp(splat.g, 0.0, 1.0);
	float wet = clamp(splat.b, 0.0, 1.0);

	vec2 duv = world_pos.xz / detail_scale;
	vec3 g = texture(grass_tex, duv).rgb * grass_tint;
	vec3 d = texture(dirt_tex, duv * 0.7).rgb * dirt_tint;
	vec3 r = texture(rock_tex, duv * 1.3).rgb * rock_tint;

	// macro variation kills obvious tiling
	float macro = texture(macro_tex, world_pos.xz / (world_size * macro_scale)).r;
	macro = mix(0.82, 1.18, macro);

	vec3 albedo = mix(g, d, clamp(road * 1.15, 0.0, 1.0));
	albedo = mix(albedo, r, clamp(rocky * 1.2, 0.0, 1.0));
	albedo *= macro;

	vec3 n1 = texture(detail_n, duv).xyz * 2.0 - 1.0;
	vec3 n2 = texture(detail_n, duv * 3.7).xyz * 2.0 - 1.0;
	vec3 nrm = normalize(vec3(n1.xy * 0.6 + n2.xy * 0.4, 1.0));

	ALBEDO = albedo;
	NORMAL_MAP = nrm;
	ROUGHNESS = mix(0.92, 0.55, clamp(rocky + wet, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = mix(0.12, 0.35, wet);
	// wet ground darkens slightly
	ALBEDO = mix(ALBEDO, ALBEDO * 0.65, wet * 0.6);
}
