extends Node2D

const TILE_SIZE := 32
const OPEN_HOLD_TIME := 0.1

@export var panel_name: String = ""
@export var one_way: bool = false

var is_open := false
var _contact_time := 0.0
var _tex_closed: Texture2D
var _tex_open: Texture2D

func _ready() -> void:
	$Sprite2D.visible = false
	add_to_group("teleport_panels")
	_tex_closed = load("res://Sprites/teleport_closed.png")
	_tex_open = load("res://Sprites/teleport_open.png")
	queue_redraw()

func get_grid_pos() -> Vector2i:
	return Vector2i(floori(position.x / TILE_SIZE), floori(position.y / TILE_SIZE))

func get_collision_rect() -> Rect2:
	return Rect2(position, Vector2(float(TILE_SIZE), float(TILE_SIZE)))

func _process(delta: float) -> void:
	if is_open:
		return
	var main := get_tree().current_scene
	if main == null:
		return
	var player = main.player
	if player.movement_locked:
		_contact_time = 0.0
		return
	var player_hitbox: Rect2 = player._hitbox_rect(player.position)
	var panel_near: Rect2 = get_collision_rect().grow(2.0)
	var input := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if panel_near.intersects(player_hitbox) and input.length_squared() > 0.0:
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
	if not is_open:
		return false
	return get_collision_rect().intersects(player._hitbox_rect(player.position))

func reset() -> void:
	is_open = false
	_contact_time = 0.0
	queue_redraw()
