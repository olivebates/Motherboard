extends "res://scripts/WaterEnemy.gd"

const SPIDER_MAX_HP = 10
const ROTATE_RADIUS = 96.0
const LUNGE_RADIUS = 64.0
const LUNGE_TRAVEL = 96.0
const LUNGE_DECAY = 2.5
const LUNGE_DURATION = 0.5
const RETRACT_DURATION = 2.0
const ANGLE_STIFFNESS = 120.0
const ANGLE_DAMPING = 22.0
const AIM_TOLERANCE = 0.3
const PRE_LUNGE_TIME = 0.2
const STUN_TIME = 8.0
const COOLDOWN_TIME = 0.4
const PRE_WAKE_TIME = 0.8
const STUN_TEX = preload("res://Sprites/objects/switch_open2.png")

enum State { IDLE, ROTATING, PRE_LUNGE, LUNGING, RETRACTING, COOLDOWN, STUNNED }

var _state = State.IDLE
var _angle = PI / 2
var _angle_velocity = 0.0
var _lunge_dir = Vector2.RIGHT
var _dist_traveled = 0.0
var _lunge_time = 0.0
var _lunge_initial_speed = 0.0
var _retract_start_pos = Vector2.ZERO
var _retract_time = 0.0
var _pre_lunge_timer = 0.0
var _stun_timer = 0.0
var _cooldown_timer = 0.0
var _shake_mag = 0.0
var _shake_timer = 0.0
var _shake_dur = 0.001
var _normal_tex: Texture2D = null

@onready var _hitbox_col: CollisionShape2D = $HitboxArea/HitboxShape

func _ready() -> void:
	super._ready()
	hp = SPIDER_MAX_HP
	_normal_tex = _sprite.texture
	_sprite.centered = true
	_sprite.position = Vector2(16.0, 16.0 - _ground_offset())
	_sprite.rotation = _angle
	# Keep the hitbox node at the tile center despite the origin shift.
	$HitboxArea.position.y -= _ground_offset()
	_lunge_initial_speed = LUNGE_TRAVEL * LUNGE_DECAY / (1.0 - exp(-LUNGE_DECAY * LUNGE_DURATION))

func _hitbox(pos: Vector2) -> Rect2:
	var half: Vector2
	if _hitbox_col.shape is CircleShape2D:
		var r = (_hitbox_col.shape as CircleShape2D).radius
		half = Vector2(r, r)
	else:
		half = (_hitbox_col.shape as RectangleShape2D).size / 2.0
	var anchor: Vector2 = _hitbox_col.get_parent().position + _hitbox_col.position
	return Rect2(pos + anchor - half, half * 2.0)

func get_max_hp() -> int:
	return SPIDER_MAX_HP

func _handle_beam() -> void:
	if _state == State.STUNNED:
		return
	super._handle_beam()

func _die() -> void:
	_enter_stun()

func _enter_stun() -> void:
	_state = State.STUNNED
	_stun_timer = STUN_TIME
	_angle_velocity = 0.0
	_sprite.texture = STUN_TEX

func _wake_from_stun() -> void:
	_sprite.texture = _normal_tex
	hp = SPIDER_MAX_HP
	_angle = PI / 2
	_angle_velocity = 0.0
	_sprite.rotation = _angle
	if position.distance_to(_start_pos) > 2.0:
		_retract_start_pos = position
		_retract_time = 0.0
		_state = State.RETRACTING
	else:
		_state = State.COOLDOWN
		_cooldown_timer = COOLDOWN_TIME

func _start_shake(mag: float, dur: float) -> void:
	_shake_mag = mag
	_shake_timer = dur
	_shake_dur = maxf(dur, 0.001)

func _get_shake_offset() -> Vector2:
	if _shake_timer <= 0.0:
		return Vector2.ZERO
	var t = _shake_timer / _shake_dur
	return Vector2(sin(_shake_timer * 40.0) * _shake_mag * t, 0.0)

func _process(delta: float) -> void:
	_update_health_bar()
	if not _in_current_room():
		return
	_eject_from_solid()
	var overlay = _main.get("map_overlay")
	if overlay != null and overlay._open:
		return
	if _main.electric_beam == null:
		return
	if _dead:
		return

	if _shake_timer > 0.0:
		_shake_timer -= delta

	_visual_pos = _visual_pos.lerp(position, minf(1.0, SPRITE_SPEED * delta))
	_sprite.position = _visual_pos - position + Vector2(16.0, 16.0 - _ground_offset()) + _get_shake_offset()

	_handle_beam()
	if _dead:
		return

	var player = _main.player

	match _state:
		State.IDLE:
			if (player.get_body_center() - get_center()).length() <= ROTATE_RADIUS:
				_angle = _sprite.rotation
				_angle_velocity = 0.0
				_state = State.ROTATING

		State.ROTATING:
			var to_player = player.get_body_center() - get_center()
			var target_angle = to_player.angle()
			var diff = angle_difference(_angle, target_angle)
			_angle_velocity += (diff * ANGLE_STIFFNESS - _angle_velocity * ANGLE_DAMPING) * delta
			_angle += _angle_velocity * delta
			_sprite.rotation = _angle
			var dist = to_player.length()
			var aimed = absf(angle_difference(_angle, target_angle)) <= AIM_TOLERANCE
			if dist <= LUNGE_RADIUS and aimed:
				_lunge_dir = Vector2(cos(_angle), sin(_angle))
				_state = State.PRE_LUNGE
				_angle_velocity = 0.0
				_pre_lunge_timer = PRE_LUNGE_TIME
				_start_shake(1.0, PRE_LUNGE_TIME)
				_dist_traveled = 0.0
				_lunge_time = 0.0
			elif dist > ROTATE_RADIUS:
				_state = State.IDLE
				_angle_velocity = 0.0

		State.PRE_LUNGE:
			_pre_lunge_timer -= delta
			if _pre_lunge_timer <= 0.0:
				_dist_traveled = 0.0
				_lunge_time = 0.0
				_state = State.LUNGING

		State.LUNGING:
			_lunge_time += delta
			var speed = _lunge_initial_speed * exp(-LUNGE_DECAY * _lunge_time)
			var move = _lunge_dir * speed * delta
			var prev_pos = position
			_move_x(move.x)
			_move_y(move.y)
			var actual = (position - prev_pos).length()
			_dist_traveled += actual
			if move.length() > 0.5 and actual < move.length() * 0.9:
				_main._trigger_shake(2.0)
				_start_shake(2.0, 0.4)
				_retract_start_pos = position
				_retract_time = 0.0
				_state = State.RETRACTING
			elif _lunge_time >= LUNGE_DURATION or _dist_traveled >= LUNGE_TRAVEL:
				_retract_start_pos = position
				_retract_time = 0.0
				_state = State.RETRACTING

		State.RETRACTING:
			_retract_time += delta
			var t = clampf(_retract_time / RETRACT_DURATION, 0.0, 1.0)
			var eased = t * t * (3.0 - 2.0 * t)
			position = _retract_start_pos.lerp(_start_pos, eased)
			if t >= 1.0:
				position = _start_pos
				_visual_pos = _start_pos
				_state = State.COOLDOWN
				_cooldown_timer = COOLDOWN_TIME

		State.COOLDOWN:
			_cooldown_timer -= delta
			if _cooldown_timer <= 0.0:
				_state = State.IDLE

		State.STUNNED:
			_stun_timer -= delta
			if _stun_timer <= PRE_WAKE_TIME and _shake_timer <= 0.0:
				_start_shake(1.5, PRE_WAKE_TIME)
			if _stun_timer <= 0.0:
				_wake_from_stun()

	if _state != State.STUNNED:
		if not player.movement_locked and (player.get_body_center() - get_center()).length() < CONTACT_DIST:
			_main._reset_room()

func reset() -> void:
	super.reset()
	_sprite.centered = true
	_sprite.position = Vector2(16.0, 16.0 - _ground_offset())
	_sprite.rotation = _angle
	if _normal_tex != null:
		_sprite.texture = _normal_tex
	_state = State.IDLE
	_angle = PI / 2
	_angle_velocity = 0.0
	_dist_traveled = 0.0
	_lunge_time = 0.0
	_retract_time = 0.0
	_pre_lunge_timer = 0.0
	_stun_timer = 0.0
	_cooldown_timer = 0.0
	_shake_mag = 0.0
	_shake_timer = 0.0
