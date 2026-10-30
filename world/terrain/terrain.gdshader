shader_type spatial;
// Keep solid depth-writing terrain in Mobile's merged alpha draw list. This
// rebinds the per-pass descriptors when switching from the ocean shader while
// Godot asynchronously specializes pipelines. Coverage remains fully opaque.
render_mode world_vertex_coords, depth_draw_always;
#include "res://world/ocean/shaders/underwater_light.gdshaderinc"
uniform sampler2D grain : repeat_enable, filter_linear_mipmap_anisotropic;
// Equipment shares this draw layout so Mobile never switches incompatible
// specialized shader layouts between terrain, skinned palms and held tools.
uniform int surface_kind = 0;
uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D colour_map : source_color, hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec2 uv_scale = vec2(1.0);
uniform float normal_strength = 0.0;
uniform float roughness = 0.4;
uniform float metalness = 0.0;
// Terrain materials (Poly Haven, CC0). Sand is sampled from above only; rock is triplanar.
uniform sampler2D sand_colour : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D sand_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_colour : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
// Sand is Poly Haven's rippled beach (aerial_beach_01, a 30 m scan) shrunk so the ripples are a
// hand's width apart, like the small ripples waves leave on a sandy seabed. Rock is rock_boulder_dry.
uniform float sand_tile_size = 5.5;
uniform float rock_tile_size = 3.0;
uniform vec3 sand_tint = vec3(1.55, 1.5, 1.38);
uniform vec3 rock_tint = vec3(0.92, 0.95, 0.9);
// Baked sun occlusion darkens the surface only while the sun is up (1 = day, 0 = night).
uniform float sun_shadow_strength = 1.0;
uniform float sand_normal_strength = 1.0;
uniform float rock_normal_strength = 1.0;
uniform vec3 emitted : source_color = vec3(0.0);

// Decodes a tangent-space normal; works for both RG-compressed and RGB maps.
vec3 unpack_normal(vec4 texel, float strength) {
 vec2 xy = (texel.xy * 2.0 - 1.0) * strength;
 return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}
varying vec3 world_position;
varying vec3 world_normal;
varying float sunlight;
// Caustic brightness for the sun, worked out once per pixel in fragment() and used in light().
varying float caustic;
// The material's SPECULAR value, which light() cannot read directly.
varying float specular_level;
void vertex() {
 world_position=VERTEX;
 world_normal=NORMAL;
 sunlight=COLOR.g;
}
void fragment() {
 AO = 1.0;
 AO_LIGHT_AFFECT = 0.0;
 SPECULAR = 0.5;
 caustic = caustic_light(world_position, TIME);
 if (surface_kind > 0) {
  // Procedural housings have no texture UVs. Only the imported skin samples
  // UV textures; sampling a missing UV channel produces undefined derivatives.
  ALBEDO = tint.rgb;
  if (surface_kind == 2) {
   ALBEDO *= texture(colour_map, UV * uv_scale).rgb;
   vec3 detail = texture(normal_map, UV * uv_scale).rgb * 2.0 - 1.0;
   detail.xy *= normal_strength;
   // Derive the skin's cotangent frame from the posed surface. Equipment and
   // terrain do not need tangent attributes or degenerate imported tangents.
   vec3 dp1 = dFdx(VERTEX), dp2 = dFdy(VERTEX);
   vec2 duv1 = dFdx(UV * uv_scale), duv2 = dFdy(UV * uv_scale);
   vec3 dp2perp = cross(dp2, NORMAL), dp1perp = cross(NORMAL, dp1);
   vec3 t = dp2perp * duv1.x + dp1perp * duv2.x;
   vec3 b = dp2perp * duv1.y + dp1perp * duv2.y;
   float scale = inversesqrt(max(max(dot(t,t),dot(b,b)), 0.00000001));
   NORMAL = normalize(mat3(t * scale, b * scale, NORMAL) * normalize(detail));
  }
  ROUGHNESS = roughness;
  METALLIC = metalness;
  EMISSION = emitted;
 } else {
 vec3 n = normalize(world_normal);
 float sand_amount = COLOR.r;
 // Gradients come from outside the branches so every fetch has valid mip selection.
 vec2 sand_uv = world_position.xz / sand_tile_size;
 vec2 sand_dx = dFdx(sand_uv), sand_dy = dFdy(sand_uv);
 vec3 blend = pow(abs(n), vec3(4.0));
 blend /= max(dot(blend, vec3(1.0)), 0.001);
 vec3 axis_sign = vec3(n.x < 0.0 ? -1.0 : 1.0, n.y < 0.0 ? -1.0 : 1.0, n.z < 0.0 ? -1.0 : 1.0);
 vec2 rock_x = vec2(world_position.z * axis_sign.x, world_position.y) / rock_tile_size;
 vec2 rock_y = vec2(world_position.x * axis_sign.y, world_position.z) / rock_tile_size;
 vec2 rock_z = vec2(-world_position.x * axis_sign.z, world_position.y) / rock_tile_size;
 vec2 rx_dx = dFdx(rock_x), rx_dy = dFdy(rock_x);
 vec2 ry_dx = dFdx(rock_y), ry_dy = dFdy(rock_y);
 vec2 rz_dx = dFdx(rock_z), rz_dy = dFdy(rock_z);

 // Slow tint drift hides the texture repeat on open seabed.
 float drift = mix(0.86, 1.14, texture(grain, world_position.xz * 0.012).r);

 vec3 sand = vec3(0.0);
 vec3 sand_n = n;
 if (sand_amount > 0.002) {
  sand = textureGrad(sand_colour, sand_uv, sand_dx, sand_dy).rgb * sand_tint * drift;
  vec3 t = unpack_normal(textureGrad(sand_normal, sand_uv, sand_dx, sand_dy), sand_normal_strength);
  // Whiteout blend onto the world normal; sand is projected from above.
  t = vec3(t.xy + n.xz, abs(t.z) * n.y);
  sand_n = normalize(t.xzy);
 }
 vec3 rock = vec3(0.0);
 vec3 rock_n = n;
 if (sand_amount < 0.998) {
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
  rock *= rock_tint * drift;
  tx.x *= axis_sign.x;
  ty.x *= axis_sign.y;
  tz.x *= -axis_sign.z;
  tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
  ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
  tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
  rock_n = normalize(tx.zyx * blend.x + ty.xzy * blend.y + tz.xyz * blend.z);
 }
 float ripples = sin(world_position.x * 7.0 + sin(world_position.z * 0.9) * 1.2);
 ALBEDO = mix(rock, sand, sand_amount) * (0.97 + 0.03 * ripples * sand_amount) * mix(1.0, mix(0.25, 1.0, sunlight), sun_shadow_strength);
 vec3 shaded_normal = normalize(mix(rock_n, sand_n, sand_amount));
 NORMAL = normalize((VIEW_MATRIX * vec4(shaded_normal, 0.0)).xyz);
 ROUGHNESS = mix(0.82, 0.94, sand_amount);
 SPECULAR = 0.16;
 AO = COLOR.b;
 AO_LIGHT_AFFECT = 0.0;
 // No caustics where the baked sun visibility says the seabed is in shade.
 caustic = mix(1.0, caustic, sunlight);
 }
 specular_level = SPECULAR;
 ALPHA=1.0;
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
