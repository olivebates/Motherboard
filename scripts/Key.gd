extends Node2D

var start_grid_pos: Vector2i
var _original_position: Vector2
var _collected := false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	add_to_group("keys")
	_original_position = position
	start_grid_pos = Vector2i(int(position.x) / 32, int(position.y) / 32)
	z_index = -5
	$Sprite2D.visible = false
	_setup_animations()

func _setup_animations() -> void:
	var frames = SpriteFrames.new()
	frames.remove_animation("default")
	_add_sheet(frames, "idle",   "res://Sprites/objects/Key_File.webp", 7, 2, 14, 10.0, true)
	_add_sheet(frames, "vanish", "res://Sprites/objects/Vanish.webp",   6, 1,  6, 12.0, false)
	sprite.sprite_frames = frames
	sprite.play("idle")

func _add_sheet(frames: SpriteFrames, anim: String, path: String, cols: int, rows: int, count: int, fps: float, loop: bool) -> void:
	var tex: Texture2D = load(path)
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, loop)
	var f = 0
	for row in range(rows):
		for col in range(cols):
			if f >= count:
				break
			var atlas = AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(col * 32, row * 32, 32, 32)
			frames.add_frame(anim, atlas)
			f += 1

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
	sprite.play("vanish")
	await sprite.animation_finished
	sprite.visible = false

func reset() -> void:
	var my_room := _room_of(_original_position)
	var door_active := false
	for door in get_tree().get_nodes_in_group("key_doors"):
		if _room_of(door.position) == my_room:
			door_active = true
			break
	if not door_active:
		return
	_collected = false
	position = _original_position
	sprite.visible = true
	sprite.scale = Vector2.ONE
	sprite.position = Vector2.ZERO
	sprite.play("idle")
