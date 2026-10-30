class_name AbyssReef
extends Node3D
## Places coral, kelp and rock from the reef kit over the seabed in clustered patches ("zones").
## Small pieces are merged per area into one mesh per material, so a whole patch costs one or two
## draw calls. Big set pieces (arch, spire, coral mound) are placed one by one and keep the
## collision that came with the kit.

const KIT := 'res://world/reef/reef_kit.glb'
const CELL := 32.0
const VIEW_DISTANCE := 70.0
const SET_PIECE_VIEW_DISTANCE := 160.0

# kind: 'rock' uses the terrain's rock material; 'coral' uses the reef material.
# mesh: names inside the kit; one is picked at random per piece.
# zone: noise frequency and threshold decide where the species may grow, so it forms patches.
var species := [
	{name = 'boulder', kind = 'rock', mesh = ['RockBoulderA', 'RockBoulderB', 'RockBoulderC'], clusters = 26, per = Vector2i(2, 6), radius = 4.0, zone = Vector2(0.018, -0.1),
		ground = Vector2(-22.0, -2.0), slope = Vector2(0.0, 1.2), scale = Vector2(0.8, 2.2)},
	{name = 'slab', kind = 'rock', mesh = ['RockSlabA', 'RockSlabB'], clusters = 10, per = Vector2i(1, 3), radius = 3.0, zone = Vector2(0.02, -0.05),
		ground = Vector2(-22.0, -2.0), slope = Vector2(0.0, 0.5), scale = Vector2(0.8, 1.8)},
	{name = 'coral_branching', kind = 'coral', mesh = ['CoralBranchingA', 'CoralBranchingB'], clusters = 22, per = Vector2i(5, 12), radius = 3.2, zone = Vector2(0.03, 0.12),
		ground = Vector2(-18.0, -3.0), slope = Vector2(0.0, 0.7), scale = Vector2(0.8, 1.6)},
	{name = 'coral_brain', kind = 'coral', mesh = ['CoralBrain'], clusters = 16, per = Vector2i(4, 9), radius = 2.8, zone = Vector2(0.03, 0.05),
		ground = Vector2(-18.0, -3.0), slope = Vector2(0.0, 0.6), scale = Vector2(0.8, 1.8)},
	{name = 'coral_table', kind = 'coral', mesh = ['CoralTable'], clusters = 10, per = Vector2i(2, 5), radius = 2.8, zone = Vector2(0.03, 0.08),
		ground = Vector2(-18.0, -3.0), slope = Vector2(0.0, 0.5), scale = Vector2(0.8, 1.6)},
	{name = 'coral_tube', kind = 'coral', mesh = ['CoralTube'], clusters = 14, per = Vector2i(3, 7), radius = 2.2, zone = Vector2(0.03, 0.2),
		ground = Vector2(-18.0, -3.0), slope = Vector2(0.0, 0.8), scale = Vector2(0.8, 1.6)},
	{name = 'coral_fan', kind = 'coral', mesh = ['CoralFan'], clusters = 14, per = Vector2i(3, 7), radius = 2.5, zone = Vector2(0.03, 0.1),
		ground = Vector2(-18.0, -3.0), slope = Vector2(0.1, 1.0), scale = Vector2(0.9, 1.8)},
	{name = 'anemone', kind = 'coral', mesh = ['Anemone'], clusters = 12, per = Vector2i(3, 8), radius = 2.0, zone = Vector2(0.03, 0.0),
		ground = Vector2(-18.0, -3.0), slope = Vector2(0.0, 0.6), scale = Vector2(0.9, 1.8)},
	{name = 'kelp', kind = 'coral', mesh = ['KelpStalkA', 'KelpStalkB'], clusters = 16, per = Vector2i(3, 8), radius = 3.0, zone = Vector2(0.02, 0.0),
		ground = Vector2(-22.0, -5.5), slope = Vector2(0.0, 0.4), scale = Vector2(0.7, 1.2)},
]

# Large single pieces. spacing keeps two of the same kind apart; collide copies the kit's collision.
var set_pieces := [
	{name = 'arch', kind = 'rock', mesh = 'RockArch', count = 3, spacing = 70.0, ground = Vector2(-24.0, -4.0), slope = Vector2(0.0, 0.6), scale = Vector2(0.9, 1.3), clear = 12.0},
	{name = 'spire', kind = 'rock', mesh = 'RockSpire', count = 4, spacing = 55.0, ground = Vector2(-24.0, -4.0), slope = Vector2(0.0, 0.8), scale = Vector2(0.8, 1.3), clear = 6.0},
	{name = 'mound', kind = 'coral', mesh = 'CoralMound', count = 6, spacing = 40.0, ground = Vector2(-20.0, -4.0), slope = Vector2(0.0, 0.5), scale = Vector2(0.9, 1.4), clear = 6.0},
]

@export var enabled := true
## Build simpler versions (levels of detail) of every merged patch, which Godot swaps in with
## distance, so faraway reef costs far fewer triangles than the full-detail pieces up close.
@export var generate_lods := true
@export var keep_clear_of_mushroom := 28.0
@export var keep_clear_of_entrances := 8.0

var meshes: Dictionary = {}
var collisions: Dictionary = {}
var coral_material: ShaderMaterial
var piece_count := 0

func set_daylight(daylight: float) -> void:
	if coral_material:
		coral_material.set_shader_parameter('day_amount', daylight)

func _ready() -> void:
	if not enabled:
		return
	var terrain := get_node_or_null('../Terrain') as AbyssTerrain
	if terrain == null or terrain.generator == null:
		return
	var generator := terrain.generator
	var mushroom := get_node_or_null('../Mushroom') as AbyssMushroom
	load_kit()
	coral_material = make_coral_material()
	var half := Vector2(terrain.settings.region_chunks) * terrain.settings.chunk_size * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain.settings.seed + 211
	# cells[material kind][cell] -> Array of [mesh_name, Transform3D, Color]
	var cells := {'rock': {}, 'coral': {}}
	for index in range(species.size()):
		place_species(index, species[index], generator, mushroom, half, rng, cells)
	var rock_material: Material = terrain.material
	for kind in cells:
		for cell: Vector2i in cells[kind]:
			var instance := MeshInstance3D.new()
			instance.mesh = merge(cells[kind][cell], kind == 'rock')
			instance.material_override = rock_material if kind == 'rock' else coral_material
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.visibility_range_end = VIEW_DISTANCE
			add_child(instance)
	for index in range(set_pieces.size()):
		place_set_pieces(index, set_pieces[index], generator, mushroom, half, rng, rock_material)

## Reads every mesh (and its collision, if any) out of the kit by name. Node positions in the kit
## are only a display layout, so only the meshes themselves are used.
func load_kit() -> void:
	var root: Node = (load(KIT) as PackedScene).instantiate()
	for node in root.find_children('*', 'MeshInstance3D', true, false):
		var instance := node as MeshInstance3D
		var arrays := instance.mesh.surface_get_arrays(0)
		meshes[String(instance.name)] = {
			vertices = arrays[Mesh.ARRAY_VERTEX],
			normals = arrays[Mesh.ARRAY_NORMAL],
			uvs = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array(),
			tangents = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array(),
			colours = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray(),
			indices = arrays[Mesh.ARRAY_INDEX],
		}
		var shapes := []
		for body in instance.get_children():
			if body is StaticBody3D:
				for child in body.get_children():
					if child is CollisionShape3D and child.shape:
						shapes.append([(body as StaticBody3D).transform * (child as CollisionShape3D).transform, child.shape])
		collisions[String(instance.name)] = shapes
	root.free()

func make_coral_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load('res://world/reef/reef.gdshader')
	material.set_shader_parameter('albedo_map', load('res://world/reef/reef_kit_ReefAtlas_basecolor.png'))
	material.set_shader_parameter('normal_map', load('res://world/reef/reef_kit_ReefAtlas_normal.png'))
	material.set_shader_parameter('orm_map', load('res://world/reef/reef_kit_ReefAtlas_orm.png'))
	material.set_shader_parameter('glow_map', load('res://world/reef/reef_kit_ReefAtlas_glowmask.png'))
	return material

func place_species(index: int, def: Dictionary, generator: AbyssTerrainGenerator, mushroom: AbyssMushroom, half: Vector2, rng: RandomNumberGenerator, cells: Dictionary) -> void:
	var zone := FastNoiseLite.new()
	zone.seed = index * 31 + 7
	zone.frequency = def.zone.x
	zone.fractal_octaves = 2
	var accepted := 0
	var attempts := 0
	while accepted < def.clusters and attempts < def.clusters * 40:
		attempts += 1
		var centre := Vector2(rng.randf_range(-half.x + 4.0, half.x - 4.0), rng.randf_range(-half.y + 4.0, half.y - 4.0))
		if zone.get_noise_2d(centre.x, centre.y) < def.zone.y: continue
		if not suitable(centre, def, generator, mushroom): continue
		accepted += 1
		for k in range(rng.randi_range(def.per.x, def.per.y)):
			var p := centre + Vector2(rng.randfn(0.0, def.radius * 0.5), rng.randfn(0.0, def.radius * 0.5))
			if not suitable(p, def, generator, mushroom): continue
			var scale: float = rng.randf_range(def.scale.x, def.scale.y)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(scale, scale * rng.randf_range(0.85, 1.2), scale))
			var ground := generator.height(p.x, p.y)
			var key := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
			if not cells[def.kind].has(key): cells[def.kind][key] = []
			cells[def.kind][key].append([def.mesh[rng.randi() % def.mesh.size()], Transform3D(basis, Vector3(p.x, ground - 0.06, p.y)), rng.randf()])
			piece_count += 1

func place_set_pieces(index: int, def: Dictionary, generator: AbyssTerrainGenerator, mushroom: AbyssMushroom, half: Vector2, rng: RandomNumberGenerator, rock_material: Material) -> void:
	var spots: Array[Vector2] = []
	var attempts := 0
	while spots.size() < def.count and attempts < 600:
		attempts += 1
		var p := Vector2(rng.randf_range(-half.x + 12.0, half.x - 12.0), rng.randf_range(-half.y + 12.0, half.y - 12.0))
		if not suitable(p, def, generator, mushroom): continue
		# The footprint must be flat all the way round, not just in the middle.
		var ok := true
		for ring in range(8):
			var q: Vector2 = p + Vector2.from_angle(TAU * ring / 8.0) * def.clear
			if absf(generator.height(q.x, q.y) - generator.height(p.x, p.y)) > 2.5 or not suitable(q, def, generator, mushroom): ok = false
		if not ok: continue
		for other in spots:
			if other.distance_to(p) < def.spacing: ok = false
		if not ok: continue
		spots.append(p)
	for p in spots:
		var scale: float = rng.randf_range(def.scale.x, def.scale.y)
		var holder := StaticBody3D.new()
		holder.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(scale, scale, scale)), Vector3(p.x, generator.height(p.x, p.y) - 0.1, p.y))
		var instance := MeshInstance3D.new()
		instance.mesh = merge([[def.mesh, Transform3D.IDENTITY, rng.randf()]], def.kind == 'rock')
		instance.material_override = rock_material if def.kind == 'rock' else coral_material
		instance.visibility_range_end = SET_PIECE_VIEW_DISTANCE
		holder.add_child(instance)
		for entry in collisions[def.mesh]:
			var shape := CollisionShape3D.new()
			shape.shape = entry[1]
			shape.transform = entry[0]
			holder.add_child(shape)
		add_child(holder)
		piece_count += 1

func suitable(p: Vector2, def: Dictionary, generator: AbyssTerrainGenerator, mushroom: AbyssMushroom) -> bool:
	var ground := generator.height(p.x, p.y)
	if ground < def.ground.x or ground > def.ground.y: return false
	var slope := Vector2(generator.height(p.x + 0.6, p.y) - generator.height(p.x - 0.6, p.y), generator.height(p.x, p.y + 0.6) - generator.height(p.x, p.y - 0.6)).length() / 1.2
	if slope < def.slope.x or slope > def.slope.y: return false
	if mushroom and p.distance_to(mushroom.base_xz) < keep_clear_of_mushroom: return false
	for entrance in generator.entrances:
		if p.distance_to(Vector2(entrance.x, entrance.z)) < keep_clear_of_entrances: return false
	return true

func merge(pieces: Array, is_rock: bool) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var tangents := PackedFloat32Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	for piece in pieces:
		var source: Dictionary = meshes[piece[0]]
		var transform: Transform3D = piece[1]
		var offset := vertices.size()
		var src_vertices: PackedVector3Array = source.vertices
		vertices.append_array(transform * src_vertices)
		var rotation := Transform3D(transform.basis.orthonormalized(), Vector3.ZERO)
		normals.append_array(rotation * source.normals)
		var src_colours: PackedColorArray = source.colours
		if is_rock:
			# The terrain shader reads colour as (sand amount, sun, occlusion); the kit stores occlusion in R.
			for c in src_colours:
				colours.append(Color(0.0, 1.0, c.r))
		else:
			# Reef shader: R glow weight, G per-piece random (re-rolled per placement), B sway weight.
			for c in src_colours:
				colours.append(Color(c.r, fposmod(c.g + piece[2], 1.0), c.b))
			uvs.append_array(source.uvs)
			var src_tangents: PackedFloat32Array = source.tangents
			for i in range(0, src_tangents.size(), 4):
				var t: Vector3 = rotation * Vector3(src_tangents[i], src_tangents[i + 1], src_tangents[i + 2])
				tangents.append_array(PackedFloat32Array([t.x, t.y, t.z, src_tangents[i + 3]]))
		for i: int in source.indices:
			indices.append(i + offset)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	if not is_rock:
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = indices
	if generate_lods:
		var importer := ImporterMesh.new()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
		importer.generate_lods(60.0, 25.0, [])
		return importer.get_mesh()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
