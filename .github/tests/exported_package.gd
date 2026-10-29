extends SceneTree
func _initialize() -> void: run.call_deferred()
func fail(message: String) -> void:
	push_error(message)
	quit(1)
func run() -> void:
	print('EXPORTED renderer=',ProjectSettings.get_setting('rendering/renderer/rendering_method.android'),' MSAA=',ProjectSettings.get_setting('rendering/anti_aliasing/quality/msaa_3d.android'))
	var index=load('res://terrain/baked/index.tres')
	if not index or index.files.is_empty() or index.files.size()!=index.coordinates.size():
		fail('Exported terrain index is empty or inconsistent')
		return
	print('EXPORTED index: ',index.coordinates.size(),' coordinates; ',index.files.size(),' paths')
	for path in index.files:
		var chunk=load(path)
		if not chunk or not chunk.mesh or not chunk.collision:
			fail('Exported mesh/collision is missing: '+path)
			return
	var world=Node3D.new()
	root.add_child(world)
	var terrain=load('res://terrain/terrain.gd').new()
	world.add_child(terrain)
	var deadline=Time.get_ticks_msec()+15000
	while not terrain.all_ready and Time.get_ticks_msec()<deadline:
		await process_frame
		OS.delay_msec(1)
	if terrain.chunks.size()!=index.coordinates.size() or not terrain.all_ready:
		fail('Exported scene failed to instantiate every terrain chunk')
		return
	for i in range(3): await physics_frame
	var query=PhysicsRayQueryParameters3D.create(Vector3(0,1,8),Vector3(0,-30,8),1)
	var hit=world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		fail('Published game data has no seabed collision beneath the player spawn')
		return
	print('EXPORTED terrain: ',terrain.chunks.size(),' instantiated chunks; seabed beneath spawn=',hit.position)
	world.queue_free()
	await process_frame
	print('EXPORTED PACKAGE: PASS')
	quit()
