shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_opaque, depth_test_disabled;

## Stylized scrolling flame. UV.y = base(0) → tip(1).

uniform sampler2D noise_tex : source_color, repeat_enable, filter_linear;
uniform sampler2D mask_tex : source_color, filter_linear;
uniform vec4 core_color : source_color = vec4(1.0, 0.95, 0.75, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.45, 0.08, 1.0);
uniform vec4 edge_color : source_color = vec4(0.55, 0.05, 0.0, 1.0);
uniform float scroll_a : hint_range(0.0, 4.0) = 1.35;
uniform float scroll_b : hint_range(0.0, 4.0) = 0.85;
uniform float dissolve : hint_range(0.0, 1.5) = 0.55;
uniform float intensity : hint_range(0.0, 4.0) = 1.6;
uniform float time_scale : hint_range(0.0, 4.0) = 1.0;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	vec2 uv = v_uv;
	float t = TIME * time_scale;

	float n1 = texture(noise_tex, uv * vec2(1.4, 2.2) + vec2(t * 0.15, -t * scroll_a)).r;
	float n2 = texture(noise_tex, uv * vec2(2.1, 1.6) + vec2(-t * 0.22, -t * scroll_b)).r;
	float n = n1 * 0.55 + n2 * 0.45;

	float mask = texture(mask_tex, uv).a;
	float shape = mask * smoothstep(0.0, 0.18, uv.y) * (1.0 - smoothstep(0.55, 1.0, uv.y));

	float body = shape * smoothstep(dissolve, dissolve + 0.35, n + (1.0 - uv.y) * 0.65);
	float core = shape * smoothstep(0.55, 0.95, n) * (1.0 - uv.y);

	vec3 col = mix(edge_color.rgb, mid_color.rgb, clamp(body * 1.4, 0.0, 1.0));
	col = mix(col, core_color.rgb, clamp(core * 1.8, 0.0, 1.0));

	float alpha = clamp(body * intensity, 0.0, 1.0);
	ALBEDO = col * (1.0 + core * 1.5);
	ALPHA = alpha;
	EMISSION = col * (1.2 + core * 2.5) * intensity;
}
