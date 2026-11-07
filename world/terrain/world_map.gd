class_name AbyssWorldMap
extends RefCounted
## The shape of the sea floor: one height for every point (x, z).
##
## The map is split into areas, each a place to grow into its own biome later. Each has a depth and its own kind of
## ground, and they blend into one another across open sea floor. The abyssal plateau holds a giant hole.
## Change an area here and the terrain follows; nothing is baked.

const AREAS := [
	{name='Shallows', centre=Vector2(0, 0), radius=650.0, edge=0.25, depth=-12.0, relief=3.0, ground='rolling'},
	{name='Reef shelf', centre=Vector2(-1150, 750), radius=750.0, edge=0.5, depth=-35.0, relief=8.0, ground='rolling'},
	{name='Kelp plain', centre=Vector2(1150, 800), radius=750.0, edge=0.5, depth=-55.0, relief=3.0, ground='flat'},
	{name='Canyons', centre=Vector2(-1250, -1050), radius=850.0, edge=0.4, depth=-110.0, relief=45.0, ground='ridged'},
	{name='Dune sea', centre=Vector2(1250, -1000), radius=850.0, edge=0.5, depth=-85.0, relief=10.0, ground='dunes'},
	{name='Abyssal plateau', centre=Vector2(0, -1450), radius=700.0, edge=0.3, depth=-220.0, relief=5.0, ground='flat'},
]
## Between the areas, and how strongly it pulls on their edges.
const OPEN := {name='Open sea floor', depth=-70.0, relief=10.0, ground='rolling'}
const OPEN_WEIGHT := 0.15
## The hole's rim rises a little before it falls away.
const RIM_HEIGHT := 4.0
const RIM_WIDTH := 40.0

var settings: AbyssTerrainSettings
var rolling := FastNoiseLite.new()
var ridges := FastNoiseLite.new()
var warp := FastNoiseLite.new()
var detail := FastNoiseLite.new()

func _init(config: AbyssTerrainSettings = null) -> void:
	settings=config if config else AbyssTerrainSettings.new()
	rolling.seed=settings.seed
	rolling.frequency=0.0025
	rolling.fractal_octaves=4
	ridges.seed=settings.seed+1
	ridges.frequency=0.004
	ridges.fractal_type=FastNoiseLite.FRACTAL_RIDGED
	ridges.fractal_octaves=3
	warp.seed=settings.seed+2
	warp.frequency=0.0015
	warp.fractal_octaves=2
	detail.seed=settings.seed+3
	detail.frequency=0.06
	detail.fractal_octaves=2

func height(x: float,z: float) -> float:
	var p:=Vector2(x,z)
	# Wobble every distance a little so the areas are not circles.
	var wobble:=warp.get_noise_2d(x,z)
	var weight:=OPEN_WEIGHT
	var sum:=OPEN_WEIGHT*_ground(OPEN,x,z)
	for area in AREAS:
		var r: float=area.radius
		var d:=p.distance_to(area.centre)+wobble*r*0.2
		if d>=r: continue
		var w:=smoothstep(r,r*(1.0-area.edge),d)
		sum+=w*_ground(area,x,z)
		weight+=w
	return _hole(x,z,sum/weight+detail.get_noise_2d(x,z)*0.6)

## Which area a point is mostly in (its name), for whatever later needs to know.
func area_at(x: float,z: float) -> String:
	var best:=OPEN_WEIGHT
	var name: String=OPEN.name
	var wobble:=warp.get_noise_2d(x,z)
	for area in AREAS:
		var r: float=area.radius
		var w:=smoothstep(r,r*(1.0-area.edge),Vector2(x,z).distance_to(area.centre)+wobble*r*0.2)
		if w>best:
			best=w
			name=area.name
	return name

func _ground(area: Dictionary,x: float,z: float) -> float:
	var n:=0.0
	match area.ground:
		'rolling': n=rolling.get_noise_2d(x,z)
		'flat': n=rolling.get_noise_2d(x,z)*0.4
		'ridged': n=ridges.get_noise_2d(x,z)
		'dunes': n=(1.0-absf(sin((x*0.8+z*0.6)*0.02+rolling.get_noise_2d(x,z)*4.0)))*2.0-1.0
	return area.depth+area.relief*n

func _hole(x: float,z: float,h: float) -> float:
	var top:=settings.hole_radius
	var r:=Vector2(x,z).distance_to(settings.hole_centre)
	if r>=top+RIM_WIDTH+20.0: return h
	# Ragged walls, not a perfect cylinder.
	var rr:=r+warp.get_noise_2d(x*4.0,z*4.0)*18.0
	if rr>=top: return h+RIM_HEIGHT*smoothstep(top+RIM_WIDTH,top,rr)
	# Steepest at the rim, easing out onto the floor.
	var t:=clampf((top-rr)/(top-settings.hole_floor_radius),0.0,1.0)
	var fall:=1.0-pow(1.0-t,2.0)
	return lerpf(h+RIM_HEIGHT,settings.hole_floor+detail.get_noise_2d(x,z)*3.0,fall)
