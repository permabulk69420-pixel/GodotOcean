class_name OceanHandThrusters
extends Node3D

const MODEL = preload('res://player/thrusters/hand_thruster.glb')
const MODEL_LEFT = preload('res://player/thrusters/hand_thruster_left.glb')
const MATERIAL_SHADER = preload('res://terrain/terrain.gdshader')
const PICKUP_RADIUS := 0.45
const GRAB_THRESHOLD := 0.55
const PROPELLER_RATE := TAU * 7.3
const PROPULSION_ACCELERATION := 36.0
const MAX_SPEED := 22.5

var player: ShallowsSwimmer
var hands: Array[OceanVRHand] = []
var motors: Array[Node3D] = []
var held: Array[Node3D] = [null, null]
var previous_grip := [0.0, 0.0]
var propellers: Array[Node3D] = []
var propeller_speed := [0.0, 0.0]
var throttles := [0.0, 0.0]
var propulsion := Vector3.ZERO
var tracked_frames := 0
var materials: Dictionary = {}

func _ready() -> void:
	player = get_parent() as ShallowsSwimmer
	hands.assign([player.get_node('XROrigin3D/LeftHand/Hand'), player.get_node('XROrigin3D/RightHand/Hand')])
	# Sample controllers and update palms before the swimmer integrates movement.
	process_physics_priority = -20

func spawn_motors() -> void:
	var forward := -player.head.global_basis.z
	forward.y = 0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP)
	for side in range(2):
		var motor := Node3D.new()
		motor.name = 'LeftThruster' if side == 0 else 'RightThruster'
		var visual: Node3D = (MODEL_LEFT if side == 0 else MODEL).instantiate()
		motor.add_child(visual)
		for mesh: MeshInstance3D in visual.find_children('*', 'MeshInstance3D', true, false):
			var source := mesh.mesh.surface_get_material(0)
			if not materials.has(source):
				var material := ShaderMaterial.new()
				material.shader = MATERIAL_SHADER
				material.set_shader_parameter('surface_kind', 1)
				material.set_shader_parameter('tint', source.albedo_color)
				material.set_shader_parameter('roughness', source.roughness)
				material.set_shader_parameter('metalness', source.metallic)
				material.set_shader_parameter('emitted', Vector3(source.emission.r, source.emission.g, source.emission.b) * source.emission_energy_multiplier)
				materials[source] = material
			mesh.material_override = materials[source]
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var grip: Node3D = visual.find_child('GripPoint', true, false)
		assert(grip, 'Thruster model must contain its authored handle socket')
		visual.transform = grip.transform.affine_inverse()
		player.get_parent().add_child(motor)
		motor.global_position = player.head.global_position + forward * 0.9 + right * (-0.36 if side == 0 else 0.36) + Vector3.DOWN * 0.22
		motor.global_basis = Basis.looking_at(forward)
		motors.append(motor)
		propellers.append(visual.find_child('Propeller', true, false))

func try_grab(side: int) -> void:
	if held[side] or not hands[side].object_grip.is_inside_tree(): return
	var closest: Node3D
	var distance := PICKUP_RADIUS * PICKUP_RADIUS
	for motor in motors:
		if motor in held: continue
		var candidate := motor.global_position.distance_squared_to(hands[side].object_grip.global_position)
		if candidate < distance:
			closest = motor
			distance = candidate
	if not closest: return
	hands[side].holding = true
	hands[side].pose(1.0, 0.0)
	closest.reparent(hands[side].object_grip, false)
	# Seat the handle on the animated palm, with the long pod aligned to the
	# tracked forearm. Imported grip-bone roll must not turn the motor sideways.
	closest.transform = Transform3D(hands[side].object_grip.global_basis.inverse() * hands[side].controller.global_basis, Vector3.ZERO)
	held[side] = closest

func release(side: int) -> void:
	if held[side]:
		var motor := held[side]
		motor.reparent(player.get_parent(), true)
		throttles[motors.find(motor)] = 0.0
		held[side] = null
	hands[side].holding = false

func _physics_process(delta: float) -> void:
	propulsion = Vector3.ZERO
	throttles.fill(0.0)
	if not player.ocean: return
	for side in range(2):
		var controller := hands[side].controller
		var active := player.controls_enabled and controller.get_is_active() and controller.get_has_tracking_data()
		var grip := controller.get_float(&'grip') if active else 0.0
		var trigger := controller.get_float(&'trigger') if active else 0.0
		hands[side].pose(grip, trigger)
		if not active:
			release(side)
		elif grip >= GRAB_THRESHOLD and previous_grip[side] < GRAB_THRESHOLD:
			try_grab(side)
		elif grip < GRAB_THRESHOLD and previous_grip[side] >= GRAB_THRESHOLD:
			release(side)
		previous_grip[side] = grip
		var motor := held[side]
		if not motor: continue
		var index := motors.find(motor)
		throttles[index] = trigger
		# The tools only propel while submerged: they cannot be used as jetpacks.
		if trigger > 0.03 and motor.global_position.y < player.ocean.sample_surface(motor.global_position).height:
			propulsion += -motor.global_basis.z.normalized() * trigger
	if motors.is_empty() and player.spawned and player.controls_enabled and (hands[0].controller.get_has_tracking_data() or hands[1].controller.get_has_tracking_data()):
		tracked_frames += 1
		if tracked_frames >= 4: spawn_motors()
	for i in range(motors.size()):
		propeller_speed[i] = lerpf(propeller_speed[i], throttles[i] * PROPELLER_RATE, 1.0 - exp(-18.0 * delta))
		if propellers[i]: propellers[i].rotate_object_local(Vector3.BACK, propeller_speed[i] * delta)
	propulsion = propulsion.limit_length(2.0)

func _exit_tree() -> void:
	for motor in motors:
		if is_instance_valid(motor): motor.queue_free()
