class_name AbyssVoxelIndex
extends Resource
## What the bake wrote: which batch files exist, and which blocks the surface can pass through.

@export var signature := ''
@export var batches: Array[Vector3i] = []
## Blocks whose cells can hold part of the surface (they, or a neighbour on their + side, are not all one kind).
## Only these are ever meshed.
@export var surface_blocks: Array[Vector3i] = []

static func batch_path(c: Vector3i) -> String:
	return 'res://world/terrain/baked/batch_%s_%s_%s.res'%[c.x,c.y,c.z]
