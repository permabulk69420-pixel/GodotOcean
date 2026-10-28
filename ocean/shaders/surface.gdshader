shader_type spatial;
render_mode world_vertex_coords, cull_disabled, depth_draw_opaque;
uniform float simulation_time;
uniform sampler2D cached_displacement : filter_nearest;
uniform sampler2D cached_normals : filter_nearest;
uniform bool cache_ready = false;
#include "res://ocean/shaders/sky_radiance.gdshaderinc"

uniform sampler2D detail_normals : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D detail_texture : repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec3 absorption = vec3(0.28, 0.065, 0.028);
uniform vec3 deep_color : source_color = vec3(0.008, 0.055, 0.085);
uniform vec3 shallow_color : source_color = vec3(0.025, 0.32, 0.29);
uniform vec3 foam_color : source_color = vec3(0.92, 0.98, 0.96);
varying vec3 ocean_position;
varying vec3 ocean_normal;
varying float wave_compression;
varying float crest_height;

void vertex() {
	ivec2 cache_pixel = ivec2(VERTEX_ID % 1024, VERTEX_ID / 1024);
	vec3 displacement = cache_ready ? texelFetch(cached_displacement, cache_pixel, 0).xyz : vec3(0.0);
	vec4 cached = cache_ready ? texelFetch(cached_normals, cache_pixel, 0) : vec4(0.0, 1.0, 0.0, 0.0);
	vec3 wave_normal = cached.xyz; float compression = cached.w;
	VERTEX += displacement;
	ocean_position = VERTEX;
	ocean_normal = wave_normal;
	wave_compression = compression;
	crest_height = displacement.y;
	NORMAL = wave_normal;
}

void fragment() {
	vec2 uv = ocean_position.xz;
	float t = simulation_time;
	vec2 texel = vec2(1.0 / 1024.0);
	vec2 p = uv * 0.045 + vec2(t * 0.005, -t * 0.003);
	vec2 q = uv * 0.31 + vec2(-t * 0.012, t * 0.008);
	float n = texture(detail_texture, p).r;
	float small = texture(detail_texture, q).r;
	vec2 gradient=texture(detail_normals,p).rg*2.0-1.0;
	vec2 fine=texture(detail_normals,q).rg*2.0-1.0;
	vec3 world_normal=normalize(ocean_normal+vec3(gradient.x+fine.x*0.2727,0.0,gradient.y+fine.y*0.2727));
	vec3 eye_direction = normalize(CAMERA_POSITION_WORLD - ocean_position);
	vec3 view_normal = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	float thickness = 200.0;
	vec3 transmission = exp(-absorption * min(thickness, 200.0));
	float facing = clamp(dot(world_normal, eye_direction), 0.0, 1.0);
	float fresnel = 0.02037 + 0.97963 * pow(1.0 - facing, 5.0);
	float whitecap = smoothstep(0.10, 0.42, wave_compression) * smoothstep(0.40, 0.77, n + small * 0.22);
	float foam = clamp(whitecap, 0.0, 1.0);
	vec3 scatter = mix(shallow_color, deep_color, 1.0 - exp(-thickness * 0.045));
	vec3 transmitted = scatter * (1.0 - transmission);
	if (!FRONT_FACING) {
		world_normal = -world_normal;
		float internal = 1.0 - smoothstep(0.61, 0.69, dot(world_normal, eye_direction));
		vec3 ray=refract(-eye_direction,world_normal,1.333);
		vec3 sky=length(ray)>0.0 ? refracted_sky(normalize(ray)) : shallow_color*0.35;
		transmitted = mix(sky, shallow_color * 0.35, internal);
		fresnel = 0.0;
		foam *= 0.25;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	ALBEDO = mix(scatter * 0.10, foam_color, foam);
	EMISSION = transmitted * (1.0 - fresnel) * (1.0 - foam);
	EMISSION += shallow_color * max(crest_height, 0.0) * pow(1.0 - facing, 3.0) * 0.12;
	ROUGHNESS = mix(0.055 + (1.0 - facing) * 0.025, 0.65, foam);
	SPECULAR = 0.25;
	METALLIC = 0.0;
}
