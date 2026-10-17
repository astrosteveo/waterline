// The terrain's look, shared by terrain.gdshader (shallows and land, which receive shadows)
// and terrain_deep.gdshader (deep seabed, which doesn't). Each vertex's colour says what the
// ground there is made of: red sand, green grass, blue rock, and alpha how deep the seabed
// lies (0 at the surface, 1 at 20 m), which darkens it; between vertices they blend. The
// textures are kiln's (art/textures), mapped in world space: sand and grass from straight
// above, rock from all three sides, so cliffs don't smear. Sand and rock have ORM maps
// (occlusion, roughness and metallic in red, green and blue); grass is equally rough all over,
// a number its recipe gives (kiln.lock.json's "values").

uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_orm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grass_roughness : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_orm : filter_linear_mipmap_anisotropic, repeat_enable;
// Metres one tile of each texture covers (as its kiln recipe's tile).
uniform float sand_tile = 4.0;
uniform float grass_tile = 4.0;
uniform float rock_tile = 4.0;
// How strongly each normal map tilts the surface.
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
// The colour deep seabed shades toward, multiplied in.
uniform vec3 deep_tint : source_color = vec3(0.62, 0.66, 0.6);
// How strongly the brightness wobbles over tens of metres (the rock and grass textures sampled
// large, about 10% either way at 1), so the tiles don't repeat in rows.
uniform float variation : hint_range(0.0, 2.0) = 1.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// A normal map's tilt (x along the texture's u, y up the image).
vec2 tilt(sampler2D map, vec2 uv) {
	return (texture(map, uv).xy * 2.0 - 1.0) * normal_strength;
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 p = world_position;
	// Each projection's uv runs along +axis, and up the image along the second +axis.
	vec2 uv_top = vec2(p.x, -p.z);
	vec2 uv_x = vec2(p.z, -p.y);
	vec2 uv_z = vec2(p.x, -p.y);
	vec3 sides = pow(abs(n), vec3(4.0));
	sides /= sides.x + sides.y + sides.z;

	float sand = COLOR.r;
	float grass = COLOR.g;
	float rock = COLOR.b;

	vec3 albedo = vec3(0.0);
	float roughness = 0.0;
	float occlusion = 0.0;
	vec3 bent = n;
	if (sand > 0.0) {
		vec2 uv = uv_top / sand_tile;
		albedo += texture(sand_albedo, uv).rgb * sand;
		vec2 orm = texture(sand_orm, uv).rg;
		occlusion += orm.r * sand;
		roughness += orm.g * sand;
		vec2 t = tilt(sand_normal, uv);
		bent += vec3(t.x, 0.0, t.y) * sand;
	}
	if (grass > 0.0) {
		vec2 uv = uv_top / grass_tile;
		albedo += texture(grass_albedo, uv).rgb * grass;
		occlusion += grass;
		roughness += grass_roughness * grass;
		vec2 t = tilt(grass_normal, uv);
		bent += vec3(t.x, 0.0, t.y) * grass;
	}
	if (rock > 0.0) {
		vec2 ux = uv_x / rock_tile;
		vec2 uy = uv_top / rock_tile;
		vec2 uz = uv_z / rock_tile;
		vec3 colour = texture(rock_albedo, ux).rgb * sides.x + texture(rock_albedo, uy).rgb * sides.y
				+ texture(rock_albedo, uz).rgb * sides.z;
		vec2 orm = texture(rock_orm, ux).rg * sides.x + texture(rock_orm, uy).rg * sides.y
				+ texture(rock_orm, uz).rg * sides.z;
		vec2 tx = tilt(rock_normal, ux);
		vec2 ty = tilt(rock_normal, uy);
		vec2 tz = tilt(rock_normal, uz);
		vec3 t = vec3(0.0, tx.y, tx.x) * sides.x + vec3(ty.x, 0.0, ty.y) * sides.y + vec3(tz.x, tz.y, 0.0) * sides.z;
		albedo += colour * rock;
		occlusion += orm.r * rock;
		roughness += orm.g * rock;
		bent += t * rock;
	}
	// Each texture's smallest mipmap is its average, so the wobble averages 1.
	float rock_mean = textureLod(rock_albedo, vec2(0.5), 10.0).g;
	float grass_mean = textureLod(grass_albedo, vec2(0.5), 10.0).g;
	float wobble = 0.5 * (texture(rock_albedo, p.xz / 97.0).g / rock_mean + texture(grass_albedo, p.zx / 61.0).g / grass_mean);
	albedo *= mix(1.0, wobble, variation);
	albedo *= mix(vec3(1.0), deep_tint, COLOR.a);

	ALBEDO = albedo;
	ROUGHNESS = roughness;
	AO = occlusion;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(bent), 0.0)).xyz);
}
