extends Node2D

@export var id: String = ""

var _active = false

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("floor_switches")
	_update_frame()

func get_grid_pos() -> Vector2i:
	return Vector2i(floori(position.x / 32.0), floori(position.y / 32.0))

func reset() -> void:
	if _active:
		_active = false
		if id != "":
			GameManager.set_floor_switch(id, false)
		_update_frame()

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

	if not _active:
		for droid in get_tree().get_nodes_in_group("nanodroids"):
			if not droid._destroyed and switch_rect.has_point(droid.get_center()):
				_active = true
				break

	if _active != was_active:
		GameManager.last_activator_pos = position + Vector2(16.0, 16.0)
		GameManager.set_floor_switch(id, _active)
		_update_frame()

func _update_frame() -> void:
	# Frame 0 = unpressed, frame 1 = pressed down.
	if sprite != null:
		sprite.frame = 1 if _active else 0
