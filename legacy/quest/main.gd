extends Node3D
## Standalone Quest entry point. The desktop scene and ImGui are not loaded.

@onready var origin: XROrigin3D = $XROrigin3D
@onready var camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var left_controller: XRController3D = $XROrigin3D/LeftController
@onready var water: MeshInstance3D = $Water

var xr: OpenXRInterface
var xr_has_focus := false

func _ready() -> void:
	xr = XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr and (xr.is_initialized() or (OS.has_feature("android") and xr.initialize())):
		get_viewport().use_xr = true
		_connect_xr_signals(xr)
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
	if xr_has_focus and left_controller.get_is_active():
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

func _connect_xr_signals(interface: XRInterface) -> void:
	interface.connect(&"session_visible", _on_session_visible)
	# Godot 4.3 spells this signal with two s characters.
	interface.connect(&"session_focussed", _on_session_focused)
	interface.connect(&"session_stopping", _on_session_stopping)

func _on_session_visible() -> void:
	# Visible XR frames need animated water, even before input focus arrives.
	xr_has_focus = false
	get_tree().paused = false

func _on_session_focused() -> void:
	xr_has_focus = true
	get_tree().paused = false

func _on_session_stopping() -> void:
	xr_has_focus = false
	get_tree().paused = true
