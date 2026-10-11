// A craft's wake: foam ribbons on the water. Each vertex holds the rest position (world x, z)
// of the surface point it marks, and rides the same Gerstner waves the water draws, so the
// wake lies on the surface as the swells move under it. The Ocean autoload keeps the wave
// uniforms in step (Ocean.add_follower). COLOR.a is the foam's strength at that vertex.
shader_type spatial;
render_mode world_vertex_coords, blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled;

#include "res://water/gerstner.gdshaderinc"

uniform float water_level = 0.0;
// Height above the surface, so the foam never sinks into it.
uniform float lift = 0.05;
uniform vec3 foam_color : source_color = vec3(0.93, 0.97, 1.0);
uniform sampler2D foam_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float noise_scale = 0.35;

varying vec2 world_xz;

void vertex() {
	vec3 offset;
	vec3 tangent_x;
	vec3 tangent_z;
	gerstner_sum(VERTEX.xz, 0.0, offset, tangent_x, tangent_z);
	world_xz = VERTEX.xz;
	VERTEX = vec3(VERTEX.x, 0.0, VERTEX.z) + offset + vec3(0.0, water_level + lift, 0.0);
	NORMAL = normalize(cross(tangent_z, tangent_x));
}

void fragment() {
	// Soft edges across the ribbon (UV.x from 0 to 1), broken up by noise.
	float edge = 1.0 - abs(UV.x * 2.0 - 1.0);
	float noise = texture(foam_noise, world_xz * noise_scale).r;
	// Strong foam breaks up into patches as it fades.
	float foam = smoothstep(0.0, 0.5, edge) * mix(smoothstep(0.3, 0.7, noise), 1.0, COLOR.a * 0.6);
	ALBEDO = foam_color;
	ROUGHNESS = 1.0;
	ALPHA = clamp(foam * COLOR.a, 0.0, 1.0);
}
