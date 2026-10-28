extends SceneTree
var scene: Node3D
var stereo: XRInterfaceExtension
var failures: Array[String]=[]
var capture_dir := '/tmp/abyss-runtime'
var frame_times: Array[float]=[]
var left: XRPositionalTracker
var right: XRPositionalTracker
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func frames(count: int) -> void:
	for i in range(count):
		var before:=Time.get_ticks_usec()
		await process_frame
		await RenderingServer.frame_post_draw
		frame_times.append((Time.get_ticks_usec()-before)/1000.0)
func controller(tracker_name: StringName) -> XRPositionalTracker:
	var tracker:=XRControllerTracker.new()
	tracker.type=XRServer.TRACKER_CONTROLLER
	tracker.name=tracker_name
	tracker.set_pose(&'default',Transform3D(Basis.IDENTITY,Vector3(0,1,-0.3)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	tracker.set_input(&'primary',Vector2.ZERO)
	XRServer.add_tracker(tracker)
	return tracker
func capture(name: String) -> void:
	var img:=root.get_texture().get_image()
	check(not img.is_empty(),'Rendered view must contain pixels')
	var dark:=0
	for y in range(0,img.get_height(),16):
		for x in range(0,img.get_width(),16):
			var c:=img.get_pixel(x,y)
			if c.r+c.g+c.b<0.006: dark+=1
	check(dark<20,'Rendered view must not contain large black rectangles')
	img.save_png(capture_dir.path_join(name+'.png'))
func run() -> void:
	if OS.has_environment('OCEAN_CAPTURE_DIR'): capture_dir=OS.get_environment('OCEAN_CAPTURE_DIR')
	DirAccess.make_dir_recursive_absolute(capture_dir)
	root.msaa_3d=Viewport.MSAA_4X
	if OS.get_environment('OCEAN_STEREO')!='0':
		stereo=load('res://.github/tests/quest_xr_interface.gd').new()
		XRServer.add_interface(stereo)
		check(stereo.initialize(),'Simulated VR initializes')
		XRServer.primary_interface=stereo
		root.use_xr=true
		left=controller(&'left_hand')
		right=controller(&'right_hand')
	scene=load('res://ocean/main.tscn').instantiate()
	root.add_child(scene)
	check(scene.ocean.surface.visible,'Water is visible before refraction depth arrives')
	check(not scene.has_node('Reef'),'Ocean contains no scenery')
	if stereo:
		scene.connect_xr_lifecycle(stereo)
		stereo.emit_signal(&'session_focussed')
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	await frames(4)
	check(scene.ocean.is_processing() and scene.is_physics_processing(),'Real simulation and movement remain enabled')
	check(scene.ocean.simulation_time>0,'Waves advance in time')
	check(scene.cache_bound,'Shared GPU wave geometry reaches the material')
	check(scene.ocean.surface.visible,'Water remains visible after startup')
	capture('surface')
	var cache: AbyssWaveCache=scene.ocean.wave_cache
	var image:=cache.displacement.get_image()
	var params:=cache.last_parameters.duplicate()
	var vertices: PackedVector3Array=scene.ocean.surface.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var maximum_error:=0.0
	for i in range(0,60000,3000):
		var v:=vertices[i]
		var expected: Vector3=scene.ocean.displacement_at(Vector2(v.x+params[0],v.z+params[1]),params[2])
		var pixel:=image.get_pixel(i%1024,i/1024)
		maximum_error=maxf(maximum_error,expected.distance_to(Vector3(pixel.r,pixel.g,pixel.b)))
	print('Actual cached GPU displacement maximum error: ',maximum_error,' m')
	check(maximum_error<0.008,'Rendered wave geometry agrees with gameplay queries')
	var first_time: float=scene.ocean.simulation_time
	# Exercise refraction failure while the live water continues drawing.
	scene.depth_active=false
	scene.ocean.material.set_shader_parameter('depth_available',false)
	await frames(2)
	check(scene.ocean.surface.visible,'Depth failure cannot hide the ocean')
	capture('depth-fallback')
	scene.depth_active=true
	if stereo:
		check(right!=null and scene.right_controller.get_is_active(),'Tracked controller is active')
		var initial: Vector3=scene.origin.position
		left.set_input(&'primary',Vector2(1,0))
		await frames(2)
		left.set_input(&'primary',Vector2.ZERO)
		check(scene.origin.position.x>initial.x,'Left stick strafes the real player')
		# Accelerate elapsed simulation time; normal physics and controller movement stay active.
		Engine.time_scale=6.0
		right.set_input(&'primary',Vector2(0,-1))
		var descent_frames:=0
		while scene.depth<2.0 and descent_frames<90:
			await frames(1)
			descent_frames+=1
		right.set_input(&'primary',Vector2.ZERO)
		check(scene.depth>=2.0 and scene.submerged,'Controller swimming reaches at least two metres beneath the moving water')
		check(scene.origin.position.y<initial.y,'Controller input moved the player downward')
		print('Controller dive: ',descent_frames,' frames; head=',scene.camera.global_position,' depth=',scene.depth)
	else:
		scene.origin.position.y=-5
	await frames(2)
	check(scene.submerged,'Live diving enters underwater rendering')
	check(scene.world.environment==scene.underwater_environment,'Underwater absorption activates')
	capture('underwater')
	if stereo:
		right.set_input(&'primary',Vector2(0,1))
		var ascent_frames:=0
		while (scene.camera.global_position.y<1.6 or scene.submerged) and ascent_frames<90:
			await frames(1)
			ascent_frames+=1
		right.set_input(&'primary',Vector2.ZERO)
		print('Controller resurfacing: ',ascent_frames,' frames; head=',scene.camera.global_position,' depth=',scene.depth)
		Engine.time_scale=1.0
	else:
		scene.origin.position.y=1
	await frames(2)
	check(not scene.submerged,'Controller swimming resurfaces above the moving water')
	capture('resurfaced')
	check(scene.ocean.simulation_time>first_time,'Simulation continues throughout movement and diving')
	if stereo:
		stereo.emit_signal(&'session_stopping')
		check(paused,'XR stopping pauses the session')
		stereo.emit_signal(&'session_visible')
		check(not paused,'Visible XR resumes the real session')
		stereo.emit_signal(&'session_focussed')
	frame_times.sort()
	print('Live frames: ',frame_times.size(),'; median software-renderer frame time: ',frame_times[frame_times.size()/2],' ms; not a Quest GPU measurement')
	scene.release_depth()
	root.use_xr=false
	XRServer.primary_interface=null
	if stereo:
		XRServer.remove_tracker(left)
		XRServer.remove_tracker(right)
		stereo.uninitialize()
		XRServer.remove_interface(stereo)
	RenderingServer.force_sync()
	print('Abyss live runtime: ','PASS' if failures.is_empty() else 'FAIL')
	quit(0 if failures.is_empty() else 1)
