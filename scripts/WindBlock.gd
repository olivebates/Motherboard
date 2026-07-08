extends Node2D

@export var start_grid_pos: Vector2i = Vector2i(0, 0)

var grid_pos: Vector2i = Vector2i.ZERO
var _tween: Tween = null

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("push_blocks")
	add_to_group("wind_pushable")
	start_grid_pos = GridUtils.to_grid(position)
	grid_pos = start_grid_pos
	position = PushBlockUtils.grid_to_world(grid_pos)
	sprite.centered = false
	sprite.position = PushBlockUtils.SPRITE_OFFSET

func get_collision_rect() -> Rect2:
	return PushBlockUtils.collision_rect(grid_pos)

func push(direction: Vector2i) -> void:
	PushBlockUtils.push(self, direction)

func push_undo(old_pos: Vector2i) -> void:
	PushBlockUtils.push_undo(self, old_pos)

func reset() -> void:
	PushBlockUtils.reset(self)
