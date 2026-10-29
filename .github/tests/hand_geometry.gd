extends SceneTree

func _initialize() -> void: run.call_deferred()
func point(v: Vector3) -> Array: return [v.x,v.y,v.z]
func append_mesh(output: Dictionary, vertices: PackedVector3Array, indices: PackedInt32Array, transform: Transform3D) -> void:
	var start: int=output.vertices.size()
	for vertex in vertices: output.vertices.append(point(transform*vertex))
	for index in indices: output.indices.append(start+index)
func capture(side: String, throttle: float) -> Dictionary:
	var controller=XRController3D.new()
	root.add_child(controller)
	var hand=load('res://player/vr_hand.gd').new()
	hand.left_hand=side=='left'
	controller.add_child(hand)
	await process_frame
	if OS.get_environment('HAND_FIT_UNSAFE')=='1':
		# Negative control: the old blind Grip endpoint and uncorrected palm.
		hand.animator.play('Grip')
		hand.animator.seek(hand.animator.get_animation('Grip').length,true)
		hand.animator.pause()
		hand.skeleton.force_update_all_bone_transforms()
		hand.object_grip.global_transform=hand.skeleton.global_transform*hand.skeleton.get_bone_global_pose(hand.grip_bone)
	else:
		hand.holding=true
		hand.pose(1.0,throttle)
	var skin_mesh: MeshInstance3D=hand.find_children('*','MeshInstance3D',true,false)[0]
	var skin: Skin=skin_mesh.skin
	var arrays=skin_mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
	var bone_ids: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
	var stride: int=weights.size()/vertices.size()
	var transforms: Array[Transform3D]=[]
	for i in range(skin.get_bind_count()):
		var bone=skin.get_bind_bone(i)
		if bone<0: bone=hand.skeleton.find_bone(skin.get_bind_name(i))
		transforms.append(hand.skeleton.global_transform*hand.skeleton.get_bone_global_pose(bone)*skin.get_bind_pose(i))
	var posed=PackedVector3Array()
	for i in range(vertices.size()):
		var position=Vector3.ZERO
		for channel in range(stride):
			var weight=weights[i*stride+channel]
			if weight>0: position+=(transforms[bone_ids[i*stride+channel]]*vertices[i])*weight
		posed.append(position)
	var data={'hand':{'vertices':[],'indices':[]},'thruster':{'vertices':[],'indices':[]}}
	append_mesh(data.hand,posed,arrays[Mesh.ARRAY_INDEX],Transform3D.IDENTITY)
	var model: Node3D=load('res://player/thrusters/hand_thruster_left.glb' if side=='left' else 'res://player/thrusters/hand_thruster.glb').instantiate()
	root.add_child(model)
	model.global_transform=Transform3D(controller.global_basis,hand.object_grip.global_position)
	for mesh: MeshInstance3D in model.find_children('*','MeshInstance3D',true,false):
		var a=mesh.mesh.surface_get_arrays(0)
		append_mesh(data.thruster,a[Mesh.ARRAY_VERTEX],a[Mesh.ARRAY_INDEX],mesh.global_transform)
	model.queue_free()
	controller.queue_free()
	await process_frame
	return data
func run() -> void:
	var result={}
	for side in ['left','right']:
		for throttle in [0.0,0.5,1.0]:
			result[side+'_trigger_'+str(throttle)]=await capture(side,throttle)
	var path=OS.get_environment('HAND_FIT_OUTPUT') if OS.has_environment('HAND_FIT_OUTPUT') else '/tmp/hand-fit.json'
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(result))
	print('Posed hand and actual held model geometry written to ',path)
	quit()
