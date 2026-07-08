extends Node2D

var grid_pos: Vector2i = Vector2i.ZERO
var start_grid_pos: Vector2i = Vector2i.ZERO
var _tween: Tween = null

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("push_blocks")
	add_to_group("nuts")
	# Snap to the tile the node was placed on in the editor
	grid_pos = GridUtils.to_grid(position)
	start_grid_pos = grid_pos
	position = PushBlockUtils.grid_to_world(grid_pos)
	sprite.centered = false
	sprite.position = PushBlockUtils.SPRITE_OFFSET

func get_collision_rect() -> Rect2:
	return PushBlockUtils.collision_rect(grid_pos)

func push(direction: Vector2i) -> void:
	# Re-route the beam once the slide settles (a Nut is a conductor).
	PushBlockUtils.push(self, direction).tween_callback(_queue_beam_update)

func push_undo(old_pos: Vector2i) -> void:
	PushBlockUtils.push_undo(self, old_pos).tween_callback(_queue_beam_update)

func reset() -> void:
	PushBlockUtils.reset(self)

func get_beam_point() -> Vector2:
	return GridUtils.tile_center(global_position + sprite.position)

func _queue_beam_update() -> void:
	var main: Node = get_tree().current_scene
	if main != null and main.has_method("_update_beam"):
		main._update_beam()
