extends SceneTree
## Loads the game, waits for the terrain, renders a few frames and exits. Shader or script errors
## in the log fail the build; this replaces the slow stereo tests on ordinary pushes.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.msaa_3d=Viewport.MSAA_4X
	var scene=load('res://game/main.tscn').instantiate()
	root.add_child(scene)
	for i in range(240):
		if scene.terrain.near_ready: break
		await process_frame
	for i in range(12):
		await process_frame
		await RenderingServer.frame_post_draw
	print('SMOKE: PASS')
	quit()
