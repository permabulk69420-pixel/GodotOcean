class_name AbyssTerrainSettings
extends Resource
## The sea floor is a height map: one height for every point (x, z), worked out from the areas in AbyssWorldMap.

@export var seed := 73129
## The map is a square this many metres on a side, centred on the spawn.
@export var world_size := 4096.0

@export_group('Giant hole')
## In the abyssal plateau, about 1.5 km north of the spawn. Its walls (AbyssHole) drop from the rim at hole_radius to
## the floor at hole_floor.
@export var hole_centre := Vector2(0.0, -1500.0)
@export var hole_radius := 220.0
@export var hole_floor := -820.0

## Everywhere the sea floor exists and the player may swim.
func play_area() -> Rect2:
	return Rect2(-Vector2.ONE*world_size*0.5, Vector2.ONE*world_size)
