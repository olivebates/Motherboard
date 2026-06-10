extends "res://scripts/Enemy.gd"

var boss_spawned := false

const _ROOM_PX_W = 25 * 32
const _ROOM_PX_H = 12 * 32

func _ready() -> void:
	super._ready()
	add_to_group("water_enemies")
	if boss_spawned:
		add_to_group("boss_spawned_enemies")

func _get_home_room() -> Vector2i:
	return Vector2i(floori(_start_pos.x / _ROOM_PX_W), floori(_start_pos.y / _ROOM_PX_H))

func _in_current_room() -> bool:
	return _get_home_room() == _main.current_room

func _process(delta: float) -> void:
	if not _in_current_room():
		return
	super._process(delta)
