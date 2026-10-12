// v0.17 shared cloud field: the sky draws it (shaders/sky.gdshader) and the
// landscape shaders use it to cast moving cloud shadows, so a shadow on a far
// hill is under a cloud you can see. Driven by global shader uniforms that
// Weather writes every frame (project.godot [shader_globals]).

global uniform float cloud_cover;    // 0 clear .. 1 overcast
global uniform float cloud_storm;
global uniform float cloud_time;     // km of drift accumulated by Weather
global uniform vec3 cloud_sun;       // towards the sun (the scattering sun)
global uniform float cloud_shadow;   // 0 off (low tiers) .. 1

const float CLOUD_BASE_KM = 1.6;

float cl_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float cl_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = cl_hash12(i);
	float b = cl_hash12(i + vec2(1.0, 0.0));
	float c = cl_hash12(i + vec2(0.0, 1.0));
	float d = cl_hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractional octave count; dropped octaves contribute their mean so the
// coverage threshold stays put and clouds lose detail rather than shrinking.
float cl_fbm(vec2 p, float oct) {
	const mat2 R = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 7; i++) {
		float w = clamp(oct - float(i), 0.0, 1.0);
		if (w <= 0.0) break;
		v += a * mix(0.5, cl_vnoise(p), w);
		p = R * p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return v + a;
}

// deck position (km, world-anchored) -> warped noise coordinates
vec2 cl_deck_uv(vec2 pkm) {
	vec2 pc = pkm + vec2(0.92, 0.38) * cloud_time;
	vec2 wq = pc * 0.06;
	vec2 warp = vec2(cl_fbm(wq + vec2(3.1, 7.7) + cloud_time * 0.0125, 2.0),
		cl_fbm(wq + vec2(8.3, 1.9) - cloud_time * 0.0125, 2.0)) - 0.5;
	return pc * 0.55 + warp * 2.2;
}

float cl_thr() { return mix(0.64, 0.24, cloud_cover); }
float cl_soft() { return mix(0.13, 0.26, cloud_cover); }

// cumulus density for a noise value n
float cl_density(float n) {
	float d = smoothstep(cl_thr(), cl_thr() + cl_soft(), n);
	float strat = smoothstep(0.62, 0.95, cloud_cover);
	return mix(d, max(d, 0.45 + 0.55 * n), strat);
}

// Direct-sun factor at a world position (metres): 1 in sunlight, down to ~0.35
// under a thick cloud. The shadow fades in past `near_m` from the camera so it
// never darkens the ground under the player while the player stays lit.
float cloud_shadow_at(vec3 wp, float cam_dist, float near_m) {
	if (cloud_shadow <= 0.0 || cloud_sun.y < 0.03) return 1.0;
	float fade = smoothstep(near_m, near_m * 2.2, cam_dist) * cloud_shadow;
	if (fade <= 0.001) return 1.0;
	// follow the sun ray up to the deck
	vec3 s = normalize(cloud_sun);
	float up = max(CLOUD_BASE_KM * 1000.0 - wp.y, 0.0) / max(s.y, 0.08);
	vec2 q = (wp.xz + s.xz * up) * 0.001;
	float n = cl_fbm(cl_deck_uv(q), 4.0);
	float dens = cl_density(n);
	float a = 1.0 - exp(-dens * 4.5 * (1.0 + cloud_storm));
	// low sun: the shadows smear out and weaken
	float k = 0.62 * smoothstep(0.03, 0.25, s.y);
	return 1.0 - a * k * fade;
}
