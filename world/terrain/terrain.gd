class_name AbyssTerrain
extends Node3D
const GROUND_COLOUR=preload('res://world/terrain/textures/ground_colour.jpg')
const GROUND_NORMAL=preload('res://world/terrain/textures/ground_normal.jpg')
@export var settings: AbyssTerrainSettings
var observer: Node3D
var chunks: Dictionary={}
var pending: Array[String]=[]
var coordinates: Dictionary={}
var requested: Dictionary={}
var material: ShaderMaterial
var near_ready:=false
var all_ready:=false
var generator: AbyssTerrainGenerator
var fallback_jobs: Dictionary={}
var completed: Array[AbyssTerrainChunk]=[]
var result_mutex:=Mutex.new()

func _ready() -> void:
	if not settings: settings=AbyssTerrainSettings.new()
	generator=AbyssTerrainGenerator.new(settings)
	material=ShaderMaterial.new()
	material.shader=load('res://world/terrain/terrain.gdshader')
	material.set_shader_parameter('ground_colour',GROUND_COLOUR)
	material.set_shader_parameter('ground_normal',GROUND_NORMAL)
	if ResourceLoader.exists('res://world/terrain/baked/index.tres'):
		var index: AbyssTerrainBakeIndex=load('res://world/terrain/baked/index.tres')
		if index.signature==settings.signature() and not index.coordinates.is_empty():
			var files:=index.files
			var order:=[]
			for i in range(files.size()): order.append(i)
			order.sort_custom(func(a,b): return Vector3(index.coordinates[a]).length_squared()<Vector3(index.coordinates[b]).length_squared())
			for i in order:
				pending.append(files[i])
				coordinates[files[i]]=index.coordinates[i]
			return
	# The same generator works for uncached chunks; only one low-priority task runs at a time.
	for coordinate in settings.coordinates():
		var key:=str(coordinate)
		pending.append(key)
		coordinates[key]=coordinate
	pending.sort_custom(func(a,b): return Vector3(coordinates[a]).length_squared()<Vector3(coordinates[b]).length_squared())

func _process(_delta: float) -> void:
	for path in pending.slice(0,4):
		if not path.begins_with('res://'): break
		if not requested.has(path):
			ResourceLoader.load_threaded_request(path,'Resource',false)
			requested[path]=true
	if not pending.is_empty():
		var path:=pending[0]
		if path.begins_with('res://'):
			if ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_LOADED:
				var data: AbyssTerrainChunk=ResourceLoader.load_threaded_get(path)
				_install(data)
				pending.pop_front()
				requested.erase(path)
			elif ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_FAILED and fallback_jobs.is_empty():
				requested.erase(path)
				push_warning('Regenerating unavailable terrain chunk: '+path)
				pending.pop_front()
				var coordinate: Vector3i=coordinates[path]
				fallback_jobs[coordinate]=WorkerThreadPool.add_task(_generate.bind(coordinate),false,'Shallows chunk')
		elif fallback_jobs.is_empty():
			pending.pop_front()
			var coordinate: Vector3i=coordinates[path]
			fallback_jobs[coordinate]=WorkerThreadPool.add_task(_generate.bind(coordinate),false,'Shallows chunk')
	result_mutex.lock()
	var results:=completed.duplicate()
	completed.clear()
	result_mutex.unlock()
	for data in results:
		WorkerThreadPool.wait_for_task_completion(fallback_jobs[data.coordinate])
		fallback_jobs.erase(data.coordinate)
		_install(data)
	all_ready=pending.is_empty() and fallback_jobs.is_empty()
	# Initial neighbourhood must have physical colliders before swimming is enabled.
	near_ready=all_ready or (chunks.size()>=12 and (pending.is_empty() or Vector3(coordinates[pending[0]]).length()>2.0))

func request_chunk(coordinate: Vector3i) -> void:
	if chunks.has(coordinate) or fallback_jobs.has(coordinate): return
	for path in pending:
		if coordinates[path]==coordinate: return
	var key:=str(coordinate)
	coordinates[key]=coordinate
	pending.append(key)
	all_ready=false

func _generate(coordinate: Vector3i) -> void:
	var worker:=AbyssTerrainGenerator.new(settings)
	var data:=worker.generate(coordinate)
	result_mutex.lock()
	completed.append(data)
	result_mutex.unlock()

func _install(data: AbyssTerrainChunk) -> void:
	chunks[data.coordinate]=true
	if not data.mesh: return
	var chunk:=StaticBody3D.new()
	chunk.name='Chunk_%s_%s_%s'%[data.coordinate.x,data.coordinate.y,data.coordinate.z]
	chunk.collision_layer=1
	chunk.collision_mask=0
	var visual:=MeshInstance3D.new()
	visual.mesh=data.mesh
	visual.material_override=material
	visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(visual)
	var collider:=CollisionShape3D.new()
	collider.shape=data.collision
	chunk.add_child(collider)
	add_child(chunk)

func _exit_tree() -> void:
	# Drain prefetched resources so their asynchronous load requests cannot outlive the scene.
	for path in requested:
		if ResourceLoader.load_threaded_get_status(path) in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]:
			ResourceLoader.load_threaded_get(path)
	requested.clear()
	for id in fallback_jobs.values(): WorkerThreadPool.wait_for_task_completion(id)
