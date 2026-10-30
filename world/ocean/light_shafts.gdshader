shader_type spatial;
// Sunbeams under the water: long, soft, faint strips of light that slant down from the surface
// along the sun's direction, fade in and out, and drift. Every beam is placed from its instance
// number around the camera (like the plankton), so nothing is stored or updated per beam.
// They only add light, never write depth, and fade out near the camera, far away and towards
// their bottom end, so they stay cheap and never cut sharply into the seabed.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled, skip_vertex_transform, shadows_disabled;
#include "res://world/ocean/shaders/underwater_light.gdshaderinc"

uniform vec3 centre = vec3(0.0);
// Side of the square around the camera that the beams are spread over (metres).
uniform float spread = 44.0;
// Length of a beam from the surface down (metres along the beam).
uniform float beam_length = 22.0;
uniform vec2 width_range = vec2(0.5, 2.6);
uniform vec3 colour : source_color = vec3(0.80, 0.97, 0.92);
uniform float brightness = 0.10;
// Seconds for one beam to fade in and out before it reappears somewhere else.
uniform float lifetime = 9.0;

varying vec2 beam_uv;
varying float strength;
varying float camera_distance;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	float id = float(INSTANCE_ID);
	// Each beam lives for a while, then comes back somewhere new.
	float offset = hash(id + 3.7);
	float life = TIME / lifetime + offset;
	float cycle = floor(life);
	float age = life - cycle;
	float seed = id * 7.13 + cycle * 1.37;
	vec2 spot = vec2(hash(seed), hash(seed + 11.3)) * spread;
	// Beams wrap around the camera at the camera's own depth, so the part beside the viewer is near.
	vec2 rel = mod(spot - centre.xz + spread * 0.5, spread) - spread * 0.5;
	vec3 down = -normalize(underwater_sun_direction);
	float to_surface = (water_surface_height - centre.y) / max(-down.y, 0.2);
	vec3 top = vec3(centre.x + rel.x, centre.y, centre.z + rel.y) - down * max(to_surface, 0.0);
	float width = mix(width_range.x, width_range.y, hash(seed + 5.1));
	float along = 0.5 - VERTEX.y;
	vec3 middle = top + down * along * beam_length;
	vec3 to_camera = CAMERA_POSITION_WORLD - middle;
	vec3 across = normalize(cross(down, to_camera) + vec3(1e-4, 0.0, 0.0));
	vec3 world = middle + across * VERTEX.x * width;
	beam_uv = vec2(VERTEX.x * 2.0, along);
	camera_distance = length(CAMERA_POSITION_WORLD - world);
	float edge = 1.0 - smoothstep(0.3, 0.5, max(abs(rel.x), abs(rel.y)) / spread);
	float fade = sin(age * PI);
	strength = brightness * edge * fade * fade * mix(0.4, 1.0, hash(seed + 2.9)) * underwater_caustics;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float across = 1.0 - beam_uv.x * beam_uv.x;
	float profile = across * across;
	float ends = smoothstep(0.0, 0.08, beam_uv.y) * (1.0 - smoothstep(0.35, 1.0, beam_uv.y));
	float near = smoothstep(1.5, 6.0, camera_distance);
	float far = exp(-camera_distance * 0.04);
	ALBEDO = colour;
	ALPHA = clamp(strength * profile * ends * near * far, 0.0, 1.0);
}
