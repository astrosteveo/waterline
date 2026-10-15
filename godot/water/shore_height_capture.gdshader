// Used by ShoreMap: a full-screen pass for its top-down capture camera that turns the depth
// buffer into the scenery's height at each texel. The height is encoded in two 8-bit
// channels (red: 2 m steps, green: the fraction of a step) for heights from -64 to 64 m.
// Any other camera discards it.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
// ShoreMap's capture camera; every other camera discards this pass.
uniform vec3 capture_camera_position;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// The frame is converted from linear to sRGB on output; undo that so the stored values are exact.
vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	if (distance(CAMERA_POSITION_WORLD, capture_camera_position) > 0.5) {
		discard;
	}
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	// Reverse Z clears to 0: no scenery here, so store the lowest height.
	float height = depth > 0.0 ? world.y : -64.0;
	float u = clamp((height + 64.0) / 128.0, 0.0, 0.999999) * 64.0;
	float coarse = floor(u);
	ALBEDO = srgb_to_linear(vec3(coarse / 63.0, u - coarse, 0.0));
}
