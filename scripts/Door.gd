extends Node2D

@export var id: String = ""

const ANIM_DURATION := 0.15

var is_open := false
var _opening := false
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

func _get_room() -> Vector2i:
	var gp = get_grid_pos()
	return Vector2i(floori(float(gp.x) / 25.0), floori(float(gp.y) / 12.0))

func set_open(open: bool) -> void:
	if not open and SaveManager.is_room_solved(_get_room()):
		return
	if open:
		if is_open or _opening:
			return
		_opening = true
		var main = get_tree().current_scene
		main.shoot_door_ball(main.player.get_body_center(), position + Vector2(16.0, 16.0), _do_open)
	else:
		_opening = false
		if not is_open:
			return
		is_open = false
		if _door_tween:
			_door_tween.kill()
		sprite.modulate = Color.WHITE
		sprite.visible = true
		_apply_shrink_scale(0.0)
		_door_tween = create_tween()
		_door_tween.tween_method(_apply_shrink_scale, 0.0, 1.0, ANIM_DURATION)

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

func _apply_shrink_scale(s: float) -> void:
	var half := _sprite_half_size()
	sprite.scale = Vector2(s, s)
	sprite.position = half * (1.0 - s)

func _sprite_half_size() -> Vector2:
	if sprite.texture:
		return sprite.texture.get_size() * 0.5
	return Vector2(16.0, 16.0)
