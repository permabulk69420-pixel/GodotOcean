class_name AbyssTerrainBakeIndex
extends Resource

@export var signature := ''
@export var coordinates: Array[Vector3i] = []

# Export preserves the coordinates; derive paths instead of serializing a mutable
# PackedStringArray whose values were lost during text-resource conversion.
var files: PackedStringArray:
	get:
		var result:=PackedStringArray()
		for c in coordinates:
			result.append('res://world/terrain/baked/%s_%s_%s.res'%[c.x,c.y,c.z])
		return result
