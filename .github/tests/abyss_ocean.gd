extends SceneTree

var failures: Array[String] = []
var scene: Node3D
var stereo: XRInterfaceExtension
var capture_dir := "/tmp/abyss-preview"

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	if OS.has_environment("OCEAN_CAPTURE_DIR"): capture_dir = OS.get_environment("OCEAN_CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	root.msaa_3d = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d.android")
	check(root.msaa_3d == Viewport.MSAA_4X, "Ocean starts at 4x MSAA")
	if OS.get_environment("OCEAN_STEREO") != "0":
		stereo = load("res://.github/tests/quest_xr_interface.gd").new()
		XRServer.add_interface(stereo)
		check(stereo.initialize(), "Stereo interface initializes")
		XRServer.primary_interface = stereo
		root.use_xr = true
	scene = load("res://ocean/main.tscn").instantiate()
	root.add_child(scene)
	check(not scene.has_node("Reef"), "Ocean scene must not add decorative scenery")
	scene.set_physics_process(false)
	var ocean: AbyssOcean = scene.ocean
	ocean.set_process(false)
	ocean.simulation_time = 12.0
	ocean.apply_wave_uniforms(ocean.material)
	check(ocean.wave_data.size() == 64, "Expected full directional wave spectrum")
	var mesh: ArrayMesh = ocean.surface.mesh
	var arrays := mesh.surface_get_arrays(0)
	print("Ocean geometry: ", arrays[Mesh.ARRAY_VERTEX].size(), " vertices; ", arrays[Mesh.ARRAY_INDEX].size()/3, " triangles")
	check(arrays[Mesh.ARRAY_VERTEX].size() > 400000, "Full ocean geometry must be present")
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for offset in range(0, indices.size(), 9000):
		var a := vertices[indices[offset]]
		var b := vertices[indices[offset + 1]]
		var c := vertices[indices[offset + 2]]
		check((b - a).cross(c - a).y < 0.0, "Ocean triangles must face above the surface")
	for x in range(-4, 5):
		for z in range(-4, 5):
			var sample := ocean.sample_surface(Vector3(x * 5.7, 0, z * 5.3), 12.0)
			check(is_finite(sample.height) and sample.normal.y > 0.1, "Wave sample must be finite and upright")
			check(sample.horizontal_error < 0.002, "Gameplay height query must invert horizontal displacement")
	var start := ocean.displacement_at(Vector2(7.0, 9.0), 12.0)
	check(start.distance_to(ocean.displacement_at(Vector2(7.0, 9.0), 13.0)) > 0.01, "Waves must move in time")
	if stereo:
		scene.connect_xr_lifecycle(stereo)
		stereo.emit_signal(&"session_visible")
		check(not paused and not scene.xr_focused, "Visible XR must animate without input focus")
		stereo.emit_signal(&"session_focussed")
		check(not paused and scene.xr_focused, "OpenXR focus signal must enable input")
	for frame in range(3): await process_frame
	scene.update_water_state()
	check(ocean.surface.visible, "Water must render after depth becomes available")
	check(scene.depth_capture.depth_rid.is_valid(), "Resolved eye depth must be available for refraction")
	check(not scene.submerged, "Player must start above the water at tracked eye height")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir.path_join("surface.png"))
	await _probe_gpu(ocean)
	scene.origin.position = Vector3(0, -5.0, 8)
	scene.update_water_state()
	check(scene.submerged and scene.depth > 1.0, "Diving must enter the underwater environment")
	check(scene.world.environment == scene.underwater_environment, "Underwater light absorption must be active")
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir.path_join("underwater.png"))
	scene.origin.position.y = 0.0
	scene.update_water_state()
	check(not scene.submerged, "Surfacing must restore above-water rendering")
	if stereo:
		stereo.emit_signal(&"session_stopping")
		check(paused, "Stopping XR pauses simulation")
		stereo.emit_signal(&"session_visible")
		check(not paused, "Visible XR resumes after stopping")
		scene.release_depth()
		root.use_xr = false
		XRServer.primary_interface = null
		stereo.uninitialize()
		XRServer.remove_interface(stereo)
		RenderingServer.force_sync()
	print("Abyss ocean: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _probe_gpu(ocean: AbyssOcean) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(16, 1)
	viewport.disable_3d = true
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var rectangle := ColorRect.new()
	rectangle.size = Vector2(16, 1)
	var shader := Shader.new()
	shader.code = 'shader_type canvas_item;\n#include "res://ocean/shaders/waves.gdshaderinc"\nvoid fragment() { vec3 d; vec3 n; float c; ocean_sample(vec2(UV.x * 80.0 - 40.0, 0.0), d, n, c); COLOR = vec4(d.y, n.x, n.z, 1.0); }'
	var material := ShaderMaterial.new()
	material.shader = shader
	ocean.apply_wave_uniforms(material)
	rectangle.material = material
	viewport.add_child(rectangle)
	for frame in range(2): await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var maximum_error := 0.0
	for i in range(16):
		var expected := ocean.displacement_at(Vector2((float(i) + 0.5) / 16.0 * 80.0 - 40.0, 0.0), ocean.simulation_time).y
		maximum_error = maxf(maximum_error, absf(image.get_pixel(i, 0).r - expected))
	print("CPU/GPU wave height maximum error: ", maximum_error, " m")
	check(maximum_error < 0.008, "Rendered waves and gameplay height queries must agree")
	viewport.queue_free()
