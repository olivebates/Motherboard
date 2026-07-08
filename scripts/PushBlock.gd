extends Node2D

const TILE_SIZE := 32
const HIGHLIGHT_COLOR := Color.WHITE
const HIGHLIGHT_LINE_WIDTH := 1.5
# Border oscillates ±1 px around this base offset from the block edge
const HIGHLIGHT_BASE_OFFSET := 3.0

@export var start_grid_pos: Vector2i = Vector2i(0, 0)

var grid_pos: Vector2i = Vector2i.ZERO
var _tween: Tween = null
var _highlighted := false
var _highlight_time := 0.0

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("push_blocks")
	start_grid_pos = GridUtils.to_grid(position)
	grid_pos = start_grid_pos
	position = PushBlockUtils.grid_to_world(grid_pos)
	sprite.centered = false
	sprite.position = PushBlockUtils.SPRITE_OFFSET

func _process(delta: float) -> void:
	if _highlighted:
		_highlight_time += delta
		queue_redraw()

func _draw() -> void:
	if not _highlighted:
		return
	# Oscillate offset by 1px each second using a triangle wave
	var offset := HIGHLIGHT_BASE_OFFSET + sin(_highlight_time * PI) * 1.0
	var rect := Rect2(-offset, -offset, float(TILE_SIZE) + offset * 2.0, float(TILE_SIZE) + offset * 2.0)
	draw_rect(rect, HIGHLIGHT_COLOR, false, HIGHLIGHT_LINE_WIDTH)

func set_highlight(val: bool) -> void:
	_highlighted = val
	if not val:
		_highlight_time = 0.0
	queue_redraw()

func get_collision_rect() -> Rect2:
	return PushBlockUtils.collision_rect(grid_pos)

func push(direction: Vector2i) -> void:
	if _highlighted:
		_clear_all_highlights()
	PushBlockUtils.push(self, direction)

func _clear_all_highlights() -> void:
	for b in get_tree().get_nodes_in_group("push_blocks"):
		if b.has_method("set_highlight"):
			b.set_highlight(false)

func push_undo(old_pos: Vector2i) -> void:
	PushBlockUtils.push_undo(self, old_pos)

func reset() -> void:
	PushBlockUtils.reset(self)
	set_highlight(false)
