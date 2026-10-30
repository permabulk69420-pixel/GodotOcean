shader_type spatial;
// Glowing plankton. Every speck is computed from its instance number, so nothing is stored per
// particle: they drift in a cube that wraps around the camera and flare up near recent
// positions of the hands, thrusters and head (the trail array).
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled, skip_vertex_transform;

const int TRAIL_COUNT = 64;
uniform vec3 centre = vec3(0.0);
uniform float volume_size = 16.0;
uniform float now = 0.0;
uniform float day_amount = 0.0;
uniform vec3 current = vec3(0.10, 0.0, 0.06);
uniform vec3 colour_a : source_color = vec3(0.03, 0.25, 1.0);
uniform vec3 colour_b : source_color = vec3(0.12, 0.85, 1.0);
uniform float base_glow = 1.5;
uniform float visibility_range = 12.0;
uniform vec4 trail[TRAIL_COUNT];
uniform float trail_power[TRAIL_COUNT];

varying vec3 tint;
varying float brightness;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	float id = float(INSTANCE_ID);
	vec3 seed = vec3(hash(id), hash(id + 17.17), hash(id + 31.31));
	vec3 base = seed * volume_size;
	vec3 sway = vec3(sin(now * 0.31 + seed.x * 6.283), sin(now * 0.23 + seed.y * 6.283) * 0.6, cos(now * 0.27 + seed.z * 6.283)) * 0.7;
	vec3 point = base + current * now + sway;
	vec3 rel = mod(point - centre + volume_size * 0.5, volume_size) - volume_size * 0.5;
	vec3 world = centre + rel;
	float edge = 1.0 - smoothstep(0.34, 0.5, max(max(abs(rel.x), abs(rel.y)), abs(rel.z)) / volume_size);
	float dist = length(rel);
	float range = 1.0 - smoothstep(0.35 * visibility_range, visibility_range, dist);

	// Slow twinkle, different for every speck.
	float twinkle = 0.45 + 0.55 * sin(now * (0.6 + seed.x * 1.8) + seed.y * 40.0);
	float idle = base_glow * (0.25 + 0.75 * twinkle) * (0.3 + 0.7 * seed.z);

	// Bright flare where something moved through recently, fading over a few seconds.
	float flare = 0.0;
	for (int i = 0; i < TRAIL_COUNT; i++) {
		float age = now - trail[i].w;
		if (age >= 0.0 && age < 7.0) {
			float radius = 1.2 + trail_power[i] * 2.0;
			float d = distance(world, trail[i].xyz);
			flare += (1.0 - smoothstep(0.0, radius, d)) * trail_power[i] * exp(-age * 0.75);
		}
	}
	flare = min(flare, 3.0);

	float daylight_scale = mix(1.0, 0.04, day_amount);
	brightness = (idle * daylight_scale + flare * 1.8) * edge * range;
	float warm = clamp(step(0.85, seed.y) * 0.7 + flare * 0.35, 0.0, 1.0);
	tint = mix(colour_a, colour_b, warm);
	// Keep every speck a small, steady glint on screen: close ones are capped, far ones are
	// not allowed to shrink below a few pixels (which would flicker).
	float size = (0.014 + 0.02 * seed.z) * (1.0 + flare * 0.15);
	// A few rarer, slightly larger specks give the field some depth.
	size *= 1.0 + 1.2 * step(0.965, seed.x);
	size = clamp(size, dist * 0.0045, dist * 0.0095);
	brightness *= smoothstep(0.25, 0.9, dist);
	if (brightness < 0.004) {
		size = 0.0;
	}
	vec3 view_centre = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	VERTEX = view_centre + vec3(VERTEX.xy * size, 0.0);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r2 = dot(c, c);
	// A tight bright core with a faint halo reads as a point of light.
	float core = exp(-r2 * 9.0) + 0.18 * exp(-r2 * 2.5);
	ALBEDO = mix(tint, vec3(1.0), 0.25 * exp(-r2 * 14.0)) * brightness;
	ALPHA = clamp(core, 0.0, 1.0) * (1.0 - smoothstep(0.7, 1.0, r2));
}
