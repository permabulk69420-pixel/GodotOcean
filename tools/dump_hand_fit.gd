extends SceneTree
func _initialize() -> void: run.call_deferred()
func matrix(t: Transform3D) -> Array:
	return [[t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x],[t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y],[t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z],[0,0,0,1]]
func vec(v: Vector3) -> Array: return [v.x,v.y,v.z]
func quat(q: Quaternion) -> Array: return [q.x,q.y,q.z,q.w]
func run() -> void:
	var output={}
	for side in ['left','right']:
		var controller=XRController3D.new()
		root.add_child(controller)
		var hand=load('res://player/hands/vr_hand.gd').new()
		hand.left_hand=side=='left'
		controller.add_child(hand)
		await process_frame
		var skeleton: Skeleton3D=hand.skeleton
		var mesh: MeshInstance3D=hand.find_children('*','MeshInstance3D',true,false)[0]
		var arrays=mesh.mesh.surface_get_arrays(0)
		var skin: Skin=mesh.skin
		var data={'skeleton_transform':matrix(skeleton.global_transform),'vertices':[],'indices':Array(arrays[Mesh.ARRAY_INDEX]),'weights':Array(arrays[Mesh.ARRAY_WEIGHTS]),'bones':Array(arrays[Mesh.ARRAY_BONES]),'binds':[],'parents':[],'names':[],'poses':{},'grip_origin':vec((skeleton.global_transform*skeleton.get_bone_global_pose(hand.grip_bone)).origin)}
		for v in arrays[Mesh.ARRAY_VERTEX]: data.vertices.append(vec(v))
		for i in range(skin.get_bind_count()):
			var bone=skin.get_bind_bone(i)
			if bone<0: bone=skeleton.find_bone(skin.get_bind_name(i))
			data.binds.append({'bone':bone,'matrix':matrix(skin.get_bind_pose(i))})
		for i in range(skeleton.get_bone_count()):
			data.parents.append(skeleton.get_bone_parent(i))
			data.names.append(skeleton.get_bone_name(i))
		for pose in ['Open','Grip','Fist']:
			hand.animator.play(pose)
			hand.animator.seek(hand.animator.get_animation(pose).length,true)
			hand.animator.pause()
			skeleton.force_update_all_bone_transforms()
			var transforms=[]
			for i in range(skeleton.get_bone_count()):
				transforms.append({'position':vec(skeleton.get_bone_pose_position(i)),'rotation':quat(skeleton.get_bone_pose_rotation(i)),'scale':vec(skeleton.get_bone_pose_scale(i))})
			data.poses[pose]=transforms
		output[side]=data
		controller.queue_free()
	FileAccess.open(OS.get_environment('HAND_FIT_INPUT') if OS.has_environment('HAND_FIT_INPUT') else '/tmp/hand-fit-input.json',FileAccess.WRITE).store_string(JSON.stringify(output))
	print('Hand fit data exported')
	quit()
