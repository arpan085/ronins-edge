shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, depth_draw_always;

// River / lake / waterfall surface.
//
// Flow is a UV scroll along the channel direction supplied per-vertex in UV2,
// so rivers actually run downhill and the lake only drifts. Baked depth
// arrives in COLOR.r and drives the shallow->deep ramp, the opacity and the
// shoreline fade.
//
// v0.9 adds refraction (the bed wobbles through the ripple normal), a real
// Fresnel, and an optional screen-space reflection march.
//
// Deliberately, the depth buffer is NOT load-bearing. On renderers that do not
// hand a depth copy to transparent materials it reads as zero, and a shader
// that trusted it made every river in the world an infinitely deep white
// sheet. Everything essential now runs off the baked depth; the depth buffer
// has to prove itself before refraction clamping or SSR will use it.

uniform sampler2D ripple_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 shallow_col : source_color = vec3(0.30, 0.46, 0.44);
uniform vec3 deep_col : source_color = vec3(0.055, 0.14, 0.19);
uniform vec3 foam_col : source_color = vec3(0.88, 0.93, 0.95);
uniform float flow_speed = 0.55;
uniform float ripple_scale = 0.62;
uniform float foam_amount : hint_range(0.0, 3.0) = 0.85;
uniform float wave_height = 0.055;
uniform float sky_tint_strength : hint_range(0.0, 1.0) = 0.28;
uniform float refract_strength : hint_range(0.0, 0.2) = 0.045;
uniform float depth_range : hint_range(1.0, 8.0) = 4.0;  // metres packed into COLOR.r
// Live sky colours, pushed by DayNight, so reflections track the time of day.
// Two of them: at a grazing angle water mirrors the HORIZON, looking straight
// down it mirrors the ZENITH, and a single flat colour for both turned every
// low-angle river into a sheet of pink plastic at sunset.
uniform vec3 sky_col : source_color = vec3(0.42, 0.52, 0.64);
uniform vec3 sky_top_col : source_color = vec3(0.26, 0.42, 0.72);
// What a ray reflected BELOW the horizon hits: the far bank. Without screen
// space reflections the honest stand-in is the average colour of the land.
uniform vec3 bank_col : source_color = vec3(0.16, 0.17, 0.12);
// Water is a near-perfect mirror at a grazing angle, and with no reflected
// geometry to put in it that is a flat sheet of sky. Capping the Fresnel term
// keeps some of the water's own colour in the surface at every angle.
// Water at a grazing angle really is a mirror, but the sunset sky it mirrors
// here is close to white, so an unclamped Fresnel turned every shallow stream
// into a sheet of pale paper laid over the grass. Capping the reflectance
// keeps some bed and some water colour in the surface at every angle.
uniform float fresnel_cap : hint_range(0.2, 1.0) = 0.52;
uniform float clarity : hint_range(0.05, 6.0) = 2.60;   // metres to full opacity
uniform int ssr_steps : hint_range(0, 32) = 0;
uniform float ssr_thickness = 0.55;
uniform float ssr_strength : hint_range(0.0, 1.0) = 0.7;
// 0 = shipping. 1..9 visualise intermediate terms for tests/WaterProbe.
uniform int debug_mode : hint_range(0, 10) = 0;
// debug_mode 10: flat emissive tint, so a test harness can mask the water
uniform vec3 debug_tint : source_color = vec3(1.0, 0.0, 1.0);
// v0.13 ---------------------------------------------------------------
// flow_mode 1 is the main river ribbon: UV is (metres downstream, metres
// across), so the current always runs along +U and bends cost nothing.
// Mode 0 (lake, old streams) takes a per-vertex world flow vector in UV2.
uniform int flow_mode : hint_range(0, 1) = 0;
// COLOR.g = rapids (0..1): the current runs this many times faster
uniform float rapid_speed = 2.6;
// R foam web, G/B fbm; tiles (tools/make_water_noise.py)
uniform sampler2D foam_noise : filter_linear_mipmap, repeat_enable;
uniform float whitewater : hint_range(0.0, 2.0) = 1.0;

varying float v_depth;
varying vec2 v_flow;
varying vec3 v_world;
varying float v_fast;
varying float v_churn;
varying vec2 v_uv;

float view_z(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 p = inv_proj * vec4(vec3(uv * 2.0 - 1.0, d), 1.0);
	return -(p.z / p.w);            // positive distance in front of the camera
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_depth = COLOR.r;
	v_flow = UV2;
	v_fast = COLOR.g;
	v_churn = COLOR.b;
	v_uv = UV;
	float w = sin(v_world.x * 0.35 + TIME * 1.3) * cos(v_world.z * 0.29 - TIME * 0.9);
	float amp = wave_height * clamp(v_depth * 1.5, 0.15, 1.0);
	VERTEX.y += w * amp;
	if (flow_mode == 1) {
		// rapids: short standing waves that hold their place in the current,
		// plunge pools: a restless boil
		float sw = sin(UV.x * 2.3 + sin(UV.y * 1.7) * 1.4) * sin(UV.y * 2.9 + TIME * 0.7);
		float boil = sin(UV.x * 1.9 - TIME * 2.3) * cos(UV.y * 2.2 + TIME * 1.7);
		VERTEX.y += sw * 0.07 * v_fast * clamp(v_depth * 3.0, 0.0, 1.0) + boil * 0.06 * v_churn;
	}
}

void fragment() {
	// Where the flow runs, and how fast, in the coordinates it runs through.
	vec2 P2;
	vec2 vel;
	vec2 fl;
	if (flow_mode == 1) {
		P2 = v_uv;
		fl = vec2(1.0, 0.0);
		vel = fl * flow_speed * mix(1.0, rapid_speed, v_fast);
	} else {
		P2 = v_world.xz;
		fl = length(v_flow) > 0.01 ? normalize(v_flow) : vec2(0.0, 1.0);
		vel = v_flow * flow_speed;
	}
	vec2 cross_fl = vec2(-fl.y, fl.x);
	// Two-phase advection. Each layer drifts with the current for one period
	// and snaps back while its twin, half a period out, carries the look.
	// Scrolling by TIME alone (the old way) sheared the pattern apart wherever
	// the flow bent or changed speed, and got worse the longer the game ran.
	float per = 2.6;
	float ph = TIME / per;
	float pa = fract(ph);
	float pb = fract(ph + 0.5);
	float wa = 1.0 - abs(2.0 * pa - 1.0);
	vec2 oa = vel * (pa - 0.5) * per;
	vec2 ob = vel * (pb - 0.5) * per;
	vec2 ja = vec2(0.371, 0.613) * floor(ph);
	vec2 jb = vec2(0.619, 0.293) * floor(ph + 0.5);
	float sc = ripple_scale;
	// Three scales. The two big ones ride the current; the finest is
	// wind chop, independent of the flow, so it never shears.
	vec3 n1 = mix(texture(ripple_n, (P2 - ob) * sc * 0.45 + jb).rgb,
		texture(ripple_n, (P2 - oa) * sc * 0.45 + ja).rgb, wa);
	vec3 n2 = mix(texture(ripple_n, (P2 - ob * 0.85) * sc * 1.30 - jb).rgb,
		texture(ripple_n, (P2 - oa * 0.85) * sc * 1.30 - ja).rgb, wa);
	vec3 n3 = texture(ripple_n, v_world.xz * sc * 3.10 + vec2(0.61, 0.79) * TIME * 0.22).rgb;
	float chop = 1.0 + v_fast * 0.9 + v_churn * 1.2;
	vec3 nmap = normalize(
		(n1 * 2.0 - 1.0) * 0.50 +
		(n2 * 2.0 - 1.0) * 0.32 * chop +
		(n3 * 2.0 - 1.0) * 0.18) * 0.5 + 0.5;
	vec3 nrm = normalize(nmap * 2.0 - 1.0);

	// v_depth arrives packed over a 0..4 m span in an 8-bit vertex colour.
	// Decode to metres once and work in metres from here down; the mismatch
	// between the packed value and the ramps below was what made every
	// shallow stream render as solid white foam.
	float dd = clamp(v_depth, 0.0, 1.0) * depth_range;
	vec3 col = mix(shallow_col, deep_col, smoothstep(0.05, 3.50, dd));
	// aerated water is paler and greener
	col = mix(col, shallow_col * 1.25, clamp(v_fast * 0.35 + v_churn * 0.4, 0.0, 0.6));

	// foam is a waterline fringe, not a fill: only the last 25 cm
	float edge = 1.0 - smoothstep(0.0, 0.25, dd);
	float fnoise = mix(texture(foam_noise, (P2 - ob) * sc * 0.9 + jb).g,
		texture(foam_noise, (P2 - oa) * sc * 0.9 + ja).g, wa);
	// capped: at 1.0 a thin fringe cell turned a whole quad pure white
	float foam = clamp(edge * foam_amount * (0.35 + 1.3 * fnoise), 0.0, 0.80);
	// Whitewater. Rapids: lace stretched along the current; plunge pools:
	// a churning web that thins out downstream.
	float web = mix(texture(foam_noise, (P2 - ob) * vec2(0.16, 0.42) + jb).r,
		texture(foam_noise, (P2 - oa) * vec2(0.16, 0.42) + ja).r, wa);
	float streak = mix(texture(foam_noise, (P2 - ob) * vec2(0.035, 0.30) - jb).g,
		texture(foam_noise, (P2 - oa) * vec2(0.035, 0.30) - ja).g, wa);
	// shallow fast water breaks white most readily
	float rap = v_fast * smoothstep(0.34, 0.74, streak * 0.7 + web * 0.6) * clamp(1.25 - dd * 0.45, 0.4, 1.0);
	float pool = v_churn * smoothstep(0.18, 0.62, web + (fnoise - 0.5) * 0.6 + v_churn * 0.25);
	foam = clamp(foam + (rap + pool) * whitewater, 0.0, 0.94);

	float raw_d = texture(depth_tex, SCREEN_UV).r;
	bool has_depth = raw_d > 0.0;
	float surf_z = -VERTEX.z;
	float scene_z = has_depth ? view_z(SCREEN_UV, INV_PROJECTION_MATRIX) : surf_z;
	float opacity = clamp(dd / clarity, 0.0, 1.0);
	float shore = smoothstep(0.0, 0.18, dd);

	// ---- refraction: resample the scene through the ripple normal, scaled by
	// depth so a shallow edge cannot smear over dry land.
	vec2 roff = nrm.xy * refract_strength * clamp(dd * 0.75, 0.0, 1.0);
	vec2 ruv = clamp(SCREEN_UV + roff, vec2(0.002), vec2(0.998));
	if (has_depth && view_z(ruv, INV_PROJECTION_MATRIX) < surf_z) ruv = SCREEN_UV;
	// The surface used to composite the scene itself: sample the screen
	// texture, mix the water colour over it, and ship the result opaque. That
	// relies on SCREEN_TEXTURE being readable, and on this project's fallback
	// renderer it is not -- the same reason DEPTH_TEXTURE reads zero here --
	// so every river came out as a sheet of near-white. Hardware alpha
	// blending does the same compositing with no texture read at all, and
	// gets sorting right for free. The screen sample is now only a refraction
	// nudge, and only when it is actually usable.
	vec3 behind = has_depth ? texture(screen_tex, ruv).rgb : vec3(0.0);
	vec3 through = mix(col, sky_col, sky_tint_strength * 0.35);

	// ---- screen-space reflection
	// A stronger normal perturbation for the reflection than for the shading:
	// it is what scatters the reflected ray across the sky gradient and turns
	// a mirror into a shimmer.
	vec3 N = normalize(NORMAL + vec3(nrm.x, nrm.y, 0.0) * 0.42);
	vec3 P = VERTEX;
	vec3 R = reflect(normalize(P), N);
	vec3 refl = vec3(0.0);
	float rw = 0.0;
	if (has_depth && ssr_steps > 0 && R.z < 0.0) {
		float step_len = 0.55;
		vec3 q = P;
		for (int i = 0; i < ssr_steps; i++) {
			q += R * step_len;
			step_len *= 1.22;
			vec4 cp = PROJECTION_MATRIX * vec4(q, 1.0);
			if (cp.w <= 0.0) break;
			vec2 suv = (cp.xy / cp.w) * 0.5 + 0.5;
			if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) break;
			float sz = view_z(suv, INV_PROJECTION_MATRIX);
			float qz = -q.z;
			if (sz < qz && qz - sz < ssr_thickness + step_len) {
				vec2 e = abs(suv - 0.5) * 2.0;
				rw = (1.0 - smoothstep(0.72, 1.0, max(e.x, e.y)))
				   * (1.0 - float(i) / float(ssr_steps) * 0.35);
				refl = texture(screen_tex, suv).rgb;
				break;
			}
		}
	}

	// Schlick Fresnel with water's real F0 of 0.02. The old term was a bare
	// pow(1-cos, 3.5), which returns ~0.3 at a 45-degree view: every river was
	// compositing a third of the sky over itself and reading as a pale sheet.
	float cosv = clamp(dot(N, normalize(VIEW)), 0.0, 1.0);
	float fres = min(0.02 + 0.98 * pow(1.0 - cosv, 5.0), fresnel_cap);
	// Reflection colour comes from the live sky uniform, which DayNight keeps
	// in step with the horizon, so water goes copper at sunset instead of
	// staying the same flat blue all day.
	// Pick the sky colour along the reflected ray, so the ripple normals
	// break the reflection into a gradient instead of flat-filling it.
	vec3 rw3 = (INV_VIEW_MATRIX * vec4(reflect(-normalize(VIEW), N), 0.0)).xyz;
	float up = rw3.y;
	vec3 skyg = up < 0.05
		? mix(bank_col, sky_col, smoothstep(-0.22, 0.05, up))
		: mix(sky_col, sky_top_col, smoothstep(0.05, 0.60, up));
	vec3 mirror = mix(skyg, refl, rw * ssr_strength);
	vec3 outc = mix(through, mirror, fres);
	outc = mix(outc, foam_col, foam);
	// How much of the bed the water hides: its own turbidity, plus whatever
	// the Fresnel reflection covers at a grazing angle.
	// Never fully opaque: a hint of the bed through even a mirrored surface
	// is what stops it reading as a painted plane.
	float cover = clamp(opacity + fres * 0.66, 0.0, 0.88);
	cover = max(cover, foam);
	cover *= shore;

	if (debug_mode > 0) {
		vec3 dbg = behind;
		if (debug_mode == 2) dbg = vec3(clamp(scene_z / 30.0, 0.0, 1.0));
		else if (debug_mode == 3) dbg = vec3(opacity);
		else if (debug_mode == 4) dbg = vec3(foam);
		else if (debug_mode == 5) dbg = vec3(fres);
		else if (debug_mode == 6) dbg = vec3(raw_d);
		else if (debug_mode == 7) dbg = vec3(1.0 - raw_d) * 40.0;
		else if (debug_mode == 8) dbg = vec3(clamp(surf_z / 30.0, 0.0, 1.0));
		else if (debug_mode == 9) dbg = vec3(shore);
		else if (debug_mode == 10) dbg = debug_tint;
		outc = dbg;
		EMISSION = dbg;
		foam = 0.0;
	}

	ALBEDO = outc;
	// a tight sun glint reads as water far more than any amount of blue does
	ROUGHNESS = debug_mode > 0 ? 1.0 : mix(0.055, 0.40, foam);
	SPECULAR = debug_mode > 0 ? 0.0 : 0.55;
	METALLIC = 0.0;
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = 1.35 * chop;
	// The surface composites the scene behind it itself, so it is opaque
	// everywhere except the last centimetres at the waterline, where fading
	// out is what stops the edge being a hard blue line on the grass.
	ALPHA = debug_mode > 0 ? 1.0 : clamp(cover, 0.0, 1.0);
}
