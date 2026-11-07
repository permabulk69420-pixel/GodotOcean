class_name AbyssTerrainGenerator
extends RefCounted
## The shape of the world. Positive density is rock; negative density is water/air. Samples use world coordinates.
## The bake (bake.gd) turns it into stored voxels; the game builds its meshes from those (mesher.gd).

## The most the cliff's crags move its face up or down (under 1.5 m sideways on the steep part). Much more than this
## carves pockets and holes into the face.
const CRAG_DEPTH := 12.0
## The hole widens by this much towards its rim, and its walls wander in and out by up to HOLE_WOBBLE.
const HOLE_FLARE := 12.0
const HOLE_WOBBLE := 5.0
## The lip is rounded over this much of the drop's width (about 5.6 m). A hard corner there is finer than the deep
## area's 2 m voxels can follow, and triangles around it came out facing into the rock, seen as holes along the lip.
const LIP_ROUNDING := 0.1
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
	crag.frequency=0.05
	crag.fractal_octaves=2
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
	# Steepest just past the lip, so the shelf ends sharply, then easing out across an apron to the plateau.
	var s:=u*u/(2.0*LIP_ROUNDING) if u<LIP_ROUNDING else u-LIP_ROUNDING*0.5
	return lerpf(shallow,deep_height(x,z),1.0-pow(1.0-minf(s,1.0),2.5))

## The ground's height without the cliff's crags or the hole (used to place things on the shallows' floor).
func height(x: float,z: float) -> float:
	return _height(x,z,drop_position(x,z))

## How much the crags apply across the drop-off: none on the shelf or the plateau, most just below the lip.
## They come in gradually over the first few metres past the lip: faster, and they push the rock out quicker than the
## cliff falls away there, which turns the face inside out (triangles facing into the rock, seen as holes).
func crag_weight(u: float) -> float:
	if u<=0.0 or u>=1.0: return 0.0
	return smoothstep(0.0,0.15,u)*pow(1.0-u,1.5)

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

## Whether a block can hold any surface (or is all rock or all water, by a wide margin).
func block_kind(block: Vector3i) -> int:
	var size:=float(AbyssTerrainSettings.BLOCK)
	var span:=surface_span(Rect2(Vector2(block.x,block.z)*size,Vector2.ONE*size),1.0)
	var reach:=AbyssTerrainSettings.DISTANCE_RANGE+1.0
	if block.y*size>span.y+reach: return AbyssVoxelBatch.EMPTY
	if (block.y+1)*size<span.x-reach: return AbyssVoxelBatch.SOLID
	return AbyssVoxelBatch.DATA

## A block's voxels, one byte each (x fastest, then y, then z): the distance to the surface in metres, positive in rock,
## clamped to DISTANCE_RANGE. The density here is mostly height above or below the ground, which on a steep face says
## the surface is much further away than it is, so each value is divided by how fast the density changes there.
func block_voxels(block: Vector3i) -> PackedByteArray:
	var n:=AbyssTerrainSettings.BLOCK
	var side:=n+2
	var base:=Vector3(block)*n-Vector3.ONE
	var subset:=relevant_segments(AABB(base,Vector3.ONE*side).grow(4))
	var raw:=PackedFloat32Array()
	raw.resize(side*side*side)
	for z in range(side):
		for y in range(side):
			for x in range(side):
				raw[x+side*(y+side*z)]=density(base+Vector3(x,y,z),subset,false)
	var out:=PackedByteArray()
	out.resize(n*n*n)
	var scale:=127.0/AbyssTerrainSettings.DISTANCE_RANGE
	for z in range(n):
		for y in range(n):
			for x in range(n):
				var i:=(x+1)+side*((y+1)+side*(z+1))
				var v:=raw[i]
				var gx:=(raw[i+1]-raw[i-1])*0.5
				var gy:=(raw[i+side]-raw[i-side])*0.5
				var gz:=(raw[i+side*side]-raw[i-side*side])*0.5
				var d:=v/maxf(sqrt(gx*gx+gy*gy+gz*gz),0.5)
				out[x+n*(y+n*z)]=clampi(roundi(d*scale)+128,1,255)
	return out
