// Shared sunlight under the water, used by every shader that draws something below the surface.
// day_night.gd sets the global values every frame.
//
// Caustics are the moving net of bright lines that waves focus onto the seabed. The pattern is a
// looping animation (world/ocean/caustics.png, made by tools/make_caustics.py) projected down from
// the surface along the sun's direction, so it lands on slopes and walls the way real light would.

global uniform sampler2DArray caustic_frames : filter_linear_mipmap_anisotropic, repeat_enable;
// Direction towards the sun as seen from under the water (bent steeper by the surface).
global uniform vec3 underwater_sun_direction;
// 0 = no caustics (night, sun low), 1 = full strength.
global uniform float underwater_caustics;
global uniform float water_surface_height;

const float CAUSTIC_FRAMES = 32.0;
// Must match RANGE in tools/make_caustics.py: stored value x RANGE = brightness (average 1).
const float CAUSTIC_RANGE = 6.0;
// Metres of surface covered by one repeat of the pattern.
const float CAUSTIC_TILE = 6.5;
// Seconds per animation loop. 3600 (Godot's TIME wrap) divides by it, so the wrap is invisible.
const float CAUSTIC_LOOP = 7.2;
// How fast the pattern fades and softens with depth below the surface.
const float CAUSTIC_FADE_PER_METRE = 0.035;
const float CAUSTIC_BLUR_PER_METRE = 0.05;

// Multiplier for direct sunlight at a world position: about 1 on average, bright lines above 1,
// darker gaps below 1. Exactly 1 above the water or when caustics are off.
float caustic_light(vec3 world_position, float time) {
	float depth = water_surface_height - world_position.y;
	if (depth <= 0.0 || underwater_caustics <= 0.001) {
		return 1.0;
	}
	vec3 sun = underwater_sun_direction;
	// Where the sunlight reaching this point came through the surface.
	vec2 entry = world_position.xz + sun.xz / max(sun.y, 0.3) * depth;
	// A slow drift (a whole number of repeats per hour, so the hourly TIME wrap is seamless).
	vec2 uv = entry / CAUSTIC_TILE + vec2(30.0, 18.0) * (time / 3600.0);
	float frame = fract(time / CAUSTIC_LOOP) * CAUSTIC_FRAMES;
	float first = floor(frame);
	float second = mod(first + 1.0, CAUSTIC_FRAMES);
	float soften = log2(1.0 + depth * CAUSTIC_BLUR_PER_METRE);
	float a = texture(caustic_frames, vec3(uv, first), soften).r;
	float b = texture(caustic_frames, vec3(uv, second), soften).r;
	float pattern = mix(a, b, frame - first) * CAUSTIC_RANGE;
	float strength = underwater_caustics * exp(-depth * CAUSTIC_FADE_PER_METRE);
	return mix(1.0, pattern, strength);
}
