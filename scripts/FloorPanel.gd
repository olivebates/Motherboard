extends Node2D

@export var id: String = ""
@export var id2: String = ""
@export var positive: bool = true

var _active := false

func _ready() -> void:
	var gp := Vector2i(floori(position.x / 32.0), floori(position.y / 32.0))
	GameManager.register_floor_panel(gp, id, id2)
	if positive:
		$Sprite2D.texture = load("res://Sprites/positive.png")
	else:
		$Sprite2D.texture = load("res://Sprites/negative.png")
	$Sprite2D.hide()
	queue_redraw()

func _process(_delta: float) -> void:
	var my_center := position + Vector2(16.0, 16.0)
	var now_active := false
	for prong_pos in GameManager.get_prong_world_positions():
		if prong_pos.distance_to(my_center) <= GameManager.PANEL_ACTIVATION_RADIUS:
			now_active = true
			break
	if now_active != _active:
		_active = now_active
		queue_redraw()

func _draw() -> void:
	draw_texture($Sprite2D.texture, Vector2.ZERO)
	if _active:
		draw_arc(Vector2(16.0, 16.0), 17.0, 0.0, TAU, 32, Color.WHITE, 1.5)
