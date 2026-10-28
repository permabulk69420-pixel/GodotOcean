extends Node3D

signal submerged_changed(submerged: bool)

@onready var ocean: AbyssOcean = $Ocean
@onready var origin: XROrigin3D = $Player
@onready var camera: XRCamera3D = $Player/Head
@onready var left_controller: XRController3D = $Player/LeftHand
@onready var right_controller: XRController3D = $Player/RightHand
@onready var world: WorldEnvironment = $Environment
@onready var sun: DirectionalLight3D = $Sun

var depth_capture: AbyssDepthCapture
var depth_active := true
var xr: XRInterface
var xr_focused := false
var submerged := false
var depth := 0.0
var surface_environment: Environment
var underwater_environment: Environment
var look := Vector2.ZERO

func _ready() -> void:
	ocean.observer = camera
	depth_capture = AbyssDepthCapture.new()
	# Wait for the first resolved depth texture before drawing refractive water.
	ocean.surface.hide()
	var compositor := Compositor.new()
	compositor.compositor_effects = [depth_capture]
	world.compositor = compositor
	surface_environment = world.environment
	underwater_environment = surface_environment.duplicate(true)
	underwater_environment.fog_enabled = true
	underwater_environment.fog_light_color = Color(0.018, 0.22, 0.29)
	underwater_environment.fog_density = 0.026
	underwater_environment.fog_sky_affect = 1.0
	underwater_environment.ambient_light_color = Color(0.06, 0.32, 0.40)
	underwater_environment.ambient_light_energy = 0.38
	underwater_environment.volumetric_fog_enabled = true
	underwater_environment.volumetric_fog_density = 0.012
	underwater_environment.volumetric_fog_albedo = Color(0.12, 0.42, 0.49)
	xr = XRServer.find_interface("OpenXR")
	if xr and (xr.is_initialized() or (OS.has_feature("android") and xr.initialize())):
		get_viewport().use_xr = true
		connect_xr_lifecycle(xr)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	elif OS.has_feature("android"):
		push_error("An initialized OpenXR runtime is required on Quest.")
		get_tree().quit(1)
	else:
		camera.position.y = 1.6
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func connect_xr_lifecycle(interface: XRInterface) -> void:
	interface.connect(&"session_visible", _on_visible)
	interface.connect(&"session_focussed", _on_focused)
	interface.connect(&"session_stopping", _on_stopping)

func _on_visible() -> void:
	xr_focused = false
	get_tree().paused = false

func _on_focused() -> void:
	xr_focused = true
	get_tree().paused = false

func _on_stopping() -> void:
	xr_focused = false
	get_tree().paused = true

func _process(delta: float) -> void:
	if not depth_active or not depth_capture.depth_rid.is_valid(): return
	var texture: Texture = depth_capture.stereo_depth if depth_capture.stereo_mode else depth_capture.mono_depth
	if not texture.get_rid().is_valid(): return
	if not ocean.surface.visible:
		var parameter := "ocean_depth_stereo" if depth_capture.stereo_mode else "ocean_depth_mono"
		ocean.material.set_shader_parameter(parameter, texture)
		ocean.material.set_shader_parameter("stereo_depth_enabled", depth_capture.stereo_mode)
		ocean.surface.show()

func _unhandled_input(event: InputEvent) -> void:
	if get_viewport().use_xr: return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look.x -= event.relative.x * 0.002
		look.y = clampf(look.y - event.relative.y * 0.002, -1.45, 1.45)
		origin.rotation.y = look.x
		camera.rotation.x = look.y
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var movement := Vector3.ZERO
	if get_viewport().use_xr:
		if xr_focused and left_controller.get_is_active():
			var stick := left_controller.get_vector2("primary")
			movement += camera.global_basis.x * stick.x - camera.global_basis.z * stick.y
		if xr_focused and right_controller.get_is_active():
			movement.y += right_controller.get_vector2("primary").y
	else:
		movement += camera.global_basis.x * (float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)))
		movement -= camera.global_basis.z * (float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)))
		movement.y += float(Input.is_physical_key_pressed(KEY_SPACE)) - float(Input.is_physical_key_pressed(KEY_CTRL))
	if movement.length_squared() > 0.01:
		origin.global_position += movement.limit_length() * delta * (3.2 if submerged else 2.2)
	update_water_state()

func update_water_state() -> void:
	var sample := ocean.sample_surface(camera.global_position)
	depth = float(sample.height) - camera.global_position.y
	var next := submerged
	if depth > 0.08: next = true
	elif depth < -0.08: next = false
	if next != submerged:
		submerged = next
		world.environment = underwater_environment if submerged else surface_environment
		submerged_changed.emit(submerged)
	if submerged:
		sun.light_energy = 1.6 * exp(-maxf(depth, 0.0) * 0.045)
	else:
		sun.light_energy = 1.6

func release_depth() -> void:
	depth_active = false
	if is_instance_valid(ocean) and is_instance_valid(ocean.surface):
		ocean.surface.hide()
		ocean.material.set_shader_parameter("ocean_depth_mono", null)
		ocean.material.set_shader_parameter("ocean_depth_stereo", null)
	if is_instance_valid(world): world.compositor = null
	if depth_capture:
		depth_capture.mono_depth.texture_rd_rid = RID()
		depth_capture.stereo_depth.texture_rd_rid = RID()

func _exit_tree() -> void:
	release_depth()
