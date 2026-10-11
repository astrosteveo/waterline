// Bright daytime sky: a horizon-to-zenith gradient, a sun disc with a halo, and soft
// cumulus clouds from a noise texture projected onto a dome.
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
