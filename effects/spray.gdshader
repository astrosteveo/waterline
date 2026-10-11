// Spray particles: soft billboards that fade out as they reach the water. Each particle reads
// the wave height under its centre from the same Gerstner waves the water draws (the Ocean
// autoload keeps the wave uniforms in step), so a falling droplet sinks out of sight softly
// instead of being cut flat by the water surface. They also fade close to the camera.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled;

#include "res://water/gerstner.gdshaderinc"

uniform float water_level = 0.0;
uniform sampler2D puff : source_color, filter_linear, hint_default_white;
uniform vec3 tint : source_color = vec3(0.95, 0.98, 1.0);
// Light passing through from behind, as through thin water.
uniform vec3 backlight_color : source_color = vec3(0.85, 0.9, 0.95);
// Fully faded this far above the water surface and below; opaque above.
uniform float waterline_fade = 0.35;
// Fade in between these distances from the camera.
uniform float near_fade_start = 3.0;
uniform float near_fade_end = 6.0;

varying float water_y;
varying vec3 world_position;

void vertex() {
	// Face the camera, keeping the particle's own size.
	mat4 facing = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	mat4 sized = facing * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * sized;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	world_position = (sized * vec4(VERTEX, 1.0)).xyz;
	// The water under the particle's centre (its rest position is close enough to its x, z).
	vec3 offset;
	vec3 tangent_x;
	vec3 tangent_z;
	gerstner_sum(MODEL_MATRIX[3].xz, 0.0, offset, tangent_x, tangent_z);
	water_y = offset.y + water_level;
}

void fragment() {
	float above = world_position.y - water_y;
	float waterline = smoothstep(0.0, waterline_fade, above);
	float near = smoothstep(near_fade_start, near_fade_end, distance(world_position, CAMERA_POSITION_WORLD));
	ALBEDO = tint * COLOR.rgb;
	ALPHA = texture(puff, UV).a * COLOR.a * waterline * near;
	ROUGHNESS = 1.0;
	BACKLIGHT = backlight_color;
}
