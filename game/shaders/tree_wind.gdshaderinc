// Shared by tree_bark.gdshader and tree_leaf.gdshader (v0.14).
// Same travelling gust field as grass.gdshader so a gust crosses the meadow
// and then reaches the trees. Motion is deliberately slow and small: v0.13
// fluttered leaves at ~0.5 Hz with up to 35 cm amplitude, which read as a
// storm in a light breeze.

uniform vec2 wind_dir = vec2(0.86, 0.51);
uniform float wind_strength : hint_range(0.0, 3.0) = 0.6;
uniform float gust : hint_range(0.0, 3.0) = 0.0;
uniform float gust_speed : hint_range(0.0, 30.0) = 2.0;
uniform float gust_scale : hint_range(0.005, 0.2) = 0.030;
uniform float sway_scale = 0.07;   // leaf flutter, metres per unit wind
uniform float trunk_sway = 0.012;  // whole-tree lean, metres per metre of bend
uniform float season : hint_range(0.0, 1.0) = 0.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;

float tw_hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float tw_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = tw_hash21(i);
	float b = tw_hash21(i + vec2(1.0, 0.0));
	float c = tw_hash21(i + vec2(0.0, 1.0));
	float d = tw_hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// v: model-space vertex, bw: bend weight (COLOR.r), rnd: per-card random,
// wp: instance origin in world space, phase: per-instance phase.
vec3 tree_wind(vec3 v, float bw, float rnd, vec3 wp, float phase, float time) {
	vec2 wd = normalize(wind_dir + vec2(0.0001));
	vec2 flow = wp.xz - wd * time * gust_speed;
	float gf = tw_noise(flow * gust_scale) * 0.70 + tw_noise(flow * gust_scale * 3.7 + 17.13) * 0.30;
	gf = gf * gf * (3.0 - 2.0 * gf);
	float amp = wind_strength * (0.35 + 0.65 * gf) + gust * gf;
	vec3 w3 = vec3(wd.x, 0.0, wd.y);
	// slow whole-tree lean (period ~10-25 s), grows with height
	float slow = sin(time * 0.42 + phase) * 0.6 + sin(time * 0.19 + phase * 1.7) * 0.4;
	vec3 off = w3 * (0.45 + 0.55 * slow) * amp * trunk_sway * bw * bw * 10.0;
	// leaf flutter: each card on its own phase, small and unhurried
	float fl = sin(time * 1.15 + rnd * 6.2831 + phase) * 0.6 + sin(time * 1.75 + rnd * 17.0) * 0.4;
	off += (w3 * 0.7 + vec3(0.0, 0.45, 0.0)) * fl * amp * sway_scale * smoothstep(0.45, 1.0, bw);
	return v + off;
}
