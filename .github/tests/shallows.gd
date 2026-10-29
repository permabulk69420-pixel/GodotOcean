extends SceneTree
var failures: Array[String]=[]
var terrain: ShallowsTerrain
var swimmer: ShallowsSwimmer
var ocean: AbyssOcean
var fixture: Node3D
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func frames(count: int) -> void:
	for i in range(count): await physics_frame
func key(code: Key,pressed: bool) -> void:
	var event:=InputEventKey.new()
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)
func ray(a: Vector3,b: Vector3) -> Dictionary:
	return fixture.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1))
func check_surface_integrity() -> void:
	var settings:=ShallowsSettings.new()
	var index: ShallowsBakeIndex=load('res://terrain/baked/index.tres')
	var open_edges:=0
	var folded:=0
	var triangles:=0
	for path in index.files:
		var data: ShallowsChunkData=load(path)
		var arrays:=data.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var ids: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		triangles+=ids.size()/3
		var counts: Dictionary={}
		for i in range(0,ids.size(),3):
			var a:=ids[i];var b:=ids[i+1];var c:=ids[i+2]
			if (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).dot(normals[a]+normals[b]+normals[c])>0.00001: folded+=1
			for edge in range(3):
				var lo:=mini(ids[i+edge],ids[i+(edge+1)%3]);var hi:=maxi(ids[i+edge],ids[i+(edge+1)%3])
				var key:=lo+hi*vertices.size()
				counts[key]=counts.get(key,0)+1
		var base:=Vector3(data.coordinate)*settings.chunk_size
		for key in counts:
			if counts[key]!=1: continue
			var a:=vertices[key%vertices.size()]-base
			var b:=vertices[key/vertices.size()]-base
			var boundary:=false
			for axis in range(3):
				if absf(a[axis])<0.0001 and absf(b[axis])<0.0001 or absf(a[axis]-settings.chunk_size)<0.0001 and absf(b[axis]-settings.chunk_size)<0.0001: boundary=true
			if not boundary: open_edges+=1
	print('Terrain integrity: ',index.files.size(),' chunks; ',triangles,' triangles; ',open_edges,' interior open edges; ',folded,' reversed faces')
	check(open_edges==0,'Smoothed terrain must not have interior holes')
	check(folded==0,'Smoothed terrain faces must point out of the solid volume')
	check(triangles<350000,'Initial biome must remain within its geometry budget')

func run() -> void:
	check_surface_integrity()
	fixture=Node3D.new()
	root.add_child(fixture)
	terrain=ShallowsTerrain.new()
	fixture.add_child(terrain)
	var deadline:=Time.get_ticks_msec()+10000
	while not terrain.all_ready and Time.get_ticks_msec()<deadline:
		await process_frame
		OS.delay_msec(1)
	check(terrain.all_ready,'Baked terrain must finish loading')
	await frames(3)
	var generator:=ShallowsGenerator.new()
	for route in generator.routes:
		for p in route: check(generator.density(p)< -2.0,'Cave network must have continuous swimmable clearance')
	var seabed:=ray(Vector3(60,1,60),Vector3(60,-30,60))
	check(not seabed.is_empty(),'Seabed must have real collision')
	var chamber:=generator.chamber
	var roof:=ray(chamber,chamber+Vector3.UP*14)
	var floor_hit:=ray(chamber,chamber+Vector3.DOWN*14)
	check(not roof.is_empty() and not floor_hit.is_empty(),'Cave chamber must have a collidable roof and floor')
	if not roof.is_empty(): check(roof.position.y<generator.height(chamber.x,chamber.z)-1.0,'Cave roof must be underground, below the seabed')
	# Independently generated neighbouring chunks must share positions and normals at the boundary.
	var a: ShallowsChunkData=load('res://terrain/baked/0_-1_-1.res')
	var b: ShallowsChunkData=load('res://terrain/baked/0_-1_-2.res')
	var av:=a.mesh.surface_get_arrays(0)
	var bv:=b.mesh.surface_get_arrays(0)
	var edge: Dictionary={}
	for i in range(av[Mesh.ARRAY_VERTEX].size()):
		var p: Vector3=av[Mesh.ARRAY_VERTEX][i]
		if absf(p.z+16)<0.0001: edge[p.snapped(Vector3.ONE*0.0001)]=av[Mesh.ARRAY_NORMAL][i]
	var shared:=0
	for i in range(bv[Mesh.ARRAY_VERTEX].size()):
		var p: Vector3=bv[Mesh.ARRAY_VERTEX][i]
		if absf(p.z+16)<0.0001:
			var k:=p.snapped(Vector3.ONE*0.0001)
			check(edge.has(k),'Shared chunk boundary vertices must match')
			if edge.has(k):
				shared+=1
				check(edge[k].distance_to(bv[Mesh.ARRAY_NORMAL][i])<0.002,'Shared terrain normals must be continuous')
	check(shared>5,'Seam test must cover a real terrain boundary')
	var repeated:=generator.generate(Vector3i(0,-1,-1))
	check(repeated.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].to_byte_array()==av[Mesh.ARRAY_VERTEX].to_byte_array(),'The same seed must reproduce the baked chunk')
	var different:=ShallowsSettings.new()
	different.seed+=1
	check(absf(ShallowsGenerator.new(different).height(24,24)-generator.height(24,24))>0.01,'Changing the seed must change geology')
	var scene: Node3D=load('res://ocean/main.tscn').instantiate()
	swimmer=scene.get_node('Player')
	scene.remove_child(swimmer)
	scene.free()
	fixture.add_child(swimmer)
	swimmer.head.position.y=1.6
	ocean=AbyssOcean.new()
	ocean.settings=AbyssOceanSettings.new()
	ocean.build_spectrum()
	swimmer.ocean=ocean
	swimmer.terrain=terrain
	swimmer.controls_enabled=true
	swimmer.spawned=true
	if not floor_hit.is_empty() and not roof.is_empty():
		swimmer.global_position=chamber-Vector3.UP*1.6
		swimmer.velocity=Vector3.ZERO
		key(KEY_SPACE,true)
		await frames(180)
		key(KEY_SPACE,false)
		check(swimmer.head.global_position.y<=roof.position.y+0.04,'Swimming upward must stop at the cave ceiling')
		check(swimmer.get_slide_collision_count()>0,'Ceiling check must register real physics contact')
		swimmer.global_position=chamber-Vector3.UP*1.6
		swimmer.velocity=Vector3.ZERO
		key(KEY_CTRL,true)
		await frames(180)
		key(KEY_CTRL,false)
		var feet: float=swimmer.collider.global_position.y-(swimmer.collider.shape as CapsuleShape3D).height*0.5
		check(feet>=floor_hit.position.y-0.12,'Swimming downward must not pass through the cave floor')
	var water: float=ocean.sample_surface(Vector3(0,0,8)).height
	swimmer.global_position=Vector3(0,water+0.3-1.6,8)
	swimmer.velocity=Vector3.ZERO
	key(KEY_SPACE,true)
	await frames(180)
	key(KEY_SPACE,false)
	check(swimmer.head.global_position.y<water+0.9,'Holding ascend must not fly out of the water')
	await frames(180)
	check(absf(swimmer.head.global_position.y-water-0.25)<0.35,'Released controls should float near the surface')
	swimmer.head.position.x=0.35
	var pivot:=swimmer.head.global_position
	var yaw:=swimmer.rotation.y
	key(KEY_E,true)
	await frames(60)
	key(KEY_E,false)
	check(absf(swimmer.rotation.y-yaw)>1.0,'Turning must be smooth and continuous')
	check(Vector2(swimmer.head.global_position.x-pivot.x,swimmer.head.global_position.z-pivot.z).length()<0.05,'Smooth turning must preserve the head pivot')
	print('Shallows checks: ',terrain.chunks.size(),' chunks; ',shared,' shared seam vertices; cave collision, deterministic generation, surface buoyancy, smooth turn')
	print('Shallows physics: ','PASS' if failures.is_empty() else 'FAIL')
	fixture.queue_free()
	ocean.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
