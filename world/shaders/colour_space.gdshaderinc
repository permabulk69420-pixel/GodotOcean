// The Compatibility (OpenGL) renderer works in sRGB inside shaders: colour uniforms (source_color) and colour textures
// arrive unconverted, and ALBEDO, EMISSION and a sky's COLOR are converted from sRGB to linear after the shader runs.
// Vulkan hands shaders linear values and takes linear values back. These shaders do their colour maths in linear, so
// under OpenGL they convert where colours come in (linear_in) and once where the result goes out (linear_out). These are
// the same approximations Godot's OpenGL renderer uses, so the round trip is exact. On Vulkan both do nothing.
#ifndef COLOUR_SPACE_INCLUDED
#define COLOUR_SPACE_INCLUDED
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
vec3 linear_in(vec3 c) { return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878); }
float linear_in(float c) { return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878); }
vec3 linear_out(vec3 c) { return max(vec3(1.055) * pow(max(c, vec3(0.0)), vec3(0.416666667)) - vec3(0.055), vec3(0.0)); }
#else
vec3 linear_in(vec3 c) { return c; }
float linear_in(float c) { return c; }
vec3 linear_out(vec3 c) { return c; }
#endif
#endif
