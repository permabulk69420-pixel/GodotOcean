class_name AbyssVoxelStore
extends RefCounted
## The world's voxels as the game reads them: batch files are loaded, and blocks unpacked, the first time something asks
## for them, and let go again once the camera is far away (forget_beyond). Safe to use from worker threads.

const EMPTY_VALUE := -AbyssTerrainSettings.DISTANCE_RANGE
const SOLID_VALUE := AbyssTerrainSettings.DISTANCE_RANGE

var settings: AbyssTerrainSettings
var index: AbyssVoxelIndex
## Only used when there is no bake to read (e.g. straight after changing the generator in the editor): blocks are then
## sampled from it as they are needed, which is slow.
var generator: AbyssTerrainGenerator
## Blocks that can hold any surface; only these are meshed.
var surface_blocks := {}
var low := Vector3i.ZERO
var high := Vector3i.ZERO
var _batches := {}
## Block -> its unpacked voxels (PackedByteArray), or just EMPTY or SOLID.
var _blocks := {}
var _mutex := Mutex.new()

func _init(config: AbyssTerrainSettings, baked: AbyssVoxelIndex, fallback: AbyssTerrainGenerator) -> void:
	settings=config
	index=baked
	generator=fallback
	var bounds:=settings.block_bounds()
	low=Vector3i(bounds.position)
	high=Vector3i(bounds.end)
	if index:
		for b in index.surface_blocks: surface_blocks[b]=true
		return
	push_warning('No baked terrain matches the generator; sampling blocks as they are needed (slow). Run world/terrain/bake.gd.')
	var kinds:={}
	for z in range(low.z,high.z):
		for y in range(low.y,high.y):
			for x in range(low.x,high.x): kinds[Vector3i(x,y,z)]=generator.block_kind(Vector3i(x,y,z))
	for b in kinds:
		if load('res://world/terrain/bake.gd').is_surface(b,kinds,low,high): surface_blocks[b]=true

## A block's voxels (PackedByteArray), or EMPTY or SOLID. Outside the stored range: water above, rock below, and the
## blocks at the sides carry on outwards.
func block(b: Vector3i) -> Variant:
	if b.y>=high.y: return AbyssVoxelBatch.EMPTY
	if b.y<low.y: return AbyssVoxelBatch.SOLID
	b=Vector3i(clampi(b.x,low.x,high.x-1),b.y,clampi(b.z,low.z,high.z-1))
	_mutex.lock()
	var got: Variant=_blocks.get(b)
	if got==null:
		got=_unpack(b)
		_blocks[b]=got
	_mutex.unlock()
	return got

func _unpack(b: Vector3i) -> Variant:
	var n:=AbyssTerrainSettings.BLOCK
	if not index:
		var kind:=generator.block_kind(b)
		return kind if kind!=AbyssVoxelBatch.DATA else generator.block_voxels(b)
	var per:=AbyssTerrainSettings.BATCH_BLOCKS
	var bc:=Vector3i(floori(float(b.x)/per),floori(float(b.y)/per),floori(float(b.z)/per))
	var batch: AbyssVoxelBatch=_batches.get(bc)
	if not batch:
		batch=load(AbyssVoxelIndex.batch_path(bc))
		_batches[bc]=batch
	var local:=b-bc*per
	var i:=local.x+per*(local.y+per*local.z)
	if batch.kinds[i]!=AbyssVoxelBatch.DATA: return batch.kinds[i]
	var k:=0
	for j in range(i):
		if batch.kinds[j]==AbyssVoxelBatch.DATA: k+=1
	return batch.blocks[k].decompress(n*n*n,FileAccess.COMPRESSION_ZSTD)

## The distance to the surface (metres, positive in rock, clamped) at a whole-metre point.
func value(x: int,y: int,z: int) -> float:
	var n:=AbyssTerrainSettings.BLOCK
	x=clampi(x,low.x*n,high.x*n-1)
	z=clampi(z,low.z*n,high.z*n-1)
	var b:=Vector3i(floori(float(x)/n),floori(float(y)/n),floori(float(z)/n))
	var got: Variant=block(b)
	if got is PackedByteArray:
		return (got[(x-b.x*n)+n*((y-b.y*n)+n*(z-b.z*n))]-128)*(AbyssTerrainSettings.DISTANCE_RANGE/127.0)
	return SOLID_VALUE if got==AbyssVoxelBatch.SOLID else EMPTY_VALUE

## The values at origin + (i, j, k) * step for i, j, k in 0 .. count - 1 (x fastest, then y, then z).
func fill(origin: Vector3i,step: int,count: int) -> PackedFloat32Array:
	var n:=AbyssTerrainSettings.BLOCK
	var scale:=AbyssTerrainSettings.DISTANCE_RANGE/127.0
	var out:=PackedFloat32Array()
	out.resize(count*count*count)
	var at:=0
	var cached_block:=Vector3i(1<<30,0,0)
	var cached: Variant=null
	for k in range(count):
		var z:=origin.z+k*step
		for j in range(count):
			var y:=origin.y+j*step
			for i in range(count):
				var x:=origin.x+i*step
				var cx:=clampi(x,low.x*n,high.x*n-1)
				var cz:=clampi(z,low.z*n,high.z*n-1)
				var b:=Vector3i(floori(float(cx)/n),floori(float(y)/n),floori(float(cz)/n))
				if b!=cached_block:
					cached_block=b
					cached=block(b)
				if cached is PackedByteArray:
					out[at]=(cached[(cx-b.x*n)+n*((y-b.y*n)+n*(cz-b.z*n))]-128)*scale
				else:
					out[at]=SOLID_VALUE if cached==AbyssVoxelBatch.SOLID else EMPTY_VALUE
				at+=1
	return out

## Lets go of unpacked blocks and loaded batches further than this from a point (they are read again if needed).
func forget_beyond(centre: Vector3,distance: float) -> void:
	var n:=float(AbyssTerrainSettings.BLOCK)
	_mutex.lock()
	for b in _blocks.keys():
		var box:=AABB(Vector3(b)*n,Vector3.ONE*n)
		if (box.get_center()-centre).length()-n>distance: _blocks.erase(b)
	var span:=n*AbyssTerrainSettings.BATCH_BLOCKS
	for bc in _batches.keys():
		var box:=AABB(Vector3(bc)*span,Vector3.ONE*span)
		if (box.get_center()-centre).length()-span>distance: _batches.erase(bc)
	_mutex.unlock()
