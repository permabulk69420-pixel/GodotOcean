class_name AbyssOcean
extends Node3D
## Deterministic directional spectrum shared by rendering and gameplay queries.

const WAVE_COUNT := 64
const GRAVITY := 9.81
const SURFACE_SHADER := preload("res://world/ocean/shaders/surface.gdshader")

@export var settings: AbyssOceanSettings
@export var sea_level := 0.0
@export var observer: Node3D

var simulation_time := 0.0
var wave_data := PackedVector4Array()
var phase_data := PackedVector2Array()
var horizontal_scale := 0.0
var material: ShaderMaterial
var surface: MeshInstance3D
## AbyssWaveCache (compute shader) on Vulkan; AbyssWaveCacheGL (a 2D pass) on the Compatibility renderer.
var wave_cache: RefCounted
var detail_normal_texture: NoiseTexture2D
var detail_texture: NoiseTexture2D
## The sky seen through the window overhead from under the water, for underside.gdshader.
var window_sky: AbyssWindowSky

func _ready() -> void:
	if not settings: settings = AbyssOceanSettings.new()
	build_spectrum()
	material = ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	apply_wave_uniforms(material)
	material.set_shader_parameter("absorption", settings.absorption)
	material.set_shader_parameter("deep_color", settings.deep_color)
	material.set_shader_parameter("shallow_color", settings.shallow_color)
	material.set_shader_parameter("foam_color", settings.foam_color)
	var noise := FastNoiseLite.new()
	noise.seed = settings.spectrum_seed
	noise.frequency = 0.025
	noise.fractal_octaves = 5
	detail_texture = NoiseTexture2D.new()
	detail_texture.width = 1024
	detail_texture.height = 1024
	detail_texture.seamless = true
	detail_texture.generate_mipmaps = true
	detail_texture.noise = noise
	material.set_shader_parameter("detail_texture", detail_texture)
	detail_normal_texture = NoiseTexture2D.new()
	detail_normal_texture.width=1024
	detail_normal_texture.height=1024
	detail_normal_texture.seamless=true
	detail_normal_texture.generate_mipmaps=true
	detail_normal_texture.noise=noise
	detail_normal_texture.as_normal_map=true
	detail_normal_texture.bump_strength=5.5
	material.set_shader_parameter("detail_normals",detail_normal_texture)
	window_sky = AbyssWindowSky.new()
	window_sky.name = "WindowSky"
	add_child(window_sky)
	material.set_shader_parameter("window_sky", window_sky.get_texture())
	surface = MeshInstance3D.new()
	surface.name = "OceanSurface"
	surface.mesh = _build_clipmap()
	surface.material_override = material
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.custom_aabb = AABB(Vector3(-4096, -24, -4096), Vector3(8192, 48, 8192))
	add_child(surface)
	if RenderingServer.get_rendering_device():
		wave_cache = AbyssWaveCache.new()
	else:
		wave_cache = AbyssWaveCacheGL.new()
		wave_cache.host = self
	var vertices: PackedVector3Array = surface.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var packed := PackedFloat32Array()
	for v in vertices: packed.append_array(PackedFloat32Array([v.x,v.z,0,0]))
	wave_cache.points=packed.to_byte_array()
	wave_cache.vertex_count=vertices.size()
	packed=PackedFloat32Array()
	for i in range(WAVE_COUNT):
		var w:=wave_data[i]; var p:=phase_data[i]
		packed.append_array(PackedFloat32Array([w.x,w.y,w.z,w.w,p.x,p.y,horizontal_scale,0]))
	wave_cache.spectrum=packed.to_byte_array()


func build_spectrum() -> void:
	wave_data.clear()
	phase_data.clear()
	var random := RandomNumberGenerator.new()
	random.seed = settings.spectrum_seed
	var total_slope := 0.0
	# Independent long-period swell and shorter wind sea, each with JONSWAP energy.
	for band in range(2):
		var period := settings.peak_period if band == 0 else settings.wind_wave_period
		var height := settings.significant_wave_height if band == 0 else settings.wind_wave_height
		var peak_frequency := TAU / period
		var weights := PackedFloat64Array()
		var frequencies := PackedFloat64Array()
		var sum_energy := 0.0
		for i in range(32):
			var u := (float(i) + 0.5) / 32.0
			var frequency := peak_frequency * exp(lerpf(log(0.55), log(4.0), u))
			var sigma := 0.07 if frequency <= peak_frequency else 0.09
			var peak := exp(-pow(frequency - peak_frequency, 2.0) / (2.0 * pow(sigma * peak_frequency, 2.0)))
			var energy := pow(frequency, -5.0) * exp(-1.25 * pow(peak_frequency / frequency, 4.0)) * pow(3.3, peak) * frequency
			weights.append(energy)
			frequencies.append(frequency)
			sum_energy += energy
		var target_variance := pow(height / 4.0, 2.0)
		for i in range(32):
			var omega := frequencies[i]
			var amplitude := sqrt(2.0 * target_variance * weights[i] / sum_energy)
			var spread := settings.directional_spread * (0.65 if band == 0 else 1.3)
			var angle := deg_to_rad(settings.wind_direction) + (0.32 if band == 0 else 0.0) + random.randfn(0.0, spread)
			var k := omega * omega / GRAVITY
			wave_data.append(Vector4(cos(angle), sin(angle), amplitude, k))
			phase_data.append(Vector2(omega, random.randf() * TAU))
			total_slope += amplitude * k
	# The horizontal Jacobian stays positive; wave crests cannot fold into spikes.
	horizontal_scale = minf(1.0, settings.steepness / maxf(total_slope, 0.0001))

func apply_wave_uniforms(target: ShaderMaterial) -> void:
	target.set_shader_parameter("wave_data", wave_data)
	target.set_shader_parameter("phase_data", phase_data)
	target.set_shader_parameter("horizontal_scale", horizontal_scale)
	target.set_shader_parameter("sea_level", sea_level)
	target.set_shader_parameter("simulation_time", simulation_time)

func _process(delta: float) -> void:
	simulation_time += delta
	material.set_shader_parameter("simulation_time", simulation_time)
	if observer:
		var p := observer.global_position
		surface.global_position = Vector3(snappedf(p.x, 0.25), sea_level, snappedf(p.z, 0.25))
	wave_cache.parameters=PackedFloat32Array([surface.global_position.x,surface.global_position.z,simulation_time,float(wave_cache.vertex_count)])

func displacement_at(parameter: Vector2, at_time: float = -1.0) -> Vector3:
	var t := simulation_time if at_time < 0.0 else at_time
	var displacement := Vector3.ZERO
	for i in range(WAVE_COUNT):
		var w := wave_data[i]
		var p := phase_data[i]
		var phase := w.w * (w.x * parameter.x + w.y * parameter.y) - p.x * t + p.y
		var horizontal := horizontal_scale * w.z * cos(phase)
		displacement += Vector3(horizontal * w.x, w.z * sin(phase), horizontal * w.y)
	return displacement

func sample_surface(world_position: Vector3, at_time: float = -1.0) -> Dictionary:
	var t := simulation_time if at_time < 0.0 else at_time
	var target := Vector2(world_position.x, world_position.z)
	var parameter := target
	# Newton inversion finds the surface at a world XZ position after choppy displacement.
	for iteration in range(6):
		var d := displacement_at(parameter, t)
		var error := parameter + Vector2(d.x, d.z) - target
		if error.length_squared() < 0.00000001: break
		var a := 1.0; var b := 0.0; var c := 1.0
		for i in range(WAVE_COUNT):
			var w := wave_data[i]; var p := phase_data[i]
			var phase := w.w * (w.x * parameter.x + w.y * parameter.y) - p.x * t + p.y
			var slope := horizontal_scale * w.z * w.w * sin(phase)
			a -= slope * w.x * w.x
			b -= slope * w.x * w.y
			c -= slope * w.y * w.y
		var determinant := maxf(a * c - b * b, 0.001)
		parameter -= Vector2(c * error.x - b * error.y, a * error.y - b * error.x) / determinant
	var tangent_x := Vector3.RIGHT
	var tangent_z := Vector3.BACK
	var velocity := Vector3.ZERO
	for i in range(WAVE_COUNT):
		var w := wave_data[i]; var p := phase_data[i]
		var phase := w.w * (w.x * parameter.x + w.y * parameter.y) - p.x * t + p.y
		var sine := sin(phase); var cosine := cos(phase)
		var slope := w.z * w.w
		tangent_x += Vector3(-horizontal_scale * slope * w.x * w.x * sine, slope * w.x * cosine, -horizontal_scale * slope * w.x * w.y * sine)
		tangent_z += Vector3(-horizontal_scale * slope * w.x * w.y * sine, slope * w.y * cosine, -horizontal_scale * slope * w.y * w.y * sine)
		velocity += Vector3(horizontal_scale * w.z * w.x * p.x * sine, -w.z * p.x * cosine, horizontal_scale * w.z * w.y * p.x * sine)
	var d := displacement_at(parameter, t)
	return {"height": sea_level + d.y, "normal": tangent_z.cross(tangent_x).normalized(), "velocity": velocity,
		"parameter": parameter, "horizontal_error": (parameter + Vector2(d.x, d.z) - target).length()}

func _build_clipmap() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var lookup := {}
	# Pixel-sized distant geometry; retain 25 cm spacing next to the player and 4 km coverage.
	for level in range(9):
		var step := 0.25 * pow(2.0, level)
		var half := 64.0 * step
		var inner := half * 0.5
		for z in range(128):
			for x in range(128):
				var p := Vector2(x * step - half, z * step - half)
				if level > 0 and p.x >= -inner and p.x < inner and p.y >= -inner and p.y < inner: continue
				var polygon: Array[Vector2] = [p, p + Vector2(0, step), p + Vector2(step, step), p + Vector2(step, 0)]
				if level > 0:
					# Split coarse inner edges at the exact vertices of the previous level.
					var stitched: Array[Vector2] = []
					for edge in range(4):
						var a := polygon[edge]; var b := polygon[(edge + 1) % 4]
						stitched.append(a)
						var mid := (a + b) * 0.5
						if (is_equal_approx(absf(mid.x), inner) and absf(mid.y) < inner) or (is_equal_approx(absf(mid.y), inner) and absf(mid.x) < inner): stitched.append(mid)
					polygon = stitched
				var ids: Array[int] = []
				for v in polygon:
					if not lookup.has(v):
						lookup[v] = vertices.size()
						vertices.append(Vector3(v.x, 0, v.y)); normals.append(Vector3.UP)
					ids.append(lookup[v])
				if ids.size() > 4:
					var center := p + Vector2.ONE * step * 0.5
					var center_id := vertices.size()
					vertices.append(Vector3(center.x, 0, center.y)); normals.append(Vector3.UP)
					for edge in range(ids.size()):
						indices.append_array(PackedInt32Array([center_id, ids[(edge + 1) % ids.size()], ids[edge]]))
				else:
					indices.append_array(PackedInt32Array([ids[0], ids[2], ids[1], ids[0], ids[3], ids[2]]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
