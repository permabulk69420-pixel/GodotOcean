extends Node3D

signal submerged_changed(submerged: bool)

@onready var ocean: AbyssOcean = $Ocean
@onready var player: AbyssSwimmer = $Player
@onready var terrain: AbyssTerrain = $Terrain
@onready var origin: XROrigin3D = $Player/XROrigin3D
@onready var camera: XRCamera3D = $Player/XROrigin3D/Head
@onready var left_controller: XRController3D = $Player/XROrigin3D/LeftHand
@onready var right_controller: XRController3D = $Player/XROrigin3D/RightHand
@onready var world: WorldEnvironment = $Environment
@onready var sun: DirectionalLight3D = $Sun
@onready var sky_sun: DirectionalLight3D = $SkySun
@onready var day_night: AbyssDayNight = $DayNight
@onready var plankton: AbyssPlankton = $Plankton
@onready var mushroom: AbyssMushroom = $Mushroom
@onready var ambience: AbyssAmbience = $Ambience

var cache_bound := false
var xr: XRInterface
var xr_focused := false
var submerged := false
var depth := 0.0
var surface_environment: Environment
var underwater_environment: Environment
var look := Vector2.ZERO

func _ready() -> void:
	ocean.observer = camera
	terrain.observer = camera
	player.ocean = ocean
	player.terrain = terrain
	ocean.wave_cache.start()
	surface_environment = world.environment
	underwater_environment = surface_environment.duplicate(true)
	underwater_environment.sky = surface_environment.sky
	underwater_environment.fog_enabled = true
	underwater_environment.fog_light_color = Color(0.018, 0.22, 0.29)
	underwater_environment.fog_density = 0.026
	underwater_environment.fog_sky_affect = 1.0
	underwater_environment.ambient_light_color = Color(0.06, 0.32, 0.40)
	underwater_environment.ambient_light_energy = 0.38
	day_night.evaluate()
	day_night.apply(sun, sky_sun, surface_environment, underwater_environment, ocean.material, terrain.material, 1.0)
	xr = XRServer.primary_interface
	if not xr or not xr.is_initialized(): xr = XRServer.find_interface("OpenXR")
	if xr and (xr.is_initialized() or (OS.has_feature("android") and xr.initialize())):
		get_viewport().use_xr = true
		# Mobile Vulkan uses XR variable-rate shading for fixed foveated rendering.
		get_viewport().vrs_mode = Viewport.VRS_XR
		if xr.has_method("get_available_display_refresh_rates"):
			var rates = xr.get_available_display_refresh_rates()
			if rates.has(72.0): xr.set_display_refresh_rate(72.0)
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
	player.controls_enabled = false
	get_tree().paused = false

func _on_focused() -> void:
	xr_focused = true
	player.controls_enabled = true
	get_tree().paused = false

func _on_stopping() -> void:
	xr_focused = false
	player.controls_enabled = false
	get_tree().paused = true

func _process(delta: float) -> void:
	day_night.advance(delta)
	day_night.apply(sun, sky_sun, surface_environment, underwater_environment, ocean.material, terrain.material, delta)
	var sources := PackedVector3Array([camera.global_position, left_controller.global_position, right_controller.global_position])
	var boosts := PackedFloat32Array([0.0, 0.0, 0.0])
	for i in range(player.thrusters.motors.size()):
		sources.append(player.thrusters.motors[i].global_position)
		boosts.append(player.thrusters.throttles[i] * 1.5)
	plankton.update(delta, camera.global_position, sources, boosts, day_night.daylight, submerged)
	mushroom.set_daylight(day_night.daylight)
	ambience.update(delta, submerged, player.head_depth, player.thrusters.motors, player.thrusters.throttles)
	if not cache_bound and ocean.wave_cache.ready:
		ocean.material.set_shader_parameter("cached_displacement",ocean.wave_cache.displacement)
		ocean.material.set_shader_parameter("cached_normals",ocean.wave_cache.normals)
		ocean.material.set_shader_parameter("cache_ready",true)
		cache_bound=true

func _physics_process(_delta: float) -> void:
	update_water_state()

func update_water_state() -> void:
	depth = player.head_depth
	var next := submerged
	if depth > 0.08: next = true
	elif depth < -0.08: next = false
	if next != submerged:
		submerged = next
		world.environment = underwater_environment if submerged else surface_environment
		submerged_changed.emit(submerged)
	var energy := day_night.light_energy() * (exp(-maxf(depth, 0.0) * 0.045) if submerged else 1.0)
	if not is_equal_approx(sun.light_energy,energy): sun.light_energy=energy

func release_depth() -> void:
	if is_instance_valid(ocean) and ocean.wave_cache: ocean.wave_cache.release()
	if is_instance_valid(ocean) and is_instance_valid(ocean.surface): ocean.surface.hide()

func _exit_tree() -> void:
	release_depth()
