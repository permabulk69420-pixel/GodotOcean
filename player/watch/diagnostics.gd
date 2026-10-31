class_name AbyssDiagnostics
extends RefCounted
## The numbers the watch shows. Call frame() every frame; every so often call close_interval(), then values().
## The render counts are for the visible pass of the main viewport (both eyes are drawn together, so they count once).

## Row labels by section, and which of the panel's two columns each goes in; values() returns a dictionary with
## exactly these keys. The letters in the Tests labels are the controller buttons that change them (see AbyssWatch).
const SECTIONS := [
	['Frame', ['FPS', 'Frame time', 'Slowest frame', 'GPU time', 'CPU render'], 0],
	['Tests: press the button', ['A  Render scale', 'B  Anti-aliasing', 'X  Water surface', 'Y  Seabed', 'L-stick  Texture filter', 'R-stick  Terrain pass'], 0],
	['Rendering', ['Draw calls', 'Triangles'], 1],
	['Memory', ['App RAM', 'Video', 'Textures', 'Buffers'], 1],
	['State', ['Water', 'Refresh', 'Foveation'], 1],
]
const NONE := '-'

var frames := 0
var elapsed := 0.0
var longest := 0.0
var fps := 0.0
var average_ms := 0.0
var worst_ms := 0.0

func frame(delta: float) -> void:
	frames += 1
	elapsed += delta
	longest = maxf(longest, delta)

## Turns the frames counted since the last call into the rates shown.
func close_interval() -> void:
	if frames == 0 or elapsed <= 0.0: return
	fps = float(frames) / elapsed
	average_ms = elapsed / float(frames) * 1000.0
	worst_ms = longest * 1000.0
	frames = 0
	elapsed = 0.0
	longest = 0.0

## Green when the frame rate holds the headset's rate, amber when it slips, red when it is well short.
static func rate_colour(rate: float, target: float) -> Color:
	if rate >= target * 0.95: return Color('7fe3a0')
	if rate >= target * 0.8: return Color('f1c65c')
	return Color('ef6f6c')

static func megabytes(bytes: float) -> String:
	return '%.0f MB' % (bytes / 1048576.0)

## The app's resident memory in bytes, or -1 where /proc is not readable.
static func resident_bytes() -> float:
	var file := FileAccess.open('/proc/self/status', FileAccess.READ)
	if file != null:
		while not file.eof_reached():
			var line := file.get_line()
			if line.begins_with('VmRSS:'):
				return float(line.substr(6).strip_edges().split(' ')[0]) * 1024.0
	# Some systems hide the status file but allow statm: its second number is the resident pages.
	file = FileAccess.open('/proc/self/statm', FileAccess.READ)
	if file != null:
		var parts := file.get_line().split(' ')
		if parts.size() > 1: return float(parts[1]) * 4096.0
	return -1.0

static func milliseconds(value: float) -> String:
	return '%.1f ms' % value if value > 0.0 else NONE

## `game` is the main scene (for the water state); `target` the headset's refresh rate.
func values(viewport: Viewport, game: Node, target: float) -> Dictionary:
	var rid := viewport.get_viewport_rid()
	var visible_pass := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	var draws := RenderingServer.viewport_get_render_info(rid, visible_pass, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var triangles := RenderingServer.viewport_get_render_info(rid, visible_pass, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	var resident := resident_bytes()
	var water := NONE
	if game != null and game.get('depth') != null:
		var depth: float = game.get('depth')
		water = ('%.1f m under' % depth) if game.get('submerged') else ('%.1f m above' % -depth)
	var water_surface := NONE
	var seabed := NONE
	var terrain_pass := NONE
	if game != null and game.get('ocean') != null:
		water_surface = 'On' if game.get('ocean').surface.visible else 'Hidden'
		terrain_pass = 'Opaque' if game.get('terrain_opaque_test') else 'As built'
		seabed = ['Auto', 'No terrain', 'No reef', 'No seagrass', 'Hidden'][game.get('seabed_test')]
	var xr := XRServer.primary_interface
	var strength = xr.get('vrs_strength') if xr != null else null
	var rows := {
		'FPS': '%.0f  (of %.0f)' % [fps, target],
		'Frame time': '%.1f ms' % average_ms,
		'Slowest frame': '%.1f ms' % worst_ms,
		'GPU time': milliseconds(RenderingServer.viewport_get_measured_render_time_gpu(rid)),
		'CPU render': milliseconds(RenderingServer.viewport_get_measured_render_time_cpu(rid)),
		'Draw calls': str(draws),
		'Triangles': '%.0fk' % (triangles / 1000.0),
		'App RAM': megabytes(resident) if resident >= 0.0 else NONE,
		'Video': megabytes(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)),
		'Textures': megabytes(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)),
		'Buffers': megabytes(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)),
		'Water': water,
		'Refresh': '%.0f Hz' % target,
		'A  Render scale': '%.1fx' % viewport.scaling_3d_scale,
		'B  Anti-aliasing': ['Off', '2x MSAA', '4x MSAA', '8x MSAA'][viewport.msaa_3d],
		'X  Water surface': water_surface,
		'Y  Seabed': seabed,
		'L-stick  Texture filter': ['Off', '2x', '4x', '8x', '16x'][viewport.anisotropic_filtering_level],
		'R-stick  Terrain pass': terrain_pass,
		'Foveation': ('x%.1f' % float(strength)) if strength != null and viewport.vrs_mode == Viewport.VRS_XR else 'Off',
	}
	return rows
