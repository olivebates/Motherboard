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

var _start_pos: Vector2
var _dead := false
var _main: Node2D
var _visual_pos: Vector2

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _particles: CPUParticles2D = $Particles

func _ready() -> void:
	add_to_group("enemies")
	_main = get_tree().current_scene as Node2D
	_start_pos = position
	_visual_pos = position
	_particles.one_shot = true
	_particles.explosiveness = 1.0

func get_center() -> Vector2:
	return position + Vector2(16.0, 16.0)

func _hitbox(pos: Vector2) -> Rect2:
	return Rect2(pos + _HIT_OFFSET, _HIT_SIZE)

func _process(delta: float) -> void:
	if _dead:
		return
	var player: Node2D = _main.player
	var target = player.get_body_center()
	var to_player = target - get_center()

	if to_player.length() > 1.0:
		var vel = to_player.normalized() * SPEED * delta
		_move_x(vel.x)
		_move_y(vel.y)

	_visual_pos = _visual_pos.lerp(position, minf(1.0, SPRITE_SPEED * delta))
	_sprite.position = _visual_pos - position

	# Beam kill
	if _main.electric_beam.active and _main.electric_beam.is_point_on_beam(get_center(), BEAM_RADIUS):
		_die()
		return

	# Player contact → reset room
	if not player.movement_locked and (target - get_center()).length() < CONTACT_DIST:
		_main._reset_room()

func _move_x(dx: float) -> void:
	if dx == 0.0:
		return
	var rect := _hitbox(position)
	var probe := rect.merge(_hitbox(position + Vector2(dx, 0.0)))
	var allowed := dx
	for solid in _main.get_player_blocking_rects(probe):
		if rect.position.y >= solid.end.y or solid.position.y >= rect.end.y:
			continue
		if dx > 0.0 and rect.end.x <= solid.position.x + CONTACT_EPS:
			allowed = minf(allowed, solid.position.x - rect.end.x)
		elif dx < 0.0 and rect.position.x >= solid.end.x - CONTACT_EPS:
			allowed = maxf(allowed, solid.end.x - rect.position.x)
		else:
			allowed = 0.0
	position.x += clampf(allowed, minf(dx, 0.0), maxf(dx, 0.0))

func _move_y(dy: float) -> void:
	if dy == 0.0:
		return
	var rect := _hitbox(position)
	var probe := rect.merge(_hitbox(position + Vector2(0.0, dy)))
	var allowed := dy
	for solid in _main.get_player_blocking_rects(probe):
		if rect.position.x >= solid.end.x or solid.position.x >= rect.end.x:
			continue
		if dy > 0.0 and rect.end.y <= solid.position.y + CONTACT_EPS:
			allowed = minf(allowed, solid.position.y - rect.end.y)
		elif dy < 0.0 and rect.position.y >= solid.end.y - CONTACT_EPS:
			allowed = maxf(allowed, solid.end.y - rect.position.y)
		else:
			allowed = 0.0
	position.y += clampf(allowed, minf(dy, 0.0), maxf(dy, 0.0))

func push(dir: Vector2i) -> void:
	position += Vector2(dir.x, dir.y) * TILE_SIZE

func _die() -> void:
	_dead = true
	_sprite.visible = false
	_particles.restart()

func reset() -> void:
	_dead = false
	position = _start_pos
	_visual_pos = _start_pos
	_sprite.position = Vector2.ZERO
	_sprite.visible = true
	if _particles:
		_particles.emitting = false
