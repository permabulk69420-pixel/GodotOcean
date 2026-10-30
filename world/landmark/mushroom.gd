class_name AbyssMushroom
extends Node3D
## The giant landmark mushroom: the imported model with its materials swapped for the glow
## shader, placed on the seabed at a fixed spot.

const MODEL := preload('res://world/landmark/giant_mushroom.glb')
const SHADER := preload('res://world/landmark/mushroom.gdshader')

## World x and z of the base; the height comes from the terrain.
@export var base_xz := Vector2(-24.0, 22.0)

var materials: Array[ShaderMaterial] = []

func _ready() -> void:
	var model: Node3D = MODEL.instantiate()
	add_child(model)
	var by_source: Dictionary = {}
	for mesh: MeshInstance3D in model.find_children('*', 'MeshInstance3D', true, false):
		var source := mesh.mesh.surface_get_material(0) as BaseMaterial3D
		if source == null: continue
		if not by_source.has(source):
			by_source[source] = convert_material(source)
		mesh.material_override = by_source[source]
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var terrain := get_node_or_null('../Terrain') as AbyssTerrain
	var ground := terrain.generator.height(base_xz.x, base_xz.y) if terrain and terrain.generator else -8.0
	global_position = Vector3(base_xz.x, ground, base_xz.y)

func convert_material(source: BaseMaterial3D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter('albedo_map', source.albedo_texture)
	material.set_shader_parameter('normal_map', source.normal_texture)
	material.set_shader_parameter('orm_map', source.orm_texture if source.orm_texture else source.ao_texture)
	material.set_shader_parameter('glow_map', source.emission_texture)
	materials.append(material)
	return material

func set_daylight(daylight: float) -> void:
	for material in materials:
		material.set_shader_parameter('day_amount', daylight)
