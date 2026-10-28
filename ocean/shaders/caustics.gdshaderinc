vec2 caustic_hash(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}
float caustic_cell(vec2 p, float t) {
	vec2 cell = floor(p); vec2 local = fract(p);
	float first = 10.0; float second = 10.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 random = caustic_hash(cell + neighbor);
			vec2 point = neighbor + 0.5 + 0.38 * sin(t + 6.283185 * random) - local;
			float d = dot(point, point);
			if (d < first) { second = first; first = d; } else { second = min(second, d); }
		}
	}
	return pow(1.0 - clamp((sqrt(second) - sqrt(first)) * 3.6, 0.0, 1.0), 5.0);
}
float ocean_caustics(vec3 world_position, float time) {
	vec2 p = world_position.xz + vec2(0.35, 0.20) * max(0.0, -world_position.y);
	float pattern = min(caustic_cell(p * 0.48 + vec2(time * 0.1, -time * 0.06), time * 0.65),
		caustic_cell(p * 0.63 + vec2(-time * 0.07, time * 0.05), time * 0.83));
	return pattern * exp(min(world_position.y, 0.0) * 0.055);
}
