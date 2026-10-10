shader_type sky;
render_mode use_half_res_pass;

#include "res://shaders/clouds.gdshaderinc"

// v0.17 physically based sky.
//
// The v0.16 sky was a hand-painted colour ramp (zenith/horizon/ground colours
// keyframed in DayNight) with flat-shaded noise decks on top. This one is an
// atmosphere: single Rayleigh + Mie scattering with ozone absorption, marched
// along the view ray with the sun's optical depth from an analytic Chapman
// approximation, so the blue zenith, the white haze at the horizon, the glow
// around the sun, the red sun at sunset and the purple-orange twilight all come
// out of one model instead of out of keyframes. The keyframed ramp survives as
// the "art layer": it is what the night sky is made of, and it is blended in
// through twilight where single scattering alone goes black.
//
// Clouds are lit, not painted. The cumulus deck sits on a curved shell 1.6 km
// up (so it converges to the horizon like a real deck instead of stretching to
// infinity) and every cloud pixel marches a few taps towards the sun to find how
// much cloud the light has to get through: that gives bright sun-facing edges,
// dark cores, grey bases and a silver lining when the sun is behind a cloud.
// The sunlight reaching each deck is the atmosphere's own transmittance, so the
// deck goes gold at sunset and the high cirrus stays pink after the low clouds
// have gone grey. Distant clouds dissolve into the horizon haze.
//
// Cost: everything expensive runs in the half-resolution pass. The full
// resolution pass only adds the sharp things (sun disc, moon, stars) on top,
// masked by the cloud cloud_cover the half-res pass leaves in ALPHA. The radiance
// cubemap (ambient light and reflections) takes a much cheaper path.

// --- art layer / legacy uniforms (DayNight keyframes, Weather) ---------------
uniform vec3 top_color : source_color = vec3(0.28, 0.46, 0.80);
uniform vec3 horizon_color : source_color = vec3(0.74, 0.80, 0.86);
uniform vec3 ground_color : source_color = vec3(0.20, 0.20, 0.18);
uniform vec3 sun_color : source_color = vec3(1.0, 0.97, 0.92);
uniform float sun_energy = 1.0;
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform int octaves : hint_range(2, 6) = 5;          // quality tier (Perf)

// --- physical sky (DayNight) --------------------------------------------------
uniform vec3 sky_sun_dir = vec3(0.0, 0.7071, -0.7071);   // towards the sun
uniform vec3 moon_dir = vec3(0.35, 0.79, 0.50);
uniform float sky_exposure = 26.0;    // eye adaptation: keeps the sky readable from noon to dusk
uniform float art_mix : hint_range(0.0, 1.0) = 0.0;
uniform float turbidity = 1.4;        // Mie haze multiplier (Weather raises it)
uniform vec3 amb_top = vec3(0.10, 0.20, 0.45);   // linear sky light on the clouds
uniform vec3 amb_hor = vec3(0.45, 0.55, 0.65);
uniform float moon_energy = 0.0;
uniform float moon_phase : hint_range(0.0, 1.0) = 0.82;

const float RG = 6360.0;      // km
const float RT = 6420.0;
const float H0 = 0.3;         // viewer altitude
const vec3 BR = vec3(5.802e-3, 13.558e-3, 33.1e-3);   // Rayleigh scattering, 1/km
const float BMS = 3.996e-3;                           // Mie scattering
const float BME = 4.440e-3;                           // Mie extinction
const vec3 BO = vec3(0.975e-3, 2.8215e-3, 0.1275e-3); // ozone absorption (x1.5; more turns low sunlight magenta)
const float HR = 8.0;
const float HM = 1.2;
const float CLOUD_K = 0.085;  // sunlight -> cloud radiance (keeps lit clouds near 2.0 at noon)
const float SUN_R = 0.0236;   // disc radius, rad (~1.35 deg; the real sun is 0.27 deg)
const float MOON_R = 0.0215;

// ------------------------------------------------------------------ noise
vec3 hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// ------------------------------------------------------------------ atmosphere
// Schuler's approximation of the Chapman grazing-incidence function; below the
// local horizon the ray passes the tangent point and, if that is under the
// ground, the optical depth explodes - which is the Earth's shadow.
float chapman(float x, float cosc) {
	float c = sqrt(1.5707963 * x);
	float pos = c / ((c - 1.0) * abs(cosc) + 1.0);
	if (cosc >= 0.0) return pos;
	float x0 = x * sqrt(max(1.0 - cosc * cosc, 0.0));
	float c0 = sqrt(1.5707963 * x0);
	return 2.0 * c0 * exp(min(x - x0, 60.0)) - pos;
}

// optical depth (Rayleigh, Mie, ozone) from altitude h (km) towards a direction
// with zenith cosine cosc, to the top of the atmosphere
vec3 od_light(float h, float cosc) {
	float r = RG + h;
	float odr = HR * exp(-h / HR) * chapman(r / HR, cosc);
	float odm = HM * exp(-h / HM) * chapman(r / HM, cosc);
	float k = r / (RG + 25.0);
	float cs = sqrt(max(1.0 - (1.0 - cosc * cosc) * k * k, 0.0));
	float am = 1.0 / max(cs, 0.035);
	if (cosc < 0.0) am *= 2.0;
	float odo = 15.0 * am * clamp(1.0 - max(h - 25.0, 0.0) / 15.0, 0.0, 1.0);
	return vec3(odr, odm, odo);
}

vec3 trans(vec3 od, float turb) {
	return exp(-(BR * od.x + vec3(BME * turb * od.y) + BO * od.z));
}

float phase_r(float mu) { return 0.0596831 * (1.0 + mu * mu); }

float phase_m(float mu, float g) {
	float g2 = g * g;
	return 0.1193662 * (1.0 - g2) * (1.0 + mu * mu)
		/ ((2.0 + g2) * pow(max(1.0 + g2 - 2.0 * g * mu, 1e-4), 1.5));
}

// Henyey-Greenstein normalised so an isotropic scatterer is 1.0
float hg(float mu, float g) {
	float g2 = g * g;
	return (1.0 - g2) / pow(max(1.0 + g2 - 2.0 * g * mu, 1e-4), 1.5);
}

// Highlight roll-off for the sky only. Physically the air around a low sun is
// tens of times brighter than the zenith; a camera blows that out into a white
// blob a third of the frame wide. Luminance above 1.0 is compressed towards
// 3.0, so the glow keeps its colour and the disc stays the brightest thing.
vec3 knee(vec3 c) {
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	if (l <= 1.0) return c;
	float lc = 1.0 + (l - 1.0) / (1.0 + (l - 1.0) / 2.0);
	return c * (lc / l);
}

// In-scattered light for unit sun irradiance. Directions below the horizon
// reuse the horizontal ray (the ground blend is applied by the caller).
vec3 atmosphere(vec3 d, vec3 sd, float turb, int steps) {
	vec3 dd = normalize(vec3(d.x, max(d.y, 0.0), d.z));
	float o = RG + H0;
	float b = o * dd.y;
	float c = o * o - RT * RT;
	float tmax = min(-b + sqrt(b * b - c), 100.0);
	vec3 od = vec3(0.0);
	vec3 inr = vec3(0.0);
	vec3 inm = vec3(0.0);
	vec3 ms = vec3(0.0);
	float fs = float(steps);
	for (int i = 0; i < 16; i++) {
		if (i >= steps) break;
		float f0 = float(i) / fs;
		float f1 = float(i + 1) / fs;
		f0 *= f0;
		f1 *= f1;
		float tm = 0.5 * (f0 + f1) * tmax;
		float dt = (f1 - f0) * tmax;
		vec3 p = vec3(dd.x * tm, o + dd.y * tm, dd.z * tm);
		float r = length(p);
		float h = max(r - RG, 0.0);
		vec3 dens = vec3(exp(-h / HR), exp(-h / HM), clamp(1.0 - abs(h - 25.0) / 15.0, 0.0, 1.0));
		od += dens * (dt * 0.5);
		vec3 tv = trans(od, turb);
		vec3 t = tv * trans(od_light(h, dot(p, sd) / r), turb);
		inr += t * (dens.x * dt);
		inm += t * (dens.y * dt);
		ms += tv * (BR * dens.x + vec3(BMS * turb * dens.y)) * dt;
		od += dens * (dt * 0.5);
	}
	float mu = dot(d, sd);
	// second-order light: what reached ~4 km a little higher up the sky,
	// scattered isotropically - fills the Earth's shadow with blue-grey
	vec3 tms = trans(od_light(4.0, clamp(sd.y + 0.06, -1.0, 1.0)), turb);
	return BR * inr * phase_r(mu) + vec3(BMS * turb) * inm * phase_m(mu, 0.76)
		+ ms * tms * (0.2 / (4.0 * PI));
}

// The v0.16 painted ramp: night sky, and the colour that fills twilight.
vec3 art_sky(vec3 dir, vec3 sdir) {
	float up = dir.y;
	vec2 dir_az = normalize(vec2(dir.x, dir.z) + vec2(1e-5));
	vec2 sun_az = normalize(vec2(sdir.x, sdir.z) + vec2(1e-5));
	float az = clamp(dot(dir_az, sun_az) * 0.5 + 0.5, 0.0, 1.0);
	float warmth = 1.0 - smoothstep(0.10, 0.45, abs(sdir.y));
	vec3 hor_far = mix(horizon_color, top_color, 0.50) * 0.78;
	vec3 hor = mix(horizon_color, mix(hor_far, horizon_color, pow(az, 1.5)), warmth);
	vec3 col = mix(hor, top_color, pow(clamp(up, 0.0, 1.0), 0.42));
	float sd = max(dot(dir, sdir), 0.0);
	float se = sun_energy * (sun_energy > 0.005 ? 1.0 : 0.0);
	col += sun_color * (pow(sd, 42.0) * 1.6 + pow(sd, 5.0) * 0.22) * se;
	return col;
}

// distance (km) along the view ray to a cloud shell hk km above the ground
float shell_t(vec3 d, float hk) {
	float o = RG + H0;
	float b = o * d.y;
	float rc = RG + hk;
	return -b + sqrt(max(b * b - (o * o - rc * rc), 0.0));
}

float coverage(float n, float thr, float soft) {
	return smoothstep(thr, thr + soft, n);
}

// ------------------------------------------------------------------ main
void sky() {
	vec3 d = EYEDIR;
	if (AT_HALF_RES_PASS) {
		bool cube = AT_CUBEMAP_PASS;
		float q = float(octaves);
		int steps = cube ? 6 : clamp(octaves * 2 + 2, 8, 14);
		float t = cloud_time;
		vec2 cam_km = POSITION.xz * 0.001;   // clouds are anchored to the world: ride under them and they pass overhead

		// ---- clear sky ----
		vec3 col = vec3(0.0);
		if (art_mix < 0.999) {
			col = atmosphere(d, sky_sun_dir, turbidity, steps) * sky_exposure;
		}
		if (art_mix > 0.001) {
			col = mix(col, art_sky(d, sky_sun_dir), art_mix);
		}

		// Under a closing deck the air is lit by the grey light coming through
		// the cloud, not by the sun, so the sunlit clear-sky horizon glow must
		// go: an overcast sky is darkest at the horizon (CIE overcast, ~1/3 of
		// the zenith) and its haze is the colour of the cloud base. Greying the
		// clear sky kept its bright band under every storm.
		float oc_sky = smoothstep(0.55, 0.95, cloud_cover);
		float lc = dot(mix(amb_hor, amb_top, 0.55), vec3(0.2126, 0.7152, 0.0722)) * 0.55 * (1.0 - 0.45 * cloud_storm);
		vec3 over = vec3(lc) * mix(0.62, 1.0, clamp(d.y * 2.5, 0.0, 1.0));
		col = mix(col, over, oc_sky * 0.9);

		float moon_vis = smoothstep(0.05, 0.35, moon_energy);
		if (night > 0.01 && d.y > 0.0 && !cube) {
			// Milky Way: a faint band with dust lanes
			vec3 mwn = normalize(vec3(0.42, 0.50, -0.76));
			float g = dot(d, mwn);
			vec3 ax1 = normalize(cross(mwn, vec3(0.0, 1.0, 0.0)));
			vec3 ax2 = cross(mwn, ax1);
			vec2 mq = vec2(dot(d, ax1), dot(d, ax2)) * 7.0 + g * 9.0;
			float band = exp(-g * g / 0.03);
			float mn = cl_fbm(mq, 4.0);
			float dust = smoothstep(0.46, 0.70, cl_fbm(mq * 1.7 + 5.0, 3.0)) * exp(-g * g / 0.004);
			col += vec3(0.55, 0.60, 0.75) * band * (0.30 + 0.9 * mn) * (1.0 - 0.75 * dust)
				* 0.040 * night * smoothstep(0.02, 0.30, d.y);
		}
		if (moon_vis > 0.0) {
			float md = max(dot(d, moon_dir), 0.0);
			col += vec3(0.62, 0.70, 0.92) * (pow(md, 900.0) * 0.35 + pow(md, 60.0) * 0.035) * moon_vis;
		}

		// Cloud level of detail from the screen footprint. Near the horizon one
		// pixel spans kilometres of deck, so even the coarsest octave aliases
		// into stripes; fwidth must be taken here, outside any branch.
		float tc = shell_t(d, 1.6);
		float tci = shell_t(d, 8.0);
		float fpc = max(fwidth(tc), tc * 0.004);
		float fpi = max(fwidth(tci), tci * 0.004);

		// the key light for the clouds: the sun by day, the moon by night
		float nk = smoothstep(0.35, 0.85, night);
		vec3 kdir = normalize(mix(sky_sun_dir, moon_dir, nk));
		float mu = dot(d, kdir);
		vec3 moon_light = vec3(0.50, 0.57, 0.75) * 0.22 * moon_energy;
		float vis = 1.0;

		if (d.y > 0.0) {
			// ---- cirrus, 8 km ----
			float air_ci = exp(-tci * turbidity / 45.0);
			if (cloud_cover < 0.98 && cloud_storm < 0.95) {
				vec2 pci = cam_km + d.xz * tci + vec2(1.7, 0.4) * t * 1.5;
				vec2 sp = mat2(vec2(0.94, 0.34), vec2(-0.34, 0.94)) * pci;
				vec2 qc = sp * vec2(0.05, 0.13);
				float imax = log2(3.8 / fpi);
				float oc = min(cube ? 2.0 : max(q - 1.0, 2.0), imax + 1.0);
				float ci = cl_fbm(qc + vec2(cl_fbm(qc * 0.6 + 3.3, 2.0), cl_fbm(qc * 0.5 + 9.1, 2.0)) * 1.8, max(oc, 1.0));
				ci = mix(ci, 0.5, clamp(-imax, 0.0, 1.0));
				float cthr = mix(0.62, 0.50, cloud_cover);
				float cm = smoothstep(cthr, cthr + 0.20, ci) * mix(0.45, 0.75, cloud_cover) * (1.0 - cloud_storm);
				cm *= smoothstep(0.0, 0.10, d.y) * air_ci;
				vec3 sun8 = trans(od_light(8.0, sky_sun_dir.y), turbidity) * (sky_exposure * CLOUD_K);
				vec3 key8 = mix(sun8, moon_light, nk);
				vec3 cl = key8 * (0.45 + 0.12 * hg(mu, 0.60)) + amb_top * 0.55;
				col = mix(col, cl, clamp(cm, 0.0, 1.0));
			}

			// ---- cumulus, 1.6 km ----
			float air = exp(-tc * turbidity / 50.0);
			if (air > 0.01) {
				// octave i has a period of 1.8/2^i km; keep it above two pixels
				float imax = log2(0.9 / fpc);
				float oc = min(cube ? 3.0 : q + 0.5, imax + 1.0);
				oc = max(oc, 1.0);
				vec2 sq = cl_deck_uv(cam_km + d.xz * tc);
				float n = cl_fbm(sq, oc);
				n = mix(n, 0.5, clamp(-imax, 0.0, 1.0));   // too far for any shape: mean cloud_cover
				// billows: high-frequency ridged noise eats into the edges, which is
				// what turns soft blobs into cauliflower cumulus
				if (!cube && oc > 3.0) {
					float bn = abs(cl_vnoise(sq * 6.1 + 3.7) - 0.5) + abs(cl_vnoise(sq * 12.7 - 1.3) - 0.5) * 0.5;
					n -= (bn - 0.37) * 0.10 * clamp(oc - 3.0, 0.0, 1.0);
				}
				float thr = mix(0.64, 0.24, cloud_cover);
				float soft = mix(0.13, 0.26, cloud_cover);
				float dens = coverage(n, thr, soft);
				// past ~60% cloud_cover a stratus sheet closes the gaps: overcast is a
				// lid with texture, not broken cloud with blue holes
				float strat = smoothstep(0.62, 0.95, cloud_cover);
				dens = mix(dens, max(dens, 0.45 + 0.55 * n), strat);
				dens *= smoothstep(0.0, 0.06, d.y);
				if (dens > 0.002) {
					// march towards the light through the deck
					int taps = cube ? 1 : clamp(octaves - 2, 2, 4);
					float to = cube ? 2.0 : max(oc - 1.5, 2.0);
					vec2 l2 = normalize(kdir.xz + vec2(1e-4, 0.0));
					float reach = clamp(0.9 / max(kdir.y, 0.06), 0.6, 6.0);
					float stp = reach / float(taps);
					float acc = 0.0;
					for (int k = 1; k <= 4; k++) {
						if (k > taps) break;
						vec2 tq = sq + l2 * (stp * float(k) * 0.45);
						acc += coverage(cl_fbm(tq, to), thr, soft);
					}
					acc /= float(taps);
					float sig = 2.6 * (1.0 + cloud_storm * 1.5);
					float tau = sig * (dens * 0.9 + acc * min(reach, 3.0) * 0.8);
					float beer = exp(-tau);
					float msl = exp(-tau * 0.22) * 0.30;
					float powder = 1.0 - exp(-dens * 5.0);
					float phase = mix(hg(mu, -0.20), hg(mu, 0.45), 0.55);
					float face = 1.0 + 0.55 * max(-mu, 0.0);
					// silver lining: thin edges in front of the light
					float silver = pow(max(mu, 0.0), 8.0) * (1.0 - smoothstep(0.0, 0.55, dens)) * 1.2;
					vec3 sunc = trans(od_light(1.6, sky_sun_dir.y), turbidity) * (sky_exposure * CLOUD_K);
					// a thick, widespread deck is greyer than fair-weather puffs: the
					// light has been scattered through far more cloud on the way in
					vec3 key = mix(sunc, moon_light, nk) * (1.0 - cloud_storm * 0.55)
						* (1.0 - 0.35 * smoothstep(0.40, 0.90, cloud_cover));
					vec3 direct = key * (beer * phase * mix(0.55, 1.0, powder) * 0.55 + msl * face + silver * exp(-tau * 0.35));
					vec3 amb = mix(amb_hor, amb_top, 0.55);
					// under a closed deck the light reaching the base is grey
					amb = mix(amb, vec3(dot(amb, vec3(0.2126, 0.7152, 0.0722))), strat * 0.8);
					amb *= (1.0 - 0.60 * dens) * (1.0 - cloud_storm * 0.45);
					vec3 cc = direct + amb * 0.95;
					float a = (1.0 - exp(-dens * 4.5 * (1.0 + cloud_storm))) * air;
					col = mix(col, cc, a);
					vis *= 1.0 - a;
				}
			}
		}

		// below the horizon: haze into the ground bounce colour
		if (d.y < 0.0) {
			col = mix(col, ground_color, pow(clamp(-d.y * 2.2, 0.0, 1.0), 0.5));
			vis = 0.0;
		}
		COLOR = knee(col);
		ALPHA = vis;
	} else {
		vec4 hr = HALF_RES_COLOR;
		vec3 col = hr.rgb;
		float vis = hr.a;
		if (!AT_CUBEMAP_PASS && vis > 0.003 && d.y > -0.01) {
			// sun disc with limb darkening, reddened by the air it shines through
			float sdd = dot(d, sky_sun_dir);
			if (sdd > 0.9990 && art_mix < 0.999) {
				float r = sqrt(max(2.0 * (1.0 - sdd), 0.0)) / SUN_R;
				if (r < 1.0) {
					float limb = 1.0 - 0.62 * (1.0 - sqrt(max(1.0 - r * r, 0.0)));
					vec3 tv = trans(od_light(H0, max(d.y, 0.0)), turbidity);
					float edge = smoothstep(1.0, 0.86, r);
					// a deck thick enough to hide the sky hides the disc completely
					float dv = vis * vis * (1.0 - cloud_storm);
					col += tv * limb * edge * dv * 10.0 * clamp(sky_exposure / 26.0, 1.0, 5.0) * (1.0 - art_mix);
				}
			}
			// stars
			if (night > 0.01 && d.y > 0.0) {
				vec3 p = d * 150.0;
				vec3 c = floor(p);
				vec3 h = hash33(c);
				if (h.x > 0.93) {
					vec3 sp = c + 0.5 + (hash33(c + 17.0) - 0.5) * 0.6;
					float dist = length(p - sp);
					float mag = (h.x - 0.93) / 0.07;
					float b = mag * mag * mag * 1.1 + 0.06;
					vec3 tint = mix(vec3(1.0, 0.78, 0.58), vec3(0.72, 0.82, 1.0), h.y);
					float tw = 0.7 + 0.3 * sin(TIME * (1.5 + 3.0 * h.z) + h.y * 40.0);
					col += tint * smoothstep(0.24, 0.0, dist) * b * tw * night * vis
						* smoothstep(0.02, 0.25, d.y);
				}
			}
			// the moon, with its phase and maria
			float moon_vis = smoothstep(0.05, 0.35, moon_energy);
			float md = dot(d, moon_dir);
			if (moon_vis > 0.0 && md > 0.9995) {
				vec3 mu_ = normalize(cross(vec3(0.0, 1.0, 0.0), moon_dir));
				vec3 mv = cross(moon_dir, mu_);
				vec2 uv = vec2(dot(d, mu_), dot(d, mv)) / MOON_R;
				float r2 = dot(uv, uv);
				if (r2 < 1.0) {
					vec3 n = vec3(uv, sqrt(1.0 - r2));
					float pa = (1.0 - moon_phase) * PI;
					float lit = smoothstep(-0.04, 0.12, dot(n, vec3(sin(pa), 0.0, cos(pa))));
					float maria = cl_fbm(uv * 2.2 + 7.0, 4.0);
					float alb = mix(0.62, 1.0, smoothstep(0.38, 0.62, maria));
					vec3 mc = vec3(1.0, 0.96, 0.88) * alb * (0.75 + 0.25 * n.z) * (lit * 1.6 + 0.025);
					col = mix(col, mc + col * 0.3, smoothstep(1.0, 0.93, r2) * vis * moon_vis);
				}
			}
		}
		COLOR = col;
	}
}
