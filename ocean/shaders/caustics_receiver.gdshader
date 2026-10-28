shader_type spatial;
render_mode world_vertex_coords;
#include "res://ocean/shaders/caustics.gdshaderinc"
uniform vec3 tint : source_color = vec3(0.70, 0.63, 0.42);
varying vec3 world_position;
varying vec3 world_normal;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f*f*(3.0-2.0*f);
	return mix(mix(hash(i), hash(i+vec2(1,0)), u.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), u.x), u.y);
}
void vertex() { world_position = VERTEX; world_normal = NORMAL; }
void fragment() {
	vec2 p = world_position.xz;
	float patches = noise(p * 0.14) * 0.6 + noise(p * 0.75) * 0.4;
	ALBEDO = tint * mix(0.75, 1.1, patches) * COLOR.rgb;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(world_normal), 0.0)).xyz);
	ROUGHNESS = 0.86;
	EMISSION = ALBEDO * vec3(0.35, 0.9, 1.0) * ocean_caustics(world_position, TIME) * 1.65 * max(0.0, normalize(world_normal).y);
}
