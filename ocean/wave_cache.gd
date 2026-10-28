class_name AbyssWaveCache
extends CompositorEffect
## Calculate the displaced mesh once for both eyes, before transparent water draws.
var displacement := Texture2DRD.new()
var normals := Texture2DRD.new()
var points := PackedByteArray()
var spectrum := PackedByteArray()
var vertex_count := 0
var parameters := PackedFloat32Array([0,0,0,0])
var rd: RenderingDevice
var resources: Array[RID] = []
var pipeline := RID()
var uniform_set := RID()
var outputs: Array[RID] = []
var ready := false
var last_parameters := PackedFloat32Array()
func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT
func _render_callback(_type: int, _data: RenderData) -> void:
	if not ready: _allocate()
	if not ready: return
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipeline)
	rd.compute_list_bind_uniform_set(list,uniform_set,0)
	rd.compute_list_set_push_constant(list,parameters.to_byte_array(),16)
	rd.compute_list_dispatch(list,ceili(vertex_count/64.0),1,1)
	rd.compute_list_end()
	last_parameters=parameters.duplicate()
func _allocate() -> void:
	if points.is_empty(): return
	rd = RenderingServer.get_rendering_device()
	var shader := rd.shader_create_from_spirv(load('res://ocean/shaders/wave_cache.glsl').get_spirv())
	resources.append(shader)
	pipeline=rd.compute_pipeline_create(shader)
	resources.append(pipeline)
	var uniforms: Array[RDUniform] = []
	for i in range(2):
		var bytes := points if i == 0 else spectrum
		var buffer := rd.storage_buffer_create(bytes.size(),bytes)
		resources.append(buffer)
		var uniform := RDUniform.new()
		uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding=i
		uniform.add_id(buffer)
		uniforms.append(uniform)
	for i in range(2):
		var format := RDTextureFormat.new()
		format.width=1024
		format.height=ceili(vertex_count/1024.0)
		format.format=RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
		format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		var texture := rd.texture_create(format,RDTextureView.new())
		resources.append(texture)
		outputs.append(texture)
		var uniform := RDUniform.new()
		uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding=i+2
		uniform.add_id(texture)
		uniforms.append(uniform)
	uniform_set=rd.uniform_set_create(uniforms,shader,0)
	resources.append(uniform_set)
	displacement.texture_rd_rid=outputs[0]
	normals.texture_rd_rid=outputs[1]
	ready=true
func release() -> void:
	enabled=false
	RenderingServer.call_on_render_thread(_free)
func _free() -> void:
	displacement.texture_rd_rid=RID()
	normals.texture_rd_rid=RID()
	for i in range(resources.size()-1,-1,-1):
		if rd and resources[i].is_valid(): rd.free_rid(resources[i])
	resources.clear()
	ready=false
