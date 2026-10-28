class_name AbyssDepthCapture
extends CompositorEffect
## Share the renderer's original depth texture with the water material.

var mono_depth := Texture2DRD.new()
var stereo_depth := Texture2DArrayRD.new()
var depth_rid := RID()
var stereo_mode := false

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT
	access_resolved_depth = true

func _render_callback(callback_type: int, render_data: RenderData) -> void:
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if not buffers: return
	var depth := buffers.get_depth_texture()
	var is_stereo := buffers.get_view_count() > 1
	if depth != depth_rid or is_stereo != stereo_mode:
		depth_rid = depth
		stereo_mode = is_stereo
		if is_stereo:
			stereo_depth.texture_rd_rid = depth
		else:
			mono_depth.texture_rd_rid = depth

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		mono_depth.texture_rd_rid = RID()
		stereo_depth.texture_rd_rid = RID()
