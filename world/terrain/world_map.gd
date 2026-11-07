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
## hills: how far its rolling hills rise and fall (metres, before the hilliness that varies from place to place).
## rocks: how much of its ground has rock outcrops on it (0 to 1), and rock_height about how tall they stand.
## sand: how much of the ground between the outcrops is sand (steep ground is rock whatever this says); silt: how much
## of that sand is dull grey silt rather than pale sand (so each region has its own colour).
const REGIONS := [
	{name='Reef terraces', centre=Vector2(-850, 380), offset=6.0, land='terraces', sand=0.55, hills=18.0, rocks=0.45, rock_height=4.0, silt=0.1, cliff=false},
	{name='Kelp plain', centre=Vector2(820, 420), offset=0.0, land='plain', sand=0.95, hills=20.0, rocks=0.28, rock_height=4.0, silt=0.15, cliff=false},
	{name='Dune sea', centre=Vector2(100, 1250), offset=0.0, land='dunes', sand=1.0, hills=10.0, rocks=0.1, rock_height=2.5, silt=0.0, cliff=false},
	{name='Canyons', centre=Vector2(-1200, -500), offset=10.0, land='canyons', sand=0.8, hills=10.0, rocks=0.35, rock_height=5.0, silt=0.5, cliff=false},
	{name='Spire field', centre=Vector2(1200, -500), offset=0.0, land='stacks', sand=0.85, hills=12.0, rocks=0.3, rock_height=4.0, silt=0.45, cliff=false},
	{name='Northern slope', centre=Vector2(0, -700), offset=-8.0, land='spurs', sand=0.75, hills=8.0, rocks=0.4, rock_height=4.0, silt=0.55, cliff=false},
	{name='Abyssal plateau', centre=Vector2(0, -1500), depth=-230.0, land='plateau', sand=0.4, hills=8.0, rocks=0.55, rock_height=5.0, silt=0.85, cliff=true},
	{name='Sunken basin', centre=Vector2(-1350, 1300), offset=-40.0, land='plain', sand=0.9, hills=32.0, rocks=0.25, rock_height=6.0, silt=0.65, cliff=false},
	{name='Ridge flats', centre=Vector2(1350, 1300), offset=10.0, land='ridges', sand=0.9, hills=8.0, rocks=0.15, rock_height=3.0, silt=0.3, cliff=false},
]
## The safe shallows' own ground (they take over from the regions near the spawn).
const SHALLOWS := {land='shallows', sand=1.0, silt=0.0, hills=2.0, rocks=0.3, rock_height=1.5}
## How far the borders wander (metres), and how wide the blend across a border is (in the difference of distances to
## the two centres; the band on the ground is about half that).
const WARP := 280.0
const BLEND := 70.0
## A cliff region's share of the blend is squeezed into this middle part, so its edge is a steep slope (not sheer,
## which a height map cannot draw well).
const CLIFF_FROM := 0.15
const CLIFF_TO := 0.85
## The trench: its centre line from just inside the shallows to the hole's rim, how wide its floor is, how steep its
## walls are (rise per metre out from the floor), and how far below the general depth its floor runs, from its start
## to its end.
const TRENCH := [Vector2(20, -140), Vector2(-60, -420), Vector2(60, -760), Vector2(-30, -1080), Vector2(10, -1310)]
const TRENCH_HALF_WIDTH := 34.0
const TRENCH_WALL := 1.7
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
var detail := FastNoiseLite.new()
var rim_noise := FastNoiseLite.new()
## Large patches of lighter and darker ground, so the textures do not read as a repeating pattern.
var patches := FastNoiseLite.new()
## The rolling hills every region has, and how hilly it is from place to place.
var hills := FastNoiseLite.new()
var relief := FastNoiseLite.new()
## Rock outcrops: where they stand (above a threshold), where they cluster, the bend in their outlines, and their
## rough tops.
var rocks := FastNoiseLite.new()
var clusters := FastNoiseLite.new()
var bend := FastNoiseLite.new()
## Bends the landforms' shapes (smooth, so it never folds the ground over).
var sway := FastNoiseLite.new()
var rough := FastNoiseLite.new()
var dune_noise := FastNoiseLite.new()
var stack_field := FastNoiseLite.new()
var _trench_line := PackedVector2Array()
var _trench_length := 1.0
var _trench_box := Rect2()
var _distances := PackedFloat32Array()
var _weights := PackedFloat32Array()
# Worked out once per sample, shared by every region's ground there.
var _wx := 0.0
var _wz := 0.0
var _fx := 0.0
var _fz := 0.0
var _hill := 0.0
var _hilly := 0.0
var _rock_field := 0.0
var _cluster := 0.0

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
	rim_noise.seed=s+19
	rim_noise.frequency=0.012
	rim_noise.fractal_octaves=2
	hills.seed=s+22
	hills.frequency=0.0035
	hills.fractal_octaves=5
	relief.seed=s+23
	relief.frequency=0.0007
	relief.fractal_octaves=2
	rocks.seed=s+24
	rocks.frequency=0.01
	rocks.fractal_octaves=3
	stack_field.seed=s+30
	stack_field.frequency=0.006
	stack_field.fractal_octaves=2
	clusters.seed=s+25
	clusters.frequency=0.003
	clusters.fractal_octaves=2
	bend.seed=s+26
	bend.frequency=0.015
	bend.fractal_octaves=1
	sway.seed=s+29
	sway.frequency=0.003
	sway.fractal_octaves=2
	rough.seed=s+27
	rough.frequency=0.06
	rough.fractal_octaves=2
	dune_noise.seed=s+28
	dune_noise.frequency=0.012
	dune_noise.fractal_octaves=2
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

## (height, sand, silt): sand is 1 where the floor is sand, 0 where it is rock (slope is taken into account when
## drawing); silt is how much of the sand is grey silt.
## patch() gives the large light and dark patches.
func sample(x: float,z: float) -> Vector3:
	var general:=general_depth(x,z)
	_blend(x,z)
	_wx=x+sway.get_noise_2d(x,z)*45.0
	_wz=z+sway.get_noise_2d(x+500.0,z-300.0)*45.0
	_hilly=smoothstep(-0.45,0.55,relief.get_noise_2d(x,z))
	_hill=hills.get_noise_2d(_wx,_wz)*(0.5+1.9*_hilly)
	_fx=x+bend.get_noise_2d(x,z)*9.0
	_fz=z+bend.get_noise_2d(x-700.0,z+900.0)*9.0
	_rock_field=rocks.get_noise_2d(_fx,_fz)
	_cluster=clusters.get_noise_2d(x,z)
	var out:=Vector3.ZERO
	for i in range(REGIONS.size()):
		var w: float=_weights[i]
		if w<0.002: continue
		var region: Dictionary=REGIONS[i]
		out+=w*_ground(region,region.depth if region.has('depth') else general+region.offset,x,z)
	# The shallows take over near the spawn, and give way across their edge.
	var s:=1.0-smoothstep(SHALLOWS_RADIUS,SHALLOWS_RADIUS+SHALLOWS_EDGE,_spawn_distance(x,z))
	if s>0.0: out=out.lerp(_ground(SHALLOWS,SHALLOWS_DEPTH,x,z),s)
	var h:=out.x+detail.get_noise_2d(x,z)*0.5
	h=_trench(x,z,h)
	h=_edge(x,z,h)
	h=_hole(x,z,h)
	return Vector3(h,out.y,out.z)

## A region's ground at its level: its rolling hills, its own landforms, and its rock outcrops. (height, sand, silt)
func _ground(region: Dictionary,level: float,x: float,z: float) -> Vector3:
	var land:=_land(region,x,z)
	# Outcrops: where the rock field rises past a threshold (lower where the rocks cluster); the bigger ones stand taller.
	var threshold:=lerpf(0.7,0.0,region.rocks)-_cluster*0.45
	var outcrop:=smoothstep(threshold,threshold+0.2,_rock_field)
	var top:=0.0
	if outcrop>0.0: top=outcrop*region.rock_height*(1.0+(_rock_field-threshold)*4.0+rough.get_noise_2d(x,z)*0.4)
	var rock:=clampf(land.y+smoothstep(threshold+0.02,threshold+0.1,_rock_field),0.0,1.0)
	return Vector3(level+_hill*region.hills+land.x+top,region.sand*(1.0-rock),region.silt)

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

## A region's own landforms: (height, how much is bare rock whatever the slope).
func _land(region: Dictionary,x: float,z: float) -> Vector2:
	match region.land:
		'shallows':
			# Long low sandbars.
			return Vector2((1.0-absf(swell.get_noise_2d(x*1.6,z*1.6)))*1.2,0.0)
		'plain':
			return Vector2(swell.get_noise_2d(_wx,_wz)*5.0,0.0)
		'terraces':
			# Broad shelves, each a few metres above the next, with rocky steps between.
			var v:=(swell.get_noise_2d(_wx,_wz)*0.5+0.5)*70.0
			var step_height:=9.0+3.0*channels.get_noise_2d(x*0.4,z*0.4)
			var k:=floorf(v/step_height)
			var riser:=smoothstep(0.6,0.95,v/step_height-k)
			return Vector2((k+riser)*step_height,4.0*riser*(1.0-riser))
		'dunes':
			# Sand ridges with sharp crests, running mostly one way but bending, splitting and joining.
			var d:=Vector2(_wx,_wz).rotated(0.55)
			var n:=dune_noise.get_noise_2d(d.x,d.y*0.35)
			var crest:=1.0-sqrt(n*n+0.003)
			var size:=8.0+14.0*_hilly
			return Vector2((crest*crest-0.4)*size,0.0)
		'canyons':
			# Winding canyons cut into high ground, each wall coming down in two steps with a ledge between, and smaller
			# side canyons. Measured in metres from each canyon's middle, so the walls are steep but never sheer.
			var d:=_line_distance(channels,_wx*0.6,_wz*0.6,0.6)
			var u:=clampf((d-(22.0+12.0*swell.get_noise_2d(x,z)))/75.0,0.0,1.0)
			var deep:=1.0-(smoothstep(0.0,0.42,u)*0.55+smoothstep(0.58,1.0,u)*0.45)
			var side:=1.0-smoothstep(5.0,30.0,_line_distance(channels,_wx*1.8+400.0,_wz*1.8,1.8))
			return Vector2(-maxf(deep*60.0,side*side*(3.0-2.0*side)*18.0),0.0)
		'stacks':
			# Clusters of tall rock stacks of every size, rough-topped. Their sides are measured in metres in from each
			# stack's outline, so they are steep but never sheer.
			var t:=0.3-_cluster*0.25
			var inside:=_signed_distance(stack_field,_fx,_fz,1.0,t)
			if inside<=0.0: return Vector2.ZERO
			var tall:=12.0+22.0*_hilly+rough.get_noise_2d(x*0.3,z*0.3)*8.0
			var m:=smoothstep(0.0,tall*0.5,inside)
			return Vector2(m*(tall+minf(inside,40.0)*0.25+rough.get_noise_2d(x,z)*2.0),smoothstep(0.0,3.0,inside))
		'spurs':
			# Rocky spurs and gullies running down the slope.
			var n:=ridged.get_noise_2d(_wx*0.9,_wz*0.3)
			return Vector2((n*0.5+0.5)*14.0,0.0)
		'plateau':
			# Blocky, stepped rock, cracked.
			var v:=rolling.get_noise_2d(_wx*0.8,_wz*0.8)*30.0
			var k:=floorf(v/6.0)
			var crack:=smoothstep(0.1,0.0,absf(channels.get_noise_2d(_wx*2.5,_wz*2.5)))*6.0
			return Vector2((k+smoothstep(0.62,1.0,v/6.0-k))*6.0-crack,0.4)
		'ridges':
			# Long winding ridges standing out of the sand.
			var n:=absf(channels.get_noise_2d(_wx*1.3,_wz*1.3))
			var ridge:=1.0-smoothstep(0.0,0.12,n)
			return Vector2(ridge*ridge*(12.0+8.0*swell.get_noise_2d(x*0.5,z*0.5)),smoothstep(0.55,0.9,ridge))
	return Vector2.ZERO

## Roughly how many metres (x, z) is from the line where noise (sampled at x, z, already scaled by scale from the
## world) is zero: its value divided by how fast it changes.
func _line_distance(noise: FastNoiseLite,x: float,z: float,scale: float) -> float:
	var n:=noise.get_noise_2d(x,z)
	var gx:=noise.get_noise_2d(x+scale,z)-n
	var gz:=noise.get_noise_2d(x,z+scale)-n
	return absf(n)/maxf(sqrt(gx*gx+gz*gz),0.0015)

## Roughly how many metres inside (+) or outside (-) the outline where noise rises past threshold (x, z) is.
func _signed_distance(noise: FastNoiseLite,x: float,z: float,scale: float,threshold: float) -> float:
	var n:=noise.get_noise_2d(x,z)
	var gx:=noise.get_noise_2d(x+scale,z)-n
	var gz:=noise.get_noise_2d(x,z+scale)-n
	return (n-threshold)/maxf(sqrt(gx*gx+gz*gz),0.003)

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
	# Rounded where the walls meet the ground above (a sharp lip cannot be drawn cleanly on the grid).
	var wall:=floor_height+maxf(0.0,best-half_width)*TRENCH_WALL
	var k:=6.0
	var t:=clampf(0.5+0.5*(wall-h)/k,0.0,1.0)
	return lerpf(wall,h,t)-k*t*(1.0-t)

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
