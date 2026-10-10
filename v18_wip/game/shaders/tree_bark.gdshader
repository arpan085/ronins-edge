shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/clouds.gdshaderinc"

// Tree trunks and limbs (v0.14). UV.x = turns around the limb, UV.y = metres
// along it, so the Poly Haven bark tiles at a real-world scale on every limb.
// Bamboo culms are procedural (green with nodes) via the `bamboo` switch.

#include "res://shaders/tree_wind.gdshaderinc"

uniform sampler2D bark_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 bark_tint : source_color = vec3(1.0);
uniform float bark_tile_m = 1.2;
uniform float normal_depth = 1.0;
uniform int dbg = 0;
uniform vec3 dbg_col = vec3(1.0, 0.0, 0.0);
uniform float bamboo = 0.0;

varying float v_ao;
varying float v_var;
varying vec3 v_wn;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = INSTANCE_CUSTOM.x * 6.2831;
	VERTEX = tree_wind(VERTEX, COLOR.r, 0.0, wp, phase, TIME);
	v_ao = COLOR.g;
	v_var = INSTANCE_CUSTOM.z;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c;
	if (bamboo > 0.5) {
		float node = abs(fract(UV.y / 0.42) - 0.5) * 2.0;
		float ring = smoothstep(0.90, 0.985, node);
		vec3 g = mix(vec3(0.33, 0.42, 0.15), vec3(0.50, 0.50, 0.24), v_var);
		c = mix(g, g * 0.55 + vec3(0.07, 0.06, 0.02), ring);
		c *= 0.92 + 0.08 * sin(UV.x * 37.0 + UV.y * 0.7);
		ROUGHNESS = 0.42;
		SPECULAR = 0.45;
	} else {
		vec2 uv = vec2(UV.x, UV.y / bark_tile_m);
		c = texture(bark_albedo, uv).rgb * bark_tint * mix(0.88, 1.12, v_var);
		NORMAL_MAP = texture(bark_normal, uv).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
		ROUGHNESS = 0.92;
		SPECULAR = 0.3;
	}
	c *= mix(0.45, 1.0, v_ao);
	c *= mix(1.0, 0.62, wetness);
	float up = clamp(v_wn.y, 0.0, 1.0);
	c = mix(c, vec3(0.86, 0.89, 0.95), snow * smoothstep(0.35, 0.8, up) * 0.85);
	ALBEDO = c;
	// v0.17 moving cloud shadows (shaders/clouds.gdshaderinc), mid and far field only
	{
		float cdist = length(VERTEX);
		if (cdist > 110.0) {
			ALBEDO *= cloud_shadow_at((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, cdist, 110.0);
		}
	}
	ROUGHNESS = mix(ROUGHNESS, 0.35, wetness);
	if (dbg == 2) { EMISSION = ALBEDO; ALBEDO = vec3(0.0); SPECULAR = 0.0; }
	else if (dbg == 5) { EMISSION = dbg_col * 0.5; ALBEDO = vec3(0.0); SPECULAR = 0.0; }
}
