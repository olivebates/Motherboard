extends Node2D

func _ready() -> void:
	add_to_group("pass_blocks")
	$Sprite2D.visible = false
	$Sprite2D.centered = false
	$Sprite2D.texture = load("res://Sprites/switch_open2.png")

func get_grid_pos() -> Vector2i:
	return Vector2i(floori(position.x / 32.0), floori(position.y / 32.0))
