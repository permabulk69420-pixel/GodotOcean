class_name AbyssDayNight
extends Node
## One time-of-day value drives the sun, moon, sky, ambient light, fog and water brightness.
## The night is deliberately long and dark; bioluminescence is meant to carry the scene.

## Real seconds for one full day and night.
@export var day_length := 180.0
## 0 is sunrise-ish, 0.25 noon, 0.5 sunset-ish, 0.75 midnight.
@export_range(0.0, 1.0) var start_time := 0.34
## Higher values shorten the day (0.45 gives roughly 35% day, 65% night).
@export_range(0.0, 0.8) var night_bias := 0.45
@export var sun_azimuth_degrees := 155.0
@export var max_sun_elevation_degrees := 55.0
## Sky-light changes force Godot to refilter the sky radiance, so they step instead of running every frame.
@export var sky_update_interval := 0.5

const DAY_SUN_COLOUR := Color(1.0, 0.95, 0.85)
const LOW_SUN_COLOUR := Color(1.0, 0.62, 0.38)
const MOON_COLOUR := Color(0.45, 0.58, 1.0)
const SUN_ENERGY := 1.6
const MOON_ENERGY := 0.035
# How fast each colour of light is absorbed per metre of water (red goes first, blue lasts longest).
# Gentler than real sea water so reds and yellows on the reef survive the first 10-15 m.
const ABSORPTION := Vector3(0.075, 0.03, 0.02)
# Sunlight bends towards straight down as it enters the water (1.333 is water's refractive index).
const WATER_INDEX := 1.333
const FOG_DARKENING_PER_METRE := 0.04
const AMBIENT_DARKENING_PER_METRE := 0.045
const FOG_DENSITY_PER_METRE := 0.0012

# Day values match the original scene; night values are almost black blue. At night the surface
# fog also tints the sky (sky_affect) so it is a faint deep blue instead of pure black.
const SURFACE_DAY := {ambient = Color(0.28, 0.45, 0.55), ambient_energy = 0.45, fog = Color(0.55, 0.72, 0.79), fog_density = 0.00012, sun_scatter = 0.2, sky_affect = 0.0}
const SURFACE_NIGHT := {ambient = Color(0.035, 0.07, 0.16), ambient_energy = 0.45, fog = Color(0.006, 0.014, 0.036), fog_density = 0.00035, sun_scatter = 0.0, sky_affect = 1.0}
# Under the water the fog colour itself comes from the underwater sky (aerial perspective, set up
# in main.gd), so the fog colours here only matter as a fallback.
const UNDERWATER_DAY := {ambient = Color(0.06, 0.32, 0.40), ambient_energy = 0.75, fog = Color(0.014, 0.17, 0.25), fog_density = 0.034, sun_scatter = 0.0, sky_affect = 1.0}
const UNDERWATER_NIGHT := {ambient = Color(0.012, 0.05, 0.11), ambient_energy = 0.4, fog = Color(0.002, 0.011, 0.026), fog_density = 0.050, sun_scatter = 0.0, sky_affect = 1.0}

var time := 0.0
var sun_direction := Vector3.UP
var moon_direction := Vector3.DOWN
## 0 at night, 1 in full day.
var daylight := 1.0
var sun_energy := SUN_ENERGY
var moon_energy := 0.0
var sun_colour := DAY_SUN_COLOUR
var sky_timer := 0.0
var underwater_sky_day := -1.0
var underwater_sky_depth := -1.0

func _ready() -> void:
	time = start_time
	evaluate()

func advance(delta: float) -> void:
	if day_length > 0.0:
		time = fposmod(time + delta / day_length, 1.0)
	evaluate()

func evaluate() -> void:
	var wave := sin(TAU * time)
	var elevation_degrees: float
	if wave >= night_bias:
		elevation_degrees = (wave - night_bias) / (1.0 - night_bias) * max_sun_elevation_degrees
	else:
		elevation_degrees = (wave - night_bias) / (1.0 + night_bias) * 60.0
	var elevation := deg_to_rad(elevation_degrees)
	var azimuth := deg_to_rad(sun_azimuth_degrees)
	sun_direction = Vector3(sin(azimuth) * cos(elevation), sin(elevation), cos(azimuth) * cos(elevation)).normalized()
	moon_direction = -sun_direction
	daylight = smoothstep(-0.10, 0.30, sun_direction.y)
	sun_energy = SUN_ENERGY * smoothstep(-0.04, 0.25, sun_direction.y)
	moon_energy = MOON_ENERGY * smoothstep(-0.04, 0.30, moon_direction.y)
	sun_colour = LOW_SUN_COLOUR.lerp(DAY_SUN_COLOUR, smoothstep(0.02, 0.40, sun_direction.y))

## The brighter of sun and moon lights the world; at the hand-over both are near zero.
func light_direction() -> Vector3:
	return sun_direction if sun_energy >= moon_energy else moon_direction

func light_energy() -> float:
	return maxf(sun_energy, moon_energy)

func light_colour() -> Color:
	return sun_colour if sun_energy >= moon_energy else MOON_COLOUR

func face_light(light: DirectionalLight3D, direction: Vector3) -> void:
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	light.global_basis = Basis.looking_at(-direction, up)

func apply_environment(environment: Environment, day: Dictionary, night: Dictionary) -> void:
	var amount := daylight
	environment.ambient_light_sky_contribution = amount
	environment.ambient_light_color = night.ambient.lerp(day.ambient, amount)
	environment.ambient_light_energy = lerpf(night.ambient_energy, day.ambient_energy, amount)
	environment.fog_light_color = night.fog.lerp(day.fog, amount)
	environment.fog_density = lerpf(night.fog_density, day.fog_density, amount)
	environment.fog_sun_scatter = lerpf(night.sun_scatter, day.sun_scatter, amount)
	environment.fog_sky_affect = lerpf(night.sky_affect, day.sky_affect, amount)

func apply(sun: DirectionalLight3D, sky_sun: DirectionalLight3D, surface: Environment, underwater: Environment, water: ShaderMaterial, terrain: ShaderMaterial, delta: float, depth: float = 0.0, underwater_sky: ShaderMaterial = null) -> void:
	var direction := light_direction()
	face_light(sun, direction)
	sun.light_color = absorb(light_colour(), depth)
	sky_timer += delta
	if sky_timer >= sky_update_interval:
		sky_timer = 0.0
		face_light(sky_sun, sun_direction)
		sky_sun.light_color = sun_colour
		sky_sun.light_energy = maxf(sun_energy, 0.001)
		if underwater_sky:
			update_underwater_sky(underwater_sky, depth)
	apply_environment(surface, SURFACE_DAY, SURFACE_NIGHT)
	apply_environment(underwater, UNDERWATER_DAY, UNDERWATER_NIGHT)
	apply_depth(underwater, depth)
	water.set_shader_parameter("sky_sun_direction", sun_direction)
	water.set_shader_parameter("sky_sun_color", sun_colour)
	water.set_shader_parameter("day_amount", daylight)
	terrain.set_shader_parameter("sun_shadow_strength", daylight)
	update_underwater_light()

## The sun's direction once it has bent into the water (always pointing up towards the surface).
func underwater_sun_direction() -> Vector3:
	var across := Vector2(sun_direction.x, sun_direction.z) / WATER_INDEX
	return Vector3(across.x, sqrt(maxf(1.0 - across.length_squared(), 0.0)), across.y)

## Values every underwater shader reads (world/ocean/shaders/underwater_light.gdshaderinc).
func update_underwater_light() -> void:
	RenderingServer.global_shader_parameter_set(&"underwater_sun_direction", underwater_sun_direction())
	# Caustics need a reasonably high sun; they fade out through sunset and are off at night.
	RenderingServer.global_shader_parameter_set(&"underwater_caustics", smoothstep(0.06, 0.35, sun_direction.y))

## The underwater sky only changes when day or depth has moved noticeably: every change makes Godot
## refilter its lighting, so it is never touched every frame.
func update_underwater_sky(material: ShaderMaterial, depth: float) -> void:
	var stepped_depth := snappedf(maxf(depth, 0.0), 0.25)
	if absf(daylight - underwater_sky_day) > 0.004:
		underwater_sky_day = daylight
		material.set_shader_parameter("day_amount", daylight)
	if absf(stepped_depth - underwater_sky_depth) > 0.01:
		underwater_sky_depth = stepped_depth
		material.set_shader_parameter("depth", stepped_depth)

## Tint a light colour the way the water does: the deeper you are, the more red is lost.
func absorb(colour: Color, depth: float) -> Color:
	if depth <= 0.0:
		return colour
	return Color(colour.r * exp(-ABSORPTION.x * depth), colour.g * exp(-ABSORPTION.y * depth), colour.b * exp(-ABSORPTION.z * depth))

## Deeper water is murkier, darker and dimmer: denser fog, darker fog colour, less ambient light.
func apply_depth(environment: Environment, depth: float) -> void:
	if depth <= 0.0:
		return
	environment.fog_density += depth * FOG_DENSITY_PER_METRE
	environment.fog_light_color = environment.fog_light_color * exp(-depth * FOG_DARKENING_PER_METRE)
	environment.ambient_light_energy *= exp(-depth * AMBIENT_DARKENING_PER_METRE)
