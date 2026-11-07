class_name AbyssVoxelMesher
extends RefCounted
## Builds one block's mesh from the stored voxels, at 1, 2 or 4 m detail (lod 0, 1, 2). Runs on worker threads.
##
## Each cell is cut into six tetrahedra (all sharing the cell's diagonal from its low corner to its high corner) and the
## surface is put where the voxels change sign along their edges. Neighbouring blocks at the same detail share their
## boundary voxels exactly, so their meshes meet. Where a neighbour is one level coarser, the voxels on the shared
## boundary are replaced by what the coarser block sees there: its own voxels joined in straight lines across the same
## triangles its cells are cut into. The finer triangles lie inside those, so both meshes meet the boundary along the
## same line. Neighbours never differ by more than one level (AbyssTerrain keeps it so).

const CORNERS := [Vector3i(0,0,0),Vector3i(1,0,0),Vector3i(1,1,0),Vector3i(0,1,0),Vector3i(0,0,1),Vector3i(1,0,1),Vector3i(1,1,1),Vector3i(0,1,1)]
const TETRA := [[0,1,2,6],[0,2,3,6],[0,3,7,6],[0,7,4,6],[0,4,5,6],[0,5,1,6]]
## Towards the sun, for the baked-in shade (the shader dims sunlight and caustics where it is 0).
const SUN := Vector3(0.3584,0.5299,-0.7685)

## Returns vertices, normals, colours and indices for an ArrayMesh, and (for lod 0) the triangles for collision.
## coarse: for each neighbour offset whose block is one level coarser than this one, that level.
static func build(store: AbyssVoxelStore,block: Vector3i,lod: int,coarse: Dictionary) -> Dictionary:
	var step:=1<<lod
	var n:=AbyssTerrainSettings.BLOCK/step
	var side:=n+3
	var s2:=side*side
	var base:=block*AbyssTerrainSettings.BLOCK
	# The block's voxels at this level, with one more all round for the normals.
	var g:=store.fill(base-Vector3i.ONE*step,step,side)
	var sampler:=_Sampler.new(store)
	if not coarse.is_empty(): _match_coarser(g,side,n,step,base,lod,coarse,sampler)
	var vertices:=PackedVector3Array()
	var normals:=PackedVector3Array()
	var colours:=PackedColorArray()
	var indices:=PackedInt32Array()
	var edge_ids:={}
	var position_ids:={}
	var ids:=PackedInt32Array()
	ids.resize(8)
	var offsets:=PackedInt32Array([0,1,1+side,side,s2,1+s2,1+side+s2,side+s2])
	for k in range(n):
		for j in range(n):
			var row:=1+side*((j+1)+side*(k+1))
			for i in range(n):
				var c0:=row+i
				var mask:=0
				for c in range(8):
					ids[c]=c0+offsets[c]
					if g[ids[c]]>=0.0: mask|=1<<c
				if mask==0 or mask==255: continue
				for tetra in TETRA:
					var inside:=PackedInt32Array()
					var outside:=PackedInt32Array()
					for c in tetra:
						if g[ids[c]]>=0.0: inside.append(ids[c])
						else: outside.append(ids[c])
					if inside.is_empty() or outside.is_empty(): continue
					var crossing:=PackedInt32Array()
					var towards_water:=Vector3.ZERO
					for a in inside:
						for b in outside:
							var key:=mini(a,b)+maxi(a,b)*side*s2
							if not edge_ids.has(key):
								var pa:=_position(a,side,step,base)
								var pb:=_position(b,side,step,base)
								var t: float=g[a]/(g[a]-g[b])
								var v:=pa.lerp(pb,t).snapped(Vector3.ONE*0.0001)
								if not position_ids.has(v):
									position_ids[v]=vertices.size()
									vertices.append(v)
									var grad:=_gradient(g,a,side,step).lerp(_gradient(g,b,side,step),t)
									normals.append(-grad.normalized() if grad.length_squared()>0.0000001 else (pb-pa).normalized())
								edge_ids[key]=position_ids[v]
							crossing.append(edge_ids[key])
					for a in inside: towards_water-=_position(a,side,step,base)/inside.size()
					for b in outside: towards_water+=_position(b,side,step,base)/outside.size()
					var tris:=[0,1,2] if crossing.size()==3 else [0,1,2,1,3,2]
					for t in range(0,tris.size(),3):
						var a:=crossing[tris[t]]
						var b:=crossing[tris[t+1]]
						var c:=crossing[tris[t+2]]
						if a==b or b==c or a==c: continue
						# Godot draws the clockwise side: its front is (c - a) x (b - a). Point it at the water.
						var front:=(vertices[c]-vertices[a]).cross(vertices[b]-vertices[a])
						if front.dot(towards_water)<0.0: indices.append_array(PackedInt32Array([a,c,b]))
						else: indices.append_array(PackedInt32Array([a,b,c]))
	var result:={vertices=vertices,normals=normals,colours=colours,indices=indices}
	if indices.is_empty(): return result
	for v in range(vertices.size()): colours.append(_shade(sampler,vertices[v],normals[v]))
	if lod==0:
		var faces:=PackedVector3Array()
		faces.resize(indices.size())
		for f in range(indices.size()): faces[f]=vertices[indices[f]]
		result.faces=faces
	_add_skirts(vertices,normals,colours,indices,base,step)
	return result

## Where a finer block meets a coarser one, the finer one has extra points along the coarser one's edge. They are on
## that edge exactly, but the graphics card can still leave the odd pixel uncovered along it. So a narrow strip hangs
## from every boundary edge into the rock, drawn from both sides, for anything seen through such a gap to land on.
## Skirt vertices have alpha 0 (the terrain shader does not use it; tests use it to tell them apart). Not collided with.
static func _add_skirts(vertices: PackedVector3Array,normals: PackedVector3Array,colours: PackedColorArray,indices: PackedInt32Array,base: Vector3i,step: int) -> void:
	var size:=float(AbyssTerrainSettings.BLOCK)
	var lo:=Vector3(base)
	var count:={}
	for i in range(0,indices.size(),3):
		for e in range(3):
			var key:=Vector2i(mini(indices[i+e],indices[i+(e+1)%3]),maxi(indices[i+e],indices[i+(e+1)%3]))
			count[key]=count.get(key,0)+1
	var depth:=0.6*step
	var hung:={}
	for key in count:
		if count[key]!=1: continue
		var a:=vertices[key.x]
		var b:=vertices[key.y]
		var on_face:=false
		for axis in range(3):
			for side in [lo[axis],lo[axis]+size]:
				if absf(a[axis]-side)<0.001 and absf(b[axis]-side)<0.001: on_face=true
		if not on_face: continue
		# Each end: a copy at the edge and one hung below it (copies, so the whole skirt carries the alpha 0 mark).
		var top:=PackedInt32Array()
		var bottom:=PackedInt32Array()
		for v in [key.x,key.y]:
			if not hung.has(v):
				hung[v]=vertices.size()
				var c:=colours[v]
				for offset in [0.0,depth]:
					vertices.append(vertices[v]-normals[v]*offset)
					normals.append(normals[v])
					colours.append(Color(c.r,c.g,c.b,0.0))
			top.append(hung[v])
			bottom.append(hung[v]+1)
		indices.append_array(PackedInt32Array([top[0],top[1],bottom[1],top[0],bottom[1],bottom[0],top[0],bottom[1],top[1],top[0],bottom[0],bottom[1]]))

static func _position(index: int,side: int,step: int,base: Vector3i) -> Vector3:
	var x:=index%side
	var y:=(index/side)%side
	var z:=index/(side*side)
	return Vector3(base)+Vector3(x-1,y-1,z-1)*step

static func _gradient(g: PackedFloat32Array,i: int,side: int,step: int) -> Vector3:
	return Vector3(g[i+1]-g[i-1],g[i+side]-g[i-side],g[i+side*side]-g[i-side*side])/(2.0*step)

## Sand where the ground faces up; how much of the sun reaches it (0 in the shadow of rock above); how open it is.
static func _shade(sampler: _Sampler,p: Vector3,n: Vector3) -> Color:
	var sun:=1.0
	# Deeper than this the water has all but absorbed the sun anyway.
	if p.y> -64.0:
		for i in range(1,14):
			var q:=p+n*0.6+SUN*(i*2.0)
			if q.y> -2.0: break
			if sampler.at(q)>0.1:
				sun=0.0
				break
	var ao:=1.0
	for r in [0.7,1.7,3.2]:
		var clearance:=-sampler.at(p+n*r)
		ao-=maxf(0.0,r-clearance)/r*0.19
	return Color(smoothstep(0.35,0.86,n.y),sun,clampf(ao,0.16,1.0),1.0)

static func _match_coarser(g: PackedFloat32Array,side: int,n: int,step: int,base: Vector3i,lod: int,coarse: Dictionary,sampler: _Sampler) -> void:
	for k in range(n+1):
		for j in range(n+1):
			var on_jk:=j==0 or j==n or k==0 or k==n
			var i:=0
			while i<=n:
				var o:=Vector3i(-1 if i==0 else (1 if i==n else 0),-1 if j==0 else (1 if j==n else 0),-1 if k==0 else (1 if k==n else 0))
				var axes:=int(o.x!=0)+int(o.y!=0)+int(o.z!=0)
				var level:=lod
				for sx in ([0,o.x] if o.x!=0 else [0]):
					for sy in ([0,o.y] if o.y!=0 else [0]):
						for sz in ([0,o.z] if o.z!=0 else [0]):
							if sx!=0 or sy!=0 or sz!=0: level=maxi(level,coarse.get(Vector3i(sx,sy,sz),lod))
				# A block's corners are on every level's grid, so they never need it.
				if level>lod and axes<3:
					var p:=base+Vector3i(i,j,k)*step
					g[(i+1)+side*((j+1)+side*(k+1))]=_coarse_value(sampler,p,o,1<<level)
				i+=1 if on_jk else n
	return

## The value at p as a block with voxels every `size` metres sees it, on a boundary of this block: across the face (in
## the face's two directions, along that block's triangles) or along the edge.
static func _coarse_value(sampler: _Sampler,p: Vector3i,o: Vector3i,size: int) -> float:
	var free: Array[int]=[]
	for a in range(3):
		if o[a]==0: free.append(a)
	if free.size()==1:
		var c:=free[0]
		var c0:=floori(float(p[c])/size)*size
		var t:=float(p[c]-c0)/size
		var q0:=p
		q0[c]=c0
		var q1:=q0
		q1[c]=c0+size
		return lerpf(sampler.at_point(q0),sampler.at_point(q1),t)
	# On a face: the other two directions in order (x before y before z); the cells' faces are cut from their low
	# corner to their high corner in those.
	var u:=free[0]
	var w:=free[1]
	var u0:=floori(float(p[u])/size)*size
	var w0:=floori(float(p[w])/size)*size
	var fu:=float(p[u]-u0)/size
	var fw:=float(p[w]-w0)/size
	var q00:=p
	q00[u]=u0
	q00[w]=w0
	var q11:=q00
	q11[u]+=size
	q11[w]+=size
	var v00:=sampler.at_point(q00)
	var v11:=sampler.at_point(q11)
	if fu>=fw:
		var q10:=q00
		q10[u]+=size
		var v10:=sampler.at_point(q10)
		return v00+fu*(v10-v00)+fw*(v11-v10)
	var q01:=q00
	q01[w]+=size
	var v01:=sampler.at_point(q01)
	return v00+fw*(v01-v00)+fu*(v11-v01)

## Reads voxels at any point, keeping the blocks it has used so each is only fetched from the store once.
class _Sampler:
	var store: AbyssVoxelStore
	var blocks:={}
	func _init(from: AbyssVoxelStore) -> void: store=from
	func at(p: Vector3) -> float:
		return at_point(Vector3i(roundi(p.x),roundi(p.y),roundi(p.z)))
	func at_point(p: Vector3i) -> float:
		var n:=AbyssTerrainSettings.BLOCK
		var x:=clampi(p.x,store.low.x*n,store.high.x*n-1)
		var z:=clampi(p.z,store.low.z*n,store.high.z*n-1)
		var b:=Vector3i(floori(float(x)/n),floori(float(p.y)/n),floori(float(z)/n))
		var got: Variant=blocks.get(b)
		if got==null:
			got=store.block(b)
			blocks[b]=got
		if got is PackedByteArray: return (got[(x-b.x*n)+n*((p.y-b.y*n)+n*(z-b.z*n))]-128)*(AbyssTerrainSettings.DISTANCE_RANGE/127.0)
		return AbyssVoxelStore.SOLID_VALUE if got==AbyssVoxelBatch.SOLID else AbyssVoxelStore.EMPTY_VALUE
