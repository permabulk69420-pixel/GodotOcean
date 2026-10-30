class_name AbyssSeagrass
extends Node3D
## Scatters seagrass clumps over the gentle, sandy parts of the seabed. Clumps are grouped into
## square cells, each a pair of batched draw calls that disappears beyond view_distance.

const MODEL := preload('res://world/vegetation/seagrass.glb')
const SHADER := preload('res://world/vegetation/seagrass.gdshader')

@export var cell_size := 32.0
@export var view_distance := 55.0
@export var attempts := 12000
## Fraction of attempts kept inside a dense patch (patches come from low-frequency noise).
@export var patch_density := 0.55
@export var tall_fraction := 0.28
@export var min_ground := -22.0
@export var max_ground := -2.5
@export var max_slope := 0.32
@export var keep_clear_of_mushroom := 27.0
@export var keep_clear_of_entrances := 8.0

var count := 0

func _ready() -> void:
	var terrain := get_node_or_null('../Terrain') as AbyssTerrain
	if terrain == null or terrain.generator == null:
		return
	var generator := terrain.generator
	var settings := terrain.settings
	var model: Node3D = MODEL.instantiate()
	var short_mesh: Mesh
	var tall_mesh: Mesh
	for mesh: MeshInstance3D in model.find_children('*', 'MeshInstance3D', true, false):
		if mesh.name == &'SeagrassTall': tall_mesh = mesh.mesh
		else: short_mesh = mesh.mesh
	model.free()
	if short_mesh == null or tall_mesh == null:
		return
	var material := ShaderMaterial.new()
	material.shader = SHADER
	var mushroom := get_node_or_null('../Mushroom') as AbyssMushroom

	var half := Vector2(settings.region_chunks) * settings.chunk_size * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = settings.seed + 97
	var patches := FastNoiseLite.new()
	patches.seed = settings.seed + 5
	patches.frequency = 0.03
	patches.fractal_octaves = 2
	var cells: Dictionary = {}
	for i in range(attempts):
		var x := rng.randf_range(-half.x + 2.0, half.x - 2.0)
		var z := rng.randf_range(-half.y + 2.0, half.y - 2.0)
		var patch := smoothstep(-0.15, 0.35, patches.get_noise_2d(x, z))
		if rng.randf() > patch * patch_density: continue
		var ground := generator.height(x, z)
		if ground < min_ground or ground > max_ground: continue
		var gradient := Vector2(generator.height(x + 0.6, z) - generator.height(x - 0.6, z), generator.height(x, z + 0.6) - generator.height(x, z - 0.6)) / 1.2
		if gradient.length() > max_slope: continue
		if mushroom and Vector2(x, z).distance_to(mushroom.base_xz) < keep_clear_of_mushroom: continue
		var near_entrance := false
		for entrance in generator.entrances:
			if Vector2(x, z).distance_to(Vector2(entrance.x, entrance.z)) < keep_clear_of_entrances: near_entrance = true
		if near_entrance: continue
		var tall := rng.randf() < tall_fraction
		var scale := rng.randf_range(0.85, 1.2)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(scale, scale * rng.randf_range(0.9, 1.1), scale))
		var key := Vector3i(floori(x / cell_size), int(tall), floori(z / cell_size))
		if not cells.has(key): cells[key] = []
		cells[key].append(Transform3D(basis, Vector3(x, ground - 0.04, z)))
		count += 1

	for key: Vector3i in cells:
		var transforms: Array = cells[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = tall_mesh if key.y == 1 else short_mesh
		multimesh.instance_count = transforms.size()
		for j in range(transforms.size()): multimesh.set_instance_transform(j, transforms[j])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = view_distance
		add_child(instance)
