shader_type canvas_item;
render_mode unshaded;
// Bakes the sky seen through the bright window overhead into a small table (see window_sky.gd), so the water's
// underside reads it with one texture lookup instead of working out the atmospheric scattering for every pixel.
// Across: closeness to the sun, packed so the bright glow around it gets most of the columns.
// Down: how high the direction points, from just under the horizon to straight up.
// underside.gdshader turns a direction into the same position; the two mappings must stay inverses of each other.
#include "res://world/ocean/shaders/sky_radiance.gdshaderinc"

void fragment() {
	float cosine = 1.0 - 2.0 * UV.x * UV.x;
	float up = UV.y * UV.y * 1.1 - 0.1;
	COLOR = vec4(sky_radiance(up, cosine), 1.0);
}
