#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Points { vec4 points[]; };
layout(set=0,binding=1,std430) readonly buffer Spectrum { vec4 waves[]; };
layout(set=0,binding=2,rgba16f) uniform writeonly image2D displacement_map;
layout(set=0,binding=3,rgba16f) uniform writeonly image2D normal_map;
layout(push_constant,std430) uniform Parameters { vec4 data; } params;
void main() {
 uint id=gl_GlobalInvocationID.x;
 if(id>=uint(params.data.w)) return;
 vec2 position=points[id].xy+params.data.xy;
 float spacing=max(0.25,max(abs(points[id].x),abs(points[id].y))/64.0);
 vec3 d=vec3(0),tx=vec3(1,0,0),tz=vec3(0,0,1);
 for(int i=0;i<64;i++) {
  vec4 w=waves[i*2]; vec4 p=waves[i*2+1];
  // Remove frequencies the distant mesh cannot represent, avoiding spatial aliasing.
  float weight=1.0-smoothstep(1.5707963,3.1415926,w.w*spacing);
  if(weight<0.0001) continue;
  w.z*=weight;
  float phase=w.w*dot(w.xy,position)-p.x*params.data.z+p.y;
  float s=sin(phase),c=cos(phase),h=p.z;
  d+=vec3(h*w.z*c*w.x,w.z*s,h*w.z*c*w.y);
  float slope=w.z*w.w;
  tx+=vec3(-h*slope*w.x*w.x*s,slope*w.x*c,-h*slope*w.x*w.y*s);
  tz+=vec3(-h*slope*w.x*w.y*s,slope*w.y*c,-h*slope*w.y*w.y*s);
 }
 ivec2 pixel=ivec2(int(id)%1024,int(id)/1024);
 imageStore(displacement_map,pixel,vec4(d,1));
 imageStore(normal_map,pixel,vec4(normalize(cross(tz,tx)),1.0-(tx.x*tz.z-tx.z*tz.x)));
}
