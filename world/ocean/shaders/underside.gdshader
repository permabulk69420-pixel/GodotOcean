shader_type spatial;
// The water surface seen from underneath: what main.gd draws while the head is under the water (surface.gdshader is the
// surface seen from above, and its underside part is kept only for the watch's old-versus-new test). From below, the
// engine's lighting adds nothing visible, so the whole colour is worked out here and drawn unshaded; the underwater fog
// still goes on top.
//
// Kept cheap for the headset, where this covers much of the view whenever you look up:
// - The sky through the bright window overhead comes from a small table that window_sky.gd bakes from the same
//   atmospheric scattering whenever the sun moves, instead of evaluating the scattering for every pixel.
// - One ripple lookup instead of two, with plain (not anisotropic) filtering, fading out with distance.
// - Nothing from above the water: no foam, whitecaps, reflections or mirrored glints of the mushroom's cap.
render_mode world_vertex_coords, cull_disabled, depth_draw_opaque, unshaded;
#include "res://world/ocean/shaders/underwater_water.gdshaderinc"

// Shared with surface.gdshader (same names, so switching shaders keeps the values ocean.gd, day_night.gd and mushroom.gd set).
uniform float simulation_time;
uniform sampler2D cached_displacement : filter_nearest;
uniform sampler2D cached_normals : filter_nearest;
uniform bool cache_ready = false;
uniform sampler2D detail_normals : repeat_enable, filter_linear_mipmap;
uniform vec3 absorption = vec3(0.28, 0.065, 0.028);
uniform vec3 deep_color : source_color = vec3(0.008, 0.055, 0.085);
uniform vec3 shallow_color : source_color = vec3(0.025, 0.32, 0.29);
uniform vec3 sky_sun_direction = vec3(0.0, 0.53, 0.85);
uniform vec3 sky_sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float day_amount = 1.0;
// How much of the small ripple detail bends the light (1 = same as from above). Lower values keep the bright window
// overhead smooth and wavy instead of broken into specks.
uniform float underside_detail = 0.3;
// Brightness of the sky seen through the window overhead, and of the sun inside it.
uniform float underside_window_brightness = 1.0;
uniform float underside_sun_glare = 4.0;
// Further away than this (or 1.8 times the viewer's depth, if that is more) the surface is mostly fog and the ripples
// are left out. The window overhead is always nearer than this.
uniform float underside_far_distance = 35.0;
uniform vec3 glow_source = vec3(0.0);
uniform float glow_strength = 0.0;
uniform float glow_radius = 60.0;
uniform vec3 glow_low : source_color = vec3(0.03, 0.80, 0.70);
uniform vec3 glow_high : source_color = vec3(0.45, 0.20, 1.0);
uniform float glow_pulse_speed = 0.10;
uniform float glow_day = 0.30;

// Only for this shader: the baked sky (window_sky.gd).
uniform sampler2D window_sky : filter_linear, repeat_disable;

varying vec3 ocean_position;
varying vec3 ocean_normal;
varying float crest_height;

void vertex() {
	ivec2 cache_pixel = ivec2(VERTEX_ID % 1024, VERTEX_ID / 1024);
	vec3 displacement = cache_ready ? texelFetch(cached_displacement, cache_pixel, 0).xyz : vec3(0.0);
	vec3 wave_normal = cache_ready ? texelFetch(cached_normals, cache_pixel, 0).xyz : vec3(0.0, 1.0, 0.0);
	VERTEX += displacement;
	ocean_position = VERTEX;
	ocean_normal = wave_normal;
	crest_height = displacement.y;
}

void fragment() {
	vec3 eye_vector = CAMERA_POSITION_WORLD - ocean_position;
	float eye_distance = max(length(eye_vector), 0.0001);
	vec3 eye_direction = eye_vector / eye_distance;
	// The colour is drawn as is, so it needs its own brightness drop at night.
	float light_level = mix(0.035, 1.0, day_amount);
	vec3 colour;
	if (FRONT_FACING) {
		// The top of the surface only shows from under the water for a moment while the head crosses it.
		vec3 scatter = mix(shallow_color, deep_color, 1.0 - exp(-200.0 * 0.045));
		colour = scatter * (1.0 - exp(-absorption * 200.0)) * light_level;
	} else {
		vec3 normal = ocean_normal;
		float far_limit = max(underside_far_distance, 1.8 * max(ocean_position.y - CAMERA_POSITION_WORLD.y, 0.0));
		if (eye_distance < far_limit) {
			vec2 p = ocean_position.xz * 0.045 + vec2(simulation_time * 0.005, -simulation_time * 0.003);
			vec2 ripple = texture(detail_normals, p).rg * 2.0 - 1.0;
			float fade = 1.0 - smoothstep(far_limit * 0.75, far_limit, eye_distance);
			normal += vec3(ripple.x, 0.0, ripple.y) * (underside_detail * fade);
		}
		vec3 world_normal = -normalize(normal);
		// Light from the sky only gets through inside a cone overhead (Snell's window, about 49 degrees from straight
		// up); outside it the surface acts as a mirror and shows the water below.
		float window = smoothstep(0.63, 0.75, dot(world_normal, eye_direction));
		// At night the mirrored part keeps the faint teal it always had.
		colour = mix(shallow_color * 0.35 * 0.035, underwater_water_colour(reflect(-eye_direction, world_normal), sky_sun_direction, 1.0, 1.5, 0.0), day_amount);
		if (window > 0.0) {
			vec3 air = refract(-eye_direction, world_normal, 1.333);
			vec3 sky_through = vec3(0.0);
			if (dot(air, air) > 0.000001) {
				float toward_sun = dot(air, sky_sun_direction);
				// Same packing as window_sky.gdshader.
				vec2 cell = sqrt(clamp(vec2(0.5 - 0.5 * toward_sun, (air.y + 0.1) / 1.1), 0.0, 1.0));
				// Sky seen through the water is a little bluer than from above.
				sky_through = texture(window_sky, cell).rgb * vec3(0.78, 0.92, 1.08) * underside_window_brightness;
				// The sun's disc and the glare around it, from one logarithm.
				float closeness = log2(max(toward_sun, 0.000001));
				float sun_up = smoothstep(-0.05, 0.2, sky_sun_direction.y);
				sky_through += sky_sun_color * (sun_up * underside_sun_glare) * (exp2(closeness * 900.0) * 8.0 + exp2(closeness * 60.0) * 0.25);
			}
			colour = mix(colour, sky_through, window);
		}
		colour += shallow_color * max(crest_height, 0.0) * 0.12 * light_level;
		if (glow_strength > 0.0) {
			vec3 to_source = glow_source - ocean_position;
			float spread = length(to_source.xz);
			// Past two and a half radii the pools and the pulse are far below anything visible.
			if (spread < glow_radius * 2.5) {
				// The mushroom's light on the water, as from above: a tight teal pool from the stalk under a wide
				// violet one from the cap, with a slow wave running outward through both.
				float pool = exp(-pow(spread / glow_radius, 2.0));
				float core = exp(-spread / (glow_radius * 0.2));
				float wave = 0.5 + 0.5 * sin(TAU * fract(TIME * glow_pulse_speed) - spread * 0.05);
				vec3 spill = (glow_high * pool * 0.10 + glow_low * core * 0.35) * mix(0.6, 1.0, wave);
				colour += spill * glow_strength * mix(1.0, glow_day, day_amount);
			}
		}
	}
	ALBEDO = colour;
}
