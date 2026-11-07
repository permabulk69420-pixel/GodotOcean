class_name AbyssVoxelBatch
extends Resource
## One batch file: 4 x 4 x 4 blocks of the world's voxels (see AbyssTerrainSettings).

const EMPTY := 0
const SOLID := 1
const DATA := 2

## Which batch this is, counted in batches from the world's origin.
@export var coordinate := Vector3i.ZERO
## For each block (x fastest, then y, then z): EMPTY (all water), SOLID (all rock) or DATA.
@export var kinds := PackedByteArray()
## For each DATA block in the same order: its 32 x 32 x 32 voxels (x fastest, then y, then z), one byte each, zstd-compressed.
@export var blocks: Array[PackedByteArray] = []
