class_name AbyssTerrainGenerator
extends RefCounted
## Positive density is rock; negative density is water/air. Samples use world coordinates.
const CORNERS := [Vector3i(0,0,0),Vector3i(1,0,0),Vector3i(1,1,0),Vector3i(0,1,0),Vector3i(0,0,1),Vector3i(1,0,1),Vector3i(1,1,1),Vector3i(0,1,1)]
const TETRA := [[0,1,2,6],[0,2,3,6],[0,3,7,6],[0,7,4,6],[0,4,5,6],[0,5,1,6]]
## The most the cliff's crags move its face up or down (about 4 m sideways on the steep part).
const CRAG_DEPTH := 36.0
## The hole widens by this much towards its rim, and its walls wander in and out by up to HOLE_WOBBLE.
const HOLE_FLARE := 12.0
const HOLE_WOBBLE := 5.0
## Cave carving is skipped this far outside the cave network's bounds, where it cannot change anything near the surface.
const CAVE_REACH := 12.0
var settings: AbyssTerrainSettings
var broad := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var deep_noise := FastNoiseLite.new()
var edge_noise := FastNoiseLite.new()
var crag := FastNoiseLite.new()
var hole_noise := FastNoiseLite.new()
var segments: Array[Vector4] = []
var ends: Array[Vector4] = []
var routes: Array[PackedVector3Array] = []
var entrances := PackedVector3Array()
var chamber := Vector3.ZERO
var network_bounds := AABB()
var sun_direction := Vector3(0.3584,0.5299,-0.7685).normalized()

func _init(config: AbyssTerrainSettings = null) -> void:
	settings=config if config else AbyssTerrainSettings.new()
	broad.seed=settings.seed
	broad.frequency=0.027
	broad.fractal_octaves=3
	detail.seed=settings.seed+411
	detail.frequency=0.10
	detail.fractal_octaves=2
	deep_noise.seed=settings.seed+907
	deep_noise.frequency=0.011
	deep_noise.fractal_octaves=3
	edge_noise.seed=settings.seed+1303
	edge_noise.frequency=0.012
	edge_noise.fractal_octaves=2
	crag.seed=settings.seed+1777
	crag.frequency=0.04
	crag.fractal_octaves=3
	hole_noise.seed=settings.seed+2113
	hole_noise.frequency=0.045
	hole_noise.fractal_octaves=2
	build_network()

## The shallows' own sea floor.
func shallows_height(x: float,z: float) -> float:
	var n := broad.get_noise_2d(x,z)
	var shelves := smoothstep(-0.30,0.40,n)*3.3
	var channels := exp(-pow((x-10.0*sin(z*0.045))/8.0,2.0))*1.4
	return minf(-3.0,-settings.mean_depth+shelves+detail.get_noise_2d(x,z)*0.65-channels)

## Where a point sits across the drop-off: 0 or less on the shallows' shelf, 0 at the lip, 1 at the foot of the cliff.
func drop_position(x: float,z: float) -> float:
	return (x-settings.shelf_edge-edge_noise.get_noise_1d(z)*settings.shelf_wobble)/settings.drop_width

## The deep plateau's floor, rising into a rim along the edges of the play area.
func deep_height(x: float,z: float) -> float:
	var area:=settings.play_area()
	var to_edge:=minf(area.end.x-x,minf(z-area.position.y,area.end.y-z))
	var rim:=pow(1.0-smoothstep(0.0,48.0,to_edge),2.0)*36.0
	return settings.deep_floor+deep_noise.get_noise_2d(x,z)*5.0+detail.get_noise_2d(x,z)*0.65+rim

func _height(x: float,z: float,u: float) -> float:
	var shallow:=shallows_height(x,z)
	if u<=0.0: return shallow
	# Steepest right at the lip, so the shelf ends sharply, then easing out across an apron to the plateau.
	return lerpf(shallow,deep_height(x,z),1.0-pow(1.0-minf(u,1.0),2.5))

## The ground's height without the cliff's crags or the hole (used to place things on the shallows' floor).
func height(x: float,z: float) -> float:
	return _height(x,z,drop_position(x,z))

## How much the crags apply across the drop-off: none on the shelf or the plateau, most just below the lip.
func crag_weight(u: float) -> float:
	if u<=0.0 or u>=1.0: return 0.0
	return smoothstep(0.0,0.08,u)*pow(1.0-u,1.5)

## Positive outside the hole (in the rock around it and under its floor).
func hole_distance(p: Vector3) -> float:
	var c:=settings.hole_centre
	var r:=Vector2(p.x-c.x,p.z-c.y).length()
	var rim:=settings.deep_floor
	var wall:=settings.hole_radius+smoothstep(rim-16.0,rim+4.0,p.y)*HOLE_FLARE+hole_noise.get_noise_3d(p.x,p.y,p.z)*HOLE_WOBBLE
	var below_floor:=rim-settings.hole_depth-p.y+hole_noise.get_noise_2d(p.x,p.z)*2.0
	return -smooth_union(-(r-wall),-below_floor,8.0)

## The ground, the cliff's crags and the hole, without the caves.
func ground_density(p: Vector3) -> float:
	var u:=drop_position(p.x,p.z)
	var value:=_height(p.x,p.z,u)-p.y
	var w:=crag_weight(u)
	if w>0.0 and absf(value)<7.0+CRAG_DEPTH*w: value+=crag.get_noise_3d(p.x,p.y,p.z)*CRAG_DEPTH*w
	if value> -7.0 and Vector2(p.x,p.z).distance_to(settings.hole_centre)<settings.hole_radius+HOLE_FLARE+HOLE_WOBBLE+12.0:
		value=smooth_union(value,hole_distance(p),3.0)
	return value

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
	network_bounds=AABB(Vector3(segments[0].x,segments[0].y,segments[0].z),Vector3.ZERO)
	var widest:=0.0
	for i in range(segments.size()):
		network_bounds=network_bounds.expand(Vector3(segments[i].x,segments[i].y,segments[i].z)).expand(Vector3(ends[i].x,ends[i].y,ends[i].z))
		widest=maxf(widest,segments[i].w)
	network_bounds=network_bounds.grow(widest+CAVE_REACH)

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
	var value:=ground_density(p)
	if value< -7.0: return value
	if all_caves and not network_bounds.has_point(p): return value
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
	# Deeper than this the march could not reach the surface, and the water has all but absorbed the sun anyway.
	for i in range(28 if p.y> -64.0 else 0):
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

## The density on the plane x = coarse_from as the coarse chunks there see it: their 2 m samples, joined in straight lines
## across the same triangles their faces are cut into (the diagonal runs from low y and z to high y and z). Fine triangles
## lie inside those, so the fine side's surface meets the plane exactly where the coarse side's does.
func coarse_face_density(p: Vector3) -> float:
	var step:=settings.voxel_size*2.0
	var y0:=floorf(p.y/step)*step
	var z0:=floorf(p.z/step)*step
	var fy:=(p.y-y0)/step
	var fz:=(p.z-z0)/step
	var v00:=density(Vector3(p.x,y0,z0))
	if fy==0.0 and fz==0.0: return v00
	var v11:=density(Vector3(p.x,y0+step,z0+step))
	if fy>=fz:
		var v10:=density(Vector3(p.x,y0+step,z0))
		return v00+fy*(v10-v00)+fz*(v11-v10)
	var v01:=density(Vector3(p.x,y0,z0+step))
	return v00+fz*(v01-v00)+fy*(v11-v01)

## Every chunk the surface passes through. Columns are 16 m in the shallows and 32 m (with 32 m layers) past coarse_from.
func chunk_coordinates() -> Array[Vector3i]:
	var result: Array[Vector3i]=[]
	var area:=settings.play_area()
	var step:=settings.chunk_size
	var cx:=floori(area.position.x/step)
	while cx<ceili(area.end.x/step):
		var scale:=settings.chunk_scale(Vector3i(cx,0,0))
		var size:=step*scale
		var cz:=floori(area.position.y/step)
		while cz<ceili(area.end.y/step):
			var span:=surface_span(Rect2(Vector2(cx,cz)*step,Vector2.ONE*size),settings.voxel_size*scale)
			for layer in range(floori(span.x/size),floori(span.y/size)+1):
				result.append(Vector3i(cx,layer*scale,cz))
			cz+=scale
		cx+=scale
	return result

## The lowest and highest the surface can reach over a column's footprint, with room to spare.
func surface_span(footprint: Rect2,voxel: float) -> Vector2:
	var low:=INF
	var high:=-INF
	var crags:=0.0
	var reach:=footprint.grow(voxel*2.0)
	var samples:=8
	for i in range(samples+1):
		for j in range(samples+1):
			var x:=reach.position.x+reach.size.x*i/samples
			var z:=reach.position.y+reach.size.y*j/samples
			var u:=drop_position(x,z)
			var h:=_height(x,z,u)
			low=minf(low,h)
			high=maxf(high,h)
			crags=maxf(crags,crag_weight(u))
	if crags>0.0:
		# The weight is only sampled, so pad it a little.
		low-=CRAG_DEPTH*minf(crags+0.1,1.0)
		high+=CRAG_DEPTH*minf(crags+0.1,1.0)
	var hole:=settings.hole_radius+HOLE_FLARE+HOLE_WOBBLE+12.0
	var nearest:=Vector2(clampf(settings.hole_centre.x,reach.position.x,reach.end.x),clampf(settings.hole_centre.y,reach.position.y,reach.end.y))
	if nearest.distance_to(settings.hole_centre)<hole: low=minf(low,settings.deep_floor-settings.hole_depth-8.0)
	for i in range(segments.size()):
		var a:=Vector3(segments[i].x,segments[i].y,segments[i].z)
		var b:=Vector3(ends[i].x,ends[i].y,ends[i].z)
		var r:=segments[i].w+2.0
		var box:=Rect2(Vector2(minf(a.x,b.x),minf(a.z,b.z)),Vector2(absf(a.x-b.x),absf(a.z-b.z))).grow(r)
		if box.intersects(reach):
			low=minf(low,minf(a.y,b.y)-r)
			high=maxf(high,maxf(a.y,b.y)+r)
	var margin:=2.0+voxel*2.0
	# Nothing rises above the water, so the layer above the sea floor is never needed.
	return Vector2(low-margin,minf(high+margin,-0.001))

func generate(coordinate: Vector3i) -> AbyssTerrainChunk:
	var data:=AbyssTerrainChunk.new()
	data.coordinate=coordinate
	data.signature=settings.signature()
	var size:=settings.chunk_extent(coordinate)
	var voxel:=settings.voxel_size*settings.chunk_scale(coordinate)
	var cells:=roundi(size/voxel)
	var side:=cells+1
	var base:=Vector3(coordinate)*settings.chunk_size
	var subset:=relevant_segments(AABB(base,Vector3.ONE*size).grow(4))
	# A fine chunk against the coarse area takes its +x face from the coarse neighbour's samples, so the seam is closed.
	var against_coarse:=settings.chunk_scale(coordinate)==1 and is_equal_approx(base.x+size,settings.coarse_from)
	var values:=PackedFloat32Array()
	values.resize(side*side*side)
	var any_air:=false
	var any_solid:=false
	for y in range(side):
		for z in range(side):
			for x in range(side):
				var p:=base+Vector3(x,y,z)*voxel
				var value:=coarse_face_density(p) if against_coarse and x==cells else density(p,subset,false)
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
								var pa:=Vector3(lo%side,lo/(side*side),(lo/side)%side)*voxel+base
								var pb:=Vector3(hi%side,hi/(side*side),(hi/side)%side)*voxel+base
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
			if minf(minf(local.x,local.y),local.z)<0.001 or maxf(maxf(local.x,local.y),local.z)>size-0.001: continue
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
