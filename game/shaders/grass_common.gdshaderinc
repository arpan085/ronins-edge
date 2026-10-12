// v0.15 GPU-placed ground cover, shared by grass_gpu.gdshader and
// ground_detail.gdshader.
//
// Nothing about a plant's placement lives on the CPU any more. Every ring of
// grass is a pool of tiles that all draw the SAME MultiMesh: a plain grid of
// instance origins. The vertex shader turns a grid point into a plant -- it
// hashes the world-space grid cell for jitter, yaw, size and rank, reads the
// terrain height, biome, density and splat maps, and drops the instance
// (collapses it to a point) where nothing should grow. Moving a tile is one
// transform write, so a ring "streams" at any speed with no build hitch and
// nothing pops: the outer band of each ring dissolves instance by instance
// (each has its own fade distance, from its rank) while the next ring's inner
// band fills in. The idea is Terrain3D's -- data maps on the GPU, the CPU only
// moves cells -- written natively for Godot 4.3.

uniform sampler2D height_tex : filter_nearest, repeat_disable;   // R32F metres
uniform sampler2D biome_tex : filter_nearest, repeat_disable;    // R id, G moisture, B grass, A trees
uniform sampler2D biome_lin : filter_linear, repeat_disable;     // same image, filtered
uniform sampler2D splat_tex : filter_linear, repeat_disable;     // R grass G dirt B rock A mud
uniform sampler2D river_tex : filter_linear, repeat_disable;     // R main stem
uniform sampler2D prox_tex : filter_linear, repeat_disable;      // 1 = in the main channel
uniform float world_size = 1536.0;
uniform float cell = 2.0;
uniform int grid = 769;
uniform float water_level = 6.0;
// Terrain chunk LOD, mirrored from Terrain.gd so roots sit on the mesh that
// is actually drawn (a 4 m stride hill is up to a metre off the 2 m grid).
uniform vec3 lod_center = vec3(768.0, 0.0, 768.0);
uniform vec4 lod_dist = vec4(190.0, 380.0, 620.0, 900.0);
uniform float chunk_m = 96.0;

// ring
uniform float spacing = 0.3;
uniform float ring_r0 = 0.0;
uniform float ring_in = 0.0;
uniform float ring_r1 = 36.0;
uniform float ring_out = 10.0;
uniform float fade_w = 3.0;
uniform float size_mul = 1.0;
uniform float density_mul = 1.0;
uniform vec3 cam_pos = vec3(0.0);
// directional shadow maps only get a share of the near ring (see gc_shadow_pass)
uniform float shadow_keep = 0.5;
uniform float shadow_r = 24.0;

// wind: a travelling gust field (same idea as the trees' tree_wind include)
uniform vec2 wind_dir = vec2(0.86, 0.51);
uniform float wind_strength : hint_range(0.0, 3.0) = 0.6;
uniform float gust : hint_range(0.0, 3.0) = 0.0;
uniform float gust_speed = 1.3;
uniform float gust_scale = 0.022;
uniform float flutter = 0.02;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

float gc_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec4 gc_hash42(vec2 p) {
	vec4 p4 = fract(vec4(p.xyxy) * vec4(0.1031, 0.1030, 0.0973, 0.1099));
	p4 += dot(p4, p4.wzxy + 33.33);
	return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

// identical to terrain.gdshader's vnoise, so tints line up with the ground
float gc_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = gc_hash12(i);
	float b = gc_hash12(i + vec2(1.0, 0.0));
	float c = gc_hash12(i + vec2(0.0, 1.0));
	float d = gc_hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float gc_hf(ivec2 p) {
	return texelFetch(height_tex, clamp(p, ivec2(0), ivec2(grid - 1)), 0).r;
}

// Height of the DRAWN terrain at xz: same LOD stride as the chunk under it,
// same 00-11 diagonal as Terrain._chunk_mesh. `slope` gets 1 - normal.y of
// that same quad (what Terrain.slope_at measures at full resolution), from
// the four texels already fetched.
float gc_height_slope(vec2 xz, out float slope) {
	vec2 cc = (floor(xz / chunk_m) + 0.5) * chunk_m;
	float d = distance(cc, lod_center.xz);
	int st = d < lod_dist.x ? 1 : (d < lod_dist.y ? 2 : (d < lod_dist.z ? 4 : (d < lod_dist.w ? 8 : 16)));
	float span = cell * float(st);
	vec2 f = xz / span;
	vec2 i0 = floor(f);
	vec2 t = f - i0;
	ivec2 g0 = ivec2(i0) * st;
	float h00 = gc_hf(g0);
	float h10 = gc_hf(g0 + ivec2(st, 0));
	float h01 = gc_hf(g0 + ivec2(0, st));
	float h11 = gc_hf(g0 + ivec2(st, st));
	float gx = ((h10 - h00) + (h11 - h01)) * 0.5 / span;
	float gz = ((h01 - h00) + (h11 - h10)) * 0.5 / span;
	slope = 1.0 - inversesqrt(1.0 + gx * gx + gz * gz);
	return t.x >= t.y ? h00 + (h10 - h00) * t.x + (h11 - h10) * t.y
					  : h00 + (h11 - h01) * t.x + (h01 - h00) * t.y;
}

float gc_height(vec2 xz) {
	float sl;
	return gc_height_slope(xz, sl);
}

int gc_biome(vec2 xz) {
	ivec2 ts = textureSize(biome_tex, 0);
	ivec2 p = clamp(ivec2(xz / world_size * vec2(ts)), ivec2(0), ts - ivec2(1));
	return int(texelFetch(biome_tex, p, 0).r * 255.0 + 0.5);
}

// Directional-light shadow passes render with an orthographic projection; the
// player's camera never does. Grass shadows are speckle at any distance, so
// the shadow pass draws only part of the ring.
bool gc_shadow_pass(mat4 proj) {
	return proj[3][3] > 0.5;
}

// Ring fade for this instance: 1 inside the ring, dissolving through the
// inner and outer bands at a distance set by its own rank.
float gc_ring_scale(float d, float rank) {
	float fo = ring_r1 - ring_out * rank;
	float s = 1.0 - smoothstep(fo - fade_w, fo, d);
	if (ring_in > 0.0) {
		float fi = ring_r0 + ring_in * rank;
		s *= smoothstep(fi, fi + fade_w, d);
	}
	return s;
}

// Wind at a root: xyz = bend axis (downwind lean), w = tip angle in radians.
// Weight the angle by height along the plant when applying it.
vec4 gc_wind(vec2 xz, float stiff, float phase) {
	vec2 wd = normalize(wind_dir + vec2(0.0001));
	vec2 flow = xz - wd * TIME * gust_speed;
	float g1 = gc_vnoise(flow * gust_scale);
	float g2 = gc_vnoise(flow * gust_scale * 3.1 + 17.13);
	float gf = smoothstep(0.15, 0.9, g1 * 0.7 + g2 * 0.3);
	// small, slow and capped: a breeze leans a meadow a few degrees and a
	// storm lays it over by forty, never a blade folded in half
	float ang = stiff * (wind_strength * (0.05 + 0.14 * gf) + gust * 0.20 * gf);
	ang += sin(TIME * 1.9 + phase * 6.2831 + dot(xz, wd) * 0.45) * flutter * (0.35 + wind_strength) * stiff;
	return vec4(wd.y, 0.0, -wd.x, min(ang, 0.8));
}

// Rodrigues rotation of p about a unit axis
vec3 gc_rotate(vec3 p, vec3 axis, float ang) {
	float sa = sin(ang);
	float ca = cos(ang);
	return p * ca + cross(axis, p) * sa + axis * dot(axis, p) * (1.0 - ca);
}

vec3 gc_rot_y(vec3 p, float a) {
	float s = sin(a);
	float c = cos(a);
	return vec3(p.x * c + p.z * s, p.y, -p.x * s + p.z * c);
}
