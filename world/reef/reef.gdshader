shader_type spatial;
// Coral, anemone and kelp from the reef kit. Vertex colour: R = glow weight, G = per-piece random,
// B = sway weight. Patches of coral are tinted by area so a reef reads as colour zones, and the
// glow mask lights up at night in each coral's own hue mixed with a bioluminescent teal.
render_mode cull_disabled;

uniform sampler2D albedo_map : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_map : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D glow_map : source_color, hint_default_black, repeat_enable, filter_linear_mipmap_anisotropic;

uniform float tint_strength = 0.55;
uniform float patch_size = 9.0;
uniform float glow_strength = 2.2;
uniform float pulse_speed = 0.13;
uniform float sway_amount = 0.32;
uniform float sway_speed = 0.9;
// 0 at night, 1 in full day.
uniform float day_amount = 0.0;
uniform float day_glow = 0.12;
// By day, coral close to the viewer keeps more of its own colour (reds, oranges, purples) instead
// of taking on the blue of the water; the effect fades out over near_colour_distance metres.
uniform vec3 near_colour_boost = vec3(1.75, 1.15, 0.95);
uniform float near_colour_distance = 9.0;

varying vec3 world_pos;
varying vec3 vcolour;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 patch_tint(float h) {
	if (h < 0.2) return vec3(1.0, 0.72, 0.52);
	if (h < 0.4) return vec3(1.0, 0.58, 0.78);
	if (h < 0.6) return vec3(0.82, 0.64, 1.0);
	if (h < 0.8) return vec3(1.0, 0.96, 0.58);
	return vec3(0.58, 1.0, 0.9);
}

void vertex() {
	vcolour = COLOR.rgb;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float weight = COLOR.b * COLOR.b;
	if (weight > 0.0) {
		float phase = dot(world_pos.xz, vec2(0.31, 0.23)) + COLOR.g * 6.283;
		float wave = sin(TIME * sway_speed + phase) + 0.4 * sin(TIME * sway_speed * 2.3 + phase * 1.7);
		VERTEX += inverse(mat3(MODEL_MATRIX)) * (vec3(wave * 0.6 + 0.5, 0.0, wave * 0.4 + 0.3) * sway_amount * weight);
	}
}

void fragment() {
	vec3 base = texture(albedo_map, UV).rgb;
	// Kelp (high sway weight) keeps its own green; coral gets the patch tint.
	float tintable = tint_strength * (1.0 - smoothstep(0.1, 0.45, vcolour.b));
	vec3 tint = mix(vec3(1.0), patch_tint(hash21(floor(world_pos.xz / patch_size))), tintable);
	vec3 albedo = base * tint;
	float closeness = 1.0 - smoothstep(1.5, near_colour_distance, length(world_pos - CAMERA_POSITION_WORLD));
	ALBEDO = min(albedo * mix(vec3(1.0), near_colour_boost, closeness * day_amount), vec3(0.95));
	vec4 orm = texture(orm_map, UV);
	AO = orm.r;
	ROUGHNESS = orm.g;
	METALLIC = 0.0;
	SPECULAR = 0.35;

	NORMAL_MAP = vec3(texture(normal_map, UV).xy, 0.5);
	NORMAL_MAP.z = 0.5 + 0.5 * sqrt(max(1.0 - dot(NORMAL_MAP.xy * 2.0 - 1.0, NORMAL_MAP.xy * 2.0 - 1.0), 0.0));

	float mask = texture(glow_map, UV).r;
	float m = max(albedo.r, max(albedo.g, albedo.b));
	vec3 hue = albedo / max(m, 0.001);
	// At night the glow leans towards bioluminescent teal; by day it is just the coral's own colour.
	vec3 glow_colour = mix(hue, vec3(0.15, 0.85, 1.0), 0.35 * (1.0 - day_amount));
	float wave2 = 0.5 + 0.5 * sin(TIME * pulse_speed * TAU - (vcolour.g * 3.0 + hash21(floor(world_pos.xz * 0.7)) * 4.0));
	float pulse = mix(0.55, 1.0, wave2);
	float brightness = mix(1.0, day_glow, day_amount);
	EMISSION = glow_colour * mask * mix(0.5, 1.0, vcolour.r) * pulse * glow_strength * brightness;
}

// Full-precision replacement for the built-in light maths (see the water shader): the headset
// runs the built-in version in half precision, where viewing an unlit side along the light
// direction can give NaN and a black square.
void light() {
	float n_dot_l = dot(NORMAL, LIGHT);
	vec3 half_sum = LIGHT + VIEW;
	float half_length = length(half_sum);
	if (n_dot_l > 0.0 && half_length > 0.001) {
		vec3 half_vector = half_sum / half_length;
		float c_n_dot_l = min(n_dot_l, 1.0);
		float c_n_dot_v = clamp(dot(NORMAL, VIEW), 0.0001, 1.0);
		float c_n_dot_h = clamp(dot(NORMAL, half_vector), 0.0, 1.0);
		float c_l_dot_h = clamp(dot(LIGHT, half_vector), 0.0, 1.0);
		float fd90_minus_1 = 2.0 * c_l_dot_h * c_l_dot_h * ROUGHNESS - 0.5;
		float fd_v = 1.0 + fd90_minus_1 * pow(1.0 - c_n_dot_v, 5.0);
		float fd_l = 1.0 + fd90_minus_1 * pow(1.0 - c_n_dot_l, 5.0);
		DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (fd_v * fd_l * c_n_dot_l / PI);
		float alpha = max(ROUGHNESS * ROUGHNESS, 0.002);
		float a = c_n_dot_h * alpha;
		float k = alpha / (1.0 - c_n_dot_h * c_n_dot_h + a * a);
		float d = k * k / PI;
		float g = 0.5 / mix(2.0 * c_n_dot_l * c_n_dot_v, c_n_dot_l + c_n_dot_v, alpha);
		vec3 f0 = vec3(0.16 * 0.35 * 0.35);
		float f90 = clamp(dot(f0, vec3(50.0 * 0.33)), 0.0, 1.0);
		vec3 fresnel_term = f0 + (f90 - f0) * pow(1.0 - c_l_dot_h, 5.0);
		SPECULAR_LIGHT += min(c_n_dot_l * d * g * fresnel_term * LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT, vec3(2000.0));
	}
}
