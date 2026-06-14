extends Node2D

@export var id: String = ""

const ANIM_DURATION = 0.15

var is_open = false
var _opening = false
var _door_tween: Tween = null

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("enemy_doors")

func get_grid_pos() -> Vector2i:
	return Vector2i(int(position.x) / 32, int(position.y) / 32)

func _process(_delta: float) -> void:
	if is_open or _opening or id == "":
		return
	if _all_matching_enemies_dead():
		_open()

func _all_matching_enemies_dead() -> bool:
	var found = false
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.enemy_id == id:
			found = true
			if e.is_dead() == false:
				return false
	return found

func _open() -> void:
	if is_open or _opening:
		return
	_opening = true
	var main = get_tree().current_scene
	main.shoot_door_ball(main.player.get_body_center(), position + Vector2(16.0, 16.0), _do_open)

func _do_open() -> void:
	if not _opening:
		return
	_opening = false
	is_open = true
	if _door_tween:
		_door_tween.kill()
	GameManager.shake_requested.emit(5.0)
	sprite.visible = true
	sprite.modulate = Color.WHITE
	_apply_shrink_scale(1.0)
	_door_tween = create_tween()
	_door_tween.tween_method(_apply_shrink_scale, 1.0, 0.0, ANIM_DURATION)
	_door_tween.tween_callback(_on_open_finished)

func _on_open_finished() -> void:
	sprite.visible = false
	sprite.modulate = Color.WHITE
	_apply_shrink_scale(1.0)

func reset() -> void:
	_opening = false
	is_open = false
	if _door_tween:
		_door_tween.kill()
	sprite.modulate = Color.WHITE
	sprite.visible = true
	_apply_shrink_scale(1.0)

func _apply_shrink_scale(s: float) -> void:
	var half = _sprite_half_size()
	sprite.scale = Vector2(s, s)
	sprite.position = half * (1.0 - s)

func _sprite_half_size() -> Vector2:
	if sprite.texture:
		return sprite.texture.get_size() * 0.5
	return Vector2(16.0, 16.0)
