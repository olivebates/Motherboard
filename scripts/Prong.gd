extends Node2D

var grid_pos: Vector2i:
	get:
		return Vector2i(floori(position.x / 32.0), floori(position.y / 32.0))

func setup(pixel_pos: Vector2) -> void:
	position = pixel_pos
	$Sprite2D.centered = false
	$Sprite2D.position = Vector2(-16.0, -16.0)
	$Sprite2D.scale = Vector2.ZERO
	var tween := create_tween()
	tween.tween_property($Sprite2D, "scale", Vector2(1.3, 1.3), 0.08)
	tween.tween_property($Sprite2D, "scale", Vector2.ONE, 0.07)
