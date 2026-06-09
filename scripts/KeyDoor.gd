extends Node2D

var _keys_total := 0
var _keys_collected := 0
var _opened := false

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("key_doors")
	call_deferred("_count_keys")

func _room_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / 800.0), floori(pos.y / 384.0))

func _count_keys() -> void:
	var my_room := _room_of(position)
	for key in get_tree().get_nodes_in_group("keys"):
		if _room_of(key.position) == my_room:
			_keys_total += 1

func get_grid_pos() -> Vector2i:
	return Vector2i(int(position.x) / 32, int(position.y) / 32)

func key_collected() -> void:
	_keys_collected += 1
	if _keys_collected >= _keys_total and _keys_total > 0:
		_open()

func _open() -> void:
	_opened = true
	remove_from_group("key_doors")
	sprite.visible = false

func reset() -> void:
	if _opened:
		return
	_keys_collected = 0
	sprite.visible = true
	if not is_in_group("key_doors"):
		add_to_group("key_doors")
