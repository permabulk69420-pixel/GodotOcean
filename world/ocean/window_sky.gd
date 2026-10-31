class_name AbyssWindowSky
extends SubViewport
## The sky seen through the bright window overhead when looking up from under the water, baked into a small table
## (world/ocean/shaders/window_sky.gdshader) that the water's underside reads. It is redrawn only when the sun has
## moved or the light has changed enough to notice, a 64 x 32 pixel pass a few times a second.

const SHADER := preload("res://world/ocean/shaders/window_sky.gdshader")
## Redraw once the sun has moved this far (radians, about a quarter of a degree).
const SUN_STEP := 0.0045
## ... or the daylight has changed this much.
const DAY_STEP := 0.004

var material: ShaderMaterial
var baked_sun := Vector3.ZERO
var baked_day := -1.0

func _init() -> void:
	size = Vector2i(64, 32)
	disable_3d = true
	use_hdr_2d = true
	transparent_bg = false
	gui_disable_input = true
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	material = ShaderMaterial.new()
	material.shader = SHADER
	var rect := ColorRect.new()
	rect.size = Vector2(size)
	rect.material = material
	add_child(rect)

## Call every frame with the direction towards the sun (above the water) and the daylight (0 night .. 1 day).
func bake(sun_direction: Vector3, day_amount: float) -> void:
	if baked_day >= 0.0 and baked_sun.angle_to(sun_direction) < SUN_STEP and absf(day_amount - baked_day) < DAY_STEP \
			and not (day_amount != baked_day and (day_amount == 0.0 or day_amount == 1.0)):
		return
	baked_sun = sun_direction
	baked_day = day_amount
	material.set_shader_parameter("sky_sun_direction", sun_direction)
	material.set_shader_parameter("day_amount", day_amount)
	render_target_update_mode = SubViewport.UPDATE_ONCE
