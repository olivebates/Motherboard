extends Node2D

const TILE_SIZE := 32
const APPEAR_TIME := 120.0
const BLINK_INTERVAL := 0.5

var _main: Node2D
var _timer := 0.0
var _showing := false
var _was_in_room := false
var _blink_timer := 0.0
var _blink_on := true

@onready var _sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	_main = get_tree().current_scene as Node2D
	_sprite.visible = false

func _get_home_room() -> Vector2i:
	return Vector2i(
		floori(position.x / (TILE_SIZE * 25)),
		floori(position.y / (TILE_SIZE * 12))
	)

func _in_current_room() -> bool:
	return _get_home_room() == _main.current_room

func _process(delta: float) -> void:
	var in_room = _in_current_room()

	if _was_in_room and not in_room:
		_hide()

	if in_room and not _was_in_room:
		_timer = 0.0
		_hide()

	_was_in_room = in_room

	if not in_room:
		return

	if GameManager.has_ability("chain"):
		if _showing:
			_hide()
		return

	_timer += delta

	if _timer >= APPEAR_TIME and not _showing:
		_showing = true
		_blink_on = true
		_blink_timer = 0.0
		_sprite.visible = true
		_main.player.speed_multiplier = 0.8

	if _showing:
		_blink_timer += delta
		if _blink_timer >= BLINK_INTERVAL:
			_blink_timer -= BLINK_INTERVAL
			_blink_on = not _blink_on
			_sprite.visible = _blink_on

func _hide() -> void:
	_showing = false
	_blink_timer = 0.0
	_blink_on = true
	_sprite.visible = false
	if is_instance_valid(_main) and is_instance_valid(_main.player):
		_main.player.speed_multiplier = 1.0
