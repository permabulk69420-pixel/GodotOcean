class_name AbyssTerrainSettings
extends Resource

@export var seed := 73129
@export var region_chunks := Vector2i(10, 10)
@export var chunk_size := 16.0
@export var voxel_size := 1.0
@export var bottom := -32.0
@export var top := 0.0
@export var mean_depth := 8.0

const GENERATOR_VERSION := 4

func signature() -> String:
	return ('%s:%s:%s:%s:%s:%s:%s:%s' % [GENERATOR_VERSION,seed,region_chunks,chunk_size,voxel_size,bottom,top,mean_depth]).sha256_text().substr(0,16)

func coordinates() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for z in range(-region_chunks.y/2, region_chunks.y-region_chunks.y/2):
		for x in range(-region_chunks.x/2,region_chunks.x-region_chunks.x/2):
			for y in range(floori(bottom/chunk_size),ceili(top/chunk_size)):
				result.append(Vector3i(x,y,z))
	return result
