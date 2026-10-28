extends SceneTree
## Apply Android feature overrides before starting the desktop XR preview.
func _initialize() -> void:
	var config := ConfigFile.new()
	for feature in ["mobile", "android"]:
		for property in ProjectSettings.get_property_list():
			var name: String = property.name
			if not name.ends_with("." + feature): continue
			var base := name.trim_suffix("." + feature)
			var split := base.find("/")
			if split < 0: continue
			config.set_value(base.left(split), base.substr(split + 1), ProjectSettings.get_setting(name))
	config.set_value("xr", "shaders/enabled", true)
	config.set_value("xr", "openxr/enabled", false)
	var result := config.save("res://override.cfg")
	quit(0 if result == OK else 1)
