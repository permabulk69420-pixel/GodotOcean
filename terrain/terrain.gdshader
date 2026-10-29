shader_type spatial;
// Keep solid depth-writing terrain in Mobile's merged alpha draw list. This
// rebinds the per-pass descriptors when switching from the ocean shader while
// Godot asynchronously specializes pipelines. Coverage remains fully opaque.
render_mode world_vertex_coords, depth_draw_always;
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
uniform vec3 emitted : source_color = vec3(0.0);
varying vec3 world_position;
varying vec3 world_normal;
varying float sunlight;
void vertex() {
 world_position=VERTEX;
 world_normal=NORMAL;
 sunlight=COLOR.g;
}
void fragment() {
 AO = 1.0;
 AO_LIGHT_AFFECT = 0.0;
 SPECULAR = 0.5;
 if (surface_kind > 0) {
  ALBEDO = tint.rgb * texture(colour_map, UV * uv_scale).rgb;
  if (surface_kind == 2) {
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
 vec3 weights=pow(abs(normalize(world_normal)),vec3(4.0));
 weights/=max(dot(weights,vec3(1)),0.001);
 float texture_grain=texture(grain,world_position.zy*0.08).r*weights.x+texture(grain,world_position.xz*0.08).r*weights.y+texture(grain,world_position.xy*0.08).r*weights.z;
 float ripples=sin(world_position.x*7.0+sin(world_position.z*0.9)*1.2);
 vec3 sand=mix(vec3(0.57,0.46,0.29),vec3(0.86,0.77,0.56),texture_grain);
 vec3 limestone=mix(vec3(0.23,0.25,0.22),vec3(0.55,0.53,0.43),texture_grain);
 ALBEDO=mix(limestone,sand,COLOR.r)*(0.97+0.03*ripples*COLOR.r)*mix(0.25,1.0,sunlight);
 ROUGHNESS=mix(0.82,0.94,COLOR.r);
 SPECULAR=0.16;
 AO=COLOR.b;
 AO_LIGHT_AFFECT=0.0;
 }
 ALPHA=1.0;
}
