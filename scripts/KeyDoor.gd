extends Node2D

const ANIM_DURATION := 0.15

var _keys_total := 0
var _keys_collected := 0
var _opened := false
var _tween: Tween = null

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("key_doors")
	call_deferred("_count_keys")

func _room_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / 800.0), floori(pos.y / 384.0))

func _count_keys() -> void:
	if get_tree() == null:
		call_deferred("_count_keys")
		return
	var my_room := _room_of(global_position)
	for key in get_tree().get_nodes_in_group("keys"):
		if _room_of(key.position) == my_room:
			_keys_total += 1
	if _keys_total == 0:
		_open()

func get_grid_pos() -> Vector2i:
	return Vector2i(int(position.x) / 32, int(position.y) / 32)

func key_collected() -> void:
	_keys_collected += 1
	if _keys_collected >= _keys_total:
		_open()

func _open() -> void:
	_opened = true
	SaveManager.notify_key_door_opened(get_grid_pos())
	remove_from_group("key_doors")
	GameManager.shake_requested.emit(5.0)
	sprite.visible = true
	sprite.modulate = Color.WHITE
	_apply_shrink_scale(1.0)
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_apply_shrink_scale, 1.0, 0.0, ANIM_DURATION)
	_tween.tween_callback(func() -> void:
		sprite.visible = false
		_apply_shrink_scale(1.0)
	)

func _apply_shrink_scale(s: float) -> void:
	var half := sprite.texture.get_size() * 0.5 if sprite.texture else Vector2(16.0, 16.0)
	sprite.scale = Vector2(s, s)
	sprite.position = half * (1.0 - s)

func reset() -> void:
	if _opened:
		return
	_keys_collected = 0
	if _tween:
		_tween.kill()
	sprite.visible = true
	sprite.modulate = Color.WHITE
	_apply_shrink_scale(1.0)
	if not is_in_group("key_doors"):
		add_to_group("key_doors")
