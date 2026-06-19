extends Node2D

@export var id: String = ""
@export var id2: String = ""
@export var starts_open: bool = false

var is_open := false
var _opening := false
var _anim_version := 0
var _id_active: Dictionary = {}   # id -> bool; door opens when ANY of its ids is active

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	add_to_group("doors")
	_setup_animations()
	sprite.frame = 0
	sprite.stop()
	for did in _door_ids():
		GameManager.register_door(self, did)
	GameManager.doors_update.connect(_on_doors_update)
	$Sprite2D.visible = false
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
	for did in _door_ids():
		GameManager.unregister_door(self, did)

# The door's ids — id, plus id2 when set (and distinct). Any one being active opens it.
func _door_ids() -> Array:
	var ids: Array = [id]
	if id2 != "" and id2 != id:
		ids.append(id2)
	return ids

func get_grid_pos() -> Vector2i:
	return GridUtils.to_grid(position)

func _on_doors_update(door_id: String, open: bool) -> void:
	if door_id not in _door_ids():
		return
	_id_active[door_id] = open
	# Open when any of the door's ids is active (OR), matching how floor panels work.
	set_open(_any_id_active())

func _any_id_active() -> bool:
	for did in _door_ids():
		if _id_active.get(did, false):
			return true
	return false

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

func force_open(animate: bool = false) -> void:
	_opening = false
	is_open = true
	if animate:
		# Room-completion open: play the open animation to the last frame.
		GameManager.shake_requested.emit(5.0)
		sprite.animation = "open"
		sprite.frame = 0
		_play_anim("open", func(): pass)
	else:
		# Silent restore (e.g. loading a save): snap straight to the open frame.
		# stop() resets the frame to 0, so it must be called BEFORE setting frame 4.
		_anim_version += 1
		sprite.animation = "open"
		sprite.stop()
		sprite.frame = 4
