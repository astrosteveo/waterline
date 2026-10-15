// Small floats marking the course walls. Each instance rides the same Gerstner waves the
// water draws: INSTANCE_CUSTOM.xy holds the float's rest position (world x, z), and the
// Ocean autoload keeps the wave uniforms in step (Ocean.add_follower).
shader_type spatial;
render_mode world_vertex_coords;

#include "res://water/gerstner.gdshaderinc"

uniform float water_level = 0.0;

void vertex() {
	vec3 offset;
	vec3 tangent_x;
	vec3 tangent_z;
	gerstner_sum(INSTANCE_CUSTOM.xy, 0.0, offset, tangent_x, tangent_z);
	VERTEX += offset + vec3(0.0, water_level, 0.0);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.5;
}
