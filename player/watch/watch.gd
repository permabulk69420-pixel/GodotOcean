class_name AbyssWatch
extends Node3D
## The watch on the left wrist (watch.glb). Its glass shows the frame rate; tapping the glass with the right index finger
## opens the menu panel (AbyssWatchMenu), and tapping it again closes it. On a flat screen M does the same.
## It finds the player's hands by path, so it must come after Player in the scene.

const MODEL := preload('res://player/watch/watch.glb')
const PIXELS := 256
const REFRESH := 0.5  # seconds between redraws of the glass and the menu: each redraw is a render pass, so not every frame
const BACKGROUND := Color(0.02, 0.04, 0.05)
const CAPTION_COLOUR := Color('6fb7ad')
const DIM_COLOUR := Color('7f9298')
# A tap: the fingertip is over the glass and has come down to it. It cannot tap again until it has been lifted clear.
const POKE_RADIUS := 0.03   # metres from the middle of the glass, across it
const POKE_DEPTH := 0.012   # metres above the glass or nearer
const POKE_FLOOR := -0.02   # (and not through the wrist)
const POKE_CLEAR := 0.04    # metres above the glass that re-arms it
const POKE_AWAY := 0.06     # or this far across
const OPEN_HAND := 0.3      # a hand squeezing or pulling a trigger is not tapping anything
const DEFAULT_RATE := 72.0
const SCALES := [1.0, 0.9, 0.8, 0.7]  # render scales the A button steps through
const FILTERS := [4, 2, 0]  # anisotropic levels the left stick click steps through: 16x, 4x, off

var diagnostics := AbyssDiagnostics.new()
var menu: AbyssWatchMenu
var origin: XROrigin3D
var head: Node3D
var left: AbyssVRHand
var right: AbyssVRHand
var face: Node3D  # the middle of the glass, +Y out of it
var glass: SubViewport
var number: Label
var detail: Label
var index_bones: Array[int] = []
var armed := true
var key_was := false
var test_was := [false, false, false, false, false, false]
var since_refresh := 0.0

func _ready() -> void:
	var player := get_node('../Player')
	origin = player.get_node('XROrigin3D')
	head = origin.get_node('Head')
	left = origin.get_node('LeftHand/Hand')
	right = origin.get_node('RightHand/Hand')
	for number_in_finger in [2, 3]:
		index_bones.append(right.skeleton.find_bone('b_r_index%d' % number_in_finger))

	var watch: Node3D = MODEL.instantiate()
	watch.name = 'Watch'
	left.model.add_child(watch)
	face = watch.find_child('watch_face', true, false)
	_build_glass(watch)

	menu = AbyssWatchMenu.new()
	menu.name = 'WatchMenu'
	origin.add_child(menu)  # moves with the player, so it stays where it was hung while swimming

func _build_glass(watch: Node3D) -> void:
	glass = SubViewport.new()
	glass.size = Vector2i(PIXELS, PIXELS)
	glass.disable_3d = true
	glass.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(glass)
	var backdrop := ColorRect.new()
	backdrop.color = BACKGROUND
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	glass.add_child(backdrop)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override('separation', 6)
	glass.add_child(column)
	column.add_child(_label('FPS', 34, CAPTION_COLOUR))
	number = _label('--', 110, Color.WHITE)
	column.add_child(number)
	detail = _label('', 44, DIM_COLOUR)
	column.add_child(detail)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_fog = true
	material.albedo_texture = glass.get_texture()
	(watch.find_child('Watch_Screen', true, false) as MeshInstance3D).material_override = material

static func _label(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override('font_size', size)
	label.add_theme_color_override('font_color', colour)
	return label

# Is a fingertip (in the glass's own frame: +Y out of it) on the glass?
static func poke_hit(local: Vector3) -> bool:
	return Vector2(local.x, local.z).length() < POKE_RADIUS and local.y < POKE_DEPTH and local.y > POKE_FLOOR

# Is it well clear of the glass again?
static func poke_clear(local: Vector3) -> bool:
	return local.y > POKE_CLEAR or Vector2(local.x, local.z).length() > POKE_AWAY

# `tip`: a fingertip in the world. True on the frame it taps the glass.
func tapped_by(tip: Vector3) -> bool:
	var local := face.global_transform.affine_inverse() * tip
	if armed and poke_hit(local):
		armed = false
		return true
	if not armed and poke_clear(local):
		armed = true
	return false

# The right index fingertip: a little way on from the last joint, along the last bone.
func index_tip() -> Vector3:
	var skeleton := right.skeleton
	var before := (skeleton.global_transform * skeleton.get_bone_global_pose(index_bones[0])).origin
	var last := (skeleton.global_transform * skeleton.get_bone_global_pose(index_bones[1])).origin
	return last + (last - before) * 0.9

func target_rate() -> float:
	var xr := XRServer.primary_interface
	var rate = xr.get('display_refresh_rate') if xr != null else null
	return float(rate) if rate != null and float(rate) > 0.0 else DEFAULT_RATE

func toggle_menu() -> void:
	if menu.is_open:
		menu.close()
		# The water and seabed tests are only for reading the numbers; put them back when the panel goes away.
		if get_parent().get('ocean') != null:
			get_parent().ocean.surface.visible = true
			get_parent().set_seabed_test(0)
			get_parent().set_terrain_transparent_test(false)
			get_parent().freeze_time = false
	else:
		menu.open(head.global_transform)
		if get_parent().get('ocean') != null: get_parent().freeze_time = true
		refresh()
	# GPU and CPU render times are only measured while the panel is up.
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), menu.is_open)

## The performance tests, run from the panel while it is open: 0 render scale (A), 1 anti-aliasing (B), 2 water
## surface (X), 3 seabed (Y: terrain, reef and seagrass one at a time), 4 texture filtering (left stick click), 5 whether the
## terrain is drawn the old transparent way (right stick click). Render scale and anti-aliasing stay as set; the water and seabed
## tests undo themselves on close, and the time of day is frozen while the panel is up.
func press_test(index: int) -> void:
	var game := get_parent()
	var viewport := get_viewport()
	match index:
		0:
			var nearest := 0
			for i in range(SCALES.size()):
				if absf(SCALES[i] - viewport.scaling_3d_scale) < absf(SCALES[nearest] - viewport.scaling_3d_scale): nearest = i
			viewport.scaling_3d_scale = SCALES[(nearest + 1) % SCALES.size()]
		1:
			viewport.msaa_3d = ((viewport.msaa_3d + 1) % 3) as Viewport.MSAA
		2:
			if game.get('ocean') != null: game.ocean.surface.visible = not game.ocean.surface.visible
		3:
			if game.get('ocean') != null: game.set_seabed_test((game.seabed_test + 1) % 5)
		4:
			var nearest_filter := 0
			for i in range(FILTERS.size()):
				if absi(FILTERS[i] - viewport.anisotropic_filtering_level) < absi(FILTERS[nearest_filter] - viewport.anisotropic_filtering_level): nearest_filter = i
			viewport.anisotropic_filtering_level = FILTERS[(nearest_filter + 1) % FILTERS.size()] as Viewport.AnisotropicFiltering
		5:
			if game.get('ocean') != null: game.set_terrain_transparent_test(not game.terrain_transparent_test)
	show_panel_values()

func show_panel_values() -> void:
	menu.show_values(diagnostics.values(get_viewport(), get_parent(), target_rate()))

func refresh() -> void:
	since_refresh = 0.0
	diagnostics.close_interval()
	var target := target_rate()
	number.text = '%.0f' % diagnostics.fps
	number.add_theme_color_override('font_color', AbyssDiagnostics.rate_colour(diagnostics.fps, target))
	detail.text = '%.1f ms' % diagnostics.average_ms
	glass.render_target_update_mode = SubViewport.UPDATE_ONCE
	if menu.is_open: show_panel_values()

func _process(delta: float) -> void:
	diagnostics.frame(delta)
	since_refresh += delta
	if since_refresh >= REFRESH: refresh()
	var asked := false
	var key := Input.is_key_pressed(KEY_M)
	asked = key and not key_was
	key_was = key
	if left.visible and right.visible and tapped_by(index_tip()):
		var free_hand := right.controller.get_float(&'grip') < OPEN_HAND and right.controller.get_float(&'trigger') < OPEN_HAND and not right.holding
		asked = asked or free_hand or menu.is_open
	if asked: toggle_menu()
	if menu.is_open: _read_test_buttons()

# A and B on the right controller, X and Y on the left, the left and right stick clicks (or 1 to 6 on a keyboard); each
# press runs one test.
func _read_test_buttons() -> void:
	var buttons := [
		right.controller.is_button_pressed(&'ax_button'), right.controller.is_button_pressed(&'by_button'),
		left.controller.is_button_pressed(&'ax_button'), left.controller.is_button_pressed(&'by_button'),
		left.controller.is_button_pressed(&'primary_click'), right.controller.is_button_pressed(&'primary_click'),
	]
	for index in range(buttons.size()):
		var down: bool = buttons[index] or Input.is_key_pressed(KEY_1 + index)
		if down and not test_was[index]: press_test(index)
		test_was[index] = down
