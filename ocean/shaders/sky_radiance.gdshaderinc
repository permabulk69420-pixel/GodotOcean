/**************************************************************************/
/*  sky_material.cpp                                                      */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/


uniform vec3 sky_sun_direction=vec3(0.0,0.53,0.85);
uniform vec3 sky_rayleigh_color : source_color=vec3(0.3,0.405,0.6);
uniform vec3 sky_mie_color : source_color=vec3(0.69,0.729,0.812);
uniform vec3 sky_ground_color : source_color=vec3(0.12,0.16,0.18);
uniform vec3 sky_sun_color : source_color=vec3(1.0,0.95,0.85);
// Same atmospheric scattering as the scene's PhysicalSkyMaterial. Evaluate the
// refracted ray rather than copying, resolving and resampling both eye images.
vec3 refracted_sky(vec3 direction) {
 float sun_zenith=clamp(sky_sun_direction.y,-1.0,1.0);
 float energy=max(0.0,0.757*sun_zenith)*1.6;
 float fade=1.0-clamp(1.0-exp(sky_sun_direction.y),0.0,1.0);
 vec3 beta_r=(2.0-(1.0-fade))*sky_rayleigh_color*0.0001;
 vec3 beta_m=10.0*0.003*sky_mie_color*0.000434;
 float zenith=max(0.0,direction.y);
 float mass=1.0/(zenith+0.15*pow(3.885+54.5*zenith,-1.253));
 vec3 extinction=exp(-(beta_r*8400.0*mass+beta_m*1250.0*mass));
 float cosine=dot(direction,sky_sun_direction);
 float phase_r=(3.0/(16.0*PI))*(1.0*pow(cosine*0.5+0.5,2.0)+1.0);
 float phase_m=0.0795774715459*(1.0-0.8*0.8)/pow(1.0+0.8*0.8-2.0*0.8*cosine,1.5);
 vec3 incident=energy*(beta_r*phase_r+beta_m*phase_m)/(beta_r+beta_m);
 vec3 scattering=pow(incident*(1.0-extinction),vec3(1.5));
 scattering*=mix(vec3(1.0),pow(incident*extinction,vec3(0.5)),clamp(pow(1.0-sun_zenith,5.0),0.0,1.0));
 scattering*=mix(sky_ground_color,vec3(1.0),smoothstep(-0.1,0.1,direction.y));
 float disk=smoothstep(cos(0.008726646),cos(0.004363323),cosine);
 vec3 color=scattering+energy*extinction*disk*sky_sun_color;
 return pow(max(color,vec3(0.0)),vec3(1.0/(1.2+1.2*fade)));
}
