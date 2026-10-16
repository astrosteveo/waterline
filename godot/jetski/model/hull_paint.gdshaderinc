// A hull scene's surface in the rider's colours. JetSkiModel replaces each StandardMaterial3D
// of a hull scene with this shader and copies the material's textures and values into it
// (albedo, roughness, metallic, normal map, ambient occlusion), so the surface looks as the
// model file made it except where it is painted.
//
// Paint goes on the light grey and white parts of the albedo, keeping their shading: dark and
// strongly coloured parts (a black seat, a red light) stay as they are. The colour depends on
// the height in the model's space: bottom_color below bottom_line, trim_color from there up to
// trim_line, hull_color above. hull_paint.gdshader and hull_paint_ghost.gdshader include this.

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Which channel of the texture holds the value: (1, 0, 0, 0) is red, (1/3, 1/3, 1/3, 0) grey.
uniform vec4 roughness_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D metallic_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 metallic_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform bool use_normal_map = false;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale = 1.0;
uniform bool use_ao = false;
uniform sampler2D ao_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 ao_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float ao_light_affect = 0.0;

uniform vec4 hull_color : source_color = vec4(1.0);
uniform vec4 trim_color : source_color = vec4(1.0);
uniform vec4 bottom_color : source_color = vec4(1.0);
// The height of a vertex in the model's space is dot(height_from_vertex, vec4(VERTEX, 1.0)):
// the second row of the mesh's transform relative to the model.
uniform vec4 height_from_vertex = vec4(0.0, 1.0, 0.0, 0.0);
uniform float bottom_line = -1000.0;
uniform float trim_line = -1000.0;
// Linear albedo at least this bright counts as white: painted at full strength.
uniform float white_level = 0.7;

#ifndef GHOST
// How much of the surface to hide, 0 to 1 (JetSkiModel.fade): a dither in the opaque pass,
// so a faded craft can't sort behind the water.
uniform float fade : hint_range(0.0, 1.0) = 0.0;
#endif

#ifdef GHOST
uniform float ghost_alpha = 0.38;
uniform vec4 ghost_glow : source_color = vec4(0.55, 0.8, 1.0, 1.0);
uniform float ghost_glow_energy = 0.35;
#endif

varying float hull_height;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	hull_height = dot(height_from_vertex, vec4(VERTEX, 1.0));
}

void fragment() {
	vec3 base = albedo.rgb * texture(albedo_texture, UV).rgb;
	float high = max(base.r, max(base.g, base.b));
	float low = min(base.r, min(base.g, base.b));
	// Light and nearly grey: paint. The thresholds are in linear colour. A generated model's
	// white is often a little blue (about 0.2 saturation), so that still counts as grey.
	float saturation = (high - low) / max(high, 0.001);
	float paintable = smoothstep(0.25, 0.45, high) * (1.0 - smoothstep(0.3, 0.45, saturation));
	vec3 paint = hull_color.rgb;
	if (hull_height < bottom_line) {
		paint = bottom_color.rgb;
	} else if (hull_height < trim_line) {
		paint = trim_color.rgb;
	}
	float shade = min(dot(base, vec3(0.2126, 0.7152, 0.0722)) / white_level, 1.0);
	ALBEDO = mix(base, paint * shade, paintable);
	ROUGHNESS = roughness * dot(texture(roughness_texture, UV), roughness_channel);
	METALLIC = metallic * dot(texture(metallic_texture, UV), metallic_channel);
	SPECULAR = specular;
	NORMAL_MAP = use_normal_map ? texture(normal_texture, UV).rgb : vec3(0.5, 0.5, 1.0);
	NORMAL_MAP_DEPTH = normal_scale;
	AO = use_ao ? dot(texture(ao_texture, UV), ao_channel) : 1.0;
	AO_LIGHT_AFFECT = use_ao ? ao_light_affect : 0.0;
#ifdef GHOST
	ALPHA = ghost_alpha;
	EMISSION = ghost_glow.rgb * ghost_glow_energy;
#else
	ALPHA = 1.0 - fade;
	ALPHA_HASH_SCALE = 1.0;
#endif
}
