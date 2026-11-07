class_name AbyssHole
extends Node3D
## The giant hole's walls: a mesh, sheer and in places overhanging, from the rim down past the floor. The height map
## only drops across a narrow band at the rim (AbyssWorldMap.HOLE_BAND); these walls stand just inside that band and
## hide it, and their top edge folds out over the rim onto the plateau so the two meet. The walls are built once on a
## worker thread, in pieces; pieces near the camera get collision (one built per frame).

const SEGMENTS:=160
const RING_SPACING:=4.0
## The walls stand this far inside the rim at least, and wander up to WOBBLE further in; bands of rock bulge out
## by up to LEDGE more (overhangs).
const INSET:=4.0
const WOBBLE:=16.0
const LEDGE:=10.0
## The fold over the rim reaches this far out onto the plateau.
const FOLD:=6.0
const SECTORS:=16
const RINGS_PER_PIECE:=25
const COLLISION_RANGE:=50.0
const VIEW_RANGE:=280.0

var material: Material
var pieces: Array[Dictionary]=[]
var _job:=-1
var _built: Array[Dictionary]=[]

func start(map: AbyssWorldMap,surface: Material) -> void:
	material=surface
	_job=WorkerThreadPool.add_task(_build.bind(map),false,'Hole walls')

func ready() -> bool:
	return _job==-1 and not pieces.is_empty()

## Puts the built pieces into the scene once, and gives pieces near this point collision.
func update(centre: Vector3) -> void:
	if _job!=-1:
		if not WorkerThreadPool.is_task_completed(_job): return
		WorkerThreadPool.wait_for_task_completion(_job)
		_job=-1
		for built in _built: _install(built)
		_built.clear()
	var best:=-1
	var best_d:=INF
	for i in range(pieces.size()):
		var piece: Dictionary=pieces[i]
		var box: AABB=piece.box
		var d:=centre.distance_to(centre.clamp(box.position,box.end))
		if d<COLLISION_RANGE and not piece.get('collider') and d<best_d:
			best=i
			best_d=d
		elif d>COLLISION_RANGE*1.2 and piece.get('collider'):
			piece.collider.queue_free()
			piece.erase('collider')
	if best<0: return
	var shape:=ConcavePolygonShape3D.new()
	shape.backface_collision=true
	shape.set_faces(pieces[best].faces)
	var collider:=CollisionShape3D.new()
	collider.shape=shape
	pieces[best].body.add_child(collider)
	pieces[best].collider=collider

func _install(built: Dictionary) -> void:
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,built.arrays)
	var body:=StaticBody3D.new()
	body.collision_layer=1
	body.collision_mask=0
	var visual:=MeshInstance3D.new()
	visual.mesh=mesh
	visual.material_override=material
	visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.visibility_range_end=VIEW_RANGE
	body.add_child(visual)
	add_child(body)
	pieces.append({body=body,faces=built.faces,box=built.box})

func _build(map: AbyssWorldMap) -> void:
	var settings:=map.settings
	var c:=settings.hole_centre
	var rim:=settings.hole_radius
	var wall:=FastNoiseLite.new()
	wall.seed=settings.seed+31
	wall.frequency=0.012
	wall.fractal_octaves=3
	var strata:=FastNoiseLite.new()
	strata.seed=settings.seed+32
	strata.frequency=0.02
	strata.fractal_octaves=2
	var bottom:=settings.hole_floor-12.0
	var top_heights:=PackedFloat32Array()
	var lowest_rim:=INF
	for s in range(SEGMENTS):
		var a:=TAU*s/SEGMENTS
		var p:=c+Vector2(cos(a),sin(a))*(map.hole_rim(a)+FOLD)
		top_heights.append(map.height(p.x,p.y)+0.2)
		lowest_rim=minf(lowest_rim,top_heights[s])
	# Ring 0 is the fold out on the plateau; rings 1.. run down the wall, evenly spaced from just under each point of
	# the rim to below the floor.
	var rings:=int(ceil((lowest_rim-2.0-bottom)/RING_SPACING))+2
	var grid: Array[PackedVector3Array]=[]
	for k in range(rings):
		var ring:=PackedVector3Array()
		for s in range(SEGMENTS):
			var a:=TAU*s/SEGMENTS
			var dir:=Vector2(cos(a),sin(a))
			var y: float
			var r: float
			var edge:=map.hole_rim(a)
			if k==0:
				y=top_heights[s]
				r=edge+FOLD
			else:
				y=lerpf(top_heights[s]-2.0,bottom,float(k-1)/(rings-2))
				var at:=c+dir*rim
				r=edge-INSET-(wall.get_noise_3d(at.x,y*0.5,at.y)*0.5+0.5)*WOBBLE
				r-=maxf(0.0,strata.get_noise_3d(at.x*0.5,y*1.5,at.y*0.5))*LEDGE*2.0
			ring.append(Vector3(c.x+dir.x*r,y,c.y+dir.y*r))
		grid.append(ring)
	# Normals from the faces around each point, so the pieces shade as one surface.
	var normals: Array[PackedVector3Array]=[]
	for k in range(rings):
		var ring:=PackedVector3Array()
		ring.resize(SEGMENTS)
		normals.append(ring)
	for k in range(rings-1):
		for s in range(SEGMENTS):
			var s2:=(s+1)%SEGMENTS
			var n:=_front(grid[k][s],grid[k][s2],grid[k+1][s])
			for v in [[k,s],[k,s2],[k+1,s],[k+1,s2]]: normals[v[0]][v[1]]+=n
	var per:=SEGMENTS/SECTORS
	var results: Array[Dictionary]=[]
	var k0:=0
	while k0<rings-1:
		var k1:=mini(k0+RINGS_PER_PIECE,rings-1)
		for sector in range(SECTORS):
			results.append(_piece(grid,normals,map,k0,k1,sector*per,sector*per+per))
		k0=k1
	_built=results

## Faces the inside of the hole (and up, on the fold): Godot draws the clockwise side, whose normal is (c - a) x (b - a).
func _front(a: Vector3,b: Vector3,c: Vector3) -> Vector3:
	return (c-a).cross(b-a)

func _piece(grid: Array[PackedVector3Array],normals: Array[PackedVector3Array],map: AbyssWorldMap,k0: int,k1: int,s0: int,s1: int) -> Dictionary:
	var vertices:=PackedVector3Array()
	var ns:=PackedVector3Array()
	var colours:=PackedColorArray()
	var indices:=PackedInt32Array()
	var width:=s1-s0+1
	var box:=AABB(grid[k0][s0%SEGMENTS],Vector3.ZERO)
	for k in range(k0,k1+1):
		for s in range(s0,s1+1):
			var v:=grid[k][s%SEGMENTS]
			vertices.append(v)
			var n:=normals[k][s%SEGMENTS].normalized()
			ns.append(n)
			# Rock on the walls; the fold takes the plateau's own sand.
			var sand:=map.sample(v.x,v.z).y*smoothstep(0.35,0.86,n.y) if k==0 else 0.05
			colours.append(Color(sand,1.0,1.0,1.0))
			box=box.expand(v)
	var faces:=PackedVector3Array()
	for k in range(k1-k0):
		for s in range(width-1):
			var a:=k*width+s
			var b:=a+1
			var c:=a+width
			var d:=c+1
			indices.append_array(PackedInt32Array([a,b,c,b,d,c]))
			for f in [a,b,c,b,d,c]: faces.append(vertices[f])
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=ns
	arrays[Mesh.ARRAY_COLOR]=colours
	arrays[Mesh.ARRAY_INDEX]=indices
	return {arrays=arrays,faces=faces,box=box}

func _exit_tree() -> void:
	if _job!=-1: WorkerThreadPool.wait_for_task_completion(_job)
	_job=-1
