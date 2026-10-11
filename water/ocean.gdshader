// Ocean surface: a dense grid displaced by a sum of Gerstner waves (see gerstner.gdshaderinc),
// with depth-based colour, refraction, foam on crests and in shallows, and a sun highlight.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_lambert, specular_schlick_ggx;

#include "res://water/gerstner.gdshaderinc"

// Set by Sun (res://environment/sun.gd): unit vector pointing toward the sun.
global uniform vec3 sun_direction;
// Set by ShoreMap (res://water/shore_map.gd): the static scenery's height seen from above,
// and the area it covers (x, z of its corner, then width and depth). A zero width means no map.
global uniform sampler2D shore_height_map;
global uniform vec4 shore_map_rect;

group_uniforms grid;
// Set by OceanSurface from its exported grid settings.
uniform float grid_cells = 1024.0;
uniform float inner_fraction = 0.25;
uniform float inner_spacing = 0.3;
uniform float outer_radius = 6000.0;
// Wave time, for the small ripples that only exist in the normals.
uniform float ripple_time = 0.0;
// Sum of all amplitudes, for the crest colour.
uniform float max_wave_height = 1.0;

group_uniforms colour;
uniform vec3 deep_color : source_color = vec3(0.0, 0.11, 0.30);
uniform vec3 shallow_color : source_color = vec3(0.06, 0.55, 0.55);
// Depth in meters over which the colour goes from shallow to deep.
uniform float depth_color_range = 7.0;
// How much the light reaching underwater objects is dimmed by the water above them, as a
// share of the absorption along the view.
uniform float light_down_scale = 1.6;
// How quickly light is absorbed per meter of water, for red, green and blue.
uniform vec3 absorption = vec3(0.5, 0.16, 0.11);
// Light passing through thin crests toward the camera.
uniform vec3 crest_color : source_color = vec3(0.08, 0.55, 0.45);
uniform float crest_strength = 0.35;
uniform float refraction_strength = 0.06;

group_uniforms surface;
uniform float roughness : hint_range(0.0, 1.0) = 0.04;
uniform float specular : hint_range(0.0, 1.0) = 0.25;
uniform sampler2D ripple_normals : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float ripple_scale = 0.07;
uniform float ripple_strength = 0.12;
// Ripples fade out past this distance in meters, where they would only sparkle.
uniform float ripple_fade_distance = 260.0;

group_uniforms foam;
uniform sampler2D foam_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 1.0);
uniform float foam_scale = 0.18;
// Foam starts where the surface is squeezed to this share of its area (1 - fold)...
uniform float crest_foam_start = 0.11;
// ...and is solid here.
uniform float crest_foam_full = 0.42;
// Foam along shores and rocks, within this depth in meters.
uniform float shore_foam_depth = 0.35;
// What lies under the water counts as shore only if it is within this height of the static
// scenery's top surface (or below it). Anything floating higher, such as a hull, isn't.
uniform float shore_tolerance = 0.5;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec2 rest_xz;
varying vec3 world_position;
varying float vertex_fold;
varying float height_above_level;

void vertex() {
	float spacing;
	vec2 offset_xz = ocean_grid_offset(VERTEX.xz, grid_cells, inner_fraction, inner_spacing,
			outer_radius, spacing);
	rest_xz = NODE_POSITION_WORLD.xz + offset_xz;
	vec3 offset;
	vec3 tangent_x;
	vec3 tangent_z;
	gerstner_sum(rest_xz, spacing, offset, tangent_x, tangent_z);
	VERTEX = vec3(offset_xz.x + offset.x, offset.y, offset_xz.y + offset.z);
	NORMAL = normalize(cross(tangent_z, tangent_x));
	world_position = NODE_POSITION_WORLD + VERTEX;
	height_above_level = offset.y;
	vertex_fold = tangent_x.x * tangent_z.z - tangent_z.x * tangent_x.z;
}

vec3 world_from_depth(vec2 screen_uv, float depth, mat4 inv_projection, mat4 inv_view) {
	vec4 view = inv_projection * vec4(screen_uv * 2.0 - 1.0, depth, 1.0);
	view.xyz /= view.w;
	return (inv_view * vec4(view.xyz, 1.0)).xyz;
}

void fragment() {
	// Per-pixel normal from the same waves. Waves shorter than a few pixels are faded,
	// so distant water doesn't sparkle.
	vec2 footprint = fwidth(rest_xz);
	float pixel_size = max(footprint.x, footprint.y);
	vec3 offset;
	vec3 tangent_x;
	vec3 tangent_z;
	gerstner_sum(rest_xz, pixel_size * 0.5, offset, tangent_x, tangent_z);
	vec3 wave_normal = normalize(cross(tangent_z, tangent_x));
	float fold = tangent_x.x * tangent_z.z - tangent_z.x * tangent_x.z;

	// Small ripples from two scrolling normal maps.
	float view_distance = length(world_position - CAMERA_POSITION_WORLD);
	float ripple_fade = 1.0 - smoothstep(ripple_fade_distance * 0.3, ripple_fade_distance, view_distance);
	vec2 uv_a = rest_xz * ripple_scale + vec2(0.021, 0.013) * ripple_time;
	vec2 uv_b = rest_xz * ripple_scale * 1.73 + vec2(-0.017, 0.024) * ripple_time;
	vec3 ripple_a = texture(ripple_normals, uv_a).xyz * 2.0 - 1.0;
	vec3 ripple_b = texture(ripple_normals, uv_b).xyz * 2.0 - 1.0;
	vec2 ripple = (ripple_a.xy + ripple_b.xy) * ripple_strength * ripple_fade;
	vec3 normal_world = normalize(wave_normal + vec3(ripple.x, 0.0, ripple.y));

	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_position);
	float n_dot_v = clamp(dot(normal_world, view_dir), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - n_dot_v, 5.0);

	// What lies under the water at this pixel, and how deep.
	float surface_depth = FRAGCOORD.z;
	vec2 refract_uv = clamp(SCREEN_UV + normal_world.xz * refraction_strength, vec2(0.001), vec2(0.999));
	float floor_depth = texture(depth_texture, refract_uv).r;
	// Reverse Z: a larger value is nearer. Don't refract objects in front of the water. With
	// MSAA, an edge pixel's colour is a blend of the object and what's behind it while its
	// depth is only one of them, so check the neighbouring pixels too: refracting an edge
	// pixel drew a broken outline of the craft, shifted sideways.
	vec2 texel = 1.5 / vec2(textureSize(depth_texture, 0));
	float nearest = max(floor_depth, max(
			max(texture(depth_texture, refract_uv + vec2(texel.x, 0.0)).r, texture(depth_texture, refract_uv - vec2(texel.x, 0.0)).r),
			max(texture(depth_texture, refract_uv + vec2(0.0, texel.y)).r, texture(depth_texture, refract_uv - vec2(0.0, texel.y)).r)));
	if (nearest > surface_depth) {
		refract_uv = SCREEN_UV;
		floor_depth = texture(depth_texture, SCREEN_UV).r;
	}
	vec3 floor_world = world_from_depth(refract_uv, floor_depth, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	float vertical_depth = max(world_position.y - floor_world.y, 0.0);
	float path_length = min(distance(world_position, floor_world), 200.0);
	// Nothing drawn behind the water (reverse Z clears to 0): open sea, not a shore at the
	// far plane.
	if (floor_depth <= 0.0) {
		vertical_depth = 1000.0;
		path_length = 200.0;
	}
	vec3 transmittance = exp(-absorption * path_length);
	// Light reaching what is below has crossed the water on its way down too, so things
	// deeper down are darker: without this the underwater part of a rock or a post drew as a
	// bright turquoise column.
	vec3 light_down = exp(-absorption * vertical_depth * light_down_scale);

	vec3 refracted = textureLod(screen_texture, refract_uv, 0.0).rgb;

	// Thin crests glow when the sun is behind them.
	float crest = smoothstep(0.25, 1.0, height_above_level / max(max_wave_height, 0.01));
	float toward_sun = pow(clamp(dot(-view_dir, sun_direction) * 0.5 + 0.5, 0.0, 1.0), 3.0);
	vec3 crest_glow = crest_color * crest * (0.35 + toward_sun) * crest_strength;

	// Foam where crests are squeezed together and in shallow water. The coverage lowers
	// the threshold on a noise pattern, so foam grows from the noise's peaks.
	vec2 foam_uv = rest_xz * foam_scale;
	float foam_noise = texture(foam_texture, foam_uv + vec2(0.01, 0.0) * ripple_time).r * 0.6
			+ texture(foam_texture, foam_uv * 0.37 - vec2(0.0, 0.007) * ripple_time).r * 0.4;
	float squeeze = 1.0 - min(fold, vertex_fold);
	float crest_foam = smoothstep(crest_foam_start, crest_foam_full, squeeze);
	float shore_foam = (1.0 - smoothstep(0.0, shore_foam_depth, vertical_depth)) * 0.8;
	// 1 where what lies below is the top of the static scenery (sand, a reef, a rock's top),
	// 0 on the side of a rock or a post or under a floating hull.
	float on_scenery = 1.0;
	if (shore_map_rect.z > 0.0 && floor_depth > 0.0) {
		vec2 shore_uv = (floor_world.xz - shore_map_rect.xy) / shore_map_rect.zw;
		if (all(greaterThanEqual(shore_uv, vec2(0.0))) && all(lessThan(shore_uv, vec2(1.0)))) {
			// The highest scenery in the 3 x 3 texels around the point: a point on a rock's
			// steep side often rounds to a texel just outside the rock's outline.
			ivec2 size = textureSize(shore_height_map, 0);
			ivec2 centre = ivec2(shore_uv * vec2(size));
			float scenery_height = -64.0;
			for (int dy = -1; dy <= 1; dy++) {
				for (int dx = -1; dx <= 1; dx++) {
					ivec2 texel_at = clamp(centre + ivec2(dx, dy), ivec2(0), size - 1);
					vec2 encoded = texelFetch(shore_height_map, texel_at, 0).rg;
					scenery_height = max(scenery_height, (round(encoded.r * 63.0) + encoded.g) / 64.0 * 128.0 - 64.0);
				}
			}
			shore_foam *= step(floor_world.y, scenery_height + shore_tolerance);
			float below_top = scenery_height - floor_world.y;
			on_scenery = (1.0 - smoothstep(1.5, 3.0, below_top)) * (1.0 - smoothstep(shore_tolerance, shore_tolerance + 0.5, -below_top));
		}
	}
	float coverage = max(crest_foam, shore_foam);

	// The water's own colour shades from shallow to deep with the depth of the bottom. Only the
	// top of the scenery counts as a shallow bottom: through the side of a rock, a post or a
	// hull the water looks as deep as the sea around it, not like turquoise shallows.
	float depth_mix = 1.0 - exp(-vertical_depth / depth_color_range);
	depth_mix = mix(max(depth_mix, 0.9), depth_mix, on_scenery);
	vec3 water_color = mix(shallow_color, deep_color, depth_mix);
	float foam = smoothstep(1.0 - coverage, 1.22 - coverage, foam_noise) * step(0.001, coverage);

	// In-scattered light is lit like a diffuse surface; what shows through from below is
	// already lit, so it goes in as emission. Godot adds the reflection on top.
	ALBEDO = mix(water_color * (vec3(1.0) - transmittance), foam_color, foam);
	EMISSION = (refracted * transmittance * light_down * (1.0 - fresnel) + crest_glow) * (1.0 - foam);
	// Detail too fine to draw becomes roughness (GGX alpha is roughness squared, and adds
	// twice the slope variance). The ripple maps count as a slope of about ripple_strength.
	float lost_variance = gerstner_lost_slope_variance(pixel_size * 0.5)
			+ 0.5 * ripple_strength * ripple_strength * (1.0 - ripple_fade * ripple_fade);
	float alpha = roughness * roughness;
	float far_roughness = sqrt(sqrt(alpha * alpha + 2.0 * lost_variance));
	ROUGHNESS = mix(far_roughness, 0.7, foam);
	SPECULAR = mix(specular, 0.1, foam);
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(normal_world, 0.0)).xyz);
}
