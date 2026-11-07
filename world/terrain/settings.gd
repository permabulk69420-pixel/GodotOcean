class_name AbyssTerrainSettings
extends Resource

## The terrain is stored as voxels: at every whole metre, how far it is to the ground's surface (positive in rock).
## Voxels come in 32 m blocks; a block that is all rock or all water is stored as just that. Blocks are grouped
## 4 x 4 x 4 into batch files (128 m on a side). The game streams blocks in around the camera and builds their meshes
## as it goes, in more detail close by (see lod_ranges).
const BLOCK := 32
const BATCH_BLOCKS := 4
## Stored distances are clamped to this many metres either side of the surface (one byte each).
const DISTANCE_RANGE := 4.0
const DATA_VERSION := 1

@export var seed := 73129
## The safe shallows: a square this many metres to each side of the spawn.
@export var shallows_half := Vector2(128.0, 128.0)
@export var mean_depth := 8.0
## The reef, seagrass and rubble are scattered over this much of the shallows (the original 160 m area) for now.
@export var decorated_half := Vector2(80.0, 80.0)

@export_group('Streaming')
## A block is drawn with 1 m detail while its nearest point is within the first distance of the camera, 2 m within the
## second, 4 m within the third, and not at all beyond that.
@export var lod_ranges := PackedFloat32Array([40.0, 80.0, 160.0])
## Blocks within this distance of the camera also get collision (they are always at full detail there).
@export var collision_range := 36.0

@export_group('Drop-off and deep plateau')
## The shallows' shelf ends near this x (it wanders either side by shelf_wobble) and falls away to the deep plateau.
@export var shelf_edge := 112.0
@export var shelf_wobble := 10.0
## How far out the cliff goes from its lip to the foot of its apron.
@export var drop_width := 56.0
## The deep plateau's floor, and how far it runs out from the shallows' +x side.
@export var deep_floor := -200.0
@export var deep_length := 320.0

@export_group('Hole')
@export var hole_centre := Vector2(344.0, 48.0)
@export var hole_radius := 30.0
## How far the hole goes below the plateau floor.
@export var hole_depth := 50.0

const GENERATOR_VERSION := 6

func signature() -> String:
	return ('%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s' % [GENERATOR_VERSION,DATA_VERSION,seed,shallows_half,mean_depth,
		shelf_edge,shelf_wobble,drop_width,deep_floor,deep_length,hole_centre,hole_radius,hole_depth]).sha256_text().substr(0,16)

## Everywhere the terrain exists and the player may swim: the shallows plus the deep plateau off their +x side.
func play_area() -> Rect2:
	return Rect2(-shallows_half, Vector2(shallows_half.x*2.0+deep_length, shallows_half.y*2.0))

## The range of blocks the world's voxels are stored in (inclusive minimum, exclusive maximum).
func block_bounds() -> AABB:
	var area:=play_area()
	var low:=Vector3(floorf(area.position.x/BLOCK),floorf((deep_floor-hole_depth-24.0)/BLOCK),floorf(area.position.y/BLOCK))
	var high:=Vector3(ceilf(area.end.x/BLOCK),0.0,ceilf(area.end.y/BLOCK))
	return AABB(low,high-low)
