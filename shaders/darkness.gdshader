// Full-screen darkness overlay: paints the room black, then carves soft circular
// "light" holes around the player and any powered LightSource. Driven by
// DarknessOverlay.gd (its own CanvasLayer). Light positions/radii are supplied in
// viewport pixels (FRAGCOORD space, 800x384). `darkness` is the overall opacity,
// tweened 0->1 on room entry so the black fades in.
shader_type canvas_item;

const int MAX_LIGHTS = 32;

uniform int light_count = 0;
uniform vec2 lights[MAX_LIGHTS];   // screen-pixel centers
uniform float radii[MAX_LIGHTS];   // radius in pixels
uniform float darkness = 0.0;      // 0 = fully lit, 1 = full black overlay

void fragment() {
	float lit = 0.0;
	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (i >= light_count) {
			break;
		}
		float d = distance(FRAGCOORD.xy, lights[i]);
		// Crisp edge: fully lit inside the radius, fully dark outside (no falloff).
		float l = 1.0 - step(radii[i], d);
		lit = max(lit, l);
	}
	COLOR = vec4(0.0, 0.0, 0.0, darkness * (1.0 - lit));
}
