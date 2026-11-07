class_name AbyssTerrainSettings
extends Resource

@export var seed := 73129
## The safe shallows: a square of this many 16 m chunks on a side, centred on the spawn.
@export var region_chunks := Vector2i(16, 16)
@export var chunk_size := 16.0
@export var voxel_size := 1.0
@export var mean_depth := 8.0
## The reef, seagrass and rubble are scattered over this much of the shallows (the original 160 m area) for now.
@export var decorated_half := Vector2(80.0, 80.0)

@export_group('Drop-off and deep plateau')
## The shallows' shelf ends near this x (it wanders either side by shelf_wobble) and falls away to the deep plateau.
@export var shelf_edge := 112.0
@export var shelf_wobble := 10.0
## How far out the cliff goes from its lip to the foot of its apron.
@export var drop_width := 56.0
## The deep plateau's floor, and how far it runs out from the shallows' +x side.
@export var deep_floor := -200.0
@export var deep_length := 320.0
## From this x on, chunks are twice the size with twice the voxel size (the deep area is far, dark and simple).
## A multiple of twice chunk_size, and inside the shallows' flat shelf so the seam crosses level sand.
@export var coarse_from := 96.0

@export_group('Hole')
@export var hole_centre := Vector2(344.0, 48.0)
@export var hole_radius := 30.0
## How far the hole goes below the plateau floor.
@export var hole_depth := 50.0

const GENERATOR_VERSION := 5

func signature() -> String:
	return ('%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s' % [GENERATOR_VERSION,seed,region_chunks,chunk_size,voxel_size,mean_depth,
		shelf_edge,shelf_wobble,drop_width,deep_floor,deep_length,coarse_from,hole_centre,hole_radius,hole_depth]).sha256_text().substr(0,16)

func shallows_half() -> Vector2:
	return Vector2(region_chunks)*chunk_size*0.5

## Everywhere the terrain exists and the player may swim: the shallows plus the deep plateau off their +x side.
func play_area() -> Rect2:
	var half:=shallows_half()
	return Rect2(-half, Vector2(half.x*2.0+deep_length, half.y*2.0))

## Chunk coordinates are always counted in chunk_size steps. Past coarse_from a chunk covers 2 x 2 x 2 of those steps
## (its coordinate is then even on every axis) and samples every 2 voxels.
func chunk_scale(coordinate: Vector3i) -> int:
	return 2 if coordinate.x*chunk_size>=coarse_from else 1

func chunk_extent(coordinate: Vector3i) -> float:
	return chunk_size*chunk_scale(coordinate)
