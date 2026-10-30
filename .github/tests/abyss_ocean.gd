extends SceneTree
var scene: Node3D
var stereo: XRInterfaceExtension
var failures: Array[String]=[]
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
	tracker.set_pose(&'grip',Transform3D(Basis.IDENTITY,Vector3(-0.25 if tracker_name==&'left_hand' else 0.25,1,-0.3)),Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	tracker.set_input(&'primary',Vector2.ZERO)
	XRServer.add_tracker(tracker)
	return tracker
func reach_motor(side: int, tracker: XRPositionalTracker) -> void:
	var hand: AbyssVRHand=scene.player.thrusters.hands[side]
	var motor: Node3D=scene.player.thrusters.motors[side]
	var offset: Vector3=hand.object_grip.global_position-hand.controller.global_position
	var pose:=Transform3D(Basis.IDENTITY,scene.origin.to_local(motor.global_position-offset))
	tracker.set_pose(&'grip',pose,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
func run() -> void:
	root.msaa_3d=Viewport.MSAA_4X
	if OS.get_environment('OCEAN_STEREO')!='0':
		stereo=load('res://.github/tests/quest_xr_interface.gd').new()
		XRServer.add_interface(stereo)
		check(stereo.initialize(),'Simulated VR initializes')
		XRServer.primary_interface=stereo
		root.use_xr=true
		left=controller(&'left_hand')
		right=controller(&'right_hand')
	scene=load('res://game/main.tscn').instantiate()
	root.add_child(scene)
	if stereo:
		for tracker in [left, right]:
			tracker.set_pose(&'grip',tracker.get_pose(&'grip').transform,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	check(scene.ocean.surface.visible,'Water is visible before refraction depth arrives')
	check(not scene.has_node('Reef'),'Ocean contains no scenery')
	if stereo:
		stereo.emit_signal(&'session_focussed')
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for i in range(180):
		if scene.terrain.near_ready: break
		await frames(1)
	check(scene.terrain.near_ready,"Nearby terrain collision must load before swimming")
	await frames(4)
	check(scene.ocean.is_processing() and scene.is_physics_processing(),'Real simulation and movement remain enabled')
	check(scene.ocean.simulation_time>0,'Waves advance in time')
	check(scene.cache_bound,'Shared GPU wave geometry reaches the material')
	check(scene.ocean.surface.visible,'Water remains visible after startup')
	check(scene.terrain.chunks.size()>0,'The real scene contains loaded terrain meshes and collision')
	var first_time: float=scene.ocean.simulation_time
	var shader_code: String=scene.ocean.material.shader.code
	check(not 'hint_screen_texture' in shader_code and not 'hint_depth_texture' in shader_code,'Opaque water must not force full-screen color or depth copies')
	check(scene.world.compositor==null,'The mobile tile pass must not contain compositor breaks')
	if stereo:
		check(right!=null and scene.right_controller.get_is_active(),'Tracked controller is active')
		check(scene.player.thrusters.motors.size()==2,'Both Blender thrusters are instantiated in the rendered game')
		reach_motor(0,left)
		reach_motor(1,right)
		await frames(2)
		left.set_input(&'grip',1.0)
		right.set_input(&'grip',1.0)
		await frames(2)
		check(scene.player.thrusters.held[0]!=null and scene.player.thrusters.held[1]!=null,'Both rendered hands independently pick up the motors')
		var initial: Vector3=scene.player.global_position
		left.set_input(&'primary',Vector2(1,0))
		await frames(2)
		left.set_input(&'primary',Vector2.ZERO)
		check(scene.player.global_position.x>initial.x,'Left stick strafes the real player')
		# Accelerate elapsed simulation time; normal physics and controller movement stay active.
		Engine.time_scale=6.0
		right.set_input(&'primary',Vector2(0,-1))
		var descent_frames:=0
		while scene.depth<2.0 and descent_frames<90:
			await frames(1)
			descent_frames+=1
		right.set_input(&'primary',Vector2.ZERO)
		check(scene.depth>=2.0 and scene.submerged,'Controller swimming reaches at least two metres beneath the moving water')
		check(scene.player.global_position.y<initial.y,'Controller input moved the player downward')
		print('Controller dive: ',descent_frames,' frames; head=',scene.camera.global_position,' depth=',scene.depth)
	else:
		scene.player.global_position.y=-5
	await frames(2)
	check(scene.submerged,'Live diving enters underwater rendering')
	check(scene.world.environment==scene.underwater_environment,'Underwater absorption activates')
	if stereo:
		left.set_input(&'trigger',0.6)
		right.set_input(&'trigger',0.6)
		await frames(3)
		check(scene.player.thrusters.propulsion.length()>0.9,'Both trigger throttles drive live underwater propulsion')
		left.set_input(&'trigger',0.0)
		right.set_input(&'trigger',0.0)
		left.set_input(&'grip',0.0)
		await frames(2)
		check(scene.player.thrusters.held[0]==null and scene.player.thrusters.held[1]!=null,'Dropping one rendered motor leaves the other hand holding its own')
		right.set_input(&'primary',Vector2(0,1))
		var ascent_frames:=0
		while (scene.player.submerged or scene.player.head_depth> -0.12) and ascent_frames<90:
			await frames(1)
			ascent_frames+=1
		right.set_input(&'primary',Vector2.ZERO)
		print('Controller resurfacing: ',ascent_frames,' frames; head=',scene.camera.global_position,' depth=',scene.depth)
		var initial_yaw: float=scene.player.rotation.y
		right.set_input(&'primary',Vector2(0.7,0))
		await frames(5)
		right.set_input(&'primary',Vector2.ZERO)
		check(absf(scene.player.rotation.y-initial_yaw)>0.1,'Right stick provides smooth turning')
		Engine.time_scale=1.0
	else:
		scene.player.global_position.y=1
	await frames(2)
	check(not scene.submerged,'Controller swimming resurfaces above the moving water')
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
