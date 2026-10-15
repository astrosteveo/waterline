// Test shader: draws the same displaced grid as ocean.gdshader, but writes each pixel's
// surface height as a colour instead of shading it. res://test/water_match.gd reads the
// frame back and compares it with the CPU height. Two channels hold the height:
// red the coarse step (0..63) and green the fraction within the step.
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

#include "res://water/gerstner.gdshaderinc"

uniform float grid_cells = 1024.0;
uniform float inner_fraction = 0.25;
uniform float inner_spacing = 0.3;
uniform float outer_radius = 6000.0;
// Heights from -height_range to +height_range are encoded.
uniform float height_range = 4.0;

varying float world_height;

void vertex() {
	float spacing;
	vec2 offset_xz = ocean_grid_offset(VERTEX.xz, grid_cells, inner_fraction, inner_spacing,
			outer_radius, spacing);
	vec2 rest_xz = NODE_POSITION_WORLD.xz + offset_xz;
	vec3 offset;
	vec3 tangent_x;
	vec3 tangent_z;
	gerstner_sum(rest_xz, spacing, offset, tangent_x, tangent_z);
	VERTEX = vec3(offset_xz.x + offset.x, offset.y, offset_xz.y + offset.z);
	world_height = NODE_POSITION_WORLD.y + offset.y;
}

// The frame is converted from linear to sRGB on output, so undo that here to keep the
// encoded values exact.
vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	float u = clamp((world_height + height_range) / (2.0 * height_range), 0.0, 0.999999) * 64.0;
	float coarse = floor(u);
	float fine = u - coarse;
	ALBEDO = srgb_to_linear(vec3(coarse / 63.0, fine, 0.0));
}
