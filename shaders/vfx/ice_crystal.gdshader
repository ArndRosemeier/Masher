shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;

## Glassy ice crystal — fresnel rim + cool emission + subtle sparkle.

uniform sampler2D noise_tex : source_color, repeat_enable, filter_linear;
uniform vec4 base_color : source_color = vec4(0.55, 0.82, 1.0, 0.55);
uniform vec4 rim_color : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform float emission_strength : hint_range(0.0, 8.0) = 2.4;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.8;
uniform float sparkle_amount : hint_range(0.0, 2.0) = 0.55;
uniform float opacity : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	float n = texture(noise_tex, UV * 3.5 + vec2(TIME * 0.05, TIME * -0.03)).r;
	float sparkle = step(0.82, n) * sparkle_amount;

	vec3 col = mix(base_color.rgb, rim_color.rgb, fres);
	col += rim_color.rgb * sparkle;

	ALBEDO = col;
	ALPHA = clamp(base_color.a * opacity + fres * 0.45, 0.0, 1.0);
	EMISSION = col * (emission_strength * (0.35 + fres) + sparkle * 3.0);
	ROUGHNESS = 0.15;
	METALLIC = 0.05;
}
