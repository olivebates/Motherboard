extends Node2D

const INNER_RADIUS = 8.0
const OUTER_BASE = 11.0
const OUTER_PULSE_AMP = 1.0
const OUTLINE_WIDTH = 1.5

var _time = 0.0

func _ready() -> void:
	add_to_group("orb_displays")
	PowerOrbCounter.count_changed.connect(_on_count_changed)
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var center = Vector2(16.0, 16.0)
	var filled = _is_filled()

	if filled:
		draw_circle(center, INNER_RADIUS, Color.WHITE)
		var outer_r = OUTER_BASE + sin(_time * TAU) * OUTER_PULSE_AMP
		draw_arc(center, outer_r, 0.0, TAU, 32, Color.WHITE, OUTLINE_WIDTH)
	else:
		draw_arc(center, INNER_RADIUS, 0.0, TAU, 32, Color.WHITE, OUTLINE_WIDTH)

func _is_filled() -> bool:
	return _get_rank() < PowerOrbCounter.count

func _get_rank() -> int:
	var displays = get_tree().get_nodes_in_group("orb_displays")
	displays.sort_custom(func(a, b):
		if a.position.y != b.position.y:
			return a.position.y < b.position.y
		return a.position.x < b.position.x
	)
	for i in displays.size():
		if displays[i] == self:
			return i
	return 0

func _on_count_changed(_new_count: int) -> void:
	queue_redraw()
