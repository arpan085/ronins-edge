shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

// v0.15 ground detail -- ferns, shrubs, sasa (bamboo grass) and mushrooms --
// placed on the GPU exactly like the grass (grass_common.gdshaderinc). Each
// kind has its own grid and its own probability per biome; ferns and
// mushrooms also follow the canopy (biome alpha = tree density).

#include "res://shaders/grass_common.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform int textured = 1;
uniform vec4 rects[4];
uniform int nrect = 1;
uniform float prob[10];
uniform float canopy_boost = 0.0;
uniform float base_scale = 1.0;
uniform float scale_jitter = 0.3;
uniform float stiff = 0.5;
uniform float dome_y = 0.3;          // shading centre height (m, before scale)
uniform vec3 tint_lush : source_color = vec3(0.24, 0.42, 0.17);
uniform vec3 tint_dry : source_color = vec3(0.42, 0.42, 0.20);
uniform float regrade = 0.3;
uniform float tex_lum = 0.08;
uniform float translucency = 0.4;

const int TRAIL_MAX = 12;
uniform vec4 trail[TRAIL_MAX];
uniform int trail_n = 0;
uniform float trail_radius = 1.2;
uniform float trail_push = 0.45;

varying vec2 v_uv;
varying float v_hf;
varying vec3 v_tint;
varying float v_ao;
varying float v_var;

void vertex() {
	vec3 inst = MODEL_MATRIX[3].xyz;
	vec3 lp = VERTEX - inst;
	vec2 g = floor(inst.xz / spacing);
	vec4 h1 = gc_hash42(g + vec2(201.7, -77.3));
	vec2 xz = (g + 0.5 + (h1.xy - 0.5) * 0.8) * spacing;
	bool shadow = gc_shadow_pass(PROJECTION_MATRIX);
	float dh = distance(xz, cam_pos.xz);
	bool alive = dh < ring_r1 + 0.5 && xz.x > 1.0 && xz.y > 1.0
			&& xz.x < world_size - 1.0 && xz.y < world_size - 1.0;
	if (shadow && dh > shadow_r) { alive = false; }
	vec3 outv = inst;
	vec3 nrm = vec3(0.0, 1.0, 0.0);
	if (alive) {
		// probability first: most grid points of a sparse kind grow nothing
		int biome = clamp(gc_biome(xz), 0, 9);
		vec2 uvw = xz / world_size;
		vec4 bi = textureLod(biome_lin, uvw, 0.0);
		float p = prob[biome] * mix(1.0, 1.0 + canopy_boost, smoothstep(0.25, 0.75, bi.a)) * density_mul;
		if (h1.w > p) { alive = false; }
		if (alive) {
			vec4 sp = textureLod(splat_tex, uvw, 0.0);
			float riv = textureLod(river_tex, uvw, 0.0).r;
			float prox = textureLod(prox_tex, uvw, 0.0).r;
			float sl;
			float y = gc_height_slope(xz, sl);
			if (y < water_level + 0.3 || prox > 0.85 || riv > 0.3 || sp.g > 0.5 || sl > 0.55) { alive = false; }
			vec4 h3 = gc_hash42(g + vec2(91.3, 45.6));
			vec3 root = vec3(xz.x, y - 0.04, xz.y);
			float d = distance(root, cam_pos);
			float sc = gc_ring_scale(d, h3.x);
			if (!shadow) { sc *= smoothstep(0.4, 1.4, d); }
			if (sc < 0.002) { alive = false; }
			if (alive) {
				vec4 h2 = gc_hash42(g + vec2(-17.9, 333.1));
				float s = base_scale * mix(1.0 - scale_jitter, 1.0 + scale_jitter, h3.y) * size_mul;
				float hf = clamp(COLOR.r, 0.0, 1.0);
				float yaw = h2.y * 6.2831;
				vec3 q = gc_rot_y(lp * s, yaw);
				if (textured == 1) {
					vec3 rel = q - vec3(0.0, dome_y * s, 0.0);
					nrm = normalize(normalize(rel + vec3(0.0, 0.001, 0.0)) * 0.6 + vec3(0.0, 0.8, 0.0));
				} else {
					nrm = gc_rot_y(NORMAL, yaw);
				}
				vec4 wnd = gc_wind(xz, stiff, h3.z);
				float w = pow(hf, 1.5);
				q = gc_rotate(q, wnd.xyz, wnd.w * w);
				vec3 off = vec3(0.0);
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
						off.xz += away * f * trail_push * w;
						off.y -= f * trail_push * 0.4 * w;
					}
				}
				outv = root + (q + off) * sc;
				int ri = (int(h2.w * float(nrect)) + int(COLOR.g * 8.0 + 0.5)) % max(nrect, 1);
				vec4 rect = rects[ri];
				v_uv = rect.xy + UV * rect.zw;
				v_hf = hf;
				v_ao = COLOR.g;
				float moist = clamp(bi.g * 1.9 - 0.1 + (gc_vnoise(xz * 0.013) - 0.5) * 0.55, 0.0, 1.0);
				v_tint = mix(tint_dry, tint_lush, moist);
				v_var = mix(0.85, 1.15, h3.w);
			}
		}
	}
	if (!alive) {
		v_uv = vec2(0.0); v_hf = 0.0; v_ao = 0.0; v_tint = vec3(0.0); v_var = 1.0;
	}
	VERTEX = outv;
	NORMAL = nrm;
}

void fragment() {
	vec3 c;
	float a = 1.0;
	if (textured == 1) {
		vec4 tx = texture(tex, v_uv);
		vec2 tsz = vec2(textureSize(tex, 0));
		vec2 dx = dFdx(v_uv * tsz);
		vec2 dy = dFdy(v_uv * tsz);
		float mip = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
		a = tx.a * (1.0 + min(mip, 4.0) * 0.18);
		float l = dot(tx.rgb, LUMA);
		float ratio = l / tex_lum;
		float rr = ratio <= 1.0 ? ratio : 1.0 + (ratio - 1.0) / (1.0 + (ratio - 1.0) * 1.2);
		c = mix(tx.rgb, v_tint * rr, regrade);
		c *= mix(0.55, 1.0, smoothstep(0.0, 0.6, v_hf));
	} else {
		c = v_tint * mix(0.55, 1.0, v_ao);
	}
	c *= v_var;
	c *= mix(1.0, 0.72, wetness);
	c = mix(c, vec3(0.80, 0.83, 0.88), snow * 0.7 * smoothstep(0.3, 1.0, v_hf));
	ALBEDO = min(c, vec3(0.82));
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = mix(0.8, 0.45, wetness);
	SPECULAR = 0.25;
	if (textured == 1 && !FRONT_FACING) { NORMAL = -NORMAL; }
	BACKLIGHT = vec3(translucency * (0.4 + 0.6 * v_hf));
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = clamp((ndl + 0.35) / 1.35, 0.0, 1.0);
	float fwd = pow(clamp(dot(-VIEW, LIGHT), 0.0, 1.0), 3.0);
	DIFFUSE_LIGHT += (wrap + fwd * BACKLIGHT.x) * ATTENUATION * LIGHT_COLOR / PI;
}
