extends Node2D

@export var color: Color = Color.WHITE

func _ready() -> void:
	add_to_group("teleport_anchors")
