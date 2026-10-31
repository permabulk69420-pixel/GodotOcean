shader_type spatial;
// Original reef boulder/slab/arch/spire rock_boulder_dry colour + triplanar normals.
// Separate from the fast single-texture terrain shader; no UVs required.
render_mode world_vertex_coords;
#include "res://world/ocean/shaders/underwater_light.gdshaderinc"
#include "res://world/shaders/colour_space.gdshaderinc"

uniform sampler2D rock_colour : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float rock_tile_size = 3.0;
uniform vec3 rock_tint = vec3(0.92, 0.95, 0.9);
uniform float rock_normal_strength = 1.0;
uniform float sun_shadow_strength = 1.0;

vec3 unpack_normal(vec4 texel, float strength) {
	vec2 xy = (texel.xy * 2.0 - 1.0) * strength;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}
varying vec3 world_position;
varying vec3 world_normal;
varying float sunlight;
varying float caustic;
varying float specular_level;

void vertex() {
	world_position = VERTEX;
	world_normal = NORMAL;
	sunlight = COLOR.g;
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 blend = pow(abs(n), vec3(4.0));
	blend /= max(dot(blend, vec3(1.0)), 0.001);
	vec3 axis_sign = vec3(n.x < 0.0 ? -1.0 : 1.0, n.y < 0.0 ? -1.0 : 1.0, n.z < 0.0 ? -1.0 : 1.0);
	vec2 rock_x = vec2(world_position.z * axis_sign.x, world_position.y) / rock_tile_size;
	vec2 rock_y = vec2(world_position.x * axis_sign.y, world_position.z) / rock_tile_size;
	vec2 rock_z = vec2(-world_position.x * axis_sign.z, world_position.y) / rock_tile_size;
	vec2 rx_dx = dFdx(rock_x), rx_dy = dFdy(rock_x);
	vec2 ry_dx = dFdx(rock_y), ry_dy = dFdy(rock_y);
	vec2 rz_dx = dFdx(rock_z), rz_dy = dFdy(rock_z);

	vec3 rock = vec3(0.0);
	 vec3 rock_n = n;
	 {
	  vec3 tx = vec3(0.0), ty = vec3(0.0), tz = vec3(0.0);
	  if (blend.x > 0.02) {
	   rock += blend.x * textureGrad(rock_colour, rock_x, rx_dx, rx_dy).rgb;
	   tx = unpack_normal(textureGrad(rock_normal, rock_x, rx_dx, rx_dy), rock_normal_strength);
	  } else { tx = vec3(0.0, 0.0, 1.0); }
	  if (blend.y > 0.02) {
	   rock += blend.y * textureGrad(rock_colour, rock_y, ry_dx, ry_dy).rgb;
	   ty = unpack_normal(textureGrad(rock_normal, rock_y, ry_dx, ry_dy), rock_normal_strength);
	  } else { ty = vec3(0.0, 0.0, 1.0); }
	  if (blend.z > 0.02) {
	   rock += blend.z * textureGrad(rock_colour, rock_z, rz_dx, rz_dy).rgb;
	   tz = unpack_normal(textureGrad(rock_normal, rock_z, rz_dx, rz_dy), rock_normal_strength);
	  } else { tz = vec3(0.0, 0.0, 1.0); }
	  rock *= rock_tint;
	  tx.x *= axis_sign.x;
	  ty.x *= axis_sign.y;
	  tz.x *= -axis_sign.z;
	  tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	  ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	  tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	  rock_n = normalize(tx.zyx * blend.x + ty.xzy * blend.y + tz.xyz * blend.z);
	 }
	ALBEDO = linear_out(linear_in(rock) * mix(1.0, mix(0.25, 1.0, sunlight), sun_shadow_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(rock_n, 0.0)).xyz);
	ROUGHNESS = 0.82;
	SPECULAR = 0.16;
	METALLIC = 0.0;
	AO = COLOR.b;
	AO_LIGHT_AFFECT = 0.0;
	float distance_to_eye = distance(world_position, CAMERA_POSITION_WORLD);
	float strength = 1.0 - smoothstep(30.0, 46.0, distance_to_eye);
	caustic = distance_to_eye < 46.0 ? mix(1.0, caustic_light(world_position, TIME), strength) : 1.0;
	caustic = mix(1.0, caustic, sunlight);
	specular_level = SPECULAR;
}

// Full-precision lighting (the headset runs Godot's built-in version in half precision; see the
// water shader). Same Burley diffuse + GGX specular as the default, with the sun's direct light
// shaped by the caustics.
void light() {
 float n_dot_l = dot(NORMAL, LIGHT);
 vec3 half_sum = LIGHT + VIEW;
 float half_length = length(half_sum);
 if (n_dot_l > 0.0 && half_length > 0.001) {
  float shaped = LIGHT_IS_DIRECTIONAL ? caustic : 1.0;
  vec3 half_vector = half_sum / half_length;
  float c_n_dot_l = min(n_dot_l, 1.0);
  float c_n_dot_v = clamp(dot(NORMAL, VIEW), 0.0001, 1.0);
  float c_n_dot_h = clamp(dot(NORMAL, half_vector), 0.0, 1.0);
  float c_l_dot_h = clamp(dot(LIGHT, half_vector), 0.0, 1.0);
  float fd90_minus_1 = 2.0 * c_l_dot_h * c_l_dot_h * ROUGHNESS - 0.5;
  float fd_v = 1.0 + fd90_minus_1 * pow(1.0 - c_n_dot_v, 5.0);
  float fd_l = 1.0 + fd90_minus_1 * pow(1.0 - c_n_dot_l, 5.0);
  DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (fd_v * fd_l * c_n_dot_l / PI) * shaped;
  float alpha = max(ROUGHNESS * ROUGHNESS, 0.002);
  float a = c_n_dot_h * alpha;
  float k = alpha / (1.0 - c_n_dot_h * c_n_dot_h + a * a);
  float d = k * k / PI;
  float g = 0.5 / mix(2.0 * c_n_dot_l * c_n_dot_v, c_n_dot_l + c_n_dot_v, alpha);
  // Metal parts of the held equipment tint their reflection, as in Godot's default lighting.
  vec3 f0 = mix(vec3(0.16 * specular_level * specular_level), ALBEDO, METALLIC);
  float f90 = clamp(dot(f0, vec3(50.0 * 0.33)), 0.0, 1.0);
  vec3 fresnel_term = f0 + (f90 - f0) * pow(1.0 - c_l_dot_h, 5.0);
  SPECULAR_LIGHT += min(c_n_dot_l * d * g * fresnel_term * LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT * shaped, vec3(2000.0));
 }
}
