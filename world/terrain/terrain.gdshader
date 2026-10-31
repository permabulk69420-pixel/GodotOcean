shader_type spatial;
// Drawn as a normal opaque surface: nearest first, with hidden ground rejected before it is shaded. It used to write
// ALPHA to stay in Mobile's transparent draw list (far to near, blended, no early rejection), which cost about 6 ms of
// GPU time on the Quest; Vulkan validation shows no new errors without it.
render_mode world_vertex_coords;
#include "res://world/ocean/shaders/underwater_light.gdshaderinc"
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
// The ground is one Poly Haven texture (aerial_beach_01, CC0, 4K): just its colour and normal maps, spread over a large
// area. Level ground is projected from above; steep faces and rock use the side projection that faces them.
uniform sampler2D ground_colour : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D ground_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
// Metres of seabed covered by one repeat of the texture (the source scan is 30 m wide).
uniform float ground_tile_size = 20.0;
uniform float ground_normal_strength = 1.0;
uniform vec3 sand_tint = vec3(1.55, 1.5, 1.38);
// Rocks and steep faces carry no sand: the same texture, darker and greyer.
uniform vec3 rock_tint = vec3(0.55, 0.58, 0.56);
// Baked sun occlusion darkens the surface only while the sun is up (1 = day, 0 = night).
uniform float sun_shadow_strength = 1.0;
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
 // 1 on level ground, 0 on rock and steep faces (baked into the vertex colour).
 float flat_amount = COLOR.r;
 vec3 axis_sign = vec3(n.x < 0.0 ? -1.0 : 1.0, 1.0, n.z < 0.0 ? -1.0 : 1.0);
 bool along_x = abs(n.x) > abs(n.z);
 // Texture coordinates and their gradients are worked out up here, outside the branches, so every lookup below has
 // a valid mip level. The gradients ignore the mirroring so they cannot jump where the facing flips.
 vec2 top_uv = world_position.xz / ground_tile_size;
 vec2 top_dx = dFdx(top_uv), top_dy = dFdy(top_uv);
 vec2 side_raw = (along_x ? vec2(world_position.z, world_position.y) : vec2(world_position.x, world_position.y)) / ground_tile_size;
 vec2 side_dx = dFdx(side_raw), side_dy = dFdy(side_raw);
 vec2 side_uv = along_x ? vec2(side_raw.x * axis_sign.x, side_raw.y) : vec2(-side_raw.x * axis_sign.z, side_raw.y);

 vec3 top_colour = vec3(0.0);
 vec3 top_n = n;
 if (flat_amount > 0.002) {
  top_colour = textureGrad(ground_colour, top_uv, top_dx, top_dy).rgb;
  vec3 t = unpack_normal(textureGrad(ground_normal, top_uv, top_dx, top_dy), ground_normal_strength);
  // Whiteout blend onto the world normal; level ground is projected from above.
  t = vec3(t.xy + n.xz, abs(t.z) * n.y);
  top_n = normalize(t.xzy);
 }
 vec3 side_colour = vec3(0.0);
 vec3 side_n = n;
 if (flat_amount < 0.998) {
  side_colour = textureGrad(ground_colour, side_uv, side_dx, side_dy).rgb;
  vec3 t = unpack_normal(textureGrad(ground_normal, side_uv, side_dx, side_dy), ground_normal_strength);
  if (along_x) {
   t.x *= axis_sign.x;
   t = vec3(t.xy + n.zy, abs(t.z) * n.x);
   side_n = normalize(t.zyx);
  } else {
   t.x *= -axis_sign.z;
   t = vec3(t.xy + n.xy, abs(t.z) * n.z);
   side_n = normalize(t.xyz);
  }
 }
 vec3 albedo = mix(side_colour * rock_tint, top_colour * sand_tint, flat_amount);
 ALBEDO = albedo * mix(1.0, mix(0.25, 1.0, sunlight), sun_shadow_strength);
 vec3 shaded_normal = normalize(mix(side_n, top_n, flat_amount));
 NORMAL = normalize((VIEW_MATRIX * vec4(shaded_normal, 0.0)).xyz);
 ROUGHNESS = mix(0.82, 0.94, flat_amount);
 SPECULAR = 0.16;
 AO = COLOR.b;
 AO_LIGHT_AFFECT = 0.0;
 // No caustics where the baked sun visibility says the seabed is in shade.
 caustic = mix(1.0, caustic, sunlight);
 }
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
