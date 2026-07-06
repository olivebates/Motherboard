extends Node2D

@export var color: Color = Color.WHITE
@export var music: String = ""
# When true, the room this anchor governs is rendered dark: a black overlay covers
# the room and only a light circle around the player (plus any powered LightSource)
# is visible. See DarknessOverlay.gd / Main._is_room_dark().
@export var darkness: bool = false

func _ready() -> void:
	$Sprite2D.visible = false
	add_to_group("teleport_anchors")
