shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

// The hills and mountains ringing the playable map
// (Terrain._build_distant_range). UV.x = metres beyond the map edge. Near the
// edge it borrows the terrain's own grass photo and lush regrade so the seam
// does not show; further out it is painted by height and slope.
// v0.17: the mesh is ~25-60 m between vertices out there, so the small relief
// that makes a mountain read as a mountain - gullies, spurs, outcrops - is
// added here as a detail height field with an analytic gradient, LOD-limited
// by pixel footprint so it never shimmers. It bends the lighting normal,
// darkens the hollows and decides where the forest gives way to rock, where
// scree runs down below the faces and where snow lies (flats and gullies
// above the snow line). Conifer and broadleaf forest grow in patches with a
// canopy grain; cloud shadows from the shared cloud field drift over it.

#include "res://shaders/clouds.gdshaderinc"

uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 grass_lush : source_color = vec3(0.21, 0.33, 0.10);
uniform float grass_lum_mean = 0.056;
// Forest seen from kilometres away is far darker than its leaves: the canopy
// shades itself. These are canopy albedos, not leaf colours.
uniform vec3 col_meadow : source_color = vec3(0.24, 0.30, 0.14);
uniform vec3 col_conifer : source_color = vec3(0.050, 0.082, 0.056);
uniform vec3 col_broadleaf : source_color = vec3(0.090, 0.130, 0.062);
uniform vec3 col_rock : source_color = vec3(0.37, 0.36, 0.34);
uniform vec3 col_scree : source_color = vec3(0.47, 0.45, 0.42);
uniform vec3 col_snow : source_color = vec3(0.90, 0.92, 0.96);
uniform float tree_line = 900.0;
uniform float snow_line = 1010.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_wp;
varying vec3 v_wn;
varying float v_d;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h12(i), h12(i + vec2(1, 0)), f.x), mix(h12(i + vec2(0, 1)), h12(i + vec2(1, 1)), f.x), f.y);
}

// value noise with its analytic gradient: (value, d/dx, d/dy)
vec3 vnd(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float a = h12(i);
	float b = h12(i + vec2(1.0, 0.0));
	float c = h12(i + vec2(0.0, 1.0));
	float d = h12(i + vec2(1.0, 1.0));
	float k1 = b - a;
	float k2 = c - a;
	float k4 = a - b - c + d;
	return vec3(a + k1 * u.x + k2 * u.y + k4 * u.x * u.y, du * (vec2(k1, k2) + k4 * u.yx));
}

float fbm(vec2 p, float oct) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		float w = clamp(oct - float(i), 0.0, 1.0);
		// octaves the pixel cannot resolve contribute their mean
		if (w > 0.0) {
			s += a * mix(0.5, vn(p), w);
		} else {
			s += a * 0.5;
		}
		p = p * 2.03 + vec2(17.1, 5.3);
		a *= 0.5;
	}
	return s / 0.96875;
}

// Ridged detail relief (about -0.5..0.6) with its gradient per metre. Each
// octave is rotated and damped by the slope already accumulated, so the fine
// gullies run down the big spurs instead of across them.
vec3 relief(vec2 pm, float oct) {
	const mat2 R = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	vec2 p = pm * (1.0 / 420.0);
	mat2 m = mat2(vec2(1.0 / 420.0, 0.0), vec2(0.0, 1.0 / 420.0));
	float v = 0.0;
	vec2 g = vec2(0.0);
	vec2 acc = vec2(0.0);
	float a = 1.0;
	for (int i = 0; i < 6; i++) {
		float w = clamp(oct - float(i), 0.0, 1.0);
		if (w <= 0.0) break;
		vec3 n = vnd(p);
		// ridge: 1 - |2n - 1|, crest where n = 0.5
		float s = 2.0 * n.x - 1.0;
		float r = 1.0 - abs(s);
		vec2 dr = -sign(s) * 2.0 * n.yz;
		vec2 gw = transpose(m) * dr;
		acc += dr;
		float damp = 1.0 / (1.0 + 0.5 * dot(acc, acc));
		v += a * w * damp * (r * r - 0.45);
		g += a * w * damp * 2.0 * r * gw;
		p = R * p * 2.07 + vec2(11.3, 4.7);
		m = (R * m) * 2.07;
		a *= 0.42;
	}
	return vec3(v, g);
}

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_d = UV.x;
}

void fragment() {
	vec3 wn = normalize(v_wn);
	// metres per pixel -> how many detail octaves the pixel can resolve
	float fw = max(length(fwidth(v_wp.xz)), 0.05);
	float oct = clamp(log2(420.0 / (fw * 3.0)) / log2(2.07), 0.0, 6.0);
	float oct_s = clamp(log2(286.0 / (fw * 2.5)), 0.0, 5.0);
	float slope0 = 1.0 - clamp(wn.y, 0.0, 1.0);
	float far = smoothstep(150.0, 700.0, v_d);

	// detail relief: deeper on steep ground and up high
	vec3 rl = relief(v_wp.xz, oct);
	float amp = mix(10.0, 45.0, smoothstep(0.15, 0.55, slope0)) * mix(0.6, 1.0, smoothstep(300.0, 900.0, v_wp.y)) * far;
	vec3 dn = normalize(wn - vec3(rl.y, 0.0, rl.z) * amp);
	wn = normalize(mix(wn, dn, far));
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	float hollow = clamp(0.5 - rl.x * 1.4, 0.0, 1.0);   // 1 in gullies, 0 on spurs

	float n = fbm(v_wp.xz * 0.0035, oct_s);
	float n2 = fbm(v_wp.xz * 0.021 + 7.0, oct_s - 2.5);
	float canopy = fbm(v_wp.xz * 0.075 + 3.0, oct_s - 4.0);

	// near the border: the terrain's grass photo, regraded the same way
	vec3 gph = texture(albedo_arr, vec3(v_wp.xz / 2.6, 0.0)).rgb;
	vec3 near = grass_lush * (dot(gph, LUMA) / grass_lum_mean);
	near *= mix(0.85, 1.15, texture(macro_tex, v_wp.xz / 173.0).g * 2.0);

	// forest: conifer stands and broadleaf patches with a canopy grain;
	// meadow only on the gentle low ground and in clearings
	float h = v_wp.y + (n - 0.5) * 160.0;
	vec3 forest = mix(col_broadleaf, col_conifer, smoothstep(0.42, 0.60, n + (n2 - 0.5) * 0.5));
	forest = mix(forest, col_conifer, smoothstep(350.0, 800.0, h) * 0.7);
	forest *= mix(0.70, 1.18, canopy) * mix(1.06, 0.82, hollow);
	float clearing = smoothstep(0.58, 0.70, n2) * (1.0 - smoothstep(0.10, 0.30, slope)) * (1.0 - smoothstep(250.0, 500.0, h));
	vec3 meadow = col_meadow * mix(0.85, 1.12, n2);
	vec3 far_c = mix(forest, meadow, max(clearing, (1.0 - smoothstep(60.0, 160.0, h)) * 0.5));
	vec3 c = mix(near, far_c, smoothstep(120.0, 650.0, v_d));

	// rock: steep faces, spurs and everything above the tree line
	float rock = smoothstep(0.42, 0.62, slope + (n2 - 0.5) * 0.25 - hollow * 0.10);
	rock = max(rock, smoothstep(tree_line - 120.0, tree_line + 80.0, h + (0.5 - hollow) * 120.0));
	// strata: faint banding of the rock with height, bent by the relief
	float strata = 0.5 + 0.5 * sin(v_wp.y * 0.11 + rl.x * 9.0 + n * 6.0);
	vec3 rk = col_rock * mix(0.72, 1.12, n2) * mix(0.90, 1.08, strata * (1.0 - smoothstep(0.3, 1.2, fw / 20.0)));
	rk *= mix(1.05, 0.72, hollow);
	// scree fans below the faces, in the gullies
	float scree = hollow * smoothstep(0.30, 0.50, slope) * (1.0 - smoothstep(0.45, 0.65, slope)) * smoothstep(tree_line - 300.0, tree_line, h);
	rk = mix(rk, col_scree * mix(0.85, 1.1, n2), scree * 0.8);
	c = mix(c, rk, rock * smoothstep(60.0, 300.0, v_d));

	// snow: on the flats and in the gullies above the snow line
	float sn = smoothstep(snow_line - 60.0, snow_line + 60.0, h + hollow * 140.0 - 40.0)
		* (1.0 - smoothstep(0.42, 0.78, slope - hollow * 0.25));
	sn = max(sn, snow * (1.0 - smoothstep(0.30, 0.75, slope)));
	c = mix(c, col_snow * mix(0.92, 1.0, n2), sn);

	// hollows see less sky
	float ao = mix(1.0, mix(0.78, 1.0, 1.0 - hollow), far);
	float cs = cloud_shadow_at(v_wp, length(VERTEX), 110.0);
	ALBEDO = c * ao * cs;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ROUGHNESS = 1.0;
}
