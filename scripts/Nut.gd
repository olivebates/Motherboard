extends Node2D

const TILE_SIZE := 32
const SLIDE_DURATION := 0.15
const SPRITE_OFFSET := Vector2.ZERO

var grid_pos: Vector2i = Vector2i.ZERO
var start_grid_pos: Vector2i = Vector2i.ZERO
var _tween: Tween = null

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("push_blocks")
	add_to_group("nuts")
	# Snap to the tile the node was placed on in the editor
	grid_pos = Vector2i(floori(position.x / TILE_SIZE), floori(position.y / TILE_SIZE))
	start_grid_pos = grid_pos
	position = _grid_to_world(grid_pos)
	sprite.centered = false
	sprite.position = SPRITE_OFFSET

func get_collision_rect() -> Rect2:
	return Rect2(
		grid_pos.x * TILE_SIZE,
		grid_pos.y * TILE_SIZE,
		float(TILE_SIZE),
		float(TILE_SIZE)
	)

func push(direction: Vector2i) -> void:
	var old_world := _grid_to_world(grid_pos)
	grid_pos += direction
	var new_world := _grid_to_world(grid_pos)
	position = new_world
	sprite.position = old_world - new_world + SPRITE_OFFSET

	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_SINE)
	_tween.tween_property(sprite, "position", SPRITE_OFFSET, SLIDE_DURATION)
	_tween.tween_callback(func():
		var main: Node = get_tree().current_scene
		if main != null and main.has_method("_update_beam"):
			main._update_beam()
	)

func reset() -> void:
	if _tween:
		_tween.kill()
	grid_pos = start_grid_pos
	position = _grid_to_world(grid_pos)
	sprite.position = SPRITE_OFFSET
	sprite.scale = Vector2.ONE

func get_beam_point() -> Vector2:
	return global_position + sprite.position + Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)

func _grid_to_world(gp: Vector2i) -> Vector2:
	return Vector2(gp.x * TILE_SIZE, gp.y * TILE_SIZE)
