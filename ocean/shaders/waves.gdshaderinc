const int WAVE_COUNT = 64;
uniform vec4 wave_data[64];
uniform vec2 phase_data[64];
uniform float horizontal_scale;
uniform float simulation_time;
uniform float sea_level;

void ocean_sample(vec2 position, out vec3 displacement, out vec3 normal, out float compression) {
	displacement = vec3(0.0);
	vec3 tangent_x = vec3(1.0, 0.0, 0.0);
	vec3 tangent_z = vec3(0.0, 0.0, 1.0);
	for (int i = 0; i < WAVE_COUNT; i++) {
		vec4 w = wave_data[i];
		float phase = w.w * dot(w.xy, position) - phase_data[i].x * simulation_time + phase_data[i].y;
		float s = sin(phase); float c = cos(phase);
		displacement += vec3(horizontal_scale * w.z * c * w.x, w.z * s, horizontal_scale * w.z * c * w.y);
		float slope = w.z * w.w;
		tangent_x += vec3(-horizontal_scale * slope * w.x * w.x * s, slope * w.x * c, -horizontal_scale * slope * w.x * w.y * s);
		tangent_z += vec3(-horizontal_scale * slope * w.x * w.y * s, slope * w.y * c, -horizontal_scale * slope * w.y * w.y * s);
	}
	normal = normalize(cross(tangent_z, tangent_x));
	compression = 1.0 - (tangent_x.x * tangent_z.z - tangent_x.z * tangent_z.x);
}
