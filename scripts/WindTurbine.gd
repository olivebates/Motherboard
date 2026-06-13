extends Node2D

@export var id: String = ""

var _powered := false

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("wind_turbines")

func get_grid_pos() -> Vector2i:
	return Vector2i(floori(position.x / 32.0), floori(position.y / 32.0))

func get_center() -> Vector2:
	return position + Vector2(16.0, 16.0)

func reset() -> void:
	if _powered:
		_powered = false
		GameManager.set_wind_power(id, false)
	queue_redraw()

func _process(_delta: float) -> void:
	var was_powered = _powered
	_powered = false
	for fan in get_tree().get_nodes_in_group("fans"):
		if fan.is_active() and fan.is_position_in_airflow(get_center()):
			_powered = true
			break
	if _powered != was_powered:
		GameManager.set_wind_power(id, _powered)
		queue_redraw()

func _draw() -> void:
	if _powered:
		draw_arc(Vector2(16.0, 16.0), 15.0, 0.0, TAU, 20, Color(1.0, 1.0, 0.6, 0.85), 2.0)
