// Sky: a horizon-to-zenith gradient, a sun (or moon) disc with a halo, soft cumulus clouds
// from a noise texture projected onto a dome, and stars for a night sky.
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.10, 0.32, 0.78);
uniform vec3 horizon_color : source_color = vec3(0.60, 0.80, 0.96);
// Below the horizon, seen only in reflections at grazing angles.
uniform vec3 below_color : source_color = vec3(0.16, 0.36, 0.52);
uniform float gradient_curve : hint_range(0.1, 2.0) = 0.45;

uniform float sun_size_degrees = 1.6;
uniform float sun_brightness = 30.0;
uniform float halo_strength = 0.6;

uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade_color : source_color = vec3(0.60, 0.68, 0.80);
// Higher values leave more clear sky.
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.56;
uniform float cloud_softness : hint_range(0.01, 0.5) = 0.12;
uniform float cloud_scale = 0.22;
// Clouds are thicker near the horizon, as a band of fair-weather cumulus.
uniform float horizon_cloud_boost : hint_range(0.0, 0.3) = 0.08;

// Stars: 0 for a day sky. Each cell of a grid of directions holds a star or not.
uniform float star_brightness = 0.0;
uniform float star_density : hint_range(0.0, 0.1) = 0.02;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float cloud_field(vec2 uv) {
	// Large, slow variation clusters the clouds and leaves stretches of clear sky.
	float cluster = texture(cloud_noise, uv * 0.31 + vec2(0.71, 0.29)).r;
	float detail = texture(cloud_noise, uv).r * 0.7 + texture(cloud_noise, uv * 2.7 + vec2(0.31, 0.17)).r * 0.3;
	return detail * 0.62 + cluster * 0.38;
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;

	vec3 color = mix(horizon_color, zenith_color, pow(clamp(up, 0.0, 1.0), gradient_curve));
	if (up < 0.0) {
		color = mix(horizon_color, below_color, clamp(-up * 6.0, 0.0, 1.0));
	}

	if (star_brightness > 0.0 && up > 0.0) {
		vec3 grid = dir * 220.0;
		vec3 cell = floor(grid);
		float h = hash3(cell);
		if (h < star_density) {
			vec3 centre = cell + 0.5 + (vec3(hash3(cell + 7.1), hash3(cell + 3.3), hash3(cell + 5.7)) - 0.5) * 0.6;
			float d = length(grid - centre);
			float size = 0.12 + 0.25 * hash3(cell + 1.9);
			float star = smoothstep(size, 0.0, d) * (0.3 + 0.7 * hash3(cell + 9.4));
			color += vec3(0.85, 0.9, 1.0) * star * star_brightness * smoothstep(0.0, 0.15, up);
		}
	}

	// Clouds on a flattened dome: project the view direction onto a plane above.
	if (up > 0.0) {
		vec2 uv = dir.xz / (up + 0.12) * cloud_scale;
		float n = cloud_field(uv);
		float threshold = cloud_coverage - horizon_cloud_boost * (1.0 - smoothstep(0.0, 0.35, up));
		float density = smoothstep(threshold, threshold + cloud_softness, n);
		// Thin out right at the horizon so the clouds don't bunch into a solid band.
		density *= smoothstep(0.0, 0.06, up);
		// Fake sunlight: a cloud is lit where it thins toward the sun.
		vec2 toward_sun = normalize(LIGHT0_DIRECTION.xz + vec2(0.0001)) * 0.025;
		float n_sunward = cloud_field(uv + toward_sun);
		float lit = clamp(0.6 + (n - n_sunward) * 9.0, 0.0, 1.0);
		float core = smoothstep(threshold + cloud_softness, threshold + cloud_softness * 4.0, n);
		vec3 cloud = mix(cloud_shade_color, cloud_color, lit * (1.0 - core * 0.35));
		color = mix(color, cloud, density);
	}

	// Sun disc and halo, from the first DirectionalLight3D.
	if (LIGHT0_ENABLED) {
		float sun_dot = dot(dir, LIGHT0_DIRECTION);
		float size = radians(sun_size_degrees);
		float disc = smoothstep(cos(size), cos(size * 0.7), sun_dot);
		float halo = pow(max(sun_dot, 0.0), 300.0) * 1.5 + pow(max(sun_dot, 0.0), 12.0) * 0.18;
		color += LIGHT0_COLOR * (disc * sun_brightness + halo * halo_strength) * step(0.0, up + 0.02);
	}

	COLOR = color;
}
