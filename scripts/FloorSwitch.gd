extends Node2D

@export var id: String = ""

var _active = false

func _ready() -> void:
	add_to_group("floor_switches")

func get_grid_pos() -> Vector2i:
	return Vector2i(floori(position.x / 32.0), floori(position.y / 32.0))

func reset() -> void:
	if _active:
		_active = false
		if id != "":
			GameManager.set_floor_switch(id, false)
		queue_redraw()

func _process(_delta: float) -> void:
	if id == "":
		return
	var was_active = _active
	_active = false

	var switch_rect = Rect2(position, Vector2(32.0, 32.0))
	for p in get_tree().get_nodes_in_group("players"):
		if switch_rect.has_point(p.get_body_center()):
			_active = true
			break

	if not _active:
		var gp = get_grid_pos()
		for block in get_tree().get_nodes_in_group("push_blocks"):
			if block.grid_pos == gp:
				_active = true
				break

	if _active != was_active:
		GameManager.last_activator_pos = position + Vector2(16.0, 16.0)
		GameManager.set_floor_switch(id, _active)
		queue_redraw()

func _draw() -> void:
	if _active:
		draw_rect(Rect2(2.0, 2.0, 28.0, 28.0), Color(1.0, 1.0, 1.0, 0.6), false, 2.0)
