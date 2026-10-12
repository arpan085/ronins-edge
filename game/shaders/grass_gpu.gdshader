shader_type spatial;
render_mode cull_disabled, world_vertex_coords;
#include "res://shaders/clouds.gdshaderinc"

// v0.15 grass: photo-scanned clump cards (tools/make_grass_atlas.py) placed
// entirely on the GPU -- see grass_common.gdshaderinc for the placement.
//
// Each instance is two or three crossed cards (one camera-facing card in the
// far ring) carrying a whole clump of thin scanned blades, which is what gets
// the look of real meadow grass for a fraction of the triangles the old
// ribbon blades cost. Colour is graded toward the same moisture tint and
// aerial macro variation the terrain uses at that spot, so the grass and the
// ground under it agree (Terrain3D's colour-map idea) and the far ring melts
// into the terrain instead of ending on a line.

#include "res://shaders/grass_common.gdshaderinc"

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D macro_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 v_rect[40];
uniform vec2 v_size[40];
uniform float v_lum[40];      // mean luminance of each cell (Foliage.CELL_LUM)
uniform vec2 cat_range[8];
uniform vec4 cat_props[8];   // x stiffness, y regrade, z size jitter, w translucency
uniform vec4 pal_cat[10];
uniform vec4 pal_w[10];
uniform int billboard = 0;
uniform vec3 grass_lush : source_color = vec3(0.21, 0.33, 0.10);
uniform vec3 grass_dry : source_color = vec3(0.36, 0.37, 0.17);
uniform float macro_lum_mean = 0.122;
uniform float macro_amount = 0.38;
uniform float tip_gain = 0.80;
uniform float albedo_max = 0.82;
uniform int dbg = 0;   // tests/EnvShots gdbg: 2 albedo, 3 lighting only, 4 normal

const int TRAIL_MAX = 12;
uniform vec4 trail[TRAIL_MAX];
uniform int trail_n = 0;
uniform float trail_radius = 1.4;
uniform float trail_push = 0.8;

varying vec2 v_uv;
varying float v_hf;
varying vec3 v_tint;
varying vec3 v_var;
varying float v_regrade;
varying float v_dry;
varying float v_back;
varying float v_cl;

void vertex() {
	vec3 inst = MODEL_MATRIX[3].xyz;
	vec3 lp = VERTEX - inst;
	vec2 g = floor(inst.xz / spacing);
	vec4 h1 = gc_hash42(g);
	vec2 xz = (g + 0.5 + (h1.xy - 0.5) * 0.92) * spacing;
	bool shadow = gc_shadow_pass(PROJECTION_MATRIX);
	// Work is staged so a dead plant costs as little as possible: most grid
	// points of a square tile lie outside the round ring, and many more are
	// thinned by density. Each stage collapses the instance to a point.
	float dh = distance(xz, cam_pos.xz);
	bool alive = dh < ring_r1 + 0.5 && xz.x > 1.0 && xz.y > 1.0
			&& xz.x < world_size - 1.0 && xz.y < world_size - 1.0;
	if (shadow && (h1.z > shadow_keep || dh > shadow_r)) { alive = false; }
	vec3 outv = inst;
	vec3 nrm = vec3(0.0, 1.0, 0.0);
	if (alive) {
		vec2 uvw = xz / world_size;
		vec4 bi = textureLod(biome_lin, uvw, 0.0);
		vec4 sp = textureLod(splat_tex, uvw, 0.0);
		// ---- how much grows here (the floors Foliage.gd used to apply on the CPU)
		float den = bi.b;
		float mxs = max(max(sp.r, sp.g), max(sp.b, sp.a));
		if (sp.r >= mxs) { den = max(den, 0.78); }
		else if (sp.a >= mxs) { den = max(den, 0.46); }
		else if (sp.g >= mxs) { den = max(den * 0.5, 0.20); }
		else { den = max(den * 0.45, 0.10); }
		// trails: bare-ish centre, short grass only; the verges stay deep
		float road = smoothstep(0.45, 0.85, sp.g);
		den *= mix(1.0, 0.30, road) * density_mul;
		if (h1.w > den * 1.1) { alive = false; }
		float sl = 0.0;
		float y = 0.0;
		vec4 h3 = gc_hash42(g + vec2(-53.3, 12.9));
		float sc = 0.0;
		if (alive) {
			y = gc_height_slope(xz, sl);
			float riv = textureLod(river_tex, uvw, 0.0).r;
			float prox = textureLod(prox_tex, uvw, 0.0).r;
			if (h1.w > den * 1.1 * (1.0 - smoothstep(0.50, 0.64, sl))) { alive = false; }
			if (y < water_level + 0.15 || prox > 0.9 || riv > 0.3) { alive = false; }
			vec3 root0 = vec3(xz.x, y - 0.03, xz.y);
			float d = distance(root0, cam_pos);
			sc = gc_ring_scale(d, h3.x);
			if (!shadow) { sc *= smoothstep(0.5, 1.7, d); }
			if (sc < 0.002) { alive = false; }
		}
		if (alive) {
			vec4 h2 = gc_hash42(g + vec2(37.1, 91.7));
			int biome = clamp(gc_biome(xz), 0, 9);
			// ---- which grass: biome palette, laid down in banks by a smooth field
			float roll = gc_vnoise(xz / 26.0) * 0.76 + h2.z * 0.24;
			vec4 pw = pal_w[biome];
			vec4 pc = pal_cat[biome];
			int slot = (roll > pw.x ? 1 : 0) + (roll > pw.y ? 1 : 0) + (roll > pw.z ? 1 : 0);
			float pcs = slot == 0 ? pc.x : (slot == 1 ? pc.y : (slot == 2 ? pc.z : pc.w));
			int cat = int(pcs + 0.5);
			if (road > 0.55) { cat = 0; }
			vec2 cr = cat_range[cat];
			int ncat = max(int(cr.y), 1);
			int card = int(COLOR.g * 2.0 + 0.5);
			int vi = int(cr.x) + (int(h2.w * float(ncat)) + card) % ncat;
			vec4 rect = v_rect[vi];
			vec2 sz = v_size[vi];
			vec4 cp = cat_props[cat];
			// neighbouring clumps share a height (a mid-scale field), the way a
			// real meadow grows in tussocks instead of every plant rolling its own
			float clump = gc_vnoise(xz / 3.7 + 11.0);
			float s = mix(1.0 - cp.z, 1.0 + cp.z, h3.y) * mix(0.82, 1.18, clump)
					* mix(0.85, 1.08, clamp(den, 0.0, 1.0)) * size_mul;
			sz *= s;

			// ---- shape
			float hf = COLOR.r;
			vec3 p = lp;
			p.xz *= sz.x * (1.0 + 0.22 * hf);   // cards open toward the top: a crown, not a cross
			p.y *= sz.y;
			float yaw = h2.y * 6.2831;
			if (billboard == 1) {
				vec2 tc = cam_pos.xz - xz;
				yaw = atan(tc.x, tc.y);
			}
			p = gc_rot_y(p, yaw);
			// soft dome normals: the clump shades like a mass, not like flat cards
			nrm = normalize(vec3(p.x, 0.0, p.z) / max(sz.x * 0.5, 0.05) * 0.55 + vec3(0.0, 1.0, 0.0));
			if (billboard == 1) { nrm = normalize(vec3(sin(yaw), 0.0, cos(yaw)) * 0.35 + vec3(0.0, 1.0, 0.0)); }
			vec4 wnd = gc_wind(xz, cp.x, h3.z);
			float w = pow(hf, 1.5);
			p = gc_rotate(p, wnd.xyz, wnd.w * w);
			nrm = gc_rotate(nrm, wnd.xyz, wnd.w * w * 0.5);

			// ---- whatever walks through it pushes it aside
			vec3 off = vec3(0.0);
			float reach = min(sz.y * 1.2, 1.0);
			for (int i = 0; i < TRAIL_MAX; i++) {
				if (i >= trail_n) { break; }
				vec4 tp = trail[i];
				if (tp.w <= 0.001) { continue; }
				vec2 dd = xz - tp.xz;
				float dist = length(dd);
				if (dist < trail_radius) {
					float f = 1.0 - dist / trail_radius;
					f = f * f * tp.w;
					vec2 away = dist > 0.001 ? dd / dist : vec2(1.0, 0.0);
					off.xz += away * f * trail_push * w * reach;
					off.y -= f * trail_push * 0.6 * w * reach;
				}
			}
			outv = vec3(xz.x, y - 0.03, xz.y) + (p + off) * sc;

			v_uv = rect.xy + UV * rect.zw;
			v_hf = hf;
			v_regrade = cp.y;
			v_cl = max(v_lum[vi], 0.02);
			v_back = cp.w;
			float hv = h3.w;
			v_var = vec3(mix(0.86, 1.14, hv)) * vec3(mix(0.90, 1.12, fract(hv * 3.7)), 1.0, mix(0.80, 1.20, fract(hv * 7.1)));
			float moist = clamp(bi.g * 1.9 - 0.1 + (gc_vnoise(xz * 0.013) - 0.5) * 0.55, 0.0, 1.0);
			v_dry = clamp((1.0 - moist) * 0.6 + (1.0 - clamp(den, 0.0, 1.0)) * 0.3, 0.0, 1.0);
			if (!shadow) {
				float m1 = dot(textureLod(macro_tex, xz / 47.0, 3.0).rgb, LUMA) / macro_lum_mean;
				float m2 = dot(textureLod(macro_tex, xz / 173.0 + vec2(0.37, 0.71), 3.0).rgb, LUMA) / macro_lum_mean;
				float macro = clamp(mix(1.0, m1, macro_amount) * mix(1.0, m2, macro_amount * 0.7), 0.62, 1.4);
				v_tint = mix(grass_dry, grass_lush, moist) * macro;
			} else {
				v_tint = grass_lush;
			}
		}
	}
	if (!alive) {
		v_uv = vec2(0.0); v_hf = 0.0; v_regrade = 0.0; v_back = 0.0; v_cl = 0.085;
		v_var = vec3(1.0); v_dry = 0.0; v_tint = vec3(0.0);
	}
	VERTEX = outv;
	NORMAL = nrm;
}

void fragment() {
	vec4 tx = texture(atlas, v_uv);
	// keep coverage at a distance: the mips of a sparse card average toward
	// clear and alpha-test would thin the field out to nothing
	vec2 tsz = vec2(textureSize(atlas, 0));
	vec2 dx = dFdx(v_uv * tsz);
	vec2 dy = dFdy(v_uv * tsz);
	float mip = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
	float a = tx.a * (1.0 + min(mip, 4.0) * 0.22);
	vec3 c = tx.rgb;
	float l = dot(c, LUMA);
	// texel brightness relative to its own cell, highlights rolled off: the
	// full-resolution blades of the near ring carry specks at 3-7x the mean
	// that went straight to white
	float ratio = l / v_cl;
	float rr = ratio <= 1.0 ? ratio : 1.0 + (ratio - 1.0) / (1.0 + (ratio - 1.0) * 1.2);
	vec3 graded = v_tint * rr * tip_gain;
	c = mix(c, graded, v_regrade);
	c *= v_var;
	vec3 straw = vec3(0.30, 0.25, 0.12) * rr;
	c = mix(c, straw, v_dry * 0.35 * smoothstep(0.3, 1.0, v_hf) * v_regrade);
	// the lower half of a clump stands in its own shade
	c *= mix(0.40, 1.0, smoothstep(0.0, 0.62, v_hf));
	c *= mix(1.0, 0.70, wetness);
	c = mix(c, vec3(0.80, 0.83, 0.88), snow * 0.75 * smoothstep(0.2, 1.0, v_hf));
	ALBEDO = min(c, vec3(albedo_max));
	// v0.17 moving cloud shadows (shaders/clouds.gdshaderinc), mid and far field only
	{
		float cdist = length(VERTEX);
		if (cdist > 110.0) {
			ALBEDO *= cloud_shadow_at((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, cdist, 110.0);
		}
	}
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// a waxy sheen, but a low one: at grazing angles the sky's reflection
	// whitened the far half of the field
	ROUGHNESS = mix(0.84, 0.42, wetness);
	SPECULAR = mix(0.14, 0.3, wetness);
	// both faces of a card share the clump's dome normal
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
	// translucency strength for light(): more toward the thin tips
	BACKLIGHT = vec3(v_back * (0.35 + 0.65 * v_hf));
	if (dbg == 2) { EMISSION = ALBEDO; ALBEDO = vec3(0.0); SPECULAR = 0.0; ROUGHNESS = 1.0; BACKLIGHT = vec3(0.0); }
	else if (dbg == 3) { ALBEDO = vec3(0.5); SPECULAR = 0.0; }
	else if (dbg == 4) { EMISSION = (mat3(INV_VIEW_MATRIX) * NORMAL) * 0.5 + 0.5; ALBEDO = vec3(0.0); SPECULAR = 0.0; ROUGHNESS = 1.0; BACKLIGHT = vec3(0.0); }
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = clamp((ndl + 0.3) / 1.3, 0.0, 1.0);
	// thin leaves glow when you look toward the sun through them
	float fwd = pow(clamp(dot(-VIEW, LIGHT), 0.0, 1.0), 3.0);
	float trans = fwd * BACKLIGHT.x;
	DIFFUSE_LIGHT += (wrap + trans) * ATTENUATION * LIGHT_COLOR / PI;
	vec3 hv = normalize(VIEW + LIGHT);
	float spv = pow(clamp(dot(NORMAL, hv), 0.0, 1.0), mix(16.0, 64.0, wetness)) * mix(0.05, 0.22, wetness);
	SPECULAR_LIGHT += spv * ATTENUATION * LIGHT_COLOR / PI;
}
