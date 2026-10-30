class_name AbyssAmbience
extends Node3D
## Ambient sound: waves and wind above water, a deep rumble below, and a motor hum on each
## running thruster. Everything above water is muffled by a low-pass filter when you dive, and
## the mix crossfades over about half a second.

const WAVES := preload('res://world/audio/ocean_loop.wav')
const WIND := preload('res://world/audio/wind_loop.wav')
const UNDERWATER := preload('res://world/audio/underwater_loop.wav')
# "Underwater Ambient Pad" by isaiah658 (CC0, opengameart.org): quiet background music below the surface.
const PAD := preload('res://world/audio/underwater_pad.ogg')
const THRUSTER := preload('res://world/audio/thruster_loop.wav')

const AMBIENCE_BUS := &'Ambience'
const THRUSTER_BUS := &'Thrusters'
const MUSIC_BUS := &'Music'
const CLEAR_CUTOFF := 18000.0
const MUFFLED_CUTOFF := 650.0

var waves: AudioStreamPlayer
var wind: AudioStreamPlayer
var rumble: AudioStreamPlayer
var music: AudioStreamPlayer
var thrusters: Array[AudioStreamPlayer3D] = []
var ambience_filter: AudioEffectLowPassFilter
var thruster_filter: AudioEffectLowPassFilter
## 0 above water, 1 underwater; moves smoothly so diving crossfades the mix.
var blend := 0.0

func _ready() -> void:
	ambience_filter = make_bus(AMBIENCE_BUS)
	thruster_filter = make_bus(THRUSTER_BUS)
	waves = make_player(WAVES, AMBIENCE_BUS)
	wind = make_player(WIND, AMBIENCE_BUS)
	rumble = make_player(UNDERWATER, AMBIENCE_BUS)
	# The pad gets its own unfiltered bus so diving does not muffle it.
	if AudioServer.get_bus_index(MUSIC_BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, MUSIC_BUS)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, &'Master')
	music = make_player(PAD, MUSIC_BUS)

func make_bus(bus_name: StringName) -> AudioEffectLowPassFilter:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, &'Master')
	var filter := AudioEffectLowPassFilter.new()
	filter.cutoff_hz = CLEAR_CUTOFF
	AudioServer.add_bus_effect(index, filter)
	return filter

func make_player(stream: AudioStream, bus_name: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = bus_name
	player.volume_db = -80.0
	add_child(player)
	player.play()
	return player

func update(delta: float, submerged: bool, depth: float, motors: Array[Node3D], throttles: Array) -> void:
	blend = move_toward(blend, 1.0 if submerged else 0.0, delta * 2.0)
	var above := 1.0 - blend
	# Waves stay faintly audible near the surface and fade with depth; the wind stops underwater.
	var wave_level := lerpf(-9.0, -16.0, blend) - maxf(depth, 0.0) * 0.9
	waves.volume_db = maxf(wave_level, -80.0)
	wind.volume_db = lerpf(-80.0, -13.0, above * above)
	rumble.volume_db = lerpf(-80.0, -22.0, blend * blend)
	music.volume_db = lerpf(-80.0, -26.0, blend * blend)
	# Muffle in log-frequency so the sweep sounds even.
	ambience_filter.cutoff_hz = exp(lerpf(log(CLEAR_CUTOFF), log(MUFFLED_CUTOFF), blend))
	thruster_filter.cutoff_hz = exp(lerpf(log(CLEAR_CUTOFF), log(2600.0), blend))
	update_thrusters(motors, throttles)

func update_thrusters(motors: Array[Node3D], throttles: Array) -> void:
	while thrusters.size() < motors.size():
		var player := AudioStreamPlayer3D.new()
		player.stream = THRUSTER
		player.bus = THRUSTER_BUS
		player.unit_size = 4.0
		player.max_distance = 30.0
		player.volume_db = -80.0
		add_child(player)
		thrusters.append(player)
	for i in range(motors.size()):
		var throttle: float = throttles[i] if i < throttles.size() else 0.0
		var player := thrusters[i]
		player.global_position = motors[i].global_position
		if throttle > 0.03:
			if not player.playing: player.play()
			player.pitch_scale = 0.75 + throttle * 0.95
			player.volume_db = lerpf(-30.0, -7.0, throttle)
		elif player.playing and player.volume_db > -60.0:
			player.volume_db = move_toward(player.volume_db, -80.0, 90.0 * get_process_delta_time())
			if player.volume_db <= -60.0: player.stop()
