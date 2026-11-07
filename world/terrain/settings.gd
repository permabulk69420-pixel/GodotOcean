class_name AbyssTerrainSettings
extends Resource
## The sea floor is a height map: one height for every point (x, z), worked out from the areas in AbyssWorldMap.

@export var seed := 73129
## The map is a square this many metres on a side, centred on the spawn.
@export var world_size := 4096.0

@export_group('Giant hole')
## In the abyssal plateau. The rim falls away at hole_radius; the walls come down to a flat floor hole_floor_radius
## across, at hole_floor.
@export var hole_centre := Vector2(0.0, -1450.0)
@export var hole_radius := 260.0
@export var hole_floor_radius := 120.0
@export var hole_floor := -720.0

## Everywhere the sea floor exists and the player may swim.
func play_area() -> Rect2:
	return Rect2(-Vector2.ONE*world_size*0.5, Vector2.ONE*world_size)
