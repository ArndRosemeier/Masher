shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque, depth_test_disabled;

## Expanding ground frost disc. progress 0→1 controls radius reveal.

uniform sampler2D noise_tex : source_color, repeat_enable, filter_linear;
uniform sampler2D mask_tex : source_color, filter_linear;
uniform vec4 frost_color : source_color = vec4(0.7, 0.9, 1.0, 0.75);
uniform vec4 crack_color : source_color = vec4(0.45, 0.75, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.5) = 1.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float intensity : hint_range(0.0, 3.0) = 1.35;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	vec2 uv = v_uv;
	vec2 centered = uv - vec2(0.5);
	float r = length(centered) * 2.0;

	float n = texture(noise_tex, uv * 4.0).r;
	float edge = progress * (0.85 + n * 0.25);
	float disc = smoothstep(edge, edge - 0.18, r) * smoothstep(0.0, 0.08, r);
	float mask = texture(mask_tex, uv).a;

	float cracks = smoothstep(0.55, 0.9, texture(noise_tex, uv * 7.0 + vec2(0.2, -0.1)).r);
	cracks *= disc;

	vec3 col = mix(frost_color.rgb, crack_color.rgb, cracks * 0.65);
	float alpha = disc * mask * frost_color.a * fade * intensity;
	alpha *= (0.65 + cracks * 0.5);

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
	EMISSION = col * (0.8 + cracks * 1.4) * intensity * fade;
}
