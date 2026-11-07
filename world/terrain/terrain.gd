class_name AbyssTerrain
extends Node3D
## The sea floor, drawn as a quadtree of square height-map tiles around the camera: small and detailed close by,
## doubling in size (and halving in detail) with distance. Every tile is the same 32 x 32 grid, so a far 1 km tile
## costs what a near 64 m one does. Each tile blends into the shape of the next coarser one with distance, so
## changing detail is not seen and neighbours of different detail meet; buried skirts cover any gap left. Tiles are
## built on worker threads and kept for reuse; a tile on screen is only swapped once every tile replacing it is ready,
## so nothing goes missing in between. Close tiles get collision, built from the same triangles.

const GROUND_COLOUR=preload('res://world/terrain/textures/ground_colour.jpg')
const GROUND_NORMAL=preload('res://world/terrain/textures/ground_normal.jpg')
const ROCK_COLOUR=preload('res://world/terrain/textures/rock_colour.jpg')
const ROCK_NORMAL=preload('res://world/terrain/textures/rock_normal.jpg')
## Tile sizes, nearest first. A 64 m tile has 2 m detail; a 1024 m one 32 m.
const SIZES:=[64.0,128.0,256.0,512.0,1024.0]
const SEGMENTS:=32
## A tile splits into four when the camera is within this many times its own size of it, and joins up again only
## once the camera is this much further than that (so it does not flick back and forth at the line).
const SPLIT:=1.25
const HYSTERESIS:=1.15
## The whole map is always there: far away it is a handful of large, coarse tiles (a 1 km tile costs what a near
## 64 m one does), so nothing ever appears at the edge of what has loaded. Tiles a little finer than needed are built
## ahead of time, for the camera this many times closer than it is (as Oasis does), so that when a tile splits as you
## approach, its finer tiles are usually ready and it changes over straight away.
const LEAD:=1.35
## How many tiles one background task builds (about 3 ms each on a desktop), and how many such tasks run at once.
const TILES_PER_JOB:=6
const JOBS:=3
## The tiles wanted are worked out again once the camera has moved this far.
const REFRESH_DISTANCE:=8.0
## Full-detail tiles within this distance of the camera get collision (one built per frame).
const COLLISION_RANGE:=40.0
## Built tiles kept for when they are wanted again.
const CACHE_LIMIT:=500

@export var settings: AbyssTerrainSettings
var observer: Node3D
var world: AbyssWorldMap
var hole: AbyssHole
var material: ShaderMaterial
## True once the first tiles around the start are on screen and those close by can be collided with. Only that first
## load holds the player still.
var near_ready:=false
## True when every wanted tile is on screen.
var all_ready:=false
## Tiles on screen: key -> {size, x, z, body, collider}.
var chunks:={}
var _wanted:={}
## Tiles not wanted yet but soon (see LEAD), built after the wanted ones.
var _ahead:={}
var _split:={}
var _cache:={}
var _pending: Array[String]=[]
## Background tasks running: each {id, results}.
var _jobs: Array[Dictionary]=[]
var _centre:=Vector3.INF
var _clock:=0
## Something changed (new tiles built, or a new set wanted), so what is on screen needs looking at again.
var _dirty:=false
var _shown_wanted:=0

func _ready() -> void:
	if not settings: settings=AbyssTerrainSettings.new()
	world=AbyssWorldMap.new(settings)
	material=ShaderMaterial.new()
	material.shader=load('res://world/terrain/terrain.gdshader')
	material.set_shader_parameter('ground_colour',GROUND_COLOUR)
	material.set_shader_parameter('ground_normal',GROUND_NORMAL)
	material.set_shader_parameter('rock_colour',ROCK_COLOUR)
	material.set_shader_parameter('rock_normal',ROCK_NORMAL)
	hole=AbyssHole.new()
	hole.name='Hole'
	add_child(hole)
	hole.start(AbyssWorldMap.new(settings),material)

func focus() -> Vector3:
	return observer.global_position if observer and observer.is_inside_tree() else Vector3.ZERO

func _process(_delta: float) -> void:
	var centre:=focus()
	if _centre==Vector3.INF or Vector2(centre.x,centre.z).distance_to(Vector2(_centre.x,_centre.z))>REFRESH_DISTANCE:
		_centre=centre
		_choose(centre)
	for job in _jobs.duplicate():
		if not WorkerThreadPool.is_task_completed(job.id): continue
		WorkerThreadPool.wait_for_task_completion(job.id)
		_jobs.erase(job)
		for result in job.results: _cache[result.key]=result
		_dirty=true
	while _jobs.size()<JOBS and not _pending.is_empty():
		var batch:=[]
		while not _pending.is_empty() and batch.size()<TILES_PER_JOB:
			var key: String=_pending.pop_front()
			var tile: Dictionary=_wanted.get(key,_ahead.get(key,{}))
			if not tile.is_empty() and not _cache.has(key): batch.append([key,tile.size,tile.x,tile.z])
		if batch.is_empty(): continue
		var results: Array[Dictionary]=[]
		_jobs.append({id=WorkerThreadPool.add_task(_build_job.bind(batch,results),true,'Terrain tiles'),results=results})
	if _dirty: _update_display()
	all_ready=_shown_wanted==_wanted.size() and chunks.size()==_wanted.size()
	_build_collision(centre)
	hole.update(centre)
	if not near_ready and all_ready:
		near_ready=true
		for key in chunks:
			if _wants_collision(chunks[key],centre) and not chunks[key].get('collider'): near_ready=false

## Which tiles should be on screen for a camera here: a quadtree over the whole map.
func _choose(centre: Vector3) -> void:
	var wanted:={}
	var split:={}
	var half:=settings.world_size*0.5
	var top:=SIZES.size()-1
	var root: float=SIZES[top]
	var z:=-half
	while z<half:
		var x:=-half
		while x<half:
			_visit(top,x,z,centre,wanted,split)
			x+=root
		z+=root
	_wanted=wanted
	_split=split
	all_ready=false
	_dirty=true
	_pending.clear()
	for key in _wanted:
		if not _cache.has(key): _pending.append(key)
	_pending.sort_custom(func(a: String,b: String) -> bool: return _wanted[a].near<_wanted[b].near)
	# Then the tiles that will be wanted soon (built after everything wanted now).
	_ahead.clear()
	var ahead:={}
	var ahead_split:={}
	z=-half
	while z<half:
		var x:=-half
		while x<half:
			_visit(top,x,z,centre,ahead,ahead_split,LEAD)
			x+=root
		z+=root
	var later: Array[String]=[]
	for key in ahead:
		if not _cache.has(key) and not _wanted.has(key):
			later.append(key)
			_ahead[key]=ahead[key]
	later.sort_custom(func(a: String,b: String) -> bool: return ahead[a].near<ahead[b].near)
	_pending.append_array(later)
	_trim_cache()

func _visit(level: int,x: float,z: float,centre: Vector3,wanted: Dictionary,split: Dictionary,lead:=1.0) -> void:
	var size: float=SIZES[level]
	var key:='%d:%d:%d'%[size,x,z]
	var near:=Vector2(centre.x,centre.z).distance_to(Vector2(clampf(centre.x,x,x+size),clampf(centre.z,z,z+size)))
	if level>0:
		var limit:=size*SPLIT*lead*(HYSTERESIS if _split.has(key) else 1.0)
		if near<limit:
			split[key]=true
			var h:=size*0.5
			_visit(level-1,x,z,centre,wanted,split,lead)
			_visit(level-1,x+h,z,centre,wanted,split,lead)
			_visit(level-1,x,z+h,centre,wanted,split,lead)
			_visit(level-1,x+h,z+h,centre,wanted,split,lead)
			return
	wanted[key]={size=size,x=x,z=z,near=near}

## Brings what is on screen towards the wanted set, a patch at a time, as tiles get built. A wanted tile is shown as
## soon as it is built, unless it lies over a tile still on screen that is no longer wanted (a coarser one being split,
## or finer ones being joined): that old tile stays until every wanted tile over its ground is built, and then they
## change over together. So the ground never goes missing while you move, and nothing is ever drawn twice.
func _update_display() -> void:
	_dirty=false
	var waiting:={}
	for key in chunks.keys():
		if _wanted.has(key): continue
		var old: Dictionary=chunks[key]
		var over:=[]
		var ready:=true
		for k in _wanted:
			var w: Dictionary=_wanted[k]
			if w.x<old.x+old.size and old.x<w.x+w.size and w.z<old.z+old.size and old.z<w.z+w.size:
				over.append(k)
				if not _cache.has(k): ready=false
		if ready:
			chunks[key].body.queue_free()
			chunks.erase(key)
			for k in over: _show(k)
		else:
			for k in over: waiting[k]=true
	_shown_wanted=0
	for key in _wanted:
		if not chunks.has(key) and _cache.has(key) and not waiting.has(key): _show(key)
		if chunks.has(key): _shown_wanted+=1

func _show(key: String) -> void:
	if chunks.has(key): return
	var built: Dictionary=_cache[key]
	built.used=_clock
	_clock+=1
	if not built.has('mesh'):
		var mesh:=ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,built.arrays)
		built.mesh=mesh
	var body:=StaticBody3D.new()
	body.name='Tile_%s'%key.replace(':','_')
	body.collision_layer=1
	body.collision_mask=0
	var visual:=MeshInstance3D.new()
	visual.mesh=built.mesh
	visual.material_override=material
	visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(visual)
	add_child(body)
	chunks[key]={size=_wanted[key].size,x=_wanted[key].x,z=_wanted[key].z,body=body}

func _wants_collision(tile: Dictionary,centre: Vector3) -> bool:
	if tile.size!=SIZES[0]: return false
	var x: float=tile.x
	var z: float=tile.z
	var near:=Vector2(centre.x,centre.z).distance_to(Vector2(clampf(centre.x,x,x+tile.size),clampf(centre.z,z,z+tile.size)))
	return near<COLLISION_RANGE

## Gives the nearest close tile without collision its collision (one a frame), and takes it off tiles left behind.
func _build_collision(centre: Vector3) -> void:
	var best:=''
	var best_near:=INF
	for key in chunks:
		var tile: Dictionary=chunks[key]
		var want:=_wants_collision(tile,centre)
		if not want and tile.get('collider'):
			tile.collider.queue_free()
			tile.erase('collider')
		elif want and not tile.get('collider'):
			var near:=Vector2(centre.x,centre.z).distance_to(Vector2(tile.x+tile.size*0.5,tile.z+tile.size*0.5))
			if near<best_near:
				best_near=near
				best=key
	if best=='': return
	var shape:=ConcavePolygonShape3D.new()
	shape.backface_collision=true
	shape.set_faces(_cache[best].faces)
	var collider:=CollisionShape3D.new()
	collider.shape=shape
	chunks[best].body.add_child(collider)
	chunks[best].collider=collider

func _trim_cache() -> void:
	if _cache.size()<=CACHE_LIMIT: return
	var old:=[]
	for key in _cache:
		if not _wanted.has(key) and not chunks.has(key): old.append(key)
	old.sort_custom(func(a: String,b: String) -> bool: return _cache[a].get('used',0)<_cache[b].get('used',0))
	for i in range(mini(old.size(),_cache.size()-CACHE_LIMIT)): _cache.erase(old[i])

func _build_job(batch: Array,results: Array[Dictionary]) -> void:
	var map:=AbyssWorldMap.new(settings)
	for item in batch:
		var result:=build_tile(map,item[1],item[2],item[3])
		result.key=item[0]
		results.append(result)

## One tile's mesh arrays (and its triangles, for collision). Heights are sampled one step beyond the tile on every
## side so the normals at its edges match its neighbours'.
static func build_tile(map: AbyssWorldMap,size: float,x0: float,z0: float) -> Dictionary:
	var n:=SEGMENTS
	var step:=size/n
	var side:=n+3
	var h:=PackedFloat32Array()
	var sand:=PackedFloat32Array()
	var silt:=PackedFloat32Array()
	h.resize(side*side)
	sand.resize(side*side)
	silt.resize(side*side)
	for j in range(side):
		for i in range(side):
			var here:=map.sample(x0+(i-1)*step,z0+(j-1)*step)
			h[i+side*j]=here.x
			sand[i+side*j]=here.y
			silt[i+side*j]=here.z
	var vertices:=PackedVector3Array()
	var normals:=PackedVector3Array()
	var colours:=PackedColorArray()
	var indices:=PackedInt32Array()
	var stride:=n+1
	for j in range(stride):
		for i in range(stride):
			var c:=(i+1)+side*(j+1)
			vertices.append(Vector3(x0+i*step,h[c],z0+j*step))
			var normal:=Vector3(h[c-1]-h[c+1],2.0*step,h[c-side]-h[c+side]).normalized()
			normals.append(normal)
			# Sand where the region is sandy and the ground faces up, rock elsewhere; sunlit everywhere; large lighter and
			# darker patches (in the ambient occlusion channel) so the textures do not read as a repeating pattern; and how
			# much of the sand is grey silt (in alpha).
			colours.append(Color(smoothstep(0.5,0.88,normal.y)*sand[c],1.0,map.patch(x0+i*step,z0+j*step),silt[c]))
	# Each vertex also carries the height the next coarser tile has there (its own height where that tile has a vertex,
	# else halfway along that tile's edge or diagonal), and the distance from the camera by which it has fully become
	# that: the shader blends towards it with distance, so a tile looks exactly like its coarser replacement by the time
	# they swap, and its edges match a coarser neighbour's. The largest tiles never change, so they get 0 (no blend).
	var morph:=PackedVector2Array()
	var end:=size*2.0*SPLIT if size<SIZES[SIZES.size()-1] else 0.0
	for j in range(stride):
		for i in range(stride):
			var c:=(i+1)+side*(j+1)
			var target:=h[c]
			if i%2==1 and j%2==0: target=(h[c-1]+h[c+1])*0.5
			elif i%2==0 and j%2==1: target=(h[c-side]+h[c+side])*0.5
			elif i%2==1 and j%2==1: target=(h[c+1-side]+h[c-1+side])*0.5
			morph.append(Vector2(target,end))
	for j in range(n):
		for i in range(n):
			var a:=i+stride*j
			var b:=a+1
			var c:=a+stride
			var d:=c+1
			# Godot draws the clockwise side, which faces up here.
			indices.append_array(PackedInt32Array([a,b,c,b,d,c]))
	var faces:=PackedVector3Array()
	faces.resize(indices.size())
	for f in range(indices.size()): faces[f]=vertices[indices[f]]
	# Skirts: each edge hangs down a little (more on coarse tiles), drawn from both sides, so the odd crack where a
	# coarser neighbour's edge cuts the corner does not show through.
	var drop:=minf(24.0,2.4+0.012*step*step)
	var edges:=[range(0,stride),range(n,stride*stride,stride),range(stride*n,stride*stride),range(0,stride*stride,stride)]
	for edge in edges:
		var start:=vertices.size()
		for v in edge:
			vertices.append(vertices[v]-Vector3(0.0,drop,0.0))
			normals.append(normals[v])
			colours.append(colours[v])
			morph.append(morph[v]-Vector2(drop,0.0))
		for k in range(edge.size()-1):
			var a: int=edge[k]
			var b: int=edge[k+1]
			var la:=start+k
			var lb:=start+k+1
			indices.append_array(PackedInt32Array([a,b,lb,a,lb,la,a,lb,b,a,la,lb]))
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colours
	arrays[Mesh.ARRAY_TEX_UV2]=morph
	arrays[Mesh.ARRAY_INDEX]=indices
	return {arrays=arrays,faces=faces}

func _exit_tree() -> void:
	for job in _jobs: WorkerThreadPool.wait_for_task_completion(job.id)
	_jobs.clear()
