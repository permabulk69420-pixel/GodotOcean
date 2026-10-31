class_name AbyssWaveCacheGL
extends RefCounted
## The wave cache for the Compatibility (OpenGL) renderer, which has no compute shaders (wave_cache.gd needs them).
## Same job and same interface: each frame, the displacement and normal of every surface vertex, worked out once and
## read by the water's vertex shaders. Here they are drawn into one float texture by a small 2D pass
## (world/ocean/shaders/wave_cache_gl.gdshader): displacement in the top half, normals in the bottom half.

const SHADER := preload("res://world/ocean/shaders/wave_cache_gl.gdshader")

var points := PackedByteArray()
var spectrum := PackedByteArray()
var vertex_count := 0
var parameters := PackedFloat32Array([0,0,0,0])
var displacement: Texture2D
var normals: Texture2D
## Rows per half: the normals start this many rows down (the water shaders' cached_normal_row).
var normal_row := 0
var ready := false
var active := false
## Holds the 2D pass while it runs.
var host: Node
var viewport: SubViewport
var material: ShaderMaterial

func start() -> void:
	if points.is_empty(): return
	normal_row = ceili(vertex_count / 1024.0)
	var floats := points.to_float32_array()
	floats.resize(1024 * normal_row * 4)
	var point_image := Image.create_from_data(1024, normal_row, false, Image.FORMAT_RGBAF, floats.to_byte_array())
	var waves := PackedVector4Array()
	var data := spectrum.to_float32_array()
	for i in range(0, data.size(), 4): waves.append(Vector4(data[i], data[i + 1], data[i + 2], data[i + 3]))
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("points", ImageTexture.create_from_image(point_image))
	material.set_shader_parameter("waves", waves)
	material.set_shader_parameter("rows", normal_row)
	viewport = SubViewport.new()
	viewport.name = "WaveCache"
	viewport.size = Vector2i(1024, normal_row * 2)
	viewport.disable_3d = true
	viewport.use_hdr_2d = true
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var rect := ColorRect.new()
	rect.size = Vector2(viewport.size)
	rect.material = material
	viewport.add_child(rect)
	host.add_child(viewport)
	displacement = viewport.get_texture()
	normals = displacement
	active = true
	RenderingServer.frame_pre_draw.connect(_update)

## Runs just before each frame is drawn. The 2D pass draws before the scene that reads it, so the texture is filled by
## the time the water is drawn in the first frame; the water switches to it from the next.
func _update() -> void:
	if not active: return
	material.set_shader_parameter("parameters", Vector4(parameters[0], parameters[1], parameters[2], parameters[3]))
	ready = true

func release() -> void:
	active = false
	if RenderingServer.frame_pre_draw.is_connected(_update): RenderingServer.frame_pre_draw.disconnect(_update)
	if is_instance_valid(viewport): viewport.queue_free()
