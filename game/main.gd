extends Node3D

signal submerged_changed(submerged: bool)

## Render scale for the headset: the Quest's default is more pixels than this scene's shaders can fill at 72 Hz.
const XR_RENDER_SCALE := 0.8
## The headset's refresh rate (the Quest 3 offers 72, 80, 90 and 120). Every frame then has 1000 / rate milliseconds.
const XR_REFRESH_RATE := 90.0
## How soon meshes that have simpler versions (the reef, the mushroom, the seagrass) drop to them: Godot's default is 1.
const XR_LOD_THRESHOLD := 3.0
## Underwater the fog has all but hidden anything past this, so the camera stops drawing there.
const UNDERWATER_FAR := 150.0
const UNDERWATER_SKY_SHADER := preload("res://world/ocean/shaders/underwater_sky.gdshader")
const WATER_UNDERSIDE_SHADER := preload("res://world/ocean/shaders/underside.gdshader")
const PHYSICAL_SKY_GL_SHADER := preload("res://world/physical_sky_gl.gdshader")

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
@onready var reef: AbyssReef = $Reef
@onready var seagrass: Node3D = $Seagrass
@onready var ambience: AbyssAmbience = $Ambience
@onready var light_shafts: AbyssLightShafts = $LightShafts

var cache_bound := false
var xr: XRInterface
var xr_focused := false
var submerged := false
var seabed_shown := true
var surface_far := 6000.0
## The watch's performance test steps this: 0 everything shown, 1 no terrain, 2 no reef, 3 no seagrass, 4 none of them.
var seabed_test := 0
## The water surface. 0 (the default) draws it lit above the water and, below it, with its own cheap underside shader
## (world/ocean/shaders/underside.gdshader). The rest are for the watch's performance test: 1 the old underside, unlit (what
## 0 used to be); 2 the old shader lit always; 3 the same mesh with a one-line shader (what the shape alone costs); 4 hidden.
var water_test := 0
var water_shader: Shader
var water_unlit_shader: Shader
var water_shape_shader: Shader
var water_underside_shader: Shader = WATER_UNDERSIDE_SHADER
## True while the watch panel is open, so the time of day stays put while its numbers are read.
var freeze_time := false
## The terrain is drawn as a normal opaque surface. The watch's performance test can swap the old version back in (it wrote
## ALPHA, which sent it down the transparent path) to compare what that cost.
var terrain_transparent_test := false
var terrain_shader: Shader
var terrain_old_shader: Shader
var depth := 0.0
var surface_environment: Environment
var underwater_environment: Environment
var underwater_sky: ShaderMaterial
var look := Vector2.ZERO

func _ready() -> void:
	surface_far = camera.far
	ocean.observer = camera
	terrain.observer = camera
	player.ocean = ocean
	player.terrain = terrain
	ocean.wave_cache.start()
	surface_environment = world.environment
	if not RenderingServer.get_rendering_device(): use_gl_sky(surface_environment.sky)
	underwater_environment = surface_environment.duplicate(true)
	# Under the water the "sky" is the water itself: a gradient from bright above to dark below
	# (world/ocean/shaders/underwater_sky.gdshader). The fog takes its colour from it (aerial
	# perspective), and it lights the scene from above as ambient light.
	underwater_sky = ShaderMaterial.new()
	underwater_sky.shader = UNDERWATER_SKY_SHADER
	var water_sky := Sky.new()
	water_sky.sky_material = underwater_sky
	# A small lighting copy refiltered in one go, so the fog and the open water always change in the
	# same frame (spreading it over several frames shows a band at the horizon while it catches up).
	water_sky.radiance_size = Sky.RADIANCE_SIZE_64
	water_sky.process_mode = Sky.PROCESS_MODE_QUALITY
	underwater_environment.sky = water_sky
	underwater_environment.fog_aerial_perspective = 1.0
	RenderingServer.global_shader_parameter_set(&"water_surface_height", ocean.sea_level)
	underwater_environment.fog_enabled = true
	underwater_environment.fog_light_color = Color(0.018, 0.22, 0.29)
	underwater_environment.fog_density = 0.026
	underwater_environment.fog_sky_affect = 1.0
	underwater_environment.ambient_light_color = Color(0.06, 0.32, 0.40)
	underwater_environment.ambient_light_energy = 0.38
	build_water_shaders()
	day_night.evaluate()
	day_night.apply(sun, sky_sun, surface_environment, underwater_environment, ocean.material, terrain.material, 1.0, 0.0, underwater_sky)
	xr = XRServer.primary_interface
	if not xr or not xr.is_initialized(): xr = XRServer.find_interface("OpenXR")
	if xr and (xr.is_initialized() or (OS.has_feature("android") and xr.initialize())):
		get_viewport().use_xr = true
		get_viewport().scaling_3d_scale = XR_RENDER_SCALE
		get_viewport().mesh_lod_threshold = XR_LOD_THRESHOLD
		if RenderingServer.get_rendering_device():
			# Mobile Vulkan uses XR variable-rate shading for fixed foveated rendering.
			get_viewport().vrs_mode = Viewport.VRS_XR
			# The default strength is 1.0; higher shades more of the outer view coarsely.
			if "vrs_strength" in xr: xr.set("vrs_strength", 2.0)
		else:
			# The Compatibility (OpenGL) renderer uses the headset's own fixed foveation instead: 3 is the strongest,
			# the nearest to the Vulkan strength above. Not dynamic, so it does not change under the performance tests.
			if "foveation_level" in xr: xr.set("foveation_level", 3)
			if "foveation_dynamic" in xr: xr.set("foveation_dynamic", false)
		if xr.has_method("get_available_display_refresh_rates"):
			var rates = xr.get_available_display_refresh_rates()
			if rates.has(XR_REFRESH_RATE): xr.set_display_refresh_rate(XR_REFRESH_RATE)
			elif rates.has(72.0): xr.set_display_refresh_rate(72.0)
		# Unless the game asks, the headset runs its GPU at a middle speed. Boost lets it go beyond what it can sustain
		# thermally; the headset slows itself down again if it gets too hot. If it throttles after a few minutes, use
		# PERF_SETTINGS_LEVEL_SUSTAINED_HIGH instead.
		if xr.has_method("set_gpu_level"): xr.set_gpu_level(OpenXRInterface.PERF_SETTINGS_LEVEL_BOOST)
		connect_xr_lifecycle(xr)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	elif OS.has_feature("android"):
		push_error("An initialized OpenXR runtime is required on Quest.")
		get_tree().quit(1)
	else:
		camera.position.y = 1.6
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## The Compatibility (OpenGL) renderer cannot draw the built-in PhysicalSkyMaterial in the right colours (see
## world/physical_sky_gl.gdshader), so there the same sky is drawn by a copy of its shader with the same settings.
func use_gl_sky(sky: Sky) -> void:
	var physical := sky.sky_material as PhysicalSkyMaterial
	if physical == null: return
	var copy := ShaderMaterial.new()
	copy.shader = PHYSICAL_SKY_GL_SHADER
	copy.set_shader_parameter("rayleigh", physical.rayleigh_coefficient)
	copy.set_shader_parameter("rayleigh_color", physical.rayleigh_color)
	copy.set_shader_parameter("mie", physical.mie_coefficient)
	copy.set_shader_parameter("mie_eccentricity", physical.mie_eccentricity)
	copy.set_shader_parameter("mie_color", physical.mie_color)
	copy.set_shader_parameter("turbidity", physical.turbidity)
	copy.set_shader_parameter("sun_disk_scale", physical.sun_disk_scale)
	copy.set_shader_parameter("ground_color", physical.ground_color)
	copy.set_shader_parameter("exposure", physical.energy_multiplier)
	sky.sky_material = copy

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
	if not freeze_time: day_night.advance(delta)
	day_night.apply(sun, sky_sun, surface_environment, underwater_environment, ocean.material, terrain.material, delta, maxf(player.head_depth, 0.0) if submerged else 0.0, underwater_sky)
	var sources := PackedVector3Array([camera.global_position, left_controller.global_position, right_controller.global_position])
	var boosts := PackedFloat32Array([0.0, 0.0, 0.0])
	for i in range(player.thrusters.motors.size()):
		sources.append(player.thrusters.motors[i].global_position)
		boosts.append(player.thrusters.throttles[i] * 1.5)
	plankton.update(delta, camera.global_position, sources, boosts, day_night.daylight, submerged)
	light_shafts.update(camera.global_position, day_night.daylight, submerged)
	mushroom.set_daylight(day_night.daylight)
	ocean.window_sky.bake(day_night.sun_direction, day_night.daylight)
	reef.set_daylight(day_night.daylight)
	ambience.update(delta, submerged, player.head_depth, player.thrusters.motors, player.thrusters.throttles)
	if not cache_bound and ocean.wave_cache.ready:
		ocean.material.set_shader_parameter("cached_displacement",ocean.wave_cache.displacement)
		ocean.material.set_shader_parameter("cached_normals",ocean.wave_cache.normals)
		ocean.material.set_shader_parameter("cached_normal_row",ocean.wave_cache.normal_row)
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
		apply_water_shader()
		camera.far = UNDERWATER_FAR if submerged else surface_far
	# The water is opaque and the seabed lies well below it, so from above nothing down there can be
	# seen. Skip drawing it then. The thresholds differ so the head bobbing at the surface cannot
	# flicker it, and sit above the submerge point so it is back before the head goes under.
	var show_seabed := seabed_shown
	if depth > -0.15: show_seabed = true
	elif depth < -0.3: show_seabed = false
	if show_seabed != seabed_shown:
		seabed_shown = show_seabed
		apply_seabed_visibility()
	# The colour absorption in day_night.gd already dims the light with depth; this is the rest.
	var energy := day_night.light_energy() * (exp(-maxf(depth, 0.0) * 0.02) if submerged else 1.0)
	if not is_equal_approx(sun.light_energy,energy): sun.light_energy=energy

## Builds the old unlit underwater version and the shape-only test version from the water shader's own code.
func build_water_shaders() -> void:
	water_shader = ocean.material.shader
	var code := water_shader.code
	var light_start := code.find("// Godot's Mobile renderer runs its built-in light maths")
	water_shape_shader = Shader.new()
	water_shape_shader.code = code.substr(0, code.find("void fragment() {")) + "void fragment() { ALBEDO = vec3(0.0); EMISSION = vec3(0.02, 0.10, 0.12); ROUGHNESS = 1.0; }\n"
	# Unlit: the shader already works out the whole colour as emission, so draw that and nothing else.
	water_unlit_shader = Shader.new()
	water_unlit_shader.code = code.substr(0, light_start) \
		.replace("render_mode world_vertex_coords, cull_disabled, depth_draw_opaque;", "render_mode world_vertex_coords, cull_disabled, depth_draw_opaque, unshaded;") \
		.replace("	METALLIC = 0.0;\n}", "	METALLIC = 0.0;\n	ALBEDO = EMISSION;\n	EMISSION = vec3(0.0);\n}")
	# Draw the underwater version once, a speck in front of the camera, so the engine builds it now and not on the first dive.
	var warm := MeshInstance3D.new()
	warm.mesh = ocean.surface.mesh
	warm.custom_aabb = ocean.surface.custom_aabb
	warm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var warm_material := ShaderMaterial.new()
	warm_material.shader = water_underside_shader
	warm.material_override = warm_material
	camera.add_child(warm)
	warm.position = Vector3(0.0, 0.0, -1.0)
	warm.scale = Vector3.ONE * 0.000001
	get_tree().create_timer(1.0).timeout.connect(warm.queue_free)

## Picks the water's shader and visibility for the current state.
func apply_water_shader() -> void:
	ocean.surface.visible = water_test != 4
	var shader := water_shader
	if water_test == 0 and submerged: shader = water_underside_shader
	elif water_test == 1 and submerged: shader = water_unlit_shader
	elif water_test == 3: shader = water_shape_shader
	if ocean.material.shader != shader: ocean.material.shader = shader

func set_water_test(mode: int) -> void:
	water_test = mode
	apply_water_shader()

func set_seabed_test(mode: int) -> void:
	seabed_test = mode
	apply_seabed_visibility()

func set_terrain_transparent_test(on: bool) -> void:
	if terrain_shader == null:
		terrain_shader = terrain.material.shader
		terrain_old_shader = Shader.new()
		terrain_old_shader.code = terrain_shader.code.replace('render_mode world_vertex_coords;', 'render_mode world_vertex_coords, depth_draw_always;').replace(' specular_level = SPECULAR;', ' specular_level = SPECULAR;\n ALPHA=1.0;')
	terrain_transparent_test = on
	terrain.material.shader = terrain_old_shader if on else terrain_shader

func apply_seabed_visibility() -> void:
	terrain.visible = seabed_shown and seabed_test != 1 and seabed_test != 4
	reef.visible = seabed_shown and seabed_test != 2 and seabed_test != 4
	seagrass.visible = seabed_shown and seabed_test != 3 and seabed_test != 4

func release_depth() -> void:
	if is_instance_valid(ocean) and ocean.wave_cache: ocean.wave_cache.release()
	if is_instance_valid(ocean) and is_instance_valid(ocean.surface): ocean.surface.hide()

func _exit_tree() -> void:
	release_depth()
