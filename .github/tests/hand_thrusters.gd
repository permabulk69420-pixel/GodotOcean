extends SceneTree

var failures: Array[String] = []
var fixture: Node3D
var player: ShallowsSwimmer
var xr: XRInterfaceExtension
var trackers: Array[XRControllerTracker] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func frames(count: int = 3) -> void:
	for i in range(count):
		await physics_frame
		await process_frame
func controller(side: int, pose: Transform3D) -> void:
	trackers[side].set_pose(&'grip', pose, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
func place_at_motor(side: int, index: int) -> void:
	var hand := player.thrusters.hands[side]
	var offset := hand.object_grip.global_position - hand.controller.global_position
	var local := player.origin.to_local(player.thrusters.motors[index].global_position - offset)
	controller(side, Transform3D(Basis.IDENTITY, local))

func run() -> void:
	xr = load('res://.github/tests/quest_xr_interface.gd').new()
	XRServer.add_interface(xr)
	xr.initialize()
	XRServer.primary_interface = xr
	root.use_xr = true
	for i in range(2):
		var tracker := XRControllerTracker.new()
		tracker.name = &'left_hand' if i == 0 else &'right_hand'
		tracker.type = XRServer.TRACKER_CONTROLLER
		tracker.set_input(&'primary', Vector2.ZERO)
		tracker.set_input(&'trigger', 0.0)
		tracker.set_input(&'grip', 0.0)
		trackers.append(tracker)
		XRServer.add_tracker(tracker)
		controller(i, Transform3D(Basis.IDENTITY, Vector3(-0.3 if i == 0 else 0.3, 1.2, -0.55)))
	fixture = Node3D.new()
	root.add_child(fixture)
	var scene: Node3D = load('res://game/main.tscn').instantiate()
	player = scene.get_node('Player')
	scene.remove_child(player)
	scene.free()
	fixture.add_child(player)
	player.ocean = AbyssOcean.new()
	player.ocean.settings = AbyssOceanSettings.new()
	player.ocean.build_spectrum()
	player.spawned = true
	player.position = Vector3(0, -5, 0)
	player.set_physics_process(false)
	# Deliver live tracking after XRController3D subscribes to the trackers.
	await frames(1)
	for i in range(2): controller(i, trackers[i].get_pose(&'grip').transform)
	await frames(8)
	var system := player.thrusters
	check(system.motors.size() == 2, 'Two independent world pickups spawn after tracked poses arrive')
	if system.motors.size() != 2:
		quit(1)
		return
	for i in range(2):
		check(system.hands[i].visible, 'Textured hand is visible with its controller active: '+str(system.hands[i].controller.get_is_active())+' tracking='+str(system.hands[i].controller.get_has_tracking_data()))
		var mesh: MeshInstance3D = system.hands[i].find_children('*','MeshInstance3D',true,false)[0]
		var skin := mesh.material_override as ShaderMaterial
		check(skin.get_shader_parameter('colour_map') != null and skin.get_shader_parameter('normal_map') != null and skin.get_shader_parameter('normal_strength') > 0, 'Each imported hand has the skate game colour and normal textures')
		check(system.propellers[i] != null, 'Blender model retains its separately animated impeller')
		place_at_motor(i, i)
	await frames()
	trackers[0].set_input(&'grip', 1.0)
	await frames()
	check(system.held[0] == system.motors[0] and system.held[1] == null, 'Left grip picks up only the nearby left motor')
	check(system.motors[0].global_position.distance_to(system.hands[0].object_grip.global_position) < 0.0001, 'The handle is seated on the animated palm, with no wrist offset')
	trackers[0].set_input(&'trigger', 0.5)
	await frames()
	var half := system.propulsion.length()
	check(absf(half - 0.5) < 0.001, 'Half trigger supplies half thrust')
	trackers[0].set_input(&'trigger', 1.0)
	await frames()
	check(absf(system.propulsion.length() - half * 2.0) < 0.001, 'Trigger throttle is proportional')
	trackers[1].set_input(&'grip', 1.0)
	trackers[1].set_input(&'trigger', 1.0)
	await frames()
	check(system.held[1] == system.motors[1], 'Right hand independently grabs the second motor')
	check(system.propulsion.length() > 1.7, 'Two similarly pointed motors produce more thrust than one')
	var expected := -system.held[0].global_basis.z.normalized() - system.held[1].global_basis.z.normalized()
	check(system.propulsion.distance_to(expected) < 0.0001, 'Acceleration follows the sum of both visible tool axes')
	var angle := system.propellers[0].quaternion
	await frames()
	check(not angle.is_equal_approx(system.propellers[0].quaternion), 'The actual impeller rotates while the trigger is held')
	# Exercise the swimmer's real collision motion, rather than only inspecting vectors.
	player.set_physics_process(true)
	await frames(30)
	player.set_physics_process(false)
	check(player.velocity.length() > 4.0 and player.velocity.length() <= OceanHandThrusters.MAX_SPEED + 0.001, 'Both motors accelerate the real swimmer and obey the speed cap')
	var dropped := system.motors[0].global_transform
	trackers[0].set_input(&'grip', 0.0)
	await frames()
	check(system.held[0] == null and system.held[1] != null, 'Releasing left grip drops only that motor')
	check(system.motors[0].global_transform.is_equal_approx(dropped), 'Dropped motor preserves its world position and orientation')
	var old := trackers[0].get_pose(&'grip').transform
	controller(0, Transform3D(Basis.IDENTITY, old.origin + Vector3(1, 0, 0)))
	await frames()
	check(system.motors[0].global_transform.is_equal_approx(dropped), 'A dropped motor does not follow either hand or player')
	trackers[1].invalidate_pose(&'grip')
	await frames()
	check(system.held[1] == null and system.propulsion.is_zero_approx(), 'Tracking loss releases the tool and stops propulsion')
	place_at_motor(0, 1)
	await frames()
	trackers[0].set_input(&'grip', 1.0)
	await frames()
	check(system.held[0] == system.motors[1] and system.motors[1].get_meta('model_side') == 0, 'Picking up the other motor selects the fitted left-hand mount')
	if system.held[0]:
		var body: MeshInstance3D=system.held[0].find_child('Ceramictitanium',true,false)
		var local_center:=system.held[0].to_local(body.to_global(body.get_aabb().get_center()))
		check(local_center.x<0,'The transferred motor housing is physically outside the left palm')
	trackers[0].set_input(&'grip', 0.0)
	await frames()
	controller(1, Transform3D(Basis.IDENTITY, Vector3(0.3, 1.2, -0.55)))
	trackers[1].set_input(&'grip', 0.0)
	await frames()
	place_at_motor(1, 1)
	await frames()
	trackers[1].set_input(&'grip', 1.0)
	await frames()
	check(system.held[1] != null, 'Released tool can be picked up again')
	check(system.motors[1].get_meta('model_side') == 1, 'Returning the motor to the right hand restores its fitted right-hand mount')
	player.position.y = 12
	await frames()
	check(system.propulsion.is_zero_approx(), 'Thrusters do not produce propulsion out of water')
	player.controls_enabled = false
	await frames()
	check(system.held[1] == null and system.propulsion.is_zero_approx(), 'Loss of session focus releases tools and stops their input')
	print('Hand thrusters: ', 'PASS' if failures.is_empty() else 'FAIL', '; textured palms, independent grips, throttle, thrust, real swimming, release, tracking and focus loss')
	var ocean := player.ocean
	fixture.queue_free()
	await process_frame
	ocean.free()
	root.use_xr = false
	XRServer.primary_interface = null
	for tracker in trackers: XRServer.remove_tracker(tracker)
	xr.uninitialize()
	XRServer.remove_interface(xr)
	quit(0 if failures.is_empty() else 1)
