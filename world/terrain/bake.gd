extends SceneTree
## Bakes the world's voxels into world/terrain/baked/: one AbyssVoxelBatch per 128 m batch, and index.tres.
## Blocks the surface cannot reach are only marked all rock or all water; the rest are sampled, several at once.

func _initialize() -> void: bake.call_deferred()

func bake() -> void:
	var start:=Time.get_ticks_msec()
	var settings:=AbyssTerrainSettings.new()
	var generator:=AbyssTerrainGenerator.new(settings)
	var bounds:=settings.block_bounds()
	var low:=Vector3i(bounds.position)
	var high:=Vector3i(bounds.end)
	var kinds:={}
	var todo: Array[Vector3i]=[]
	for z in range(low.z,high.z):
		for y in range(low.y,high.y):
			for x in range(low.x,high.x):
				var b:=Vector3i(x,y,z)
				kinds[b]=generator.block_kind(b)
				if kinds[b]==AbyssVoxelBatch.DATA: todo.append(b)
	var voxels:={}
	var mutex:=Mutex.new()
	var task:=WorkerThreadPool.add_group_task(func(i: int) -> void:
		var bytes:=AbyssTerrainGenerator.new(settings).block_voxels(todo[i])
		mutex.lock()
		voxels[todo[i]]=bytes
		mutex.unlock(),todo.size(),-1,true,'Terrain bake')
	WorkerThreadPool.wait_for_group_task_completion(task)
	# Sampled blocks that came out all one side by the full stored range are just that.
	var n:=AbyssTerrainSettings.BLOCK*AbyssTerrainSettings.BLOCK*AbyssTerrainSettings.BLOCK
	for b in todo:
		if voxels[b].count(255)==n: kinds[b]=AbyssVoxelBatch.SOLID
		elif voxels[b].count(1)==n: kinds[b]=AbyssVoxelBatch.EMPTY
	var index:=AbyssVoxelIndex.new()
	index.signature=settings.signature()
	for b in kinds:
		if is_surface(b,kinds,low,high): index.surface_blocks.append(b)
	DirAccess.make_dir_recursive_absolute('res://world/terrain/baked')
	var stored:=0
	var size:=0
	var per:=AbyssTerrainSettings.BATCH_BLOCKS
	for bz in range(floori(float(low.z)/per),ceili(float(high.z)/per)):
		for by in range(floori(float(low.y)/per),ceili(float(high.y)/per)):
			for bx in range(floori(float(low.x)/per),ceili(float(high.x)/per)):
				var batch:=AbyssVoxelBatch.new()
				batch.coordinate=Vector3i(bx,by,bz)
				batch.kinds.resize(per*per*per)
				for lz in range(per):
					for ly in range(per):
						for lx in range(per):
							var b:=Vector3i(bx*per+lx,by*per+ly,bz*per+lz)
							var kind: int=kinds.get(b,AbyssVoxelBatch.SOLID if b.y<low.y else AbyssVoxelBatch.EMPTY)
							batch.kinds[lx+per*(ly+per*lz)]=kind
							if kind==AbyssVoxelBatch.DATA:
								var packed: PackedByteArray=voxels[b].compress(FileAccess.COMPRESSION_ZSTD)
								batch.blocks.append(packed)
								stored+=1
								size+=packed.size()
				var path:=AbyssVoxelIndex.batch_path(batch.coordinate)
				if ResourceSaver.save(batch,path)!=OK:
					push_error('Terrain bake failed: '+path)
					quit(1)
					return
				index.batches.append(batch.coordinate)
	if ResourceSaver.save(index,'res://world/terrain/baked/index.tres')!=OK:
		push_error('Terrain bake failed: index')
		quit(1)
		return
	print('Terrain bake PASS: %d blocks sampled, %d stored (%.1f MB), %d with surface, %d batch files; %.1f seconds'%[
		todo.size(),stored,size/1048576.0,index.surface_blocks.size(),index.batches.size(),(Time.get_ticks_msec()-start)/1000.0])
	quit()

## A block's cells reach one voxel into its + neighbours, so it can hold surface if it has stored voxels, or if any of
## those neighbours is not the same single kind as it.
static func is_surface(b: Vector3i,kinds: Dictionary,low: Vector3i,high: Vector3i) -> bool:
	var own: int=kinds[b]
	if own==AbyssVoxelBatch.DATA: return true
	for o in [Vector3i(1,0,0),Vector3i(0,1,0),Vector3i(0,0,1),Vector3i(1,1,0),Vector3i(1,0,1),Vector3i(0,1,1),Vector3i(1,1,1)]:
		if kind_at(b+o,kinds,low,high)!=own: return true
	return false

## Past the top of the stored range is water, past the bottom rock, and past the sides the edge blocks carry on.
static func kind_at(b: Vector3i,kinds: Dictionary,low: Vector3i,high: Vector3i) -> int:
	if b.y>=high.y: return AbyssVoxelBatch.EMPTY
	if b.y<low.y: return AbyssVoxelBatch.SOLID
	return kinds[Vector3i(clampi(b.x,low.x,high.x-1),b.y,clampi(b.z,low.z,high.z-1))]
