extends Node2D

# Editor-only object. Looks and behaves like a TeleportPanel (closed = solid,
# player pushes against it to open; open = passable floor), but instead of being
# a teleport destination it ends the playtest when the player stands on it and
# presses Space (handled by LevelEditor._input).

const TILE_SIZE := 32
const OPEN_HOLD_TIME := 0.1

var is_open := false
var _contact_time := 0.0
var _tex_closed: Texture2D
var _tex_open: Texture2D

func _ready() -> void:
	$Sprite2D.visible = false
	add_to_group("exit_points")
	_tex_closed = load("res://Sprites/objects/teleport_closed.png")
	_tex_open = load("res://Sprites/objects/teleport_open.png")
	queue_redraw()

func get_grid_pos() -> Vector2i:
	return GridUtils.to_grid(position)

func get_collision_rect() -> Rect2:
	return Rect2(position, Vector2(float(TILE_SIZE), float(TILE_SIZE)))

func _process(delta: float) -> void:
	if is_open:
		return
	var main := get_tree().current_scene
	if main == null:
		return
	var player = main.player
	# Only active during the editor playtest (real Player); skip the stub player
	if player == null or not player.has_method("get_push_hitbox"):
		return
	if player.movement_locked:
		_contact_time = 0.0
		return
	if PlayerUtils.is_pressing_into(get_collision_rect(), player, 2.0):
		_contact_time += delta
		if _contact_time >= OPEN_HOLD_TIME:
			_open()
	else:
		_contact_time = 0.0

func _open() -> void:
	is_open = true
	GameManager.shake_requested.emit(8.0)
	queue_redraw()

func _draw() -> void:
	var tex := _tex_open if is_open else _tex_closed
	if tex:
		draw_texture(tex, Vector2.ZERO)

func is_player_standing_on(player: Node2D) -> bool:
	return is_open and PlayerUtils.standing_on(get_collision_rect(), player)

func reset() -> void:
	is_open = false
	_contact_time = 0.0
	queue_redraw()
