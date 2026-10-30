class_name AbyssWatchMenu
extends Node3D
## The panel that opens when the watch is tapped: the big frame from the watch model (menu_frame.glb) hung in front of
## you, showing a page drawn on a small viewport. For now there is one page, the diagnostics; more pages (oxygen, buttons)
## would be added as extra content in the same viewport.

const FRAME := preload('res://player/watch/menu_frame.glb')
const PIXELS := Vector2i(960, 616)
const INNER := Vector2(0.668, 0.428)  # the plate inside the frame, in the model's own metres
const FRAME_SCALE := 0.85
const DISTANCE := 0.85                # metres in front of the head
const DROP := 0.1                     # and a little below it
const FACE_Z := 0.004                 # the page sits this far (model metres) in front of the plate
const BACKGROUND := Color(0.043, 0.063, 0.078)
const ACCENT := Color('5fd0c0')
const TEXT := Color('e9eef0')
const TEXT_DIM := Color('7f9298')
const FONT := 26

var is_open := false
var viewport: SubViewport
var cells := {}  # row label -> the Label holding its value

func _ready() -> void:
	visible = false
	var frame: Node3D = FRAME.instantiate()
	frame.scale = Vector3.ONE * FRAME_SCALE
	add_child(frame)

	# Drawn only when a value changes (a render pass of its own each time), not every frame.
	viewport = SubViewport.new()
	viewport.size = PIXELS
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	viewport.add_child(_build_page())

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_fog = true
	material.albedo_texture = viewport.get_texture()
	var plane := QuadMesh.new()
	plane.size = INNER * FRAME_SCALE
	var quad := MeshInstance3D.new()
	quad.mesh = plane
	quad.material_override = material
	quad.position = Vector3(0, 0, FACE_Z * FRAME_SCALE)
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)

func _build_page() -> Control:
	var page := PanelContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := StyleBoxFlat.new()
	box.bg_color = BACKGROUND
	box.set_content_margin_all(34)
	page.add_theme_stylebox_override('panel', box)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override('separation', 14)
	page.add_child(layout)
	layout.add_child(_label('DIAGNOSTICS', 34, ACCENT))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override('separation', 56)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(columns)
	# Two columns: the first two sections on the left, the rest on the right.
	var sections := AbyssDiagnostics.SECTIONS
	for column_index in range(2):
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override('separation', 3)
		columns.add_child(column)
		for section_index in range(column_index * 2, column_index * 2 + 2):
			var section: Array = sections[section_index]
			var heading := _label(String(section[0]).to_upper(), 22, TEXT_DIM)
			heading.add_theme_constant_override('line_spacing', 0)
			column.add_child(heading)
			for row_label: String in section[1]:
				var row := HBoxContainer.new()
				row.add_child(_label(row_label, FONT, TEXT_DIM, true))
				var value := _label(AbyssDiagnostics.NONE, FONT, TEXT, false)
				value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				row.add_child(value)
				cells[row_label] = value
				column.add_child(row)
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 8)
			column.add_child(gap)
	return page

static func _label(text: String, size: int, colour: Color, expand := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override('font_size', size)
	label.add_theme_color_override('font_color', colour)
	if expand: label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

## Hang it in front of `head` (a world transform), level with the horizon whichever way the head is tilted.
func open(head: Transform3D) -> void:
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	global_position = head.origin + forward * DISTANCE + Vector3(0.0, -DROP, 0.0)
	global_basis = Basis.looking_at(forward, Vector3.UP)  # the frame faces +Z: towards you
	is_open = true
	visible = true

func close() -> void:
	is_open = false
	visible = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

## Put new values on the page (keys are the row labels) and redraw it once.
func show_values(values: Dictionary) -> void:
	for row_label: String in values:
		var cell: Label = cells.get(row_label)
		if cell != null and cell.text != values[row_label]: cell.text = values[row_label]
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
