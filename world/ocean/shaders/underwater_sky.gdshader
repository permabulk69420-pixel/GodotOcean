shader_type sky;
// The "sky" while the camera is under the water: the colour of the water in every direction
// (see underwater_water.gdshaderinc). The underwater fog takes its colour from this through the
// environment's aerial perspective, so distant things fade into a gradient (bright towards the
// surface, dark below) instead of one flat colour. It also lights the scene from above as
// ambient light and shows in reflections. day_night.gd sets day_amount and depth a couple of
// times a second (every change makes Godot refilter the sky, so it is not done every frame).
#include "res://world/ocean/shaders/underwater_water.gdshaderinc"
#include "res://world/shaders/colour_space.gdshaderinc"

// 0 at night, 1 in full day.
uniform float day_amount = 1.0;
// Metres below the surface.
uniform float depth = 0.0;

// Godot's Mobile renderer reads the fog colour from the sky's lighting copy at half the brightness
// the sky itself is drawn at, so the open water drawn on screen is scaled to match the fog.
uniform float drawn_brightness = 0.5;

void sky() {
	// The lighting copy (cubemap pass) is what Godot blurs for the fog. What is drawn on screen is
	// pre-blurred and scaled to match, so fogged scenery and open water meet without a seam.
	if (AT_CUBEMAP_PASS) {
		COLOR = linear_out(underwater_water_colour(EYEDIR, LIGHT0_DIRECTION, day_amount, depth, 0.0));
	} else {
		COLOR = linear_out(underwater_water_colour(EYEDIR, LIGHT0_DIRECTION, day_amount, depth, 1.0) * drawn_brightness);
	}
}
