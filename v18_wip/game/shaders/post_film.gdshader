shader_type canvas_item;
render_mode blend_mul, unshaded;

// v0.17 film layer, drawn between the 3D view and the HUD. Multiplicative, so
// it never has to read the screen back (a screen copy is what makes this kind
// of effect expensive on phones): a soft lens vignette and fine animated
// grain. Colour grading lives in the Environment's colour-correction LUT.

uniform float vignette = 0.26;
uniform float grain = 0.032;
uniform float aspect = 1.7778;

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 c = (UV - 0.5) * vec2(aspect, 1.0);
	float r = length(c) / length(vec2(aspect, 1.0) * 0.5);   // 0 centre .. 1 corner
	float v = 1.0 - vignette * smoothstep(0.35, 1.05, r) * (0.65 + 0.35 * r);
	// 24 fps grain, triangular distribution from two hashes
	float t = floor(TIME * 24.0);
	vec2 px = floor(FRAGCOORD.xy);
	float n = h12(px + vec2(t * 37.0, t * 17.0)) + h12(px * 1.37 + vec2(t * 11.0, 5.0)) - 1.0;
	COLOR = vec4(vec3(v * (1.0 + n * grain)), 1.0);
}
