extends Node2D

var start_grid_pos: Vector2i
var _original_position: Vector2
var _collected := false
var _collect_tween: Tween

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("keys")
	_original_position = position
	start_grid_pos = Vector2i(int(position.x) / 32, int(position.y) / 32)
	z_index = -5

func _process(_delta: float) -> void:
	if _collected:
		return
	var player: Node2D = get_tree().get_first_node_in_group("players")
	if player == null:
		return
	var key_center := position + Vector2(16.0, 16.0)
	if key_center.distance_to(player.get_body_center()) <= 16.0:
		_collect(player)

func get_grid_pos() -> Vector2i:
	return Vector2i(int(position.x) / 32, int(position.y) / 32)

func _room_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / 800.0), floori(pos.y / 384.0))

func _collect(player: Node2D) -> void:
	_collected = true
	var my_room := _room_of(_original_position)
	for door in get_tree().get_nodes_in_group("key_doors"):
		if _room_of(door.position) == my_room:
			door.key_collected()
	var target = player.get_body_center() - Vector2(16.0, 16.0)
	if _collect_tween:
		_collect_tween.kill()
	_collect_tween = create_tween().set_parallel(true)
	_collect_tween.tween_property(self, "position", target, 0.15)
	_collect_tween.tween_method(func(s: float):
		sprite.scale = Vector2(s, s)
		sprite.position = Vector2(16.0 * (1.0 - s), 16.0 * (1.0 - s))
	, 1.0, 0.0, 0.15)
	_collect_tween.chain().tween_callback(func(): sprite.visible = false)

func reset() -> void:
	var my_room := _room_of(_original_position)
	var door_active := false
	for door in get_tree().get_nodes_in_group("key_doors"):
		if _room_of(door.position) == my_room:
			door_active = true
			break
	if not door_active:
		return
	if _collect_tween:
		_collect_tween.kill()
	_collected = false
	position = _original_position
	sprite.visible = true
	sprite.scale = Vector2.ONE
	sprite.position = Vector2.ZERO
