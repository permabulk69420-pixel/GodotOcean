class_name OceanVRHand
extends Node3D

const LEFT = preload('res://player/hands/LeftHand.glb')
const RIGHT = preload('res://player/hands/RightHand.glb')
const SKIN_COLOUR = preload('res://player/hands/skin-colour.jpg')
const SKIN_NORMAL = preload('res://player/hands/skin-normal.jpg')
const MATERIAL_SHADER = preload('res://terrain/terrain.gdshader')
const GRIP_FIT = preload('res://player/hand_grip_data.gd')

@export var left_hand := true
var controller: XRController3D
var skeleton: Skeleton3D
var animator: AnimationPlayer
var grip_bone := -1
var object_grip: Node3D
var holding := false
var last_pose := ''
var last_amount := -1.0

func _ready() -> void:
	controller = get_parent() as XRController3D
	rotation.z = PI * 0.5 if left_hand else -PI * 0.5
	var model: Node3D = (LEFT if left_hand else RIGHT).instantiate()
	add_child(model)
	skeleton = model.find_children('*', 'Skeleton3D', true, false)[0]
	animator = model.find_children('*', 'AnimationPlayer', true, false)[0]
	grip_bone = skeleton.find_bone('b_l_grip' if left_hand else 'b_r_grip')
	assert(grip_bone >= 0, 'The imported hand must retain its authored palm grip bone')
	for mesh: MeshInstance3D in model.find_children('*', 'MeshInstance3D', true, false):
		var source := mesh.mesh.surface_get_material(0) as StandardMaterial3D
		var skin := ShaderMaterial.new()
		skin.shader = MATERIAL_SHADER
		skin.set_shader_parameter('surface_kind', 2)
		skin.set_shader_parameter('tint', source.albedo_color)
		skin.set_shader_parameter('colour_map', SKIN_COLOUR)
		skin.set_shader_parameter('normal_map', SKIN_NORMAL)
		skin.set_shader_parameter('normal_strength', 0.7)
		skin.set_shader_parameter('roughness', 0.62)
		skin.set_shader_parameter('uv_scale', Vector2(3, 3))
		mesh.material_override = skin
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Animated fingers can leave the imported rest-pose bounds.
		mesh.extra_cull_margin = 0.2
	object_grip = Node3D.new()
	object_grip.name = 'PalmGrip'
	controller.add_child.call_deferred(object_grip)
	pose(0, 0)

func pose(squeeze: float, trigger: float) -> void:
	var clip := 'Open'
	var amount := 0.0
	# The fitted per-joint pose closes against the actual handle rather than
	# forcing the entire hand to the endpoint of the generic Grip animation.
	if holding:
		clip = 'Grip'
		amount = 1.0
	elif squeeze > 0.08:
		clip = 'Fist' if trigger > 0.08 else 'Grip'
		amount = maxf(squeeze, trigger)
	elif trigger > 0.08:
		clip = 'Pinch'
		amount = trigger
	if clip != last_pose or absf(amount - last_amount) > 0.002:
		animator.play(clip)
		animator.seek(amount * animator.get_animation(clip).length, true)
		animator.pause()
		last_pose = clip
		last_amount = amount
	if holding:
		var rotations: Dictionary = GRIP_FIT.LEFT_ROTATIONS if left_hand else GRIP_FIT.RIGHT_ROTATIONS
		for bone_name in rotations:
			skeleton.set_bone_pose_rotation(skeleton.find_bone(bone_name), rotations[bone_name])
	skeleton.force_update_all_bone_transforms()
	if object_grip.is_inside_tree():
		object_grip.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(grip_bone)
		if holding:
			object_grip.global_position += controller.global_basis * (GRIP_FIT.LEFT_OFFSET if left_hand else GRIP_FIT.RIGHT_OFFSET)
	visible = controller.get_is_active() and controller.get_has_tracking_data()
