extends Node2D

@export var required_ability: String = "push"

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	sprite.visible = GameManager.has_ability(required_ability)

func _process(_delta: float) -> void:
	var should_show := GameManager.has_ability(required_ability)
	if sprite.visible != should_show:
		sprite.visible = should_show
