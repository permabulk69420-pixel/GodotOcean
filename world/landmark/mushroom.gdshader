shader_type spatial;
// Giant landmark mushroom. The model supplies the textures and two vertex colours:
// COLOR.r = glow weight, COLOR.g = pulse phase. All glow colour and animation is here.
render_mode cull_back;

uniform sampler2D albedo_map : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_map : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D glow_map : source_color, hint_default_black, repeat_enable, filter_linear_mipmap_anisotropic;

uniform vec3 glow_low : source_color = vec3(0.03, 0.80, 0.70);
uniform vec3 glow_high : source_color = vec3(0.45, 0.20, 1.0);
uniform float glow_strength = 2.4;
uniform float pulse_speed = 0.10;
uniform float height_low = 6.0;
uniform float height_high = 88.0;
// 0 at night, 1 in full day: the glow is dimmed (never removed) while the sun is up.
uniform float day_amount = 0.0;
uniform float day_glow = 0.30;

varying float glow_weight;
varying float phase;
varying float height;

void vertex() {
	glow_weight = COLOR.r;
	phase = COLOR.g;
	height = VERTEX.y;
}

void fragment() {
	ALBEDO = texture(albedo_map, UV).rgb;
	vec4 orm = texture(orm_map, UV);
	AO = orm.r;
	ROUGHNESS = orm.g;
	METALLIC = 0.0;
	SPECULAR = 0.5;
	NORMAL_MAP = texture(normal_map, UV).xyz;

	float mask = texture(glow_map, UV).r;
	vec3 colour = mix(glow_low, glow_high, smoothstep(height_low, height_high, height));
	// A slow wave travels along the painted phase, so the glow flows instead of blinking.
	float wave = 0.5 + 0.5 * sin(TIME * pulse_speed * TAU - phase * TAU * 1.5);
	float pulse = mix(0.6, 1.0, wave);
	float brightness = mix(1.0, day_glow, day_amount);
	EMISSION = colour * mask * mix(0.55, 1.0, glow_weight) * pulse * glow_strength * brightness;
}

// Same full-precision replacement for Godot's built-in light maths as the water uses: the
// headset evaluates the built-in version in half precision, where looking along the light
// direction at an unlit side can produce NaN and a black square.
void light() {
	float n_dot_l = dot(NORMAL, LIGHT);
	vec3 half_sum = LIGHT + VIEW;
	float half_length = length(half_sum);
	if (n_dot_l > 0.0 && half_length > 0.001) {
		vec3 half_vector = half_sum / half_length;
		float c_n_dot_l = min(n_dot_l, 1.0);
		float c_n_dot_v = max(dot(NORMAL, VIEW), 0.0001);
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
		vec3 f0 = vec3(0.16 * 0.5 * 0.5);
		float f90 = clamp(dot(f0, vec3(50.0 * 0.33)), 0.0, 1.0);
		vec3 fresnel_term = f0 + (f90 - f0) * pow(1.0 - c_l_dot_h, 5.0);
		SPECULAR_LIGHT += min(c_n_dot_l * d * g * fresnel_term * LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT, vec3(2000.0));
	}
}
