extends Node2D

const SPEED := 40.0
const SPRITE_SPEED := 20.0
const CONTACT_DIST := 14.0
const BEAM_RADIUS := 14.0
const TILE_SIZE := 32
const CONTACT_EPS := 0.1

# 20x20 hitbox centered on the 32x32 sprite
const _HIT_OFFSET := Vector2(6.0, 6.0)
const _HIT_SIZE := Vector2(20.0, 20.0)

@export var enemy_id: String = ""

var _start_pos: Vector2
var _dead := false
var _main: Node2D
var _visual_pos: Vector2

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _particles: CPUParticles2D = $Particles

func _ready() -> void:
	add_to_group("enemies")
	_main = get_tree().current_scene as Node2D
	# Shift the node origin down to the ground line so Y-sort orders enemies by
	# where they stand (their sprite bottom), not by the tile top-left. Static
	# children are compensated back up so the visuals stay put. Grid/collision
	# math below treats `position` as origin-conv via _ground_offset().
	var off := _ground_offset()
	if off != 0.0:
		position.y += off
		_particles.position.y -= off
	_start_pos = position
	_visual_pos = position
	_particles.one_shot = true
	_particles.explosiveness = 1.0

# How far the node origin sits below the tile top-left, used as the Y-sort key.
# 0 = origin at tile top-left (default for bosses, which sort by their own rules).
func _ground_offset() -> float:
	return 0.0

# Max distance (px) to the player within which the enemy walks toward them.
# INF = always chase (default). Subclasses can gate chasing on proximity.
func _chase_radius() -> float:
	return INF

func is_dead() -> bool:
	return _dead

func get_center() -> Vector2:
	return position + Vector2(16.0, 16.0 - _ground_offset())

func _hitbox(pos: Vector2) -> Rect2:
	return Rect2(pos + _HIT_OFFSET - Vector2(0.0, _ground_offset()), _HIT_SIZE)

func _process(delta: float) -> void:
	if _dead:
		return
	var player: Node2D = _main.player
	var target = player.get_body_center()
	var to_player = target - get_center()

	var dist = to_player.length()
	if dist > 1.0 and dist <= _chase_radius():
		var vel = to_player.normalized() * SPEED * delta
		_move_x(vel.x)
		_move_y(vel.y)

	_visual_pos = _visual_pos.lerp(position, minf(1.0, SPRITE_SPEED * delta))
	_sprite.position = _visual_pos - position - Vector2(0.0, _ground_offset())

	_handle_beam()
	if _dead:
		return

	# Player contact → reset room
	if not player.movement_locked and (target - get_center()).length() < CONTACT_DIST:
		_main._reset_room()

func _handle_beam() -> void:
	if _main.electric_beam.active and _main.electric_beam.is_point_on_beam(get_center(), BEAM_RADIUS):
		_die()

func _move_x(dx: float) -> void:
	if dx == 0.0:
		return
	var rect = _hitbox(position)
	var probe = rect.merge(_hitbox(position + Vector2(dx, 0.0)))
	position.x += MoveUtils.sweep_x(rect, dx, _main.get_player_blocking_rects(probe), CONTACT_EPS)

func _move_y(dy: float) -> void:
	if dy == 0.0:
		return
	var rect = _hitbox(position)
	var probe = rect.merge(_hitbox(position + Vector2(0.0, dy)))
	position.y += MoveUtils.sweep_y(rect, dy, _main.get_player_blocking_rects(probe), CONTACT_EPS)

func _eject_from_solid() -> void:
	if not MoveUtils.rect_hits_any(_hitbox(position), _main.get_player_blocking_rects(_hitbox(position))):
		return
	var off = _ground_offset()
	var origin = Vector2i(floori(position.x / TILE_SIZE), floori((position.y - off) / TILE_SIZE))
	var is_free = func(c):
		var rect = _hitbox(Vector2(c.x * TILE_SIZE, c.y * TILE_SIZE + off))
		return not MoveUtils.rect_hits_any(rect, _main.get_player_blocking_rects(rect))
	var gp = MoveUtils.find_free_cell(origin, is_free)
	if gp != null:
		position = Vector2(gp.x * TILE_SIZE, gp.y * TILE_SIZE + off)
		_visual_pos = position

func push(dir: Vector2i) -> void:
	position += Vector2(dir.x, dir.y) * TILE_SIZE

# ── Push-back interface (mirrors Player) ─────────────────────────────────────
# Used by Main's push undo/redo to shove an actor standing where a block returns.

func get_push_hitbox() -> Rect2:
	return _hitbox(position)

func push_out(displacement: Vector2) -> void:
	position += displacement
	# Leave _visual_pos where it was so the sprite lags behind and eases over,
	# instead of teleporting with the body.

func _die() -> void:
	_dead = true
	_sprite.visible = false
	_particles.restart()

func reset() -> void:
	_dead = false
	position = _start_pos
	_visual_pos = _start_pos
	_sprite.position = Vector2(0.0, -_ground_offset())
	_sprite.visible = true
	if _particles:
		_particles.emitting = false
