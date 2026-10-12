shader_type spatial;
// v0.15 hitodama (spirit fire): a cold blue-white flame drawn additively on a
// camera-facing quad. Round bright head low down, a flickering tongue that
// licks upward and sways, a soft halo. No texture, no lighting.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 core_color : source_color = vec4(0.86, 0.96, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(0.22, 0.62, 1.0, 1.0);
uniform float intensity = 3.2;
uniform float fade = 1.0;
uniform float seed = 0.0;

void vertex() {
	// spherical billboard, keeping the node's scale
	float sx = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sx, INV_VIEW_MATRIX[1] * sx,
		INV_VIEW_MATRIX[2] * sx, MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;          // x: -1..1, y: -1 top .. 1 bottom
	float h = clamp(0.5 - uv.y * 0.5, 0.0, 1.0);    // 0 bottom .. 1 top
	float t = TIME + seed * 13.7;
	vec2 p = vec2(uv.x, uv.y + 0.32);
	// the tongue narrows and sways the higher it reaches
	p.x += sin(t * 3.1 + h * 5.0) * 0.13 * h + sin(t * 7.7 + h * 9.0) * 0.04 * h;
	p.x /= mix(1.0, 0.30, smoothstep(0.35, 1.0, h));
	p.y *= mix(1.0, 0.62, step(0.0, -p.y));
	float r = length(p);
	float flick = 0.86 + 0.14 * sin(t * 11.0) * sin(t * 4.3 + 1.7);
	float head = smoothstep(0.30, 0.02, r);
	float body = smoothstep(0.62, 0.10, r);
	float halo = smoothstep(1.0, 0.0, length(uv * vec2(1.0, 0.8))) * 0.22;
	vec3 col = edge_color.rgb * (body * 0.9 + halo) + core_color.rgb * head * 1.4;
	ALBEDO = col * intensity * flick * fade;
	ALPHA = clamp(body + halo + head, 0.0, 1.0) * fade;
}
