shader_type canvas_item;
render_mode unshaded, blend_disabled;
// The wave cache for the Compatibility (OpenGL) renderer, which has no compute shaders: the same maths as
// wave_cache.glsl, drawn into a float texture instead (see wave_cache_gl.gd). One pixel per surface vertex, 1024 a row.
// The top `rows` rows hold the displacement, the next `rows` the normal and how squeezed the surface is there.
uniform sampler2D points : filter_nearest;
uniform vec4 waves[128];
// Surface x and z, time, vertex count.
uniform vec4 parameters;
uniform int rows;

void fragment() {
	ivec2 pixel = ivec2(UV * vec2(1024.0, float(rows * 2)));
	bool normal_half = pixel.y >= rows;
	ivec2 source = ivec2(pixel.x, normal_half ? pixel.y - rows : pixel.y);
	vec2 point = texelFetch(points, source, 0).xy;
	vec2 position = point + parameters.xy;
	float spacing = max(0.25, max(abs(point.x), abs(point.y)) / 64.0);
	vec3 d = vec3(0.0), tx = vec3(1.0, 0.0, 0.0), tz = vec3(0.0, 0.0, 1.0);
	for (int i = 0; i < 64; i++) {
		vec4 w = waves[i * 2]; vec4 p = waves[i * 2 + 1];
		// Remove frequencies the distant mesh cannot represent, avoiding spatial aliasing.
		float weight = 1.0 - smoothstep(1.5707963, 3.1415926, w.w * spacing);
		if (weight < 0.0001) continue;
		w.z *= weight;
		float phase = w.w * dot(w.xy, position) - p.x * parameters.z + p.y;
		float s = sin(phase), c = cos(phase), h = p.z;
		d += vec3(h * w.z * c * w.x, w.z * s, h * w.z * c * w.y);
		float slope = w.z * w.w;
		tx += vec3(-h * slope * w.x * w.x * s, slope * w.x * c, -h * slope * w.x * w.y * s);
		tz += vec3(-h * slope * w.x * w.y * s, slope * w.y * c, -h * slope * w.y * w.y * s);
	}
	COLOR = normal_half ? vec4(normalize(cross(tz, tx)), 1.0 - (tx.x * tz.z - tx.z * tz.x)) : vec4(d, 1.0);
}
