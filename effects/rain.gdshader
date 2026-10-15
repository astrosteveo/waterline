// Rain: thin streaks along the drops' velocity, turned to face the camera. Each streak fades
// out over its last part above the water, read from the same Gerstner waves the water draws
// (the Ocean autoload keeps the wave uniforms in step), so a drop never meets the surface
// with a hard edge. Streaks also fade close to the camera and toward the edge of the area
// the rain falls in. They are lit, with light passing through from behind as through
// spray, so they darken with the sky and catch the harbour lamps at night.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled;

#include "res://water/gerstner.gdshaderinc"

uniform float water_level = 0.0;
// The drops' velocity in world space: the streaks lie along it.
uniform vec3 fall_velocity = vec3(0.0, -9.0, 0.0);
// How long a streak is for each m/s of speed (the time a drop is seen to move in).
uniform float streak_time = 0.04;
uniform float streak_width = 0.015;
// A streak is drawn at least this many pixels wide, fainter in proportion, so a thin
// distant streak doesn't break up into dots.
uniform float min_pixels = 1.5;
uniform vec3 tint : source_color = vec3(0.85, 0.88, 0.92);
uniform float opacity = 0.6;
// Fully faded this far above the water surface and below it.
uniform float waterline_fade = 0.5;
// Fade in between these distances from the camera.
uniform float near_fade_start = 2.0;
uniform float near_fade_end = 5.0;
// Fade out between these distances from the camera.
uniform float far_fade_start = 14.0;
uniform float far_fade_end = 24.0;

varying float water_y;
varying vec3 world_position;
varying float thin;

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 axis = normalize(fall_velocity);
	vec3 to_camera = normalize(CAMERA_POSITION_WORLD - centre);
	vec3 side = cross(axis, to_camera);
	// Looking straight along the rain: any side will do.
	side = length(side) < 0.001 ? vec3(1.0, 0.0, 0.0) : normalize(side);
	vec3 facing = normalize(cross(side, axis));
	float streak_length = length(fall_velocity) * streak_time;
	// The width of a pixel at the drop's distance.
	float pixel = 2.0 * distance(CAMERA_POSITION_WORLD, centre) / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float width = max(streak_width, pixel * min_pixels);
	thin = streak_width / width;
	mat4 placed = mat4(vec4(side * width, 0.0), vec4(axis * streak_length, 0.0),
			vec4(facing, 0.0), vec4(centre, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * placed;
	MODELVIEW_NORMAL_MATRIX = mat3(VIEW_MATRIX) * mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), facing);
	world_position = (placed * vec4(VERTEX, 1.0)).xyz;
	// The water under the drop (its rest position is close enough to its x, z).
	vec3 offset;
	vec3 tangent_x;
	vec3 tangent_z;
	gerstner_sum(centre.xz, 0.0, offset, tangent_x, tangent_z);
	water_y = offset.y + water_level;
}

void fragment() {
	float above = world_position.y - water_y;
	float waterline = smoothstep(0.0, waterline_fade, above);
	float distance_to_camera = distance(world_position, CAMERA_POSITION_WORLD);
	float near = smoothstep(near_fade_start, near_fade_end, distance_to_camera);
	float far = 1.0 - smoothstep(far_fade_start, far_fade_end, distance_to_camera);
	// Soft across the streak and at its two ends. With multisampling a pixel at the streak's
	// edge is shaded at its centre, which can lie outside the quad, with UV outside 0 to 1:
	// clamped, or the alpha goes negative and darkens what is behind.
	vec2 uv = clamp(UV, 0.0, 1.0);
	float across = 1.0 - abs(uv.x * 2.0 - 1.0);
	float along = smoothstep(0.0, 0.3, uv.y) * (1.0 - smoothstep(0.7, 1.0, uv.y));
	ALBEDO = tint;
	ROUGHNESS = 1.0;
	BACKLIGHT = tint;
	ALPHA = clamp(opacity * COLOR.a * thin * across * along * waterline * near * far, 0.0, 1.0);
}
