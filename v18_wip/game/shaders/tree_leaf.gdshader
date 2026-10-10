shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/clouds.gdshaderinc"

// Leaf cluster cards (v0.14). Alpha-scissored cells of leaf_atlas.png with
// normals bent onto the crown ellipsoid (baked in MeshLib.tree), so a crown
// shades as one soft volume. Back faces keep the outward crown normal instead
// of the flipped card normal, otherwise half the cards in a crown go dark.

#include "res://shaders/tree_wind.gdshaderinc"

uniform sampler2D leaf_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 leaf_tint : source_color = vec3(1.0);
uniform vec3 leaf_tint_alt : source_color = vec3(1.0);
uniform float tint_jitter = 0.14;
uniform float alpha_cut = 0.42;
uniform float translucency = 0.55;
uniform vec2 atlas_px = vec2(2048.0, 1024.0);
// deepest mip the leaves are sampled at (a 512 px cell is 32 px there)
uniform float max_mip = 4.0;
uniform int dbg = 0;                 // tests/EnvShots gdbg: 2 albedo, 5 flat LOD colour
uniform vec3 dbg_col = vec3(1.0, 0.0, 0.0);

varying float v_rnd;
varying float v_ao;
varying float v_var;
varying vec3 v_wn;
varying float v_face;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = INSTANCE_CUSTOM.x * 6.2831;
	VERTEX = tree_wind(VERTEX, COLOR.r, COLOR.a, wp, phase, TIME);
	v_rnd = COLOR.a;
	v_ao = COLOR.g;
	v_var = INSTANCE_CUSTOM.z;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// TANGENT carries the card's true facing (MeshLib._card); NORMAL is bent
	vec3 cn = normalize((MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz);
	vec3 vv = normalize(-(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	v_face = abs(dot(cn, vv));
}

void fragment() {
	// Alpha coverage shrinks as the atlas minifies (mip averaging), which is
	// why distant cut-out trees went thin. v0.14 scaled alpha up with the mip
	// level without limit, so far crowns turned into solid square cards (the
	// "black blocky canopies"). v0.15 stops descending the mip chain at a
	// level that still holds the leaf clusters' outline and gives that level
	// a bounded boost: far crowns stay broken and leafy.
	vec2 dx = dFdx(UV * atlas_px);
	vec2 dy = dFdy(UV * atlas_px);
	float lod = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
	float lod_c = min(lod, max_mip);
	vec4 t = textureLod(leaf_atlas, UV, lod_c);
	// cards turning edge-on erode away instead of showing as thin streaks
	ALPHA = t.a * (1.0 + lod_c * 0.14) * smoothstep(0.05, 0.30, v_face);
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	float j = fract(v_rnd * 7.13 + v_var * 3.71);
	vec3 tint = mix(leaf_tint, leaf_tint_alt, clamp(v_var * 1.2 - 0.1 + season * 0.5, 0.0, 1.0));
	vec3 c = t.rgb * tint * mix(1.0 - tint_jitter, 1.0 + tint_jitter, j);
	c *= mix(0.48, 1.0, v_ao);
	c *= mix(1.0, 0.78, wetness);
	float up = clamp(v_wn.y, 0.0, 1.0);
	c = mix(c, vec3(0.85, 0.88, 0.93), snow * smoothstep(0.30, 0.85, up) * 0.65);
	ALBEDO = c;
	// v0.17 moving cloud shadows (shaders/clouds.gdshaderinc), mid and far field only
	{
		float cdist = length(VERTEX);
		if (cdist > 110.0) {
			ALBEDO *= cloud_shadow_at((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, cdist, 110.0);
		}
	}
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ROUGHNESS = mix(0.72, 0.4, wetness);
	SPECULAR = 0.28;
	// a FACTOR, not a colour: the engine multiplies diffuse light by ALBEDO
	// afterwards. v0.14 passed the albedo itself, so transmitted light was
	// albedo squared -- a few percent -- and crowns against the sun went black.
	BACKLIGHT = vec3(translucency);
	if (dbg == 2) { EMISSION = ALBEDO; ALBEDO = vec3(0.0); SPECULAR = 0.0; BACKLIGHT = vec3(0.0); }
	else if (dbg == 5) { EMISSION = dbg_col; ALBEDO = vec3(0.0); SPECULAR = 0.0; BACKLIGHT = vec3(0.0); }
}

// Leaves: wrapped diffuse over the crown's bent normals, plus light that
// passes THROUGH the leaves toward the eye. The crown's own shadow only
// partly blocks that: light diffuses through several layers of leaf, so a
// backlit tree glows at its rim and stays green inside instead of going to
// silhouette.
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = clamp((ndl + 0.45) / 1.45, 0.0, 1.0);
	DIFFUSE_LIGHT += wrap * 0.85 * ATTENUATION * LIGHT_COLOR / PI;
	float toward = pow(clamp(dot(-VIEW, LIGHT), 0.0, 1.0), 4.0);
	float through = toward * 0.9 + clamp(-ndl, 0.0, 1.0) * 0.30;
	float sh = mix(0.28, 1.0, ATTENUATION);
	DIFFUSE_LIGHT += through * sh * BACKLIGHT * vec3(0.95, 1.0, 0.62) * LIGHT_COLOR / PI;
	vec3 hv = normalize(VIEW + LIGHT);
	float spv = pow(clamp(dot(NORMAL, hv), 0.0, 1.0), mix(18.0, 48.0, wetness)) * mix(0.05, 0.18, wetness);
	if (dbg == 0 || dbg == 3) { SPECULAR_LIGHT += spv * ATTENUATION * LIGHT_COLOR; }
}
