class_name AbyssReef
extends Node3D
## Places coral, kelp and rock over the seabed in clustered patches ("zones"). Everything in an
## area is merged into one mesh per material, so a whole patch costs one or two draw calls.
## The shapes here are simple placeholders; swap meshes() for the real kit when it arrives.

const CELL := 32.0
const VIEW_DISTANCE := 70.0

# kind: 'rock' uses the terrain's rock material; everything else gets the coral material.
# zone: noise frequency and threshold decide where the species may grow, so it forms patches.
var species := [
	{name = 'boulder', kind = 'rock', mesh = 'boulder', clusters = 26, per = Vector2i(2, 6), radius = 4.0, zone = Vector2(0.018, -0.1),
		ground = Vector2(-22.0, -2.0), slope = Vector2(0.0, 1.2), scale = Vector2(0.8, 2.2)},
	{name = 'coral_branching', kind = 'coral', mesh = 'branching', clusters = 22, per = Vector2i(5, 12), radius = 3.2, zone = Vector2(0.03, 0.12),
		ground = Vector2(-18.0, -3.0), slope = Vector2(0.0, 0.7), scale = Vector2(0.7, 1.4), palette = [Color(0.95, 0.45, 0.25), Color(0.9, 0.3, 0.45), Color(0.95, 0.7, 0.2)]},
	{name = 'coral_dome', kind = 'coral', mesh = 'dome', clusters = 18, per = Vector2i(4, 9), radius = 2.8, zone = Vector2(0.03, 0.05),
		ground = Vector2(-18.0, -3.0), slope = Vector2(0.0, 0.6), scale = Vector2(0.7, 1.5), palette = [Color(0.6, 0.35, 0.8), Color(0.35, 0.6, 0.85), Color(0.8, 0.6, 0.4)]},
	{name = 'coral_tube', kind = 'coral', mesh = 'tube', clusters = 14, per = Vector2i(3, 7), radius = 2.2, zone = Vector2(0.03, 0.2),
		ground = Vector2(-18.0, -3.0), slope = Vector2(0.0, 0.8), scale = Vector2(0.7, 1.3), palette = [Color(0.95, 0.85, 0.3), Color(0.5, 0.85, 0.7)]},
	{name = 'coral_fan', kind = 'coral', mesh = 'fan', clusters = 14, per = Vector2i(3, 7), radius = 2.5, zone = Vector2(0.03, 0.1),
		ground = Vector2(-18.0, -3.0), slope = Vector2(0.1, 1.0), scale = Vector2(0.8, 1.5), palette = [Color(0.85, 0.3, 0.7), Color(0.6, 0.3, 0.9)]},
	{name = 'kelp', kind = 'coral', mesh = 'kelp', clusters = 16, per = Vector2i(4, 10), radius = 3.0, zone = Vector2(0.02, 0.0),
		ground = Vector2(-22.0, -5.5), slope = Vector2(0.0, 0.4), scale = Vector2(0.8, 1.5), palette = [Color(0.3, 0.55, 0.2), Color(0.45, 0.6, 0.2)]},
]

## Off until the real models arrive; the placeholder shapes are crude.
@export var enabled := false
@export var keep_clear_of_mushroom := 28.0
@export var keep_clear_of_entrances := 8.0

var meshes: Dictionary = {}
var piece_count := 0

func _ready() -> void:
	if not enabled:
		return
	var terrain := get_node_or_null('../Terrain') as AbyssTerrain
	if terrain == null or terrain.generator == null:
		return
	var generator := terrain.generator
	var mushroom := get_node_or_null('../Mushroom') as AbyssMushroom
	meshes = build_placeholders()
	var half := Vector2(terrain.settings.region_chunks) * terrain.settings.chunk_size * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain.settings.seed + 211
	# cells[material kind][cell] -> Array of [species_index, Transform3D, Color]
	var cells := {'rock': {}, 'coral': {}}
	for index in range(species.size()):
		place_species(index, species[index], generator, mushroom, half, rng, cells)
	var rock_material: Material = terrain.material
	var coral_material := StandardMaterial3D.new()
	coral_material.vertex_color_use_as_albedo = true
	coral_material.roughness = 0.75
	for kind in cells:
		for cell: Vector2i in cells[kind]:
			var mesh := merge(cells[kind][cell], kind == 'rock')
			var instance := MeshInstance3D.new()
			instance.mesh = mesh
			instance.material_override = rock_material if kind == 'rock' else coral_material
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.visibility_range_end = VIEW_DISTANCE
			add_child(instance)

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
		var tint := Color(0.55, 0.55, 0.55)
		if def.kind == 'coral':
			tint = def.palette[rng.randi() % def.palette.size()]
		for k in range(rng.randi_range(def.per.x, def.per.y)):
			var p := centre + Vector2(rng.randfn(0.0, def.radius * 0.5), rng.randfn(0.0, def.radius * 0.5))
			if not suitable(p, def, generator, mushroom): continue
			var scale: float = rng.randf_range(def.scale.x, def.scale.y)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(scale, scale * rng.randf_range(0.85, 1.2), scale))
			var ground := generator.height(p.x, p.y)
			var jitter := Color(rng.randf_range(0.85, 1.1), rng.randf_range(0.85, 1.1), rng.randf_range(0.85, 1.1))
			var key := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
			if not cells[def.kind].has(key): cells[def.kind][key] = []
			cells[def.kind][key].append([def.mesh, Transform3D(basis, Vector3(p.x, ground - 0.06, p.y)), tint * jitter])
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
		# Rocks use the terrain shader, where colour = (sand amount, sun, occlusion); corals use albedo.
		var tint: Color = Color(0.0, 1.0, 1.0) if is_rock else piece[2]
		var chunk := PackedColorArray()
		chunk.resize(src_vertices.size())
		chunk.fill(tint)
		colours.append_array(chunk)
		for i: int in source.indices:
			indices.append(i + offset)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# --- placeholder shapes -------------------------------------------------------------------

func build_placeholders() -> Dictionary:
	return {
		'boulder': boulder(),
		'branching': branching(),
		'dome': dome(),
		'tube': tube(),
		'fan': fan(),
		'kelp': kelp(),
	}

func finish(st: SurfaceTool) -> Dictionary:
	st.generate_normals()
	st.index()
	var arrays := st.commit_to_arrays()
	return {vertices = arrays[Mesh.ARRAY_VERTEX], normals = arrays[Mesh.ARRAY_NORMAL], indices = arrays[Mesh.ARRAY_INDEX]}

func cone(st: SurfaceTool, base: Vector3, axis: Vector3, height: float, radius: float, tip_radius: float = 0.0, segments: int = 6) -> void:
	axis = axis.normalized()
	var side := axis.cross(Vector3.RIGHT if absf(axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD).normalized()
	var other := axis.cross(side)
	for i in range(segments):
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var b0 := base + (side * cos(a0) + other * sin(a0)) * radius
		var b1 := base + (side * cos(a1) + other * sin(a1)) * radius
		var t0 := base + axis * height + (side * cos(a0) + other * sin(a0)) * tip_radius
		var t1 := base + axis * height + (side * cos(a1) + other * sin(a1)) * tip_radius
		for v in [b0, t0, b1, b1, t0, t1]:
			st.add_vertex(v)

func boulder() -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var rings := 5
	var segments := 8
	var radii := []
	for r in range(rings + 1):
		var row := []
		for s in range(segments):
			row.append(rng.randf_range(0.75, 1.15))
		radii.append(row)
	for r in range(rings):
		for s in range(segments):
			var s1 := (s + 1) % segments
			var pts := []
			for rr in [r, r + 1]:
				var lat := PI * 0.5 * (1.0 - float(rr) / rings)   # from the top (1.5 rad) down to the equator
				var y := sin(lat)
				var ring_r := cos(lat)
				for ss in [s, s1]:
					var lon: float = TAU * float(ss) / segments
					var k: float = radii[rr][ss]
					pts.append(Vector3(cos(lon) * ring_r * k, y * k * 0.8, sin(lon) * ring_r * k))
			for v in [pts[0], pts[2], pts[1], pts[1], pts[2], pts[3]]:
				st.add_vertex(v)
	return finish(st)

func branching() -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	cone(st, Vector3.ZERO, Vector3.UP, 0.6, 0.16, 0.09)
	for i in range(6):
		var a := TAU * i / 6.0
		var dir := Vector3(cos(a) * 0.7, 1.0, sin(a) * 0.7)
		cone(st, Vector3(0, 0.4, 0), dir, 0.8, 0.09, 0.0)
	return finish(st)

func dome() -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 3
	var segments := 8
	for r in range(rings):
		for s in range(segments):
			var s1 := (s + 1) % segments
			var pts := []
			for rr in [r, r + 1]:
				var lat := PI * 0.5 * (1.0 - float(rr) / rings)
				for ss in [s, s1]:
					var lon: float = TAU * float(ss) / segments
					pts.append(Vector3(cos(lon) * cos(lat) * 0.7, sin(lat) * 0.55, sin(lon) * cos(lat) * 0.7))
			for v in [pts[0], pts[2], pts[1], pts[1], pts[2], pts[3]]:
				st.add_vertex(v)
	return finish(st)

func tube() -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(5):
		var a := TAU * i / 5.0
		cone(st, Vector3(cos(a) * 0.22, 0, sin(a) * 0.22), Vector3.UP, 0.5 + 0.1 * i, 0.1, 0.075)
	cone(st, Vector3.ZERO, Vector3.UP, 0.85, 0.12, 0.09)
	return finish(st)

func fan() -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 5
	for i in range(steps):
		var x0 := lerpf(-0.6, 0.6, float(i) / steps)
		var x1 := lerpf(-0.6, 0.6, float(i + 1) / steps)
		var h0 := 1.0 - absf(x0) * 0.55
		var h1 := 1.0 - absf(x1) * 0.55
		for v in [Vector3(x0, 0.15, 0), Vector3(x0, h0, 0), Vector3(x1, 0.15, 0), Vector3(x1, 0.15, 0), Vector3(x0, h0, 0), Vector3(x1, h1, 0),
				Vector3(x0, 0.15, 0), Vector3(x1, 0.15, 0), Vector3(x0, h0, 0), Vector3(x1, 0.15, 0), Vector3(x1, h1, 0), Vector3(x0, h0, 0)]:
			st.add_vertex(v)
	return finish(st)

func kelp() -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 6
	for blade in range(3):
		var a := TAU * blade / 3.0
		var lean := Vector3(cos(a), 0, sin(a))
		for i in range(segs):
			var t0 := float(i) / segs
			var t1 := float(i + 1) / segs
			var w0 := 0.18 * (1.0 - 0.7 * t0)
			var w1 := 0.18 * (1.0 - 0.7 * t1)
			var side := lean.cross(Vector3.UP) * 0.5
			var c0 := lean * t0 * t0 * 1.2 + Vector3.UP * t0 * 5.0
			var c1 := lean * t1 * t1 * 1.2 + Vector3.UP * t1 * 5.0
			for v in [c0 - side * w0, c0 + side * w0, c1 - side * w1, c1 - side * w1, c0 + side * w0, c1 + side * w1,
					c0 - side * w0, c1 - side * w1, c0 + side * w0, c1 - side * w1, c1 + side * w1, c0 + side * w0]:
				st.add_vertex(v)
	return finish(st)
