extends XRInterfaceExtension
## Headset-free stereo interface for exercising the Quest scene's multiview path.

signal session_visible
signal session_focussed
signal session_stopping

var head_tracker: XRPositionalTracker
var active := false
var head := Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))

func _get_name() -> StringName: return &"Quest stereo preview"
func _get_capabilities() -> int: return XRInterface.XR_VR
func _initialize() -> bool:
	active=true
	head_tracker=XRPositionalTracker.new()
	head_tracker.name=&"head"
	head_tracker.type=XRServer.TRACKER_HEAD
	update_head_pose()
	XRServer.add_tracker(head_tracker)
	return true
func update_head_pose() -> void:
	head_tracker.set_pose(&"default",head,Vector3.ZERO,Vector3.ZERO,XRPose.XR_TRACKING_CONFIDENCE_HIGH)
func _uninitialize() -> void:
	active=false
	if head_tracker: XRServer.remove_tracker(head_tracker)
func _is_initialized() -> bool: return active
func _get_view_count() -> int: return 2
func _get_render_target_size() -> Vector2:
	var size := int(OS.get_environment("OCEAN_TEST_EYE_SIZE")) if OS.has_environment("OCEAN_TEST_EYE_SIZE") else 960
	return Vector2(size,size)
func _get_camera_transform() -> Transform3D: return XRServer.get_reference_frame() * head

func _get_transform_for_view(view: int, world_origin: Transform3D) -> Transform3D:
	var eye := Transform3D(Basis.IDENTITY, Vector3(-0.032 if view == 0 else 0.032, 0, 0))
	return world_origin * XRServer.get_reference_frame() * head * eye

func _get_projection_for_view(view: int, aspect: float, z_near: float, z_far: float) -> PackedFloat64Array:
	var p := Projection.create_perspective(96.0, aspect, z_near, z_far)
	return PackedFloat64Array([p.x.x,p.x.y,p.x.z,p.x.w,p.y.x,p.y.y,p.y.z,p.y.w,p.z.x,p.z.y,p.z.z,p.z.w,p.w.x,p.w.y,p.w.z,p.w.w])

func _pre_draw_viewport(render_target: RID) -> bool: return active

func _post_draw_viewport(render_target: RID, screen_rect: Rect2) -> void:
	for eye in range(2):
		var dst := Rect2i(int(screen_rect.position.x + screen_rect.size.x * eye / 2.0), int(screen_rect.position.y), int(screen_rect.size.x / 2.0), int(screen_rect.size.y))
		add_blit(render_target, Rect2(0, 0, 1, 1), dst, true, eye, false, Vector2.ZERO, 0, 0, 1, 1)
