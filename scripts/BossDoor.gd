extends Node2D

const TILE_SIZE = 32

var _opened := false
var grid_pos: Vector2i:
	get: return Vector2i(floori(position.x / TILE_SIZE), floori(position.y / TILE_SIZE))
var start_grid_pos: Vector2i:
	get: return Vector2i(floori(position.x / TILE_SIZE), floori(position.y / TILE_SIZE))

@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("push_blocks")
	add_to_group("boss_doors")

func get_collision_rect() -> Rect2:
	return Rect2(position.x, position.y, float(TILE_SIZE), float(TILE_SIZE))

func open() -> void:
	_opened = true
	queue_free()

func reset() -> void:
	if _opened:
		queue_free()
