extends SceneTree
func _initialize() -> void: bake.call_deferred()
func bake() -> void:
	var start:=Time.get_ticks_msec()
	var settings:=ShallowsSettings.new()
	var generator:=ShallowsGenerator.new(settings)
	var index:=ShallowsBakeIndex.new()
	index.signature=settings.signature()
	DirAccess.make_dir_recursive_absolute('res://terrain/baked')
	var triangles:=0
	for coordinate in settings.coordinates():
		var data:=generator.generate(coordinate)
		if not data.mesh: continue
		var path:='res://terrain/baked/%s_%s_%s.res'%[coordinate.x,coordinate.y,coordinate.z]
		if ResourceSaver.save(data,path,ResourceSaver.FLAG_COMPRESS)!=OK:
			push_error('Terrain bake failed: '+path)
			quit(1)
			return
		index.coordinates.append(coordinate)
		index.files.append(path)
		triangles+=data.mesh.surface_get_array_index_len(0)/3
		if index.files.size()%10==0: print('Terrain bake: ',index.files.size(),' chunks; ',triangles,' triangles; ',(Time.get_ticks_msec()-start)/1000.0,' seconds')
	ResourceSaver.save(index,'res://terrain/baked/index.tres')
	print('Terrain bake PASS: ',index.files.size(),' chunks; ',triangles,' triangles; ',(Time.get_ticks_msec()-start)/1000.0,' seconds')
	quit()
