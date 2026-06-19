extends Node2D

const TILE_SIZE := 32

var grid_pos: Vector2i = Vector2i.ZERO
var start_grid_pos: Vector2i = Vector2i.ZERO

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("nuts")
	add_to_group("screws")
	grid_pos = GridUtils.to_grid(position)
	start_grid_pos = grid_pos
	position = _grid_to_world(grid_pos)
	sprite.centered = false
	sprite.position = Vector2.ZERO

func get_grid_pos() -> Vector2i:
	return grid_pos

func get_collision_rect() -> Rect2:
	return Rect2(
		grid_pos.x * TILE_SIZE,
		grid_pos.y * TILE_SIZE,
		float(TILE_SIZE),
		float(TILE_SIZE)
	)

func get_beam_point() -> Vector2:
	return GridUtils.tile_center(global_position + sprite.position)

func reset() -> void:
	grid_pos = start_grid_pos
	position = _grid_to_world(grid_pos)
	sprite.position = Vector2.ZERO
	sprite.scale = Vector2.ONE

func _grid_to_world(gp: Vector2i) -> Vector2:
	return Vector2(gp.x * TILE_SIZE, gp.y * TILE_SIZE)
