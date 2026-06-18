extends Node2D

@export var id: String = ""
@export var starts_open: bool = false

var is_open := false
var _opening := false
var _anim_version := 0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	add_to_group("doors")
	_setup_animations()
	sprite.frame = 0
	sprite.stop()
	GameManager.register_door(self, id)
	GameManager.doors_update.connect(_on_doors_update)
	if starts_open:
		is_open = true
		sprite.frame = 4

func _setup_animations() -> void:
	var frames = SpriteFrames.new()
	var texture = load("res://Sprites/objects/door.webp")
	var frame_w = 32
	var frame_h = 32
	var cols = 5
	frames.add_animation("open")
	frames.set_animation_loop("open", false)
	frames.set_animation_speed("open", 10)
	for i in cols:
		var atlas = AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(i * frame_w, 0, frame_w, frame_h)
		frames.add_frame("open", atlas)
	frames.add_animation("close")
	frames.set_animation_loop("close", false)
	frames.set_animation_speed("close", 10)
	for i in range(cols - 1, -1, -1):
		var atlas = AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(i * frame_w, 0, frame_w, frame_h)
		frames.add_frame("close", atlas)
	sprite.sprite_frames = frames
	sprite.animation = "open"

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
	if starts_open:
		_set_open_inverted(open)
		return
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
		_play_anim("close", func():
			sprite.animation = "open"
			sprite.frame = 0
			sprite.stop()
		)

func _set_open_inverted(puzzle_active: bool) -> void:
	if puzzle_active and SaveManager.is_room_solved(_get_room()):
		return
	if puzzle_active:
		_opening = false
		if not is_open:
			return
		is_open = false
		_play_anim("close", func():
			sprite.animation = "open"
			sprite.frame = 0
			sprite.stop()
		)
	else:
		if is_open or _opening:
			return
		_opening = true
		var main = get_tree().current_scene
		var from = GameManager.last_activator_pos
		if from == Vector2.ZERO:
			from = main.player.get_body_center()
		main.shoot_door_ball(from, position + Vector2(16.0, 16.0), _do_open)

func _play_anim(anim: String, on_finish: Callable) -> void:
	_anim_version += 1
	var v = _anim_version
	sprite.play(anim)
	sprite.animation_finished.connect(func():
		if _anim_version == v:
			on_finish.call()
	, CONNECT_ONE_SHOT)

func _do_open() -> void:
	if not _opening:
		return
	_opening = false
	is_open = true
	GameManager.shake_requested.emit(5.0)
	_play_anim("open", func(): pass)

func force_open() -> void:
	_opening = false
	_anim_version += 1
	is_open = true
	sprite.animation = "open"
	sprite.frame = 4
	sprite.stop()
