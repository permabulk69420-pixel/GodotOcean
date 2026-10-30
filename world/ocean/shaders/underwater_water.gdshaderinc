// The colour of the water itself when looking in a direction from under the surface: brighter
// towards the surface and the sun, darker blue downwards, darker overall with depth.
// Shared by the underwater sky (which the underwater fog takes its colour from) and the underside
// of the water surface (the mirror-like part outside the bright window overhead).
//
// Godot's fog reads this sky through blurred copies of it (each an average over a wide cone), and
// faraway surfaces read less blurred copies than nearby ones. The gradient is therefore kept
// straight (it changes evenly from bottom to top), because blurring an even gradient leaves eye
// level unchanged: whatever the blur, the far water and the far seabed meet the open water at the
// same colour, with no band at the horizon.
// Colours are linear (not sRGB).

// Looking level, just under the surface (the fog colour you see most).
const vec3 WATER_LEVEL_COLOUR = vec3(0.045, 0.23, 0.28);
// How much brighter looking up / darker looking down. 1.45 is about the most the blur allows.
const vec3 WATER_GRADIENT = vec3(1.45, 1.4, 1.15);
// Haze around the sun's direction.
const vec3 WATER_SUN_GLOW_COLOUR = vec3(0.60, 0.85, 0.70);
const float WATER_SUN_GLOW = 0.16;
// The whole night water: nearly black, matching how the night looked before this sky existed.
const vec3 WATER_NIGHT_COLOUR = vec3(0.0004, 0.0016, 0.0038);
// How quickly each colour fades per metre of depth (red goes first).
const vec3 WATER_DIMMING_PER_METRE = vec3(0.065, 0.042, 0.032);
const float WATER_NIGHT_DIMMING_PER_METRE = 0.04;

// direction: unit view direction. sun: unit direction towards the sun (above the water).
// day: 0 night .. 1 day. depth: metres of the viewer below the surface.
// blurred: 0 for the sky's own lighting copy (which Godot blurs for the fog), 1 for what the fog
// ends up showing (used wherever the sky is drawn directly, so the two match).
vec3 underwater_water_colour(vec3 direction, vec3 sun, float day, float depth, float blurred) {
	float up = clamp(direction.y, -1.0, 1.0);
	// A wide blur shrinks an even gradient to two thirds of its slope.
	float slope = mix(2.0 / 3.0, 4.0 / 9.0, blurred);
	vec3 water = WATER_LEVEL_COLOUR * (1.0 + WATER_GRADIENT * slope * up);
	// Light scattered forward around the sun, which looks steeper from under the water.
	vec3 bent = normalize(vec3(sun.x * 0.75, max(sun.y, 0.05), sun.z * 0.75));
	float facing = dot(direction, bent);
	float glow = mix(max(facing, 0.0), 0.212 + 0.455 * max(facing, 0.0) + 0.212 * min(facing, 0.0), blurred);
	water += WATER_SUN_GLOW_COLOUR * WATER_SUN_GLOW * glow;
	water *= exp(-max(depth, 0.0) * WATER_DIMMING_PER_METRE);
	vec3 night = WATER_NIGHT_COLOUR * exp(-max(depth, 0.0) * WATER_NIGHT_DIMMING_PER_METRE);
	return mix(night, max(water, vec3(0.0)), clamp(day, 0.0, 1.0));
}
