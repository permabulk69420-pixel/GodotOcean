class_name AbyssBuoyantBody
extends RigidBody3D

@export var ocean: AbyssOcean
@export var displacement_volume := 0.25
@export var fluid_density := 1025.0
@export var linear_water_drag := 2.0
@export var angular_water_drag := 2.5
@export var float_points := PackedVector3Array([Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5)])

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not ocean or float_points.is_empty(): return
	var immersion := 0.0
	for point in float_points:
		var world_point := state.transform * point
		var sample := ocean.sample_surface(world_point)
		var submerged := clampf(float(sample.height) - world_point.y, 0.0, 1.0)
		immersion += submerged / float_points.size()
		var force := Vector3.UP * submerged * fluid_density * ocean.GRAVITY * displacement_volume / float_points.size()
		state.apply_force(force, world_point - state.transform.origin)
	state.apply_central_force(-state.linear_velocity * linear_water_drag * mass * immersion)
	state.apply_torque(-state.angular_velocity * angular_water_drag * mass * immersion)
