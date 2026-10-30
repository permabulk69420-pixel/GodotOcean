class_name AbyssTerrainGenerator
extends RefCounted
## Positive density is rock; negative density is water/air. Samples use world coordinates.
const CORNERS := [Vector3i(0,0,0),Vector3i(1,0,0),Vector3i(1,1,0),Vector3i(0,1,0),Vector3i(0,0,1),Vector3i(1,0,1),Vector3i(1,1,1),Vector3i(0,1,1)]
const TETRA := [[0,1,2,6],[0,2,3,6],[0,3,7,6],[0,7,4,6],[0,4,5,6],[0,5,1,6]]
var settings: AbyssTerrainSettings
var broad := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var segments: Array[Vector4] = []
var ends: Array[Vector4] = []
var routes: Array[PackedVector3Array] = []
var entrances := PackedVector3Array()
var chamber := Vector3.ZERO
var sun_direction := Vector3(0.3584,0.5299,-0.7685).normalized()

func _init(config: AbyssTerrainSettings = null) -> void:
	settings=config if config else AbyssTerrainSettings.new()
	broad.seed=settings.seed
	broad.frequency=0.027
	broad.fractal_octaves=3
	detail.seed=settings.seed+411
	detail.frequency=0.10
	detail.fractal_octaves=2
	build_network()

func height(x: float,z: float) -> float:
	var n := broad.get_noise_2d(x,z)
	var shelves := smoothstep(-0.30,0.40,n)*3.3
	var channels := exp(-pow((x-10.0*sin(z*0.045))/8.0,2.0))*1.4
	return minf(-3.0,-settings.mean_depth+shelves+detail.get_noise_2d(x,z)*0.65-channels)

func build_network() -> void:
	var rng:=RandomNumberGenerator.new()
	rng.seed=settings.seed
	var shift:=Vector3(rng.randf_range(-3,3),0,rng.randf_range(-2,2))
	chamber=Vector3(24,-17,-24)+shift
	var a:=Vector3(0,height(0,-12)+0.8,-12)
	var b:=Vector3(43,height(43,-8)+0.8,-8)
	var c:=Vector3(-30,height(-30,-32)+0.8,-32)
	entrances=PackedVector3Array([a,b,c])
	_add_route(PackedVector3Array([a,Vector3(2,-12,-20)+shift,Vector3(12,-16,-28)+shift,chamber,Vector3(35,-14,-20)+shift,b]),3.1)
	_add_route(PackedVector3Array([chamber,Vector3(6,-17,-41)+shift,Vector3(-13,-14,-42)+shift,c]),2.8)
	# A chamber is part of the same field, joined to both passages.
	segments.append(Vector4(chamber.x,chamber.y,chamber.z,5.7))
	ends.append(segments[-1])

func _add_route(points: PackedVector3Array,radius: float) -> void:
	var samples:=PackedVector3Array()
	for i in range(points.size()-1):
		var a:=points[maxi(i-1,0)]
		var b:=points[i]
		var c:=points[i+1]
		var d:=points[mini(i+2,points.size()-1)]
		var count:=maxi(2,ceili(b.distance_to(c)/2.0))
		for j in range(count): samples.append(b.cubic_interpolate(c,a,d,float(j)/count))
	samples.append(points[-1])
	routes.append(samples)
	for i in range(samples.size()-1):
		var r:=radius+0.35*sin(float(i)*0.65)
		segments.append(Vector4(samples[i].x,samples[i].y,samples[i].z,r))
		ends.append(Vector4(samples[i+1].x,samples[i+1].y,samples[i+1].z,r))

func relevant_segments(bounds: AABB) -> PackedInt32Array:
	var result:=PackedInt32Array()
	for i in range(segments.size()):
		var a:=Vector3(segments[i].x,segments[i].y,segments[i].z)
		var b:=Vector3(ends[i].x,ends[i].y,ends[i].z)
		var box:=AABB(a,Vector3.ZERO).expand(b).grow(segments[i].w+2)
		if box.intersects(bounds): result.append(i)
	return result

func density(p: Vector3, subset: PackedInt32Array = PackedInt32Array(), all_caves: bool = true) -> float:
	var value:=height(p.x,p.z)-p.y
	if value< -7.0: return value
	var cave_distance:=100000.0
	var count:=segments.size() if all_caves else subset.size()
	for j in range(count):
		var i:=j if all_caves else subset[j]
		var a:=Vector3(segments[i].x,segments[i].y,segments[i].z)
		var b:=Vector3(ends[i].x,ends[i].y,ends[i].z)
		var ab:=b-a
		var t:=clampf((p-a).dot(ab)/maxf(ab.length_squared(),0.00001),0,1)
		var distance: float=p.distance_to(a+ab*t)-segments[i].w
		cave_distance=smooth_union(cave_distance,distance,0.6)
	return smooth_union(value,cave_distance,1.2)

func smooth_union(a: float,b: float,width: float) -> float:
	var h:=clampf(0.5+0.5*(b-a)/width,0,1)
	return lerpf(b,a,h)-width*h*(1.0-h)

func normal(p: Vector3, subset: PackedInt32Array) -> Vector3:
	var e:=0.12
	return -Vector3(density(p+Vector3(e,0,0),subset,false)-density(p-Vector3(e,0,0),subset,false),density(p+Vector3(0,e,0),subset,false)-density(p-Vector3(0,e,0),subset,false),density(p+Vector3(0,0,e),subset,false)-density(p-Vector3(0,0,e),subset,false)).normalized()

func lighting(p: Vector3,n: Vector3, subset: PackedInt32Array) -> Color:
	var visibility:=1.0
	var distance:=0.18
	# Static sun occlusion is baked into the mesh instead of rendering shadow maps every eye/frame.
	for i in range(28):
		var q:=p+n*0.15+sun_direction*distance
		if q.y> -2.0: break
		var field: float=density(q)
		if field>0.03:
			visibility=0.0
			break
		distance+=clampf(-field*0.7,0.35,4.0)
	var ao:=1.0
	for r in [0.7,1.7,3.2]:
		var clearance: float=-density(p+n*r,subset,false)
		ao-=maxf(0.0,r-clearance)/r*0.19
	var sand:=smoothstep(0.35,0.86,n.y)
	return Color(sand,visibility,clampf(ao,0.16,1.0),1)

func generate(coordinate: Vector3i) -> AbyssTerrainChunk:
	var data:=AbyssTerrainChunk.new()
	data.coordinate=coordinate
	data.signature=settings.signature()
	var cells:=roundi(settings.chunk_size/settings.voxel_size)
	var side:=cells+1
	var base:=Vector3(coordinate)*settings.chunk_size
	var subset:=relevant_segments(AABB(base,Vector3.ONE*settings.chunk_size).grow(4))
	var values:=PackedFloat32Array()
	values.resize(side*side*side)
	var any_air:=false
	var any_solid:=false
	for y in range(side):
		for z in range(side):
			for x in range(side):
				var value:=density(base+Vector3(x,y,z)*settings.voxel_size,subset,false)
				values[x+side*(z+side*y)]=value
				any_air=any_air or value<0
				any_solid=any_solid or value>=0
	if not any_air or not any_solid: return data
	var vertices:=PackedVector3Array()
	var normals:=PackedVector3Array()
	var colors:=PackedColorArray()
	var indices:=PackedInt32Array()
	var edge_ids: Dictionary={}
	var position_ids: Dictionary={}
	for y in range(cells):
		for z in range(cells):
			for x in range(cells):
				var ids:=PackedInt32Array()
				var mask:=0
				for j in range(8):
					var c: Vector3i=CORNERS[j]+Vector3i(x,y,z)
					ids.append(c.x+side*(c.z+side*c.y))
					if values[ids[-1]]>=0: mask|=1<<j
				if mask==0 or mask==255: continue
				for tetra in TETRA:
					var inside:=PackedInt32Array()
					var outside:=PackedInt32Array()
					for c in tetra:
						if values[ids[c]]>=0: inside.append(ids[c])
						else: outside.append(ids[c])
					if inside.is_empty() or outside.is_empty(): continue
					var crossing:=PackedInt32Array()
					for a in inside:
						for b in outside:
							var lo:=mini(a,b); var hi:=maxi(a,b)
							var key:=lo+hi*side*side*side
							if not edge_ids.has(key):
								var pa:=Vector3(lo%side,lo/(side*side),(lo/side)%side)*settings.voxel_size+base
								var pb:=Vector3(hi%side,hi/(side*side),(hi/side)%side)*settings.voxel_size+base
								var v:=pa.lerp(pb,values[lo]/(values[lo]-values[hi])).snapped(Vector3.ONE*0.00001)
								if not position_ids.has(v):
									position_ids[v]=vertices.size()
									vertices.append(v)
									normals.append(normal(v,subset))
								edge_ids[key]=position_ids[v]
							crossing.append(edge_ids[key])
					var tris:= [0,1,2] if crossing.size()==3 else [0,1,2,1,3,2]
					for k in range(0,tris.size(),3):
						var a:=crossing[tris[k]];var b:=crossing[tris[k+1]];var c:=crossing[tris[k+2]]
						var cross: Vector3=(vertices[b]-vertices[a]).cross(vertices[c]-vertices[a])
						if cross.dot(normals[a]+normals[b]+normals[c])>0:
							indices.append_array(PackedInt32Array([a,c,b]))
						else: indices.append_array(PackedInt32Array([a,b,c]))
	if indices.is_empty(): return data
	# Relax the actual mesh, then project back to the rounded density surface.
	# Border vertices stay fixed, so independently loaded neighbouring chunks remain watertight.
	var neighbours: Array[PackedInt32Array]=[]
	neighbours.resize(vertices.size())
	for i in range(0,indices.size(),3):
		for edge in range(3):
			var a:=indices[i+edge];var b:=indices[i+(edge+1)%3]
			if not neighbours[a].has(b): neighbours[a].append(b)
			if not neighbours[b].has(a): neighbours[b].append(a)
	for iteration in range(2):
		var smoothed:=vertices.duplicate()
		for i in range(vertices.size()):
			var local:=vertices[i]-base
			if minf(minf(local.x,local.y),local.z)<0.001 or maxf(maxf(local.x,local.y),local.z)>settings.chunk_size-0.001: continue
			var average:=Vector3.ZERO
			for j in neighbours[i]: average+=vertices[j]
			if neighbours[i].is_empty(): continue
			var v:=vertices[i].lerp(average/neighbours[i].size(),0.45)
			v+=normal(v,subset)*clampf(density(v,subset,false),-0.35,0.35)
			smoothed[i]=v
		vertices=smoothed
	for i in range(vertices.size()): normals[i]=normal(vertices[i],subset)
	var final_indices:=PackedInt32Array()
	for i in range(0,indices.size(),3):
		var a:=indices[i];var b:=indices[i+1];var c:=indices[i+2]
		var face: Vector3=(vertices[b]-vertices[a]).cross(vertices[c]-vertices[a])
		if face.length_squared()==0.0: continue
		if face.dot(normals[a]+normals[b]+normals[c])>0:
			final_indices.append_array(PackedInt32Array([a,c,b]))
		else: final_indices.append_array(PackedInt32Array([a,b,c]))
	indices=final_indices
	for i in range(vertices.size()): colors.append(lighting(vertices[i],normals[i],subset))
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_INDEX]=indices
	data.mesh=ArrayMesh.new()
	data.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	data.collision=data.mesh.create_trimesh_shape()
	data.collision.backface_collision=true
	return data
