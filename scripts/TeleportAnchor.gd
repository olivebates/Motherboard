extends Node2D

@export var color: Color = Color.WHITE
@export var music: String = ""

func _ready() -> void:
	$Sprite2D.visible = false
	add_to_group("teleport_anchors")
