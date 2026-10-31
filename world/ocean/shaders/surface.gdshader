shader_type spatial;
render_mode world_vertex_coords, cull_disabled, depth_draw_opaque;
uniform float simulation_time;
uniform sampler2D cached_displacement : filter_nearest;
uniform sampler2D cached_normals : filter_nearest;
uniform bool cache_ready = false;
#include "res://world/ocean/shaders/sky_radiance.gdshaderinc"
#include "res://world/ocean/shaders/underwater_water.gdshaderinc"
// Seen from below, how much of the small ripple detail bends the light (1 = same as from above).
// Lower values keep the bright window overhead smooth and wavy instead of broken into specks.
uniform float underside_detail = 0.3;
// Brightness of the sky seen through the window overhead, and of the sun inside it.
uniform float underside_window_brightness = 1.0;
uniform float underside_sun_glare = 4.0;

uniform sampler2D detail_normals : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D detail_texture : repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec3 absorption = vec3(0.28, 0.065, 0.028);
uniform vec3 deep_color : source_color = vec3(0.008, 0.055, 0.085);
uniform vec3 shallow_color : source_color = vec3(0.025, 0.32, 0.29);
uniform vec3 foam_color : source_color = vec3(0.92, 0.98, 0.96);
// Light from the giant mushroom spilling onto the water around it. mushroom.gd sets the
// source (the glowing cap); the colours and pulse speed match mushroom.gdshader.
// glow_strength = 0 switches it off.
uniform vec3 glow_source = vec3(0.0);
uniform float glow_strength = 0.0;
uniform float glow_radius = 60.0;
uniform vec3 glow_low : source_color = vec3(0.03, 0.80, 0.70);
uniform vec3 glow_high : source_color = vec3(0.45, 0.20, 1.0);
uniform float glow_pulse_speed = 0.10;
uniform float glow_day = 0.30;
varying vec3 ocean_position;
varying vec3 ocean_normal;
varying float wave_compression;
varying float crest_height;

void vertex() {
	ivec2 cache_pixel = ivec2(VERTEX_ID % 1024, VERTEX_ID / 1024);
	vec3 displacement = cache_ready ? texelFetch(cached_displacement, cache_pixel, 0).xyz : vec3(0.0);
	vec4 cached = cache_ready ? texelFetch(cached_normals, cache_pixel, 0) : vec4(0.0, 1.0, 0.0, 0.0);
	vec3 wave_normal = cached.xyz; float compression = cached.w;
	VERTEX += displacement;
	ocean_position = VERTEX;
	ocean_normal = wave_normal;
	wave_compression = compression;
	crest_height = displacement.y;
	NORMAL = wave_normal;
}

void fragment() {
	vec2 uv = ocean_position.xz;
	float t = simulation_time;
	vec2 texel = vec2(1.0 / 1024.0);
	vec2 p = uv * 0.045 + vec2(t * 0.005, -t * 0.003);
	vec2 q = uv * 0.31 + vec2(-t * 0.012, t * 0.008);
	float n = texture(detail_texture, p).r;
	float small = texture(detail_texture, q).r;
	vec2 gradient=texture(detail_normals,p).rg*2.0-1.0;
	vec2 fine=texture(detail_normals,q).rg*2.0-1.0;
	vec3 world_normal=normalize(ocean_normal+vec3(gradient.x+fine.x*0.2727,0.0,gradient.y+fine.y*0.2727));
	vec3 eye_direction = normalize(CAMERA_POSITION_WORLD - ocean_position);
	if (FRONT_FACING) {
		// Detail normals can tilt the mirror direction under the horizon, where the sky
		// radiance is the near-black ground colour. Lift such reflections back above it.
		vec3 mirror = reflect(-eye_direction, world_normal);
		float below = smoothstep(0.12, -0.04, mirror.y);
		vec3 lifted = normalize(eye_direction + vec3(mirror.x, max(mirror.y, 0.0) + 0.03, mirror.z));
		world_normal = normalize(mix(world_normal, lifted, below));
	}
	vec3 view_normal = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	float thickness = 200.0;
	vec3 transmission = exp(-absorption * min(thickness, 200.0));
	float facing = clamp(dot(world_normal, eye_direction), 0.0, 1.0);
	float fresnel = 0.02037 + 0.97963 * pow(1.0 - facing, 5.0);
	float whitecap = smoothstep(0.10, 0.42, wave_compression) * smoothstep(0.40, 0.77, n + small * 0.22);
	float foam = clamp(whitecap, 0.0, 1.0);
	vec3 scatter = mix(shallow_color, deep_color, 1.0 - exp(-thickness * 0.045));
	// Water colour is emissive, so it needs its own brightness drop at night.
	float light_level = mix(0.035, 1.0, day_amount);
	vec3 transmitted = scatter * (1.0 - transmission) * light_level;
	if (!FRONT_FACING) {
		// Seen from below. Light from the sky only gets through inside a cone overhead (Snell's
		// window, about 49 degrees from straight up); outside it the surface acts as a mirror and
		// shows the water below. A smoother normal keeps the window's edge wavy and clean.
		vec3 detail = vec3(gradient.x + fine.x * 0.2727, 0.0, gradient.y + fine.y * 0.2727) * underside_detail;
		world_normal = -normalize(ocean_normal + detail);
		float cos_view = clamp(dot(world_normal, eye_direction), 0.0, 1.0);
		float window = smoothstep(0.63, 0.75, cos_view);
		vec3 ray = refract(-eye_direction, world_normal, 1.333);
		vec3 sky_through = vec3(0.0);
		if (dot(ray, ray) > 0.000001) {
			vec3 air = normalize(ray);
			float toward_sun = clamp(dot(air, normalize(sky_sun_direction)), 0.0, 1.0);
			float sun_up = smoothstep(-0.05, 0.2, sky_sun_direction.y);
			// Sky seen through the water is a little bluer than from above.
			sky_through = refracted_sky(air) * vec3(0.78, 0.92, 1.08) * underside_window_brightness
				+ sky_sun_color * sun_up * underside_sun_glare * (pow(toward_sun, 900.0) * 8.0 + pow(toward_sun, 60.0) * 0.25);
		}
		// At night the mirrored part keeps the faint teal it always had.
		vec3 mirrored = mix(shallow_color * 0.35 * 0.035, underwater_water_colour(reflect(-eye_direction, world_normal), sky_sun_direction, 1.0, 1.5, 0.0), day_amount);
		transmitted = mix(mirrored, sky_through, window);
		fresnel = 0.0;
		foam *= 0.08;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	ALBEDO = mix(scatter * 0.10, foam_color, foam);
	EMISSION = transmitted * (1.0 - fresnel) * (1.0 - foam);
	EMISSION += shallow_color * max(crest_height, 0.0) * pow(1.0 - facing, 3.0) * 0.12 * light_level;
	if (glow_strength > 0.0) {
		vec3 to_source = glow_source - ocean_position;
		float spread = length(to_source.xz);
		// A tight teal pool from the stalk under a wide violet one from the cap. A slow wave
		// runs outward through both, so the water pulses with the mushroom. fract() keeps the
		// time small enough for the headset's precision.
		float pool = exp(-pow(spread / glow_radius, 2.0));
		float core = exp(-spread / (glow_radius * 0.2));
		float wave = 0.5 + 0.5 * sin(TAU * fract(TIME * glow_pulse_speed) - spread * 0.05);
		vec3 spill = (glow_high * pool * 0.10 + glow_low * core * 0.35) * mix(0.6, 1.0, wave);
		if (FRONT_FACING) {
			// The cap mirrored in the wave facets: glints that stretch out toward the mushroom.
			vec3 mirror = reflect(-eye_direction, world_normal);
			float glints = pow(max(dot(mirror, normalize(to_source)), 0.0), 160.0);
			spill += glow_high * glints * exp(-spread / (glow_radius * 2.5)) * 3.0;
		}
		// Dimmed, never removed, while the sun is up, like the mushroom itself.
		EMISSION += spill * glow_strength * mix(1.0, glow_day, day_amount) * (1.0 - foam);
	}
	ROUGHNESS = mix(0.055 + (1.0 - facing) * 0.025, 0.65, foam);
	SPECULAR = 0.25;
	METALLIC = 0.0;
}

// Godot's Mobile renderer runs its built-in light maths in half precision on the Quest.
// Looking up at the sun from underwater makes VIEW + LIGHT vanish, so its normalize()
// returns NaN and blanks a small square, even though the underside receives no direct
// light. This reproduces the default Burley diffuse + GGX specular in full precision and
// skips surfaces turned away from the light.
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

		float alpha = ROUGHNESS * ROUGHNESS;
		float a = c_n_dot_h * alpha;
		float k = alpha / (1.0 - c_n_dot_h * c_n_dot_h + a * a);
		float d = k * k / PI;
		float g = 0.5 / mix(2.0 * c_n_dot_l * c_n_dot_v, c_n_dot_l + c_n_dot_v, alpha);
		// Same dielectric reflectance as the SPECULAR = 0.25 set in fragment().
		vec3 f0 = vec3(0.16 * 0.25 * 0.25);
		float f90 = clamp(dot(f0, vec3(50.0 * 0.33)), 0.0, 1.0);
		vec3 fresnel_term = f0 + (f90 - f0) * pow(1.0 - c_l_dot_h, 5.0);
		// The result is converted back to half precision; keep it far below its 65504 limit.
		SPECULAR_LIGHT += min(c_n_dot_l * d * g * fresnel_term * LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT, vec3(2000.0));
	}
}
