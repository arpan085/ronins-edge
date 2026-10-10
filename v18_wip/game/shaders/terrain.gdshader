shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/clouds.gdshaderinc"

// v0.13 terrain.
//
// Six photographic CC0 ground sets (Poly Haven, tools/make_ground_arrays.py)
// live in two texture arrays: albedo, and data = normal xy / roughness /
// height. The splat map says how much of each material a point has; the
// layers' own height maps then decide which one shows, so pebbles and roots
// poke through a transition instead of two photos cross-fading. Repetition
// is broken three ways: offset re-tiling driven by a smooth noise, a macro
// layer at 47 m and 173 m, and dry/lush patches in the grass. Steep faces
// get triplanar rock, the main river's channel gets a pebble bed and dark wet
// banks (bank-proximity texture from make_river.py), and rain and snow work
// as before. The v0.12 shader is kept in git history / tools for reference.

uniform float world_size = 1536.0;
uniform float water_level = 6.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform float snow_height = 108.0;
// 0 = cheapest (no anti-tiling, no triplanar), 3 = everything
uniform int quality : hint_range(0, 3) = 2;
// tests only: 1 = layer weights as flat emissive colours
uniform int debug_view = 0;

uniform sampler2D splat_tex : filter_linear;
uniform sampler2D biome_tex : filter_linear;
uniform sampler2D prox_tex : filter_linear;
uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray data_arr : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_tex : source_color, filter_linear_mipmap, repeat_enable;

// metres per repeat, per slice: grass, forest floor, trail, rock, mud, bed
uniform vec3 tile_a = vec3(2.6, 3.2, 2.4);
uniform vec3 tile_b = vec3(4.0, 1.9, 2.8);

// The grass photo is a dry meadow; the world is summer Japan. The texel's
// own luminance is kept (that is the detail) and its hue is pulled toward a
// moisture-driven tint, leaving a little of the original colour in.
uniform vec3 grass_lush : source_color = vec3(0.21, 0.33, 0.10);
uniform vec3 grass_dry : source_color = vec3(0.36, 0.37, 0.17);
uniform float grass_lum_mean = 0.056;
uniform float grass_regrade : hint_range(0.0, 1.0) = 0.88;
// v0.15: the grass layer under the GPU grass sits in the blades' shade; the
// same gain keeps the far ring melting into the ground at its edge
uniform float grass_gain = 0.85;
uniform float macro_lum_mean = 0.122;
uniform float macro_amount : hint_range(0.0, 1.0) = 0.38;
uniform float blend_depth : hint_range(0.02, 0.6) = 0.16;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float far_dist = 240.0;

varying vec3 v_world;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// One layer: albedo + data at p (in tiles), optionally de-tiled. After
// Inigo Quilez's "texture repetition" #3: a smooth noise index picks two
// randomly offset copies of the tile and blends them where the index turns
// over, biased by the texels themselves so the seam follows the image.
void tap(vec2 p, float layer, float k, vec2 dx, vec2 dy, bool notile, out vec4 alb, out vec4 dat) {
	if (!notile) {
		alb = textureGrad(albedo_arr, vec3(p, layer), dx, dy);
		dat = textureGrad(data_arr, vec3(p, layer), dx, dy);
		return;
	}
	float l = k * 8.0;
	float ia = floor(l);
	float f = l - ia;
	vec2 oa = sin(vec2(3.0, 7.0) * ia);
	vec2 ob = sin(vec2(3.0, 7.0) * (ia + 1.0));
	vec4 a1 = textureGrad(albedo_arr, vec3(p + oa, layer), dx, dy);
	vec4 a2 = textureGrad(albedo_arr, vec3(p + ob, layer), dx, dy);
	vec4 d1 = textureGrad(data_arr, vec3(p + oa, layer), dx, dy);
	vec4 d2 = textureGrad(data_arr, vec3(p + ob, layer), dx, dy);
	float t = smoothstep(0.2, 0.8, f - 0.1 * dot(a1.rgb - a2.rgb, vec3(1.0)));
	alb = mix(a1, a2, t);
	dat = mix(d1, d2, t);
}

vec3 unpack_n(vec4 dat, float s) {
	vec2 xy = (dat.rg * 2.0 - 1.0) * s;
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 wp = v_world;
	vec2 uv_w = wp.xz / world_size;
	vec4 sp = texture(splat_tex, uv_w);
	vec4 bi = texture(biome_tex, uv_w);
	float prox = texture(prox_tex, uv_w).r;
	float d = length(wp - CAMERA_POSITION_WORLD);
	bool detail = d < far_dist;
	bool notile = quality >= 1 && d < 150.0;
	vec3 Ng = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = 1.0 - clamp(Ng.y, 0.0, 1.0);
	float k = vnoise(wp.xz * 0.115);
	// every derivative up front: dFdx inside a branch is undefined
	vec3 dpx = dFdx(wp);
	vec3 dpy = dFdy(wp);
	vec2 dxw = dpx.xz;
	vec2 dyw = dpy.xz;

	// ---- how much of each material the map asks for
	// (splat biased toward grass: the generator writes a thin grass layer
	// almost everywhere and linear weights washed the world brown)
	float w_grass = pow(sp.r, 0.70) * 1.45;
	float w_dirt = sp.g;
	float w_rock = sp.b * 0.72;
	float w_mud = sp.a;
	float forest = smoothstep(0.30, 0.75, bi.a);
	float w_forest = w_grass * forest * 0.9;
	w_grass *= 1.0 - forest * 0.9;
	// the main river: pebble bed in the channel, mud on the banks
	float chan = smoothstep(0.93, 1.0, prox);
	float w_bed = chan * 1.6;
	w_grass *= 1.0 - chan; w_forest *= 1.0 - chan;
	w_dirt *= 1.0 - chan * 0.7; w_rock *= 1.0 - chan * 0.8;
	float bank = smoothstep(0.62, 0.93, prox) * (1.0 - chan);
	w_mud += bank * 0.35;
	// slope always wins: steep faces are rock whatever the splat says
	float slope_rock = smoothstep(0.34, 0.62, slope);
	w_rock = clamp(w_rock + slope_rock * 1.6, 0.0, 2.2);
	float tot = max(w_grass + w_forest + w_dirt + w_rock + w_mud + w_bed, 1e-4);
	w_grass /= tot; w_forest /= tot; w_dirt /= tot; w_rock /= tot; w_mud /= tot; w_bed /= tot;

	// ---- sample the layers that are present
	vec4 ag = vec4(0.0), dg = vec4(0.5, 0.5, 0.9, 0.5);
	vec4 af = ag, df = dg, ad = ag, dd = dg, am = ag, dm = dg, ab = ag, db = dg;
	if (w_grass > 0.004) tap(wp.xz / tile_a.x, 0.0, k, dxw / tile_a.x, dyw / tile_a.x, notile, ag, dg);
	if (w_forest > 0.004) tap(wp.xz / tile_a.y, 1.0, k, dxw / tile_a.y, dyw / tile_a.y, notile, af, df);
	if (w_dirt > 0.004) tap(wp.xz / tile_a.z, 2.0, k, dxw / tile_a.z, dyw / tile_a.z, notile, ad, dd);
	if (w_mud > 0.004) tap(wp.xz / tile_b.y, 4.0, k, dxw / tile_b.y, dyw / tile_b.y, notile, am, dm);
	if (w_bed > 0.004) tap(wp.xz / tile_b.z, 5.0, k, dxw / tile_b.z, dyw / tile_b.z, notile, ab, db);
	// rock: triplanar on steep ground, top-down elsewhere
	vec4 ar = ag, dr = dg;
	vec3 nr_w = Ng;
	vec3 bw = pow(abs(Ng), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	bool tri = quality >= 2 && slope > 0.22 && detail;
	if (w_rock > 0.004) {
		float tr = tile_b.x;
		if (tri) {
			vec4 ax = textureGrad(albedo_arr, vec3(wp.zy / tr, 3.0), dpx.zy / tr, dpy.zy / tr);
			vec4 ay = textureGrad(albedo_arr, vec3(wp.xz / tr, 3.0), dxw / tr, dyw / tr);
			vec4 az = textureGrad(albedo_arr, vec3(wp.xy / tr, 3.0), dpx.xy / tr, dpy.xy / tr);
			vec4 qx = textureGrad(data_arr, vec3(wp.zy / tr, 3.0), dpx.zy / tr, dpy.zy / tr);
			vec4 qy = textureGrad(data_arr, vec3(wp.xz / tr, 3.0), dxw / tr, dyw / tr);
			vec4 qz = textureGrad(data_arr, vec3(wp.xy / tr, 3.0), dpx.xy / tr, dpy.xy / tr);
			ar = ax * bw.x + ay * bw.y + az * bw.z;
			dr = qx * bw.x + qy * bw.y + qz * bw.z;
			// UDN-blended triplanar normal (Ben Golus), straight to world space
			vec3 tx = unpack_n(qx, normal_strength);
			vec3 ty = unpack_n(qy, normal_strength);
			vec3 tz = unpack_n(qz, normal_strength);
			ty.y = -ty.y;
			vec3 nx = vec3(tx.xy + Ng.zy, Ng.x);
			vec3 ny = vec3(ty.xy + Ng.xz, Ng.y);
			vec3 nz = vec3(tz.xy + Ng.xy, Ng.z);
			nr_w = normalize(nx.zyx * bw.x + ny.xzy * bw.y + nz.xyz * bw.z);
		} else {
			tap(wp.xz / tr, 3.0, k, dxw / tr, dyw / tr, notile, ar, dr);
		}
	}

	// ---- height-aware blend: each layer bids its weight plus its own relief
	float hs = 0.5;
	float bg = w_grass > 0.004 ? w_grass + dg.a * hs : -9.0;
	float bf = w_forest > 0.004 ? w_forest + df.a * hs : -9.0;
	float bd = w_dirt > 0.004 ? w_dirt + dd.a * hs : -9.0;
	float br = w_rock > 0.004 ? w_rock + dr.a * hs : -9.0;
	float bm = w_mud > 0.004 ? w_mud + dm.a * hs : -9.0;
	float bb = w_bed > 0.004 ? w_bed + db.a * hs : -9.0;
	float mx = max(max(max(bg, bf), max(bd, br)), max(bm, bb)) - blend_depth;
	float eg = max(bg - mx, 0.0), ef = max(bf - mx, 0.0), ed = max(bd - mx, 0.0);
	float er = max(br - mx, 0.0), em = max(bm - mx, 0.0), eb = max(bb - mx, 0.0);
	float es = max(eg + ef + ed + er + em + eb, 1e-5);
	eg /= es; ef /= es; ed /= es; er /= es; em /= es; eb /= es;

	// ---- colour
	float moist = clamp(bi.g * 1.9 - 0.1 + (vnoise(wp.xz * 0.013) - 0.5) * 0.55, 0.0, 1.0);
	vec3 gtint = mix(grass_dry, grass_lush, moist);
	float gl = dot(ag.rgb, LUMA);
	vec3 gcol = mix(ag.rgb, gtint * (gl / grass_lum_mean), grass_regrade) * grass_gain;
	// woods: leaf litter under a canopy that lets less light through
	vec3 fcol = af.rgb * vec3(0.80, 0.85, 0.86);
	// the rocky-trail photo is a sunlit grey path; ours are packed earth
	vec3 dcol = ad.rgb * vec3(0.84, 0.80, 0.72);
	// high rock loses its moss
	float alt = smoothstep(72.0, 125.0, wp.y);
	vec3 rcol = mix(ar.rgb, vec3(dot(ar.rgb, LUMA)) * vec3(1.02, 1.0, 0.97) * 1.12, alt * 0.75);
	vec3 albedo = gcol * eg + fcol * ef + dcol * ed + rcol * er + am.rgb * em + ab.rgb * eb;
	float h = dg.a * eg + df.a * ef + dd.a * ed + dr.a * er + dm.a * em + db.a * eb;
	float rough = dg.b * eg + df.b * ef + dd.b * ed + dr.b * er + dm.b * em + db.b * eb;

	// macro variation: an aerial photo at two long repeats modulates
	// brightness, so a field is never one flat tone to the horizon
	float m1 = dot(texture(macro_tex, wp.xz / 47.0).rgb, LUMA) / macro_lum_mean;
	float m2 = dot(texture(macro_tex, wp.xz / 173.0 + vec2(0.37, 0.71)).rgb, LUMA) / macro_lum_mean;
	float macro = clamp(mix(1.0, m1, macro_amount) * mix(1.0, m2, macro_amount * 0.7), 0.62, 1.4);
	albedo *= macro;

	// ---- water: wet banks and a dark, glossy bed; rain soaks hollows
	float pool = clamp(em * 1.4 + (1.0 - slope) * 0.35, 0.0, 1.0);
	float wet = max(wetness * pool, max(bank * 0.8, chan * 0.95));
	wet = max(wet, smoothstep(0.35, 0.62, prox) * 0.25);
	albedo *= mix(1.0, 0.55, wet);
	rough = mix(rough, 0.18, wet * 0.85);

	// snow on gentle high ground
	float sn = snow * smoothstep(snow_height - 26.0, snow_height + 20.0, wp.y)
			 * (1.0 - smoothstep(0.30, 0.60, slope));
	sn = clamp(sn, 0.0, 1.0);
	albedo = mix(albedo, vec3(0.86, 0.89, 0.95), sn);
	rough = mix(rough, 0.72, sn);

	ALBEDO = albedo;
	// v0.17 moving cloud shadows (shaders/clouds.gdshaderinc), mid and far field only
	{
		float cdist = length(VERTEX);
		if (cdist > 110.0) {
			ALBEDO *= cloud_shadow_at((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, cdist, 110.0);
		}
	}
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = mix(0.28, 0.45, wet);
	METALLIC = 0.0;
	// relief doubles as cavity occlusion for the indirect light
	AO = mix(0.55, 1.0, smoothstep(0.05, 0.6, h));
	AO_LIGHT_AFFECT = 0.25;

	// ---- normals, in world space (the rock may be triplanar)
	if (detail) {
		float s = normal_strength * (1.0 - smoothstep(far_dist * 0.5, far_dist, d)) * mix(1.0, 0.55, sn);
		vec3 tn = unpack_n(dg, s) * eg + unpack_n(df, s) * ef + unpack_n(dd, s) * ed
				+ unpack_n(dm, s) * em + unpack_n(db, s) * eb;
		vec3 T = normalize(vec3(1.0, 0.0, 0.0) - Ng * Ng.x);
		vec3 B = cross(Ng, T);
		vec3 nt_w = T * tn.x + B * tn.y + Ng * max(tn.z, 1e-3);
		vec3 rn = unpack_n(dr, s);
		vec3 rock_w = tri ? nr_w : T * rn.x + B * rn.y + Ng * rn.z;
		vec3 nw = normalize(nt_w + rock_w * er);
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	}
	if (debug_view == 1) {
		ALBEDO = vec3(0.0);
		SPECULAR = 0.0;
		ROUGHNESS = 1.0;
		EMISSION = vec3(0.0, 1.0, 0.0) * eg + vec3(0.0, 1.0, 1.0) * ef + vec3(1.0, 0.0, 0.0) * ed
				+ vec3(0.5) * er + vec3(1.0, 0.0, 1.0) * em + vec3(0.0, 0.0, 1.0) * eb;
	}
}
