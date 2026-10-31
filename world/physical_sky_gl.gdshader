shader_type sky;
render_mode use_debanding;
// Godot 4.7's PhysicalSkyMaterial shader (scene/resources/3d/sky_material.cpp), for the Compatibility (OpenGL) renderer
// only: main.gd swaps it in for the scene's PhysicalSkyMaterial there, with the same settings. That renderer hands sky
// shaders their colours unconverted and treats COLOR as sRGB, which turns the built-in sky grey and dim; this copy
// converts at the edges (world/shaders/colour_space.gdshaderinc) and is otherwise unchanged. Vulkan keeps the built-in.
#include "res://world/shaders/colour_space.gdshaderinc"

uniform float rayleigh : hint_range(0, 64) = 2.0;
uniform vec4 rayleigh_color : source_color = vec4(0.3, 0.405, 0.6, 1.0);
uniform float mie : hint_range(0, 1) = 0.005;
uniform float mie_eccentricity : hint_range(-1, 1) = 0.8;
uniform vec4 mie_color : source_color = vec4(0.69, 0.729, 0.812, 1.0);
uniform float turbidity : hint_range(0, 1000) = 10.0;
uniform float sun_disk_scale : hint_range(0, 360) = 1.0;
uniform vec4 ground_color : source_color = vec4(0.1, 0.07, 0.034, 1.0);
uniform float exposure : hint_range(0, 128) = 1.0;

const vec3 UP = vec3(0.0, 1.0, 0.0);
// Optical length at zenith for molecules.
const float rayleigh_zenith_size = 8.4e3;
const float mie_zenith_size = 1.25e3;

float henyey_greenstein(float cos_theta, float g) {
	const float k = 0.0795774715459;
	return k * (1.0 - g * g) / (pow(1.0 + g * g - 2.0 * g * cos_theta, 1.5));
}

void sky() {
	if (LIGHT0_ENABLED) {
		float zenith_angle = clamp(dot(UP, normalize(LIGHT0_DIRECTION)), -1.0, 1.0);
		float sun_energy = max(0.0, 0.757 * zenith_angle) * LIGHT0_ENERGY;
		float sun_fade = 1.0 - clamp(1.0 - exp(LIGHT0_DIRECTION.y), 0.0, 1.0);

		// Rayleigh coefficients.
		float rayleigh_coefficient = rayleigh - (1.0 * (1.0 - sun_fade));
		vec3 rayleigh_beta = rayleigh_coefficient * linear_in(rayleigh_color.rgb) * 0.0001;
		// Mie coefficients from Preetham.
		vec3 mie_beta = turbidity * mie * linear_in(mie_color.rgb) * 0.000434;

		// Optical length.
		float zenith = max(0.0, dot(UP, EYEDIR));
		float optical_mass = 1.0 / (zenith + 0.15 * pow(3.885 + 54.5 * zenith, -1.253));
		float rayleigh_scatter = rayleigh_zenith_size * optical_mass;
		float mie_scatter = mie_zenith_size * optical_mass;

		// Light extinction based on thickness of atmosphere.
		vec3 extinction = exp(-(rayleigh_beta * rayleigh_scatter + mie_beta * mie_scatter));

		// In scattering.
		float cos_theta = dot(EYEDIR, normalize(LIGHT0_DIRECTION));
		float rayleigh_phase = (3.0 / (16.0 * PI)) * (1.0 + pow(cos_theta * 0.5 + 0.5, 2.0));
		vec3 betaRTheta = rayleigh_beta * rayleigh_phase;
		float mie_phase = henyey_greenstein(cos_theta, mie_eccentricity);
		vec3 betaMTheta = mie_beta * mie_phase;

		vec3 Lin = pow(sun_energy * ((betaRTheta + betaMTheta) / (rayleigh_beta + mie_beta)) * (1.0 - extinction), vec3(1.5));
		// Hack from https://github.com/mrdoob/three.js/blob/master/examples/jsm/objects/Sky.js
		Lin *= mix(vec3(1.0), pow(sun_energy * ((betaRTheta + betaMTheta) / (rayleigh_beta + mie_beta)) * extinction, vec3(0.5)), clamp(pow(1.0 - zenith_angle, 5.0), 0.0, 1.0));
		// Hack in the ground color.
		Lin *= mix(linear_in(ground_color.rgb), vec3(1.0), smoothstep(-0.1, 0.1, dot(UP, EYEDIR)));

		// Solar disk and out-scattering.
		float sunAngularDiameterCos = cos(LIGHT0_SIZE * sun_disk_scale);
		float sunAngularDiameterCos2 = cos(LIGHT0_SIZE * sun_disk_scale * 0.5);
		float sundisk = smoothstep(sunAngularDiameterCos, sunAngularDiameterCos2, cos_theta);
		vec3 L0 = (sun_energy * extinction) * sundisk * linear_in(LIGHT0_COLOR);

		vec3 color = Lin + L0;
		COLOR = linear_out(pow(color, vec3(1.0 / (1.2 + (1.2 * sun_fade)))) * exposure);
	} else {
		// There is no sun, so display nothing (the built-in shows its night sky texture here; the scene sets none).
		COLOR = vec3(0.0);
	}
}
