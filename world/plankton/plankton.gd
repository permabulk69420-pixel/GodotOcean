class_name AbyssPlankton
extends MultiMeshInstance3D
## Blue glowing plankton: one batched draw call, no per-particle state. It follows the camera
## and lights up around recent movement of the hands, thrusters and head.

const TRAIL_COUNT := 64
const SHADER := preload('res://world/plankton/plankton.gdshader')

@export var count := 3600
@export var volume_size := 16.0
## Seconds between trail samples; with 64 slots this decides how long a trail lasts.
@export var sample_interval := 0.16
## 0 keeps every speck the same deep blue; above 0 they brighten near recent movement.
@export var flare_strength := 0.0

var material: ShaderMaterial
var now := 0.0
var sample_timer := 0.0
var trail := PackedVector4Array()
var trail_power := PackedFloat32Array()
var next_slot := 0
var previous := PackedVector3Array()

func _ready() -> void:
	trail.resize(TRAIL_COUNT)
	trail_power.resize(TRAIL_COUNT)
	for i in range(TRAIL_COUNT):
		trail[i] = Vector4(0, 0, 0, -1000.0)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	material = ShaderMaterial.new()
	material.shader = SHADER
	quad.material = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = count
	custom_aabb = AABB(Vector3.ONE * -volume_size * 0.5, Vector3.ONE * volume_size)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material.set_shader_parameter('volume_size', volume_size)
	material.set_shader_parameter('flare_strength', flare_strength)
	material.set_shader_parameter('trail', trail)
	material.set_shader_parameter('trail_power', trail_power)

## positions and boosts describe everything that should light the plankton; a boost adds glow
## on top of the speed-based glow (used for running thrusters).
func update(delta: float, camera_position: Vector3, positions: PackedVector3Array, boosts: PackedFloat32Array, daylight: float, active: bool) -> void:
	visible = active and daylight < 0.97
	if not visible:
		previous = PackedVector3Array()
		return
	now += delta
	global_position = camera_position
	if previous.size() != positions.size():
		previous = positions.duplicate()
	sample_timer += delta
	if flare_strength > 0.0 and sample_timer >= sample_interval:
		for i in range(positions.size()):
			var speed := positions[i].distance_to(previous[i]) / maxf(sample_timer, 0.001)
			var power := clampf(speed * 0.55, 0.0, 1.3) + boosts[i]
			if power > 0.08:
				trail[next_slot] = Vector4(positions[i].x, positions[i].y, positions[i].z, now)
				trail_power[next_slot] = minf(power, 2.2)
				next_slot = (next_slot + 1) % TRAIL_COUNT
		previous = positions.duplicate()
		sample_timer = 0.0
		material.set_shader_parameter('trail', trail)
		material.set_shader_parameter('trail_power', trail_power)
	material.set_shader_parameter('centre', camera_position)
	material.set_shader_parameter('now', now)
	material.set_shader_parameter('day_amount', daylight)
