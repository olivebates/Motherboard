extends Node2D

@export var id: String = ""

var is_open := false
var _door_tween: Tween = null

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("doors")
	GameManager.register_door(self, id)
	GameManager.doors_update.connect(_on_doors_update)

func _exit_tree() -> void:
	GameManager.unregister_door(self, id)

func get_grid_pos() -> Vector2i:
	return Vector2i(int(position.x) / 32, int(position.y) / 32)

func _on_doors_update(door_id: String, open: bool) -> void:
	if door_id == id:
		set_open(open)

func set_open(open: bool) -> void:
	if is_open == open:
		return
	is_open = open
	if _door_tween:
		_door_tween.kill()
	if open:
		GameManager.shake_requested.emit(5.0)
		sprite.visible = true
		sprite.modulate = Color(3.0, 3.0, 3.0, 1.0)
		_door_tween = create_tween()
		_door_tween.tween_interval(0.1)
		_door_tween.tween_callback(func():
			sprite.visible = false
		)
	else:
		sprite.visible = true
