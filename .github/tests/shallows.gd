extends SceneTree
var failures: Array[String]=[]
var terrain: AbyssTerrain
var swimmer: AbyssSwimmer
var ocean: AbyssOcean
var fixture: Node3D
## Where the terrain streams around (it stands in for the camera).
var eye: Node3D
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
func ray(a: Vector3,b: Vector3,back_faces:=false) -> Dictionary:
	var query:=PhysicsRayQueryParameters3D.create(a,b,1)
	query.hit_back_faces=back_faces
	return fixture.get_world_3d().direct_space_state.intersect_ray(query)

## Moves the streaming centre and waits until every wanted block there has its mesh (and collision close by).
func stream_at(p: Vector3) -> void:
	eye.global_position=p
	var deadline:=Time.get_ticks_msec()+20000
	await process_frame
	while (not terrain.all_ready or terrain._centre.distance_to(p)>0.01) and Time.get_ticks_msec()<deadline:
		await process_frame
		OS.delay_msec(1)
	check(terrain.all_ready and terrain.near_ready,'Terrain must finish streaming in around %s'%p)
	await frames(2)

## Every open edge of every block mesh must run along open edges of the block across from it: same-detail neighbours
## share their boundary exactly, and a finer block only adds points along a coarser one's edges. Skirts (alpha 0) aside.
func check_watertight(where: String) -> void:
	var area:=terrain.settings.play_area()
	var n:=float(AbyssTerrainSettings.BLOCK)
	var open:={}
	var inside:=0
	var reversed:=0
	var triangles:=0
	var levels:=[0,0,0]
	for b in terrain.chunks:
		var entry: Dictionary=terrain.chunks[b]
		levels[entry.lod]+=1
		if not entry.has('visual'): continue
		var arrays: Array=entry.visual.mesh.surface_get_arrays(0)
		var v: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var colours: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
		var ids: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var count:={}
		for i in range(0,ids.size(),3):
			if colours[ids[i]].a<0.5: continue
			triangles+=1
			var a:=v[ids[i]]
			# Only at full detail (coarser blocks over the narrow cave tunnels fold the odd sliver, still facing the water),
			# and not for specks under 0.02 square metres, whose direction is only rounding.
			var front:=(v[ids[i+2]]-a).cross(v[ids[i+1]]-a)
			if entry.lod==0 and front.length()*0.5>0.02 and front.dot(normals[ids[i]]+normals[ids[i+1]]+normals[ids[i+2]])<0.0: reversed+=1
			for e in range(3):
				var k:=Vector2i(mini(ids[i+e],ids[i+(e+1)%3]),maxi(ids[i+e],ids[i+(e+1)%3]))
				count[k]=count.get(k,0)+1
		var lo:=Vector3(b)*n
		var list:=[]
		for k in count:
			if count[k]!=1: continue
			var p:=v[k.x]
			var q:=v[k.y]
			var on_box:=false
			for axis in range(3):
				for face in [lo[axis],lo[axis]+n]:
					if absf(p[axis]-face)<0.001 and absf(q[axis]-face)<0.001: on_box=true
			if on_box: list.append([p,q])
			else: inside+=1
		open[b]=list
	var cracks:=0
	for b in open:
		for edge in open[b]:
			var mid: Vector3=(edge[0]+edge[1])*0.5
			if mid.x<area.position.x+0.01 or mid.x>area.end.x-0.01 or mid.z<area.position.y+0.01 or mid.z>area.end.y-0.01: continue
			var covered:=[false,false,false]
			var unloaded:=false
			for o in terrain._neighbours:
				var other: Vector3i=b+o
				if not AABB(Vector3(other)*n,Vector3.ONE*n).grow(0.002).has_point(mid): continue
				if not terrain.chunks.has(other):
					unloaded=true
					continue
				for seg in open.get(other,[]):
					for i in range(3):
						if on_segment([edge[0],edge[1],mid][i],seg[0],seg[1]): covered[i]=true
			if not unloaded and not (covered[0] and covered[1] and covered[2]): cracks+=1
	print('Streamed terrain at %s: blocks by detail %s; %d triangles; %d open edges inside blocks; %d unmatched edges between blocks; %d full-detail faces against their normals'%[where,levels,triangles,inside,cracks,reversed])
	check(levels[0]>0 and levels[1]>0 and levels[2]>0,'All three detail levels must be in use around '+where)
	check(inside==0,'Block meshes must have no holes inside them ('+where+')')
	check(cracks==0,'Neighbouring blocks must meet without gaps, at any mix of detail ('+where+')')
	check(reversed==0,'Full-detail faces must point the same way as their normals ('+where+')')
	check(triangles<400000,'Streamed terrain must stay within its triangle budget ('+where+')')

func on_segment(p: Vector3,a: Vector3,b: Vector3) -> bool:
	var ab:=b-a
	var t:=clampf((p-a).dot(ab)/maxf(ab.length_squared(),1e-12),0.0,1.0)
	return p.distance_to(a+ab*t)<0.002

## Seen from straight above, the first surface at every point across the drop-off's lip must face up. Faces wound the
## other way are culled when drawn, and show as holes through the ground (as the first version of the lip did).
func check_lip_faces_up() -> void:
	var settings:=terrain.settings
	var rays:=0
	var inward:=0
	for zc in range(-112,113,32):
		await stream_at(Vector3(settings.shelf_edge,-6,zc))
		# Off the voxel grid, so no ray runs exactly along the plane where two blocks meet.
		var x:=settings.shelf_edge-settings.shelf_wobble-8.0+0.37
		while x<settings.shelf_edge+settings.shelf_wobble+20.0:
			for zi in range(zc-16,zc+16):
				if zi< -127 or zi>127: continue
				var hit:=ray(Vector3(x,2,zi+0.5),Vector3(x,-260,zi+0.5),true)
				if hit.is_empty() or hit.face_index<0: continue
				var body: CollisionObject3D=hit.collider
				var shape: ConcavePolygonShape3D=body.shape_owner_get_shape(body.shape_find_owner(hit.shape),0)
				var faces:=shape.get_faces()
				var i: int=hit.face_index*3
				rays+=1
				# Clearly facing down (a hole). Near-vertical faces of the cliff can tip a little either way and get grazed.
				if (faces[i+2]-faces[i]).cross(faces[i+1]-faces[i]).normalized().y< -0.1:
					inward+=1
					if inward<=5: print('  turned into the rock at ',hit.position)
			x+=0.5
	print('Lip from above: ',rays,' rays; ',inward,' first hits on faces turned into the rock')
	check(rays>10000,'Lip check must cover the whole drop-off')
	check(inward==0,'Every surface seen from above across the lip must face up (no holes)')

func run() -> void:
	fixture=Node3D.new()
	root.add_child(fixture)
	eye=Node3D.new()
	fixture.add_child(eye)
	terrain=AbyssTerrain.new()
	terrain.observer=eye
	fixture.add_child(terrain)
	check(terrain.store.index!=null,'The baked voxels must match the generator')
	var generator:=terrain.generator
	# The bake reproduces: a block worked out again matches what was stored.
	var block:=Vector3i(0,-1,-1)
	check(generator.block_voxels(block)==terrain.store.block(block),'The same seed must reproduce the baked voxels')
	for where in [['spawn',Vector3(0,-3,8)],['the lip',Vector3(112,-6,0)],['the deep plateau',Vector3(300,-195,40)]]:
		await stream_at(where[1])
		check_watertight(where[0])
	await check_lip_faces_up()
	for route in generator.routes:
		for p in route: check(generator.density(p)< -2.0,'Cave network must have continuous swimmable clearance')
	await stream_at(Vector3(60,-6,60))
	var seabed:=ray(Vector3(60,1,60),Vector3(60,-30,60))
	check(not seabed.is_empty(),'Seabed must have real collision')
	var chamber:=generator.chamber
	await stream_at(chamber)
	var roof:=ray(chamber,chamber+Vector3.UP*14)
	var floor_hit:=ray(chamber,chamber+Vector3.DOWN*14)
	check(not roof.is_empty() and not floor_hit.is_empty(),'Cave chamber must have a collidable roof and floor')
	if not roof.is_empty(): check(roof.position.y<generator.height(chamber.x,chamber.z)-1.0,'Cave roof must be underground, below the seabed')
	var different:=AbyssTerrainSettings.new()
	different.seed+=1
	check(absf(AbyssTerrainGenerator.new(different).height(24,24)-generator.height(24,24))>0.01,'Changing the seed must change geology')
	var scene: Node3D=load('res://game/main.tscn').instantiate()
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
	await stream_at(Vector3(0,-2,8))
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
	print('Shallows checks: streaming, watertight detail levels, lip, cave collision, deterministic bake, surface buoyancy, smooth turn')
	print('Shallows physics: ','PASS' if failures.is_empty() else 'FAIL')
	fixture.queue_free()
	ocean.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
