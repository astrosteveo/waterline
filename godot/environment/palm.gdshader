shader_type spatial;
// A palm, swaying in the wind (environment/terrain.gd draws kiln's palms with it). Each
// vertex's colour, from art/models/plants/_palm.py, says how it sways: red how far (0 at the
// foot of the trunk, 1 at a frond's tip), green its frond's phase, blue how much it flutters.
// A palm leans downwind with the wind's strength and rocks about that, each tree at its own
// phase by where it stands. Time and wind are the game's (Ocean), so a paused game holds still.

global uniform float game_time;
global uniform vec3 wind;

uniform vec3 albedo : source_color = vec3(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
// How far a frond's tip rocks, in metres: in still air, and more for each m/s of wind.
uniform float calm_sway = 0.05;
uniform float sway_per_wind = 0.03;
// How far a frond's tip leans downwind for each m/s of wind, in metres.
uniform float lean_per_wind = 0.04;
// How fast the trees rock, in radians a second.
uniform float rock_speed = 1.3;
// How far the leaflets flutter for each m/s of wind, in metres, and how fast.
uniform float flutter_per_wind = 0.005;
uniform float flutter_speed = 9.0;

void vertex() {
	float sway = COLOR.r;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = COLOR.g * TAU + dot(origin.xz, vec2(0.37, 0.23));
	float speed = length(wind.xz);
	vec2 downwind = speed > 0.01 ? wind.xz / speed : vec2(0.6, 0.8);
	float rock = sin(game_time * rock_speed + phase) + 0.35 * sin(game_time * rock_speed * 2.3 + phase * 1.7);
	vec2 push = downwind * (lean_per_wind * speed + (calm_sway + sway_per_wind * speed) * rock) * sway;
	// A pushed tip swings down a little as it goes, as on the end of a bending frond.
	float drop = -0.25 * length(push) * sway;
	float flutter = sin(game_time * flutter_speed + phase * 3.0 + VERTEX.x * 5.0) * COLOR.b * flutter_per_wind * speed;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(push.x, drop + flutter, push.y, 0.0)).xyz;
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = roughness;
}
