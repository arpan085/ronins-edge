shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled, depth_prepass_alpha;

// Instanced grass / ground cover.
//
// Motion is a travelling GUST FIELD, not a sine. Two octaves of value noise
// are sampled at (world_xz - wind_dir * TIME), so gust cells drift downwind
// and whole patches of the field lie over and stand back up as they pass.
// A pair of sine waves -- what this used to be -- always reads as a regular
// corrugation, because that is what it is.
//
// The bend itself is a rotation about the blade's root (Rodrigues, with the
// angle scaled by COLOR.r so the root stays planted and the tip travels
// furthest). Rotation is length-preserving, so a blade in a 60-degree gust
// arcs over instead of shearing into a parallelogram.
//
// Vertex colour: r = bend weight 0..1, g = baked AO, b = seed-plume flag.
// Per-instance variation rides in INSTANCE_CUSTOM (x phase, z tint, w dryness).

uniform sampler2D base_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint_lush : source_color = vec3(0.26, 0.47, 0.16);
uniform vec3 tint_dry : source_color = vec3(0.52, 0.54, 0.26);
uniform vec3 tint_root : source_color = vec3(0.19, 0.25, 0.11);
// Dusty straw, not white. A plume at 0.64 linear under a 1.55-energy sun
// tonemaps to nearly pure white and the field looked like it was in flower.
uniform vec3 tint_plume : source_color = vec3(0.44, 0.44, 0.33);
uniform vec2 wind_dir = vec2(0.86, 0.51);
uniform float wind_strength : hint_range(0.0, 3.0) = 0.6;
uniform float gust : hint_range(0.0, 3.0) = 0.0;
uniform float gust_speed : hint_range(0.0, 30.0) = 2.2;   // m/s the gust cells travel
uniform float gust_scale : hint_range(0.005, 0.2) = 0.030; // 1/metres of the big swells
uniform float flutter : hint_range(0.0, 1.0) = 0.06;
uniform float bend_scale = 0.45;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.45;
// Blades standing at eye level directly under the camera block the whole view.
// Shrink them over the last couple of metres instead of popping them out.
uniform float cam_fade_start = 3.6;
uniform float cam_fade_end = 1.3;
uniform vec3 ground_tint : source_color = vec3(0.26, 0.32, 0.16);
uniform float ground_blend : hint_range(0.0, 1.0) = 0.55;
uniform float backlight_amount : hint_range(0.0, 1.5) = 0.45;

// player / actor trail: xyz = world position, w = remaining strength 0..1
const int TRAIL_MAX = 12;
uniform vec4 trail[TRAIL_MAX];
uniform float trail_radius = 1.5;
uniform float trail_push = 0.85;

varying float v_bend;
varying float v_dry;
varying float v_tintv;
varying float v_plume;
varying float v_lit;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(vec3(0.0), 1.0)).xyz;   // instance root in world
	float phase = INSTANCE_CUSTOM.x * 6.2831;
	v_dry = INSTANCE_CUSTOM.w;
	v_tintv = INSTANCE_CUSTOM.z;
	v_bend = COLOR.r;
	v_plume = COLOR.b;
	float bw = COLOR.r;

	vec2 wd = normalize(wind_dir + vec2(0.0001));

	// ---- travelling gust field -------------------------------------------
	// Sampling at (position - wind * time) makes the pattern move downwind at
	// gust_speed while staying locked to the world, so a gust front crosses
	// the field as a visible band instead of every blade phasing alone.
	vec2 flow = wp.xz - wd * TIME * gust_speed;
	float g1 = vnoise(flow * gust_scale);                   // ~30 m swells
	float g2 = vnoise(flow * gust_scale * 3.7 + 17.13);     // ~8 m ripples
	float gf = g1 * 0.70 + g2 * 0.30;
	gf = gf * gf * (3.0 - 2.0 * gf);                        // sharpen the fronts

	// Base lean plus the gust, plus a fast per-blade flutter so the surface
	// shimmers even in a lull.
	float amp = wind_strength * (0.30 + 1.00 * gf) + gust * gf;
	// v0.14: 0.27 Hz, not 0.84 Hz -- the field used to shiver like a fan was on it
	float flut = sin(TIME * 1.7 + phase * 3.1 + dot(wp.xz, wd) * 0.35) * flutter;
	float sway = amp * (1.0 + flut);
	// Seed plumes are light and whip further than the leaves.
	sway *= 1.0 + 0.35 * v_plume;

	// ---- bend as a rotation about the root --------------------------------
	// Wind direction expressed in the instance's own frame. The instance basis
	// is a yaw plus a scale, so projecting onto its normalised X and Z columns
	// inverts the rotation exactly and costs two dot products.
	vec3 wd3 = vec3(wd.x, 0.0, wd.y);
	vec3 mx = normalize(MODEL_MATRIX[0].xyz);
	vec3 mz = normalize(MODEL_MATRIX[2].xyz);
	vec3 wdl = normalize(vec3(dot(wd3, mx), 0.0, dot(wd3, mz)) + vec3(0.0001, 0.0, 0.0));
	vec3 axis = vec3(-wdl.z, 0.0, wdl.x);

	float ang = sway * bend_scale * bw;
	float sa = sin(ang);
	float ca = cos(ang);
	vec3 p = VERTEX;
	VERTEX = p * ca + cross(axis, p) * sa + axis * dot(axis, p) * (1.0 - ca);
	vec3 nn = NORMAL;
	NORMAL = nn * ca + cross(axis, nn) * sa + axis * dot(axis, nn) * (1.0 - ca);

	// ---- actor displacement -----------------------------------------------
	vec3 offset = vec3(0.0);
	for (int i = 0; i < TRAIL_MAX; i++) {
		vec4 tp = trail[i];
		if (tp.w <= 0.001) { continue; }
		vec3 d = wp - tp.xyz;
		d.y = 0.0;
		float dist = length(d);
		if (dist < trail_radius) {
			float f = 1.0 - dist / trail_radius;
			f = f * f * tp.w;
			vec3 away = dist > 0.001 ? normalize(d) : vec3(1.0, 0.0, 0.0);
			offset += away * f * trail_push * bw;
			offset.y -= f * trail_push * 0.55 * bw;
		}
	}
	VERTEX += offset;

	float cam_d = length(wp - CAMERA_POSITION_WORLD);
	float duck = smoothstep(cam_fade_end, cam_fade_start, cam_d);
	// shrink the whole clump into its root, width included: squashing only the
	// height left metre-wide flat blades sweeping across the lens
	VERTEX *= mix(0.0, 1.0, duck);
	// lift the shading normal toward vertical: reads as soft mass, not flat cards
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.82));
	// how square-on the blade is to the gust, used to brighten the lee face
	v_lit = gf;
}

void fragment() {
	vec3 t = mix(tint_lush, tint_dry, clamp(v_dry, 0.0, 1.0));
	// Per-clump colour, not just per-clump brightness. A field where every
	// blade is the same green with a +/-16% exposure wobble is the single
	// clearest tell that grass was instanced: real ground cover is a mix of
	// species and ages, so clumps drift in HUE as well as value -- some
	// yellow-green, some blue-green, a few already gone over to straw.
	float hv = v_tintv;
	t *= mix(0.86, 1.14, hv);
	t.r *= mix(0.84, 1.22, fract(hv * 3.7));
	t.g *= mix(0.92, 1.08, fract(hv * 5.3));
	t.b *= mix(0.72, 1.28, fract(hv * 7.1));
	// Roots take the ground colour so clumps sit in the terrain instead of
	// floating on top of it as separate green objects.
	vec3 root = mix(tint_root, ground_tint, ground_blend);
	vec3 col = mix(root, t, clamp(v_bend * 1.25, 0.0, 1.0));
	col *= texture(base_tex, UV).rgb * 1.5 + 0.35;
	// Seed heads are pale and desaturated -- the part of susuki that catches
	// a low sun and reads as silver against the sky.
	col = mix(col, tint_plume * mix(0.88, 1.12, v_tintv), v_plume * 0.72);
	float ao = mix(1.0 - ao_strength, 1.0, COLOR.g);
	col *= ao;
	// Blades are paler and drier at the tip than halfway down, which is what
	// gives a field its vertical gradient from shadowed base to lit crown.
	col *= mix(1.0, 1.16, smoothstep(0.62, 1.0, v_bend));
	// a gust front lightens as it passes: leaves turn their paler underside up
	col *= 1.0 + 0.10 * v_lit * v_bend;
	col *= mix(1.0, 0.72, wetness);
	col = mix(col, vec3(0.85, 0.88, 0.94), snow * 0.8);
	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.55, wetness);
	ALPHA = 1.0;
	// Cheap translucency. Plumes are nearly transparent, which is what makes a
	// backlit field glow rather than silhouette.
	BACKLIGHT = vec3(backlight_amount * (1.0 + 0.9 * v_plume)) * vec3(1.06, 1.0, 0.78);
}
