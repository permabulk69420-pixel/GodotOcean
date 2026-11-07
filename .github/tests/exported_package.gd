extends SceneTree
func _initialize() -> void: run.call_deferred()
func fail(message: String) -> void:
	push_error(message)
	quit(1)
func run() -> void:
	print('EXPORTED renderer=',ProjectSettings.get_setting('rendering/renderer/rendering_method.android'),' MSAA=',ProjectSettings.get_setting('rendering/anti_aliasing/quality/msaa_3d.android'))
	var index=load('res://world/terrain/baked/index.tres')
	if not index or index.batches.is_empty() or index.surface_blocks.is_empty():
		fail('Exported terrain index is empty')
		return
	print('EXPORTED index: ',index.batches.size(),' batches; ',index.surface_blocks.size(),' blocks with surface')
	for c in index.batches:
		var batch=load('res://world/terrain/baked/batch_%s_%s_%s.res'%[c.x,c.y,c.z])
		if not batch or batch.kinds.size()!=64:
			fail('Exported terrain batch is missing or broken: %s'%c)
			return
	var world=Node3D.new()
	root.add_child(world)
	var eye=Node3D.new()
	world.add_child(eye)
	eye.position=Vector3(0,-2,8)
	var terrain=load('res://world/terrain/terrain.gd').new()
	terrain.observer=eye
	world.add_child(terrain)
	if terrain.store.index==null:
		fail('Exported terrain voxels do not match the generator')
		return
	var deadline=Time.get_ticks_msec()+20000
	while not (terrain.all_ready and terrain.near_ready) and Time.get_ticks_msec()<deadline:
		await process_frame
		OS.delay_msec(1)
	if not terrain.all_ready or terrain.chunks.is_empty():
		fail('Exported scene failed to stream in the terrain around the spawn')
		return
	for i in range(3): await physics_frame
	var query=PhysicsRayQueryParameters3D.create(Vector3(0,1,8),Vector3(0,-30,8),1)
	var hit=world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		fail('Published game data has no seabed collision beneath the player spawn')
		return
	print('EXPORTED terrain: ',terrain.chunks.size(),' blocks streamed in; seabed beneath spawn=',hit.position)
	# Instantiate the actual exported hand scenes and compiled interaction scripts.
	var scene=load('res://game/main.tscn').instantiate()
	var player=scene.get_node('Player')
	scene.remove_child(player)
	scene.free()
	world.add_child(player)
	await process_frame
	for hand in player.thrusters.hands:
		var mesh=hand.find_children('*','MeshInstance3D',true,false)[0]
		if hand.grip_bone<0 or not mesh.material_override.get_shader_parameter('colour_map') or not mesh.material_override.get_shader_parameter('normal_map'):
			fail('Exported hand is missing its textured skin or palm grip')
			return
	player.thrusters.spawn_motors()
	if player.thrusters.motors.size()!=2 or not player.thrusters.propellers[0] or not player.thrusters.propellers[1]:
		fail('Exported handheld thruster model or impeller is missing')
		return
	print('EXPORTED hands/thrusters: both textured hand rigs and two complete Blender motors instantiated')
	world.queue_free()
	await process_frame
	print('EXPORTED PACKAGE: PASS')
	quit()
