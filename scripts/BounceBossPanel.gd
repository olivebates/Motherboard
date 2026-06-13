extends Node2D

@export var positive: bool = true

var _active := false

func _ready() -> void:
	if positive:
		$Sprite2D.texture = load("res://Sprites/objects/positive.png")
	else:
		$Sprite2D.texture = load("res://Sprites/objects/negative.png")
	$Sprite2D.hide()
	queue_redraw()

func _process(_delta: float) -> void:
	var my_center := position + Vector2(16.0, 16.0)
	var was_active := _active
	var main := get_tree().current_scene
	var beam = main.electric_beam if main else null
	_active = beam != null and beam.active and beam.is_point_on_beam(my_center, 16.0)
	if _active != was_active:
		queue_redraw()

func _draw() -> void:
	if $Sprite2D.texture:
		draw_texture($Sprite2D.texture, Vector2.ZERO)
	if _active:
		draw_arc(Vector2(16.0, 16.0), 17.0, 0.0, TAU, 32, Color.WHITE, 1.5)
