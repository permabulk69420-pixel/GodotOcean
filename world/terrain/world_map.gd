class_name AbyssWorldMap
extends RefCounted
## The shape of the sea floor: for every point (x, z), its height and how sandy it is (the rest is rock).
##
## The floor gets deeper the further you go from the spawn, in every direction (DEPTH_CURVE), and deepest towards
## the north, where the giant hole is. Around the spawn is a small, safe patch of shallows that ends in a clear
## drop-off. Over that slope the map is divided into regions, each a place to grow into its own biome later: every
## point belongs mostly to the region whose centre is nearest, measured through a warped map so the borders wander,
## and neighbouring regions blend across their border. Each region sits a little above or below the general depth and
## has its own landforms. On top of that: a trench from the edge of the shallows to the hole, the hole itself, and the
## edge of the map, which falls away into the dark. North is -z. Nothing is baked: change something here and the
## terrain follows.

## The general depth by distance from the spawn (metres out, metres deep), joined in straight lines.
const DEPTH_CURVE := [Vector2(0, -8), Vector2(170, -9), Vector2(230, -38), Vector2(420, -50), Vector2(700, -72),
	Vector2(1000, -100), Vector2(1400, -150), Vector2(1800, -200), Vector2(2600, -250)]
## Towards the north the floor goes down this much further (times the general depth).
const NORTH_EXTRA := 0.35
## The safe shallows: within this distance of the spawn the floor is the shallows' own gentle sand, giving way over
## SHALLOWS_EDGE to whatever is beyond (by then the floor has dropped away, see DEPTH_CURVE).
const SHALLOWS_RADIUS := 170.0
const SHALLOWS_EDGE := 60.0
const SHALLOWS_DEPTH := -8.0
## offset: how far above (+) or below (-) the general depth the region sits; or depth, if it sits at a fixed depth.
const REGIONS := [
	{name='Reef terraces', centre=Vector2(-850, 380), offset=6.0, land='terraces', sand=0.55, cliff=false},
	{name='Kelp plain', centre=Vector2(820, 420), offset=0.0, land='swells', sand=0.95, cliff=false},
	{name='Dune sea', centre=Vector2(100, 1250), offset=0.0, land='dunes', sand=1.0, cliff=false},
	{name='Canyons', centre=Vector2(-1200, -500), offset=10.0, land='canyons', sand=0.35, cliff=false},
	{name='Spire field', centre=Vector2(1200, -500), offset=0.0, land='spires', sand=0.5, cliff=false},
	{name='Northern slope', centre=Vector2(0, -700), offset=-8.0, land='ridges', sand=0.6, cliff=false},
	{name='Abyssal plateau', centre=Vector2(0, -1500), depth=-230.0, land='plateau', sand=0.25, cliff=true},
	{name='Sunken basin', centre=Vector2(-1350, 1300), offset=-40.0, land='swells', sand=0.8, cliff=false},
	{name='Ridge flats', centre=Vector2(1350, 1300), offset=10.0, land='ridges', sand=0.7, cliff=false},
]
## How far the borders wander (metres), and how wide the blend across a border is (in the difference of distances to
## the two centres; the band on the ground is about half that).
const WARP := 280.0
const BLEND := 70.0
## A cliff region's share of the blend is squeezed into this middle part, so its edge is a steep slope (not sheer,
## which a height map cannot draw well).
const CLIFF_FROM := 0.15
const CLIFF_TO := 0.85
## Steep edges (the shallows' drop-off, cliff regions) get gullies cut into them up to this deep. Only down: nothing
## sticks up out of the slope.
const GULLIES := 9.0
## The trench: its centre line from just inside the shallows to the hole's rim, how wide its floor is, how steep its
## walls are (rise per metre out from the floor), and how far below the general depth its floor runs, from its start
## to its end.
const TRENCH := [Vector2(20, -140), Vector2(-60, -420), Vector2(60, -760), Vector2(-30, -1080), Vector2(10, -1310)]
const TRENCH_HALF_WIDTH := 34.0
const TRENCH_WALL := 2.4
const TRENCH_CUT_START := 22.0
const TRENCH_CUT_END := 70.0
## The map's edge: within this distance of it the floor falls away to EDGE_DEPTH. The line wanders by up to EDGE_WANDER.
const EDGE_REACH := 260.0
const EDGE_DEPTH := -520.0
const EDGE_WANDER := 160.0
## The hole's rim drops to its floor across this narrow band (its real walls are AbyssHole's mesh, just inside). The
## rim wanders in and out by up to HOLE_WANDER around the hole, so it is not a circle.
const HOLE_BAND := 3.0
const HOLE_WANDER := 30.0

var settings: AbyssTerrainSettings
var warp_x := FastNoiseLite.new()
var warp_z := FastNoiseLite.new()
var rolling := FastNoiseLite.new()
var swell := FastNoiseLite.new()
var channels := FastNoiseLite.new()
var ridged := FastNoiseLite.new()
var cells := FastNoiseLite.new()
## The same cells as `cells`, but a random value for each (to pick which cells get a pillar or outcrop, and its size).
var cell_values := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var rim_noise := FastNoiseLite.new()
var crags := FastNoiseLite.new()
## Large patches of lighter and darker ground, so the textures do not read as a repeating pattern.
var patches := FastNoiseLite.new()
var _trench_line := PackedVector2Array()
var _trench_length := 1.0
var _trench_box := Rect2()
var _distances := PackedFloat32Array()
var _weights := PackedFloat32Array()

func _init(config: AbyssTerrainSettings = null) -> void:
	settings=config if config else AbyssTerrainSettings.new()
	var s:=settings.seed
	for noise in [warp_x,warp_z]:
		noise.frequency=0.0011
		noise.fractal_octaves=3
	warp_x.seed=s+11
	warp_z.seed=s+12
	rolling.seed=s+13
	rolling.frequency=0.004
	rolling.fractal_octaves=4
	swell.seed=s+14
	swell.frequency=0.0016
	swell.fractal_octaves=2
	channels.seed=s+15
	channels.frequency=0.0022
	channels.fractal_octaves=2
	ridged.seed=s+16
	ridged.frequency=0.006
	ridged.fractal_type=FastNoiseLite.FRACTAL_RIDGED
	ridged.fractal_octaves=3
	cells.seed=s+17
	cells.noise_type=FastNoiseLite.TYPE_CELLULAR
	cells.frequency=0.011
	cells.cellular_return_type=FastNoiseLite.RETURN_DISTANCE
	cells.fractal_type=FastNoiseLite.FRACTAL_NONE
	cell_values.seed=s+17
	cell_values.noise_type=FastNoiseLite.TYPE_CELLULAR
	cell_values.frequency=0.011
	cell_values.cellular_return_type=FastNoiseLite.RETURN_CELL_VALUE
	cell_values.fractal_type=FastNoiseLite.FRACTAL_NONE
	rim_noise.seed=s+19
	rim_noise.frequency=0.012
	rim_noise.fractal_octaves=2
	crags.seed=s+20
	crags.frequency=0.022
	crags.fractal_type=FastNoiseLite.FRACTAL_RIDGED
	crags.fractal_octaves=3
	patches.seed=s+21
	patches.frequency=0.006
	patches.fractal_octaves=3
	detail.seed=s+18
	detail.frequency=0.07
	detail.fractal_octaves=2
	_distances.resize(REGIONS.size())
	_weights.resize(REGIONS.size())

func height(x: float,z: float) -> float:
	return sample(x,z).x

## (height, sand): sand is 1 where the floor is sand, 0 where it is rock (slope is taken into account when drawing).
## patch() gives the large light and dark patches.
func sample(x: float,z: float) -> Vector2:
	var general:=general_depth(x,z)
	_blend(x,z)
	var h:=0.0
	var sand:=0.0
	var steep:=0.0
	for i in range(REGIONS.size()):
		var w: float=_weights[i]
		if w<0.002: continue
		var region: Dictionary=REGIONS[i]
		var level: float=region.depth if region.has('depth') else general+region.offset
		h+=w*(level+_land(region,x,z))
		sand+=w*region.sand
		if region.cliff and w<0.998: steep=maxf(steep,4.0*w*(1.0-w))
	# The shallows take over near the spawn, and give way across their edge.
	var r:=_spawn_distance(x,z)
	var s:=1.0-smoothstep(SHALLOWS_RADIUS,SHALLOWS_RADIUS+SHALLOWS_EDGE,r)
	if s>0.0:
		h=lerpf(h,SHALLOWS_DEPTH+_land({land='shallows'},x,z),s)
		sand=lerpf(sand,1.0,s)
		steep=maxf(steep,4.0*s*(1.0-s))
	if steep>0.0: h-=steep*maxf(0.0,crags.get_noise_2d(x,z))*GULLIES
	h+=detail.get_noise_2d(x,z)*0.5
	h=_trench(x,z,h)
	h=_edge(x,z,h)
	h=_hole(x,z,h)
	return Vector2(h,sand)

## How deep the floor is in general here, before regions add their own ups and downs.
func general_depth(x: float,z: float) -> float:
	var r:=_spawn_distance(x,z)
	var depth: float=DEPTH_CURVE[DEPTH_CURVE.size()-1].y
	for i in range(DEPTH_CURVE.size()-1):
		var a: Vector2=DEPTH_CURVE[i]
		var b: Vector2=DEPTH_CURVE[i+1]
		if r<=b.x:
			depth=lerpf(a.y,b.y,(r-a.x)/(b.x-a.x))
			break
	var north:=clampf(-z/maxf(Vector2(x,z).length(),1.0),0.0,1.0)
	return depth*(1.0+NORTH_EXTRA*north*north)

## Distance from the spawn, wobbled a little so the shallows and the depth bands are not circles.
func _spawn_distance(x: float,z: float) -> float:
	return Vector2(x,z).length()+warp_x.get_noise_2d(x*0.9,z*0.9)*80.0+warp_z.get_noise_2d(x*3.0,z*3.0)*20.0

## 0.7 to 1: large lighter and darker patches of ground.
func patch(x: float,z: float) -> float:
	return 0.85+patches.get_noise_2d(x,z)*0.15

## The region a point is mostly in, by name.
func region_at(x: float,z: float) -> String:
	_blend(x,z)
	var best:=0
	for i in range(REGIONS.size()):
		if _weights[i]>_weights[best]: best=i
	return REGIONS[best].name

## Each region's share at a point (in _weights, adding up to 1).
func _blend(x: float,z: float) -> void:
	var q:=Vector2(x+warp_x.get_noise_2d(x,z)*WARP,z+warp_z.get_noise_2d(x,z)*WARP)
	var nearest:=INF
	for i in range(REGIONS.size()):
		_distances[i]=q.distance_to(REGIONS[i].centre)
		nearest=minf(nearest,_distances[i])
	var total:=0.0
	for i in range(REGIONS.size()):
		_weights[i]=exp(-(_distances[i]-nearest)/BLEND)
		total+=_weights[i]
	var sharpened:=0.0
	for i in range(REGIONS.size()):
		_weights[i]/=total
		if REGIONS[i].cliff: _weights[i]=smoothstep(CLIFF_FROM,CLIFF_TO,_weights[i])
		sharpened+=_weights[i]
	for i in range(REGIONS.size()): _weights[i]/=maxf(sharpened,0.0001)

## A region's own ups and downs, around its level.
func _land(region: Dictionary,x: float,z: float) -> float:
	match region.land:
		'shallows':
			# Gentle sand with long low sandbars, and in about one cell in five a low rounded rocky outcrop.
			var bars:=(1.0-absf(swell.get_noise_2d(x*1.6,z*1.6)))*1.2
			var pick:=cell_values.get_noise_2d(x,z)
			var outcrop:=0.0
			if pick>0.6:
				var size:=0.08+(pick-0.6)*0.3
				var f:=cells.get_noise_2d(x,z)+1.0
				outcrop=pow(1.0-smoothstep(0.0,size,f),2.0)*(1.0+(pick-0.6)*3.0)
			return rolling.get_noise_2d(x,z)*1.2+bars+outcrop
		'terraces':
			# Stepped ledges: the ground rises and falls in 5 m steps with short slopes between them.
			var v:=rolling.get_noise_2d(x*0.7,z*0.7)*18.0
			var step:=floorf(v/5.0)
			return (step+smoothstep(0.72,1.0,v/5.0-step))*5.0
		'swells':
			return swell.get_noise_2d(x,z)*6.0+rolling.get_noise_2d(x,z)*1.5
		'dunes':
			# Long dunes across the current: a gentle back slope up to a sharp crest and a steep front, wandering a little.
			var u:=(x*0.85+z*0.53)/95.0+swell.get_noise_2d(x,z)*1.6
			var s:=u-floorf(u)
			var shape:=pow(s/0.8,1.4) if s<0.8 else smoothstep(1.0,0.8,s)
			return (shape*2.0-1.0)*(8.0+swell.get_noise_2d(x*0.5,z*0.5)*4.0)+rolling.get_noise_2d(x,z)*1.5
		'canyons':
			# Flat-topped mesas cut by winding channels 90 m deep. Each wall comes down in two drops with a broad ledge
			# between, each spread over enough ground for the 2 m grid to follow without jagged fins.
			var c:=absf(channels.get_noise_2d(x,z))
			var cut:=1.0-smoothstep(0.02,0.22,c)
			var shaped:=smoothstep(0.0,0.42,cut)*0.45+smoothstep(0.55,1.0,cut)*0.55
			return rolling.get_noise_2d(x,z)*3.0-shaped*90.0
		'spires':
			# A rocky floor with steep-sided pillars in a little under half the cells, each its own width and height,
			# thickest where the field is densest. Warped, so each pillar is an irregular column rather than a round one.
			var wx:=x+rolling.get_noise_2d(x*5.0,z*5.0)*14.0
			var wz:=z+rolling.get_noise_2d(x*5.0+300.0,z*5.0)*14.0
			var f:=cells.get_noise_2d(wx*0.6,wz*0.6)+1.0
			var pick:=cell_values.get_noise_2d(wx*0.6,wz*0.6)
			var density:=swell.get_noise_2d(x*0.7,z*0.7)
			var pillar:=0.0
			if pick>0.15-density*0.4:
				var width:=0.08+absf(pick)*0.14
				pillar=smoothstep(width,width*0.55,f)*(18.0+(pick*0.5+0.5)*55.0)*(1.0+crags.get_noise_2d(x*2.0,z*2.0)*0.12)
			return rolling.get_noise_2d(x,z)*5.0+pillar
		'plateau':
			# Rugged, cracked rock.
			var crack:=smoothstep(0.08,0.0,absf(channels.get_noise_2d(x*2.5,z*2.5)))*7.0
			return rolling.get_noise_2d(x,z)*4.0-crack
		'ridges':
			return rolling.get_noise_2d(x,z)*3.0+(ridged.get_noise_2d(x,z)*0.5+0.5)*12.0
	return 0.0

func _trench(x: float,z: float,h: float) -> float:
	if _trench_line.is_empty(): _trench_line=_smooth_line(TRENCH)
	var p:=Vector2(x,z)
	if not _trench_box.has_point(p): return h
	var best:=INF
	var along:=0.0
	var length:=0.0
	for i in range(_trench_line.size()-1):
		var a: Vector2=_trench_line[i]
		var b: Vector2=_trench_line[i+1]
		var t:=clampf((p-a).dot(b-a)/(b-a).length_squared(),0.0,1.0)
		var d:=p.distance_to(a.lerp(b,t))
		if d<best:
			best=d
			along=length+t*a.distance_to(b)
		length+=a.distance_to(b)
	# The floor narrows and widens as it goes.
	var half_width:=TRENCH_HALF_WIDTH*(1.0+swell.get_noise_2d(along*2.0,0.0)*0.35)
	if best>half_width+140.0: return h
	# Its floor runs below the general depth (more so further along, and never above the shallows' own floor), so it
	# goes downhill all the way; its walls rise steeply either side.
	var f:=along/_trench_length
	var floor_height:=minf(general_depth(x,z),SHALLOWS_DEPTH)-lerpf(TRENCH_CUT_START,TRENCH_CUT_END,f)+rolling.get_noise_2d(x,z)*2.0
	return minf(h,floor_height+maxf(0.0,best-half_width)*TRENCH_WALL)

## A smooth, wandering line through the given points (Catmull-Rom, every 10 m, nudged sideways by noise).
func _smooth_line(points: Array) -> PackedVector2Array:
	var out:=PackedVector2Array()
	for i in range(points.size()-1):
		var p0: Vector2=points[maxi(i-1,0)]
		var p1: Vector2=points[i]
		var p2: Vector2=points[i+1]
		var p3: Vector2=points[mini(i+2,points.size()-1)]
		var count:=maxi(2,int(p1.distance_to(p2)/10.0))
		for j in range(count):
			var t:=float(j)/count
			var q:=0.5*((2.0*p1)+(-p0+p2)*t+(2.0*p0-5.0*p1+4.0*p2-p3)*t*t+(-p0+3.0*p1-3.0*p2+p3)*t*t*t)
			out.append(q)
	out.append(points[points.size()-1])
	# Wander sideways (not at the two ends).
	var length:=0.0
	for i in range(out.size()-1): length+=out[i].distance_to(out[i+1])
	var run:=0.0
	var wandered:=PackedVector2Array()
	for i in range(out.size()):
		if i>0: run+=out[i-1].distance_to(out[i])
		var dir:=(out[mini(i+1,out.size()-1)]-out[maxi(i-1,0)]).normalized()
		var side:=Vector2(-dir.y,dir.x)
		var fade:=smoothstep(0.0,0.12,run/length)*smoothstep(1.0,0.88,run/length)
		wandered.append(out[i]+side*warp_x.get_noise_2d(run*3.0,77.0)*45.0*fade)
	_trench_length=0.0
	for i in range(wandered.size()-1): _trench_length+=wandered[i].distance_to(wandered[i+1])
	_trench_box=Rect2(wandered[0],Vector2.ZERO)
	for q in wandered: _trench_box=_trench_box.expand(q)
	_trench_box=_trench_box.grow(TRENCH_HALF_WIDTH*1.4+140.0)
	return wandered

func _edge(x: float,z: float,h: float) -> float:
	var half:=settings.world_size*0.5
	var to_edge:=half-maxf(absf(x),absf(z))+warp_x.get_noise_2d(x*1.3,z*1.3)*EDGE_WANDER
	if to_edge>EDGE_REACH: return h
	return lerpf(h,EDGE_DEPTH,pow(smoothstep(EDGE_REACH,40.0,to_edge),1.5))

## How far from the hole's centre its rim is, in this direction (radians).
func hole_rim(angle: float) -> float:
	return settings.hole_radius+rim_noise.get_noise_2d(cos(angle)*90.0,sin(angle)*90.0)*HOLE_WANDER

func _hole(x: float,z: float,h: float) -> float:
	var offset:=Vector2(x,z)-settings.hole_centre
	var r:=offset.length()
	if r>settings.hole_radius+HOLE_WANDER+HOLE_BAND: return h
	var rim:=hole_rim(offset.angle())
	if r>rim+HOLE_BAND: return h
	return lerpf(h,settings.hole_floor+detail.get_noise_2d(x,z)*3.0,smoothstep(rim+HOLE_BAND,rim-HOLE_BAND,r))
