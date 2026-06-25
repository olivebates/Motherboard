// Screen-space post-process: recolors black pixels to a tint color (Main's
// modulate, darkened 80%). Applied via a full-screen ColorRect on a CanvasLayer
// in Main.tscn so it affects everything already rendered in the scene.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
// The replacement color for black pixels. Set from Main.gd to modulate * 0.2.
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// How dark a pixel must be to count as "black", and the soft edge of that cutoff.
uniform float threshold = 0.04;
uniform float softness = 0.04;

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	// Brightest channel: 0 for pure black, grows as the pixel lightens.
	float brightness = max(col.r, max(col.g, col.b));
	// 1.0 where the pixel is black, fading to 0.0 past the threshold.
	float blackness = 1.0 - smoothstep(threshold, threshold + softness, brightness);
	COLOR = vec4(mix(col, tint.rgb, blackness), 1.0);
}
