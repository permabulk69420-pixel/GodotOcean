extends SceneTree
## Exercise the actual Quest scene and read back its GPU-generated wave maps.

var failures: Array[String] = []
var scene: Node3D
var snapshots: Array = []
var readback_finished := false

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	root.msaa_3d = ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d.android")
	# Round-trip the scene to binary so startup uses exported property ordering.
	var source: Node3D = load("res://quest/main.tscn").instantiate()
	_check(source.get_node("Water").wave_generator == null,
		"Wave GPU resources must not be allocated while scene properties are restoring")
	var packed := PackedScene.new()
	_check(packed.pack(source) == OK, "Could not pack the Quest scene")
	var path := "user://quest-wave-check.scn"
	_check(ResourceSaver.save(packed, path) == OK, "Could not save the compiled Quest scene")
	source.free()
	scene = load(path).instantiate()
	root.add_child(scene)
	_check(scene.get_node("Water").wave_generator.map_size == 256,
		"Compiled Quest scene must initialize the 256-wide wave generator")
	var camera: XRCamera3D = scene.get_node("XROrigin3D/XRCamera3D")
	_check(camera.global_position.y >= 0.5 and camera.global_position.y <= 3.0,
		"Quest eye height must be near the ocean, got %.2f m" % camera.global_position.y)
	for frame in range(12):
		await process_frame
	if not await _capture():
		quit(1)
		return
	var first := snapshots.duplicate()
	# Advance real simulation time and render another full set of cascades.
	scene.get_node("Water").wave_generator.update(1.0, scene.get_node("Water").parameters)
	for frame in range(12):
		await process_frame
	if not await _capture():
		quit(1)
		return
	_check(snapshots.size() == 3, "Expected three wave cascades")
	for layer in range(snapshots.size()):
		var before: PackedByteArray = first[layer]
		var after: PackedByteArray = snapshots[layer]
		_check(not after.is_empty(), "Empty displacement map for cascade %d" % layer)
		if after.is_empty():
			continue
		var low := INF
		var high := -INF
		var change := 0.0
		for pixel in range(0, after.size(), 8):
			var height := after.decode_half(pixel + 2)
			if not is_finite(height):
				_check(false, "Non-finite wave height in cascade %d" % layer)
				break
			low = minf(low, height)
			high = maxf(high, height)
			change = maxf(change, absf(height - before.decode_half(pixel + 2)))
		print("Wave cascade %d: height range %.3f m, temporal change %.3f m" % [layer, high - low, change])
		_check(high - low > 0.05, "Flat wave displacement in cascade %d" % layer)
		_check(change > 0.001, "Frozen wave displacement in cascade %d" % layer)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(OS.get_environment("QUEST_CAPTURE") if OS.has_environment("QUEST_CAPTURE") else "/tmp/quest-waves.png")
	print("Quest wave check: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _capture() -> bool:
	readback_finished = false
	RenderingServer.call_on_render_thread(_read_gpu_maps)
	for frame in range(120):
		if readback_finished:
			return true
		await process_frame
	_check(false, "GPU wave readback timed out")
	return false

func _read_gpu_maps() -> void:
	var generator: WaveGenerator = scene.get_node("Water").wave_generator
	var rd := RenderingServer.get_rendering_device()
	var result: Array = []
	for layer in range(3):
		result.append(rd.texture_get_data(generator.descriptors[&"displacement_map"].rid, layer))
	_receive.call_deferred(result)

func _receive(result: Array) -> void:
	snapshots = result
	readback_finished = true
