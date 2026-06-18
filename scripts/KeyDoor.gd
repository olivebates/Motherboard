extends Node2D

var _keys_total := 0
var _keys_collected := 0
var _opened := false
var _opening := false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	$Sprite2D.visible = false
	add_to_group("key_doors")
	_setup_animations()
	sprite.frame = 0
	sprite.stop()
	call_deferred("_count_keys")

func _setup_animations() -> void:
	var frames = SpriteFrames.new()
	var texture = load("res://Sprites/objects/KeyDoor.webp")
	var frame_w = 32
	var frame_h = 42
	var cols = 10
	frames.add_animation("open")
	frames.set_animation_loop("open", false)
	frames.set_animation_speed("open", 10)
	for i in cols:
		var atlas = AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(i * frame_w, 0, frame_w, frame_h)
		frames.add_frame("open", atlas)
	sprite.sprite_frames = frames
	sprite.animation = "open"
	sprite.position = Vector2(0.0, -10.0)

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
	if _opened or _opening:
		return
	_opening = true
	var main = get_tree().current_scene
	main.shoot_door_ball(main.player.get_body_center(), position + Vector2(16.0, 21.0), _do_open)

func _do_open() -> void:
	if not _opening:
		return
	_opening = false
	_opened = true
	SaveManager.notify_key_door_opened(get_grid_pos())
	remove_from_group("key_doors")
	GameManager.shake_requested.emit(5.0)
	sprite.play("open")
	await sprite.animation_finished
	sprite.visible = false

func reset() -> void:
	if _opened:
		return
	_opening = false
	_keys_collected = 0
	sprite.stop()
	sprite.frame = 0
	sprite.scale = Vector2(1.0, 1.0)
	sprite.position = Vector2(0.0, -10.0)
	sprite.visible = true
	if not is_in_group("key_doors"):
		add_to_group("key_doors")
