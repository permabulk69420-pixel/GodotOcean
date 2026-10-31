shader_type spatial;
// Seagrass blades. Vertex colour R = height along the blade (sway weight), G = per-blade random.
// Blades are two-sided and thin, so light passes through them (translucency) and there is no
// specular term at all, which avoids the half-precision light bug the other shaders work around.
render_mode cull_disabled, depth_draw_opaque;

uniform vec3 base_colour : source_color = vec3(0.04, 0.16, 0.08);
uniform vec3 tip_colour : source_color = vec3(0.34, 0.62, 0.20);
uniform float sway_amount = 0.30;
uniform float sway_speed = 1.0;
uniform vec3 current = vec3(0.6, 0.0, 0.35);

varying float height_t;
varying float blade;

void vertex() {
	height_t = COLOR.r;
	blade = COLOR.g;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = dot(world.xz, vec2(0.37, 0.29)) + blade * 6.283;
	float wave = sin(TIME * sway_speed + phase) + 0.4 * sin(TIME * sway_speed * 2.3 + phase * 1.7);
	float weight = height_t * height_t;
	vec3 push = vec3(wave * 0.7 + current.x, 0.0, wave * 0.5 + current.z) * sway_amount * weight;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * push;
}

void fragment() {
	float t = smoothstep(0.0, 1.0, height_t);
	ALBEDO = mix(base_colour, tip_colour, t) * mix(0.8, 1.25, blade);
	ROUGHNESS = 0.6;
	SPECULAR = 0.0;
}

void light() {
	float n_dot_l = dot(NORMAL, LIGHT);
	// Front lighting plus a softer transmitted share from behind.
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (max(n_dot_l, 0.0) + 0.4 * max(-n_dot_l, 0.0)) / PI;
}
