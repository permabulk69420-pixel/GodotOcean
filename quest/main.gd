extends Node3D
## Standalone Quest entry point. The desktop scene and ImGui are not loaded.

@onready var origin: XROrigin3D = $XROrigin3D
@onready var camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_controller: XRController3D = $XROrigin3D/LeftController
@onready var water: MeshInstance3D = $Water

var xr: OpenXRInterface

func _ready() -> void:
	xr = XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr and (xr.is_initialized() or (OS.has_feature("android") and xr.initialize())):
		get_viewport().use_xr = true
		xr.session_visible.connect(_on_session_visible)
		xr.session_focused.connect(_on_session_focused)
		xr.session_stopping.connect(_on_session_visible)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	elif OS.has_feature("android"):
		push_error("Quest requires an active OpenXR runtime.")
		get_tree().quit(1)
	else:
		# Allows the Quest scene's Mobile renderer/compute path to be checked on PC.
		camera.position.y = 1.6
		print("Quest scene: desktop preview without a headset.")

func _physics_process(delta: float) -> void:
	# Optional smooth movement on the left thumbstick, relative to head direction.
	if left_controller.get_is_active():
		var stick := left_controller.get_vector2("primary")
		if stick.length() > 0.2:
			var forward := -camera.global_basis.z
			forward.y = 0.0
			forward = forward.normalized()
			var right := forward.cross(Vector3.UP)
			origin.global_position += (right * stick.x + forward * stick.y) * delta * 2.0
	# Keep the ocean clipmap centred beneath the tracked headset.
	water.global_position = Vector3(
		floorf(camera.global_position.x / 4.0) * 4.0,
		0.0,
		floorf(camera.global_position.z / 4.0) * 4.0
	)

func _on_session_visible() -> void:
	get_tree().paused = true

func _on_session_focused() -> void:
	get_tree().paused = false
