@tool
class_name AbyssOceanSettings
extends Resource

@export_range(0.1, 8.0) var significant_wave_height := 1.8
@export_range(2.0, 20.0) var peak_period := 7.5
@export_range(0.1, 4.0) var wind_wave_height := 1.1
@export_range(1.5, 6.0) var wind_wave_period := 3.2
@export_range(-180.0, 180.0) var wind_direction := -28.0
@export_range(0.0, 1.0) var directional_spread := 0.48
@export_range(0.0, 0.85) var steepness := 0.72
@export var spectrum_seed := 4127
@export var absorption := Vector3(0.28, 0.065, 0.028)
@export_color_no_alpha var deep_color := Color(0.008, 0.14, 0.20)
@export_color_no_alpha var shallow_color := Color(0.025, 0.48, 0.42)
@export_color_no_alpha var foam_color := Color(0.92, 0.98, 0.96)
