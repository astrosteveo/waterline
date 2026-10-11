// Gerstner wave sum shared by the ocean shaders.
// The CPU copy of this function is WaveSet.surface_point() and WaveSet.sample() in
// res://water/wave_set.gd. Keep the two in step: physics depends on them matching.
// OceanSurface (res://water/ocean_surface.gd) fills these uniforms from a WaveSet.

#define MAX_WAVES 16

uniform int wave_count = 0;
// Per wave: direction x, direction z, wavenumber k = TAU / wavelength, wavelength.
uniform vec4 wave_dir_k[MAX_WAVES];
// Per wave: amplitude, horizontal amplitude (amplitude * sharpness), unused, unused.
uniform vec4 wave_shape[MAX_WAVES];
// Per wave: phase at the current time, phase - omega * t wrapped to [0, TAU).
uniform float wave_phase[MAX_WAVES];

// How much of a wave to keep where samples are `spacing` meters apart. A wave needs
// about eight samples per wavelength to keep its shape; below four it shimmers.
float gerstner_fade(float wavelength, float spacing) {
	return 1.0 - smoothstep(wavelength * 0.125, wavelength * 0.25, spacing);
}

// Sums the waves for the surface point that rests at horizontal position p0.
// offset: where that point moves to, relative to p0 and the rest level.
// tangent_x, tangent_z: derivatives of the moved point with respect to p0.x and p0.y.
// The surface normal is normalize(cross(tangent_z, tangent_x)).
// spacing: sample spacing in meters, used to fade waves too short to draw.
void gerstner_sum(vec2 p0, float spacing, out vec3 offset, out vec3 tangent_x, out vec3 tangent_z) {
	offset = vec3(0.0);
	tangent_x = vec3(1.0, 0.0, 0.0);
	tangent_z = vec3(0.0, 0.0, 1.0);
	for (int i = 0; i < wave_count; i++) {
		vec4 dir_k = wave_dir_k[i];
		vec4 shape = wave_shape[i];
		float fade = gerstner_fade(dir_k.w, spacing);
		float amplitude = shape.x * fade;
		float horizontal = shape.y * fade;
		float f = dir_k.z * dot(dir_k.xy, p0) + wave_phase[i];
		float s = sin(f);
		float c = cos(f);
		offset += vec3(dir_k.x * horizontal * c, amplitude * s, dir_k.y * horizontal * c);
		float ks = dir_k.z * horizontal * s;
		float kc = dir_k.z * amplitude * c;
		tangent_x += vec3(-dir_k.x * dir_k.x * ks, dir_k.x * kc, -dir_k.x * dir_k.y * ks);
		tangent_z += vec3(-dir_k.x * dir_k.y * ks, dir_k.y * kc, -dir_k.y * dir_k.y * ks);
	}
}

// Maps a vertex of the 2 x 2 grid mesh (local x and z in [-1, 1]) to a horizontal offset
// in meters from the mesh centre. The middle of the grid (|x|, |z| < inner_fraction)
// keeps a uniform spacing of inner_spacing meters, so its vertices sit on a fixed world
// lattice when the mesh follows the camera in steps of inner_spacing. Outside it, the
// square rings of vertices spread out exponentially to outer_radius, so far water costs
// few vertices. Also returns the vertex spacing there, for gerstner_fade().
vec2 ocean_grid_offset(vec2 grid, float cells, float inner_fraction, float inner_spacing,
		float outer_radius, out float spacing) {
	float ring = max(abs(grid.x), abs(grid.y));
	float inner_radius = inner_spacing * inner_fraction * cells * 0.5;
	if (ring <= inner_fraction) {
		spacing = inner_spacing;
		return grid * (inner_radius / inner_fraction);
	}
	float growth = log(outer_radius / inner_radius) / (1.0 - inner_fraction);
	float distance = inner_radius * exp(growth * (ring - inner_fraction));
	spacing = distance * growth * 2.0 / cells;
	return grid / ring * distance;
}
