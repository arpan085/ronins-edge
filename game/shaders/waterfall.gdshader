shader_type spatial;
render_mode cull_disabled, depth_draw_never, diffuse_burley, specular_schlick_ggx;

// v0.13 waterfall sheet (and, with mode 1, the foam disc of a plunge pool).
//
// UV.x runs across the sheet (0..1), UV.y down it from the lip (0) to the
// pool (1); UV2 carries the sheet's size in metres. The streak pattern is
// advected in "time since leaving the lip": falling water accelerates, so a
// fixed spatial scroll would slide the pattern like a conveyor belt, while
// sampling by flight time stretches it out lower down exactly as real water
// does. COLOR.r shifts the phase so the two layers of a fall differ.

uniform sampler2D foam_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 water_col : source_color = vec3(0.17, 0.29, 0.30);
uniform vec3 foam_col : source_color = vec3(0.90, 0.94, 0.95);
uniform float lip_speed = 1.7;       // m/s as the water leaves the lip
uniform float opacity : hint_range(0.0, 1.0) = 0.86;
uniform int mode : hint_range(0, 1) = 0;
uniform bool debug_solid = false;   // test harness mask

varying vec2 v_m;

void vertex() {
	v_m = UV * UV2;
	if (mode == 0) {
		// the sheet trembles as it falls
		float w = sin(UV.y * 11.0 - TIME * 7.0 + UV.x * 5.0 + COLOR.r * 3.0);
		VERTEX += NORMAL * w * 0.035 * UV.y;
	} else {
		VERTEX.y += sin(v_m.x * 2.1 - TIME * 2.6) * cos(v_m.y * 1.8 + TIME * 1.9) * 0.05;
	}
}

void fragment() {
	float ph = COLOR.r * 7.31;
	float white;
	float a;
	vec3 nm;
	if (mode == 0) {
		float g = 9.8;
		float y = v_m.y;
		float tau = (sqrt(lip_speed * lip_speed + 2.0 * g * y) - lip_speed) / g;
		float t = TIME + ph;
		float s1 = texture(foam_noise, vec2(v_m.x * 0.30 + ph, (tau - t) * 1.05)).g;
		float s2 = texture(foam_noise, vec2(v_m.x * 0.85 - ph, (tau - t * 1.06) * 2.4)).b;
		float lace = texture(foam_noise, vec2(v_m.x * 0.22 + ph * 0.5, (tau - t) * 0.55)).r;
		float streak = s1 * 0.6 + s2 * 0.4;
		float v = UV.y;
		// more air lower down: whiter and more broken
		float aer = smoothstep(0.0, 0.75, v);
		white = clamp(smoothstep(0.50 - aer * 0.28, 0.80, streak + lace * 0.35) * (0.6 + aer * 0.4)
			+ aer * 0.22, 0.0, 1.0);
		// ragged sides: the sheet thins and tears at its edges
		float side = min(UV.x, 1.0 - UV.x) * UV2.x;
		float edge = smoothstep(0.0, 0.35 + streak * 1.1, side);
		float top = smoothstep(0.0, 0.05, v);
		a = opacity * edge * top * (0.50 + 0.50 * smoothstep(0.30, 0.70, streak + white * 0.3));
		// breaks into spray just above the pool
		a *= 1.0 - smoothstep(0.86, 1.0, v) * (1.0 - white) * 0.75;
		nm = texture(ripple_n, vec2(v_m.x * 0.5, (tau - t) * 1.6)).rgb;
	} else {
		// plunge-pool foam: a web pushed outward from the impact
		vec2 c = UV * 2.0 - 1.0;
		float r = length(c);
		float ang = atan(c.y, c.x);
		float t = TIME * 0.35 + ph;
		float w1 = texture(foam_noise, vec2(ang * 0.9549, r * 1.3 - t)).r;
		float w2 = texture(foam_noise, vec2(ang * 1.5915 + 0.37, r * 2.1 - t * 1.4)).r;
		float web = w1 * 0.6 + w2 * 0.5;
		white = smoothstep(0.20 + r * 0.35, 0.60 + r * 0.2, web + (1.0 - r) * 0.45);
		a = white * (1.0 - smoothstep(0.55, 1.0, r)) * opacity;
		nm = texture(ripple_n, UV * UV2 * 0.4 + vec2(t * 0.3, 0.0)).rgb;
	}
	ALBEDO = mix(water_col, foam_col, white);
	ALPHA = clamp(a, 0.0, 1.0);
	ROUGHNESS = mix(0.12, 0.65, white);
	SPECULAR = 0.5;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 0.8;
	// thin water glows when the sun is behind it
	BACKLIGHT = vec3(0.28, 0.32, 0.30) * (0.35 + white * 0.65);
	if (debug_solid) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(0.0, 1.0, 1.0);
		ALPHA = a > 0.02 ? 1.0 : 0.0;
	}
}
