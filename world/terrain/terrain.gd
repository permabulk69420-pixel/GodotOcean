class_name AbyssTerrain
extends Node3D
## Streams the terrain around the camera (observer). The voxels come from the bake (see AbyssTerrainSettings and
## AbyssVoxelStore); meshes are built from them on worker threads (AbyssVoxelMesher), in full detail close by and
## coarser further out, and only blocks near the camera get collision. Blocks far behind are let go.

const GROUND_COLOUR=preload('res://world/terrain/textures/ground_colour.jpg')
const GROUND_NORMAL=preload('res://world/terrain/textures/ground_normal.jpg')
## The wanted blocks are worked out again once the camera has moved this far.
const REFRESH_DISTANCE:=4.0
## How many blocks may be meshed at once (each takes a core away from the game while it runs), and how many new meshes
## are put into the scene per frame.
const MAX_JOBS:=1
const INSTALLS_PER_FRAME:=2
## A block whose detail changes keeps its old mesh until the new meshes around it are all ready (so no gaps open
## between them), or this long at most (seconds).
const SWAP_WAIT:=1.0

@export var settings: AbyssTerrainSettings
var observer: Node3D
var generator: AbyssTerrainGenerator
var store: AbyssVoxelStore
var material: ShaderMaterial
## True once the blocks around the start have their collision. Only that first load holds the player still: after it,
## blocks keep their collision while they are remeshed, and new ones get it well before they are reached.
var near_ready:=false
## True once every wanted block has its current mesh.
var all_ready:=false
## Blocks in the scene: block -> {lod, key, body, visual, collider, faces}.
var chunks:={}
## Blocks wanted now, and their detail level.
var wanted:={}
var keys:={}
var pending: Array[Vector3i]=[]
var running:={}
var _done: Array[Dictionary]=[]
var _done_mutex:=Mutex.new()
var _staged: Array[Dictionary]=[]
var _staged_since:=0.0
var _centre:=Vector3.INF
var _collision_blocks:={}
var _collision_queue: Array[Vector3i]=[]
var _neighbours: Array[Vector3i]=[]
## Working out the wanted blocks runs on a worker thread; its result is applied on the next frame it is ready.
var _plan_task:=-1
var _plan:={}

func _ready() -> void:
	if not settings: settings=AbyssTerrainSettings.new()
	generator=AbyssTerrainGenerator.new(settings)
	material=ShaderMaterial.new()
	material.shader=load('res://world/terrain/terrain.gdshader')
	material.set_shader_parameter('ground_colour',GROUND_COLOUR)
	material.set_shader_parameter('ground_normal',GROUND_NORMAL)
	var index: AbyssVoxelIndex=null
	if ResourceLoader.exists('res://world/terrain/baked/index.tres'):
		index=load('res://world/terrain/baked/index.tres')
		if index.signature!=settings.signature(): index=null
	store=AbyssVoxelStore.new(settings,index,generator)
	for z in range(-1,2):
		for y in range(-1,2):
			for x in range(-1,2):
				if x!=0 or y!=0 or z!=0: _neighbours.append(Vector3i(x,y,z))

func focus() -> Vector3:
	return observer.global_position if observer and observer.is_inside_tree() else Vector3.ZERO

func _process(_delta: float) -> void:
	var centre:=focus()
	if _plan_task==-1 and (_centre==Vector3.INF or centre.distance_to(_centre)>REFRESH_DISTANCE):
		_centre=centre
		_plan_task=WorkerThreadPool.add_task(_make_plan.bind(centre),false,'Terrain plan')
	if _plan_task!=-1 and WorkerThreadPool.is_task_completed(_plan_task):
		WorkerThreadPool.wait_for_task_completion(_plan_task)
		_plan_task=-1
		_apply(_plan)
	_collect()
	_build_collision()
	while running.size()<MAX_JOBS and not pending.is_empty():
		var b: Vector3i=pending.pop_front()
		if not wanted.has(b) or running.has(b): continue
		var lod: int=wanted[b]
		var coarse:={}
		for o in _neighbours:
			if wanted.get(b+o,lod)>lod: coarse[o]=wanted[b+o]
		running[b]={key=keys[b],task=WorkerThreadPool.add_task(_mesh.bind(b,lod,keys[b],coarse),false,'Terrain block')}
	all_ready=_plan_task==-1 and not wanted.is_empty() and pending.is_empty() and running.is_empty() and _staged.is_empty() and _collision_queue.is_empty()
	if not near_ready:
		var ready:=_plan_task==-1 and not wanted.is_empty()
		for b in _collision_blocks:
			var entry: Dictionary=chunks.get(b,{})
			if entry.get('key')!=keys.get(b) or (entry.has('faces') and not entry.get('collider')): ready=false
		near_ready=ready

## Which blocks are wanted around this point and at what detail (worker thread: reads only the store's block list).
func _make_plan(centre: Vector3) -> void:
	var ranges:=settings.lod_ranges
	var far:=ranges[ranges.size()-1]
	var size:=float(AbyssTerrainSettings.BLOCK)
	var low:=Vector3i(((centre-Vector3.ONE*far)/size).floor())
	var high:=Vector3i(((centre+Vector3.ONE*far)/size).floor())
	var next:={}
	var distances:={}
	for z in range(low.z,high.z+1):
		for y in range(low.y,high.y+1):
			for x in range(low.x,high.x+1):
				var b:=Vector3i(x,y,z)
				if not store.surface_blocks.has(b): continue
				var d:=_distance(centre,b)
				if d>far: continue
				var lod:=0
				while d>ranges[lod]: lod+=1
				next[b]=lod
				distances[b]=d
	# Neighbours (sides, edges and corners) at most one level apart: a far block next to a near one gets finer.
	var changed:=true
	while changed:
		changed=false
		for b in next:
			for o in _neighbours:
				var other: int=next.get(b+o,99)
				if other+1<next[b]:
					next[b]=other+1
					changed=true
	var plan_keys:={}
	for b in next:
		var mask:=0
		for i in range(_neighbours.size()):
			if next.get(b+_neighbours[i],-1)>next[b]: mask|=1<<i
		plan_keys[b]=next[b]|(mask<<2)
	var collision:={}
	for b in next:
		if distances[b]<=settings.collision_range: collision[b]=true
	_plan={centre=centre,wanted=next,keys=plan_keys,distances=distances,collision=collision}

## Puts a plan into effect: what needs meshing (nearest and finest first), what to let go, and which blocks collide.
func _apply(plan: Dictionary) -> void:
	wanted=plan.wanted
	keys=plan.keys
	var distances: Dictionary=plan.distances
	pending.clear()
	for b in wanted:
		if chunks.get(b,{}).get('key')==keys[b] or running.get(b,{}).get('key')==keys[b]: continue
		pending.append(b)
	pending.sort_custom(func(a: Vector3i,b: Vector3i) -> bool:
		return wanted[a]<wanted[b] or (wanted[a]==wanted[b] and distances[a]<distances[b]))
	for b in chunks.keys():
		if not wanted.has(b): _remove(b)
	_collision_blocks=plan.collision
	for b in chunks: _set_collision(b,_collision_blocks.has(b) and chunks[b].lod==0)
	store.forget_beyond(plan.centre,settings.lod_ranges[settings.lod_ranges.size()-1]+64.0)

func _distance(p: Vector3,b: Vector3i) -> float:
	var size:=float(AbyssTerrainSettings.BLOCK)
	var lo:=Vector3(b)*size
	return p.distance_to(p.clamp(lo,lo+Vector3.ONE*size))

func _mesh(b: Vector3i,lod: int,key: int,coarse: Dictionary) -> void:
	var result:=AbyssVoxelMesher.build(store,b,lod,coarse)
	result.block=b
	result.lod=lod
	result.key=key
	_done_mutex.lock()
	_done.append(result)
	_done_mutex.unlock()

## Puts finished meshes into the scene: new blocks straight away; changed ones are built hidden as they arrive and
## all swapped in together once their neighbours are done (the swap itself only shows and hides nodes).
func _collect() -> void:
	_done_mutex.lock()
	var results:=_done.duplicate()
	_done.clear()
	_done_mutex.unlock()
	for r in results:
		var b: Vector3i=r.block
		if running.has(b):
			WorkerThreadPool.wait_for_task_completion(running[b].task)
			running.erase(b)
		if keys.get(b)!=r.key: continue
		var entry:=_build(r)
		if chunks.has(b):
			if _staged.is_empty(): _staged_since=Time.get_ticks_msec()/1000.0
			_staged.append(entry)
		else:
			_commit(entry)
	if not _staged.is_empty() and ((pending.is_empty() and running.is_empty()) or Time.get_ticks_msec()/1000.0-_staged_since>SWAP_WAIT):
		for entry in _staged:
			if keys.get(entry.block)==entry.key: _commit(entry)
			elif entry.get('body'): entry.body.queue_free()
		_staged.clear()

## A block's node, built but not yet shown.
func _build(r: Dictionary) -> Dictionary:
	var b: Vector3i=r.block
	var entry:={block=b,lod=r.lod,key=r.key}
	var indices: PackedInt32Array=r.indices
	if indices.is_empty(): return entry
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=r.vertices
	arrays[Mesh.ARRAY_NORMAL]=r.normals
	arrays[Mesh.ARRAY_COLOR]=r.colours
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var body:=StaticBody3D.new()
	body.name='Block_%s_%s_%s_%s'%[b.x,b.y,b.z,r.key]
	body.collision_layer=1
	body.collision_mask=0
	body.visible=false
	var visual:=MeshInstance3D.new()
	visual.mesh=mesh
	visual.material_override=material
	visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(visual)
	add_child(body)
	entry.body=body
	entry.visual=visual
	if r.has('faces'): entry.faces=r.faces
	return entry

## Shows a built block in place of whatever was there.
func _commit(entry: Dictionary) -> void:
	var b: Vector3i=entry.block
	# Close by, a block's own full-detail voxels do not change when only its neighbours' detail does, so the collision
	# it already has still fits: keep it rather than build it again.
	var old: Dictionary=chunks.get(b,{})
	var kept_shape: Shape3D=old.collider.shape if old.get('lod')==0 and entry.lod==0 and old.get('collider') else null
	_remove(b)
	if entry.get('body'):
		entry.body.visible=true
		if kept_shape: _attach(entry,kept_shape)
	chunks[b]=entry
	_set_collision(b,_collision_blocks.has(b) and entry.lod==0)

## Collision is wanted (or not) for a block; new shapes are built by _build_collision, one a frame.
func _set_collision(b: Vector3i,on: bool) -> void:
	var entry: Dictionary=chunks[b]
	if on and entry.has('faces') and not entry.get('collider'):
		if not _collision_queue.has(b): _collision_queue.append(b)
	elif not on and entry.get('collider'):
		entry.collider.queue_free()
		entry.erase('collider')

## Builds the nearest waiting block's collision. A full-detail block's shape takes several milliseconds to build, so
## only one is built a frame.
func _build_collision() -> void:
	if _collision_queue.is_empty(): return
	var centre:=focus()
	_collision_queue.sort_custom(func(a: Vector3i,b: Vector3i) -> bool: return _distance(centre,a)<_distance(centre,b))
	while not _collision_queue.is_empty():
		var b: Vector3i=_collision_queue.pop_front()
		var entry: Dictionary=chunks.get(b,{})
		if not entry.has('faces') or entry.get('collider') or entry.lod!=0 or not _collision_blocks.has(b): continue
		var shape:=ConcavePolygonShape3D.new()
		shape.backface_collision=true
		shape.set_faces(entry.faces)
		_attach(entry,shape)
		return

func _attach(entry: Dictionary,shape: Shape3D) -> void:
	var collider:=CollisionShape3D.new()
	collider.shape=shape
	entry.body.add_child(collider)
	entry.collider=collider

func _remove(b: Vector3i) -> void:
	if not chunks.has(b): return
	var entry: Dictionary=chunks[b]
	if entry.get('body'): entry.body.queue_free()
	chunks.erase(b)

func _exit_tree() -> void:
	for entry in _staged:
		if entry.get('body'): entry.body.queue_free()
	_staged.clear()
	if _plan_task!=-1: WorkerThreadPool.wait_for_task_completion(_plan_task)
	_plan_task=-1
	for b in running: WorkerThreadPool.wait_for_task_completion(running[b].task)
	running.clear()
