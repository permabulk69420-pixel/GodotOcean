shader_type spatial;
// Keep solid depth-writing terrain in Mobile's merged alpha draw list. This
// rebinds the per-pass descriptors when switching from the ocean shader while
// Godot asynchronously specializes pipelines. Coverage remains fully opaque.
render_mode world_vertex_coords, depth_draw_always;
uniform sampler2D grain : repeat_enable, filter_linear_mipmap_anisotropic;
varying vec3 world_position;
varying vec3 world_normal;
varying float sunlight;
void vertex() {
 world_position=VERTEX;
 world_normal=NORMAL;
 sunlight=COLOR.g;
}
void fragment() {
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
 ALPHA=1.0;
}