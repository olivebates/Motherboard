extends Node2D

const SHAKE_DURATION := 0.8
const SHAKE_MAGNITUDE := 2.0

var _triggered := false
var _shake_time := 0.0
var _destroyed := false
var _wind_dir := Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("dust_piles")

func get_grid_pos() -> Vector2i:
	return GridUtils.to_grid(position)

func get_center() -> Vector2:
	return GridUtils.tile_center(position)

func _get_room() -> Vector2i:
	var gp = get_grid_pos()
	return Vector2i(floori(float(gp.x) / 25.0), floori(float(gp.y) / 12.0))

func reset() -> void:
	if SaveManager.is_room_solved(_get_room()):
		return
	_destroyed = false
	_triggered = false
	_shake_time = 0.0
	_wind_dir = Vector2.ZERO
	sprite.position = Vector2.ZERO
	sprite.visible = true

func _process(delta: float) -> void:
	if _destroyed:
		return

	if _triggered:
		_shake_time += delta
		var intensity := SHAKE_MAGNITUDE * (1.0 - _shake_time / SHAKE_DURATION)
		sprite.position = Vector2(
			sin(_shake_time * 80.0) * intensity,
			cos(_shake_time * 65.0) * intensity
		)
		if _shake_time >= SHAKE_DURATION:
			_dissolve()
		return

	for fan in get_tree().get_nodes_in_group("fans"):
		if fan.is_active() and fan.is_position_in_airflow(get_center()):
			_triggered = true
			_shake_time = 0.0
			_wind_dir = Vector2(fan.direction)
			break

func _dissolve() -> void:
	EffectUtils.spawn_burst(get_tree().current_scene, get_center(), {
		"explosiveness": 0.8, "amount": 20, "lifetime": 0.9,
		"direction": _wind_dir if _wind_dir.length_squared() > 0.0 else Vector2(1.0, 0.0),
		"spread": 22.0,
		"velocity_min": 25.0, "velocity_max": 70.0,
		"scale_min": 1.5, "scale_max": 3.5,
		"color": Color(0.82, 0.72, 0.52, 1.0),
	})

	_destroyed = true
	sprite.visible = false
