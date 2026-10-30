class_name AbyssLightShafts
extends MultiMeshInstance3D
## Faint sunbeams slanting down through the water around the player while the sun is up.
## One batched draw call; every beam is placed and animated on the GPU (light_shafts.gdshader).

const SHADER := preload('res://world/ocean/light_shafts.gdshader')

## How many beams exist around the player at once.
@export var count := 28
## Side of the square around the player that the beams are spread over (metres).
@export var spread := 44.0
## How bright a single beam is (it only ever adds light).
@export var brightness := 0.10

var material: ShaderMaterial

func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter('spread', spread)
	material.set_shader_parameter('brightness', brightness)
	quad.material = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = count
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Beams are placed by the shader around the camera; this box just has to contain them.
	custom_aabb = AABB(Vector3(-spread, -40.0, -spread), Vector3(spread * 2.0, 80.0, spread * 2.0))
	visible = false

## Shown only under the water while the sun is up (the shader fades them with the sun as well).
func update(camera_position: Vector3, daylight: float, submerged: bool) -> void:
	visible = submerged and daylight > 0.05
	if visible:
		global_position = camera_position
		material.set_shader_parameter('centre', camera_position)
