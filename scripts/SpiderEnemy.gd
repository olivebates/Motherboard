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

# Layered animation sheets (all 64×64 frames in a single horizontal strip). The
# idle body and the legs are separate layers stacked at the same center: idle on
# top, legs underneath. Pullback and pounce are complete spiders (legs baked in),
# so the separate legs layer is hidden while they play.
const _SHEET_IDLE = "res://Sprites/enemies/Spider/Spider_idle_before_pounce-Sheet-export.webp"
const _SHEET_LEGS = "res://Sprites/enemies/Spider/Spider_legs_rotate-Sheet-export.webp"
const _SHEET_PULLBACK = "res://Sprites/enemies/Spider/Spider_pullback-Sheet-export.webp"
const _SHEET_POUNCE = "res://Sprites/enemies/Spider/Spider_pounce-Sheet.webp"
const _FRAME_SIZE = 64
const _BODY_IDLE_FRAMES = 6
const _LEGS_FRAMES = 11
const _PULLBACK_FRAMES = 8
const _POUNCE_FRAMES = 3
const _BODY_IDLE_FPS = 8.0
const _LEGS_FPS = 28.0
# Pullback completes within the pre-lunge wind-up, then holds its last frame.
const _PULLBACK_FPS = _PULLBACK_FRAMES / PRE_LUNGE_TIME
const _POUNCE_FPS = 24.0
# Legs only shuffle while the body is actively turning; below this angular speed
# (rad/s) they freeze on their current frame.
const _LEGS_ROTATE_THRESHOLD = 0.2
# Local rotation offset for the art so it aligns with `_angle` (90° CCW; Godot
# rotation is clockwise for +, so CCW is negative).
const _SPRITE_ROT_OFFSET = -PI / 2
# Per-animation vertical nudge (sheet space, negative = toward the head) so the
# pullback/pounce bodies line up with the idle body. The pullback sheet is
# authored ~12px lower than idle; pounce already matches. Tune if the art moves.
const _PULLBACK_Y_OFFSET = -12.0
const _POUNCE_Y_OFFSET = 0.0

# Speed the spider scurries away from light (px/s) — roughly twice its normal crawl so
# it can actually break free of a light circle that's closing on it.
const FLEE_SPEED = 147.0
# Only a powered LightSource's light scares the spider (not the player's light). It
# starts fleeing when inside a source's LIGHT_RADIUS and keeps going until it is
# FLEE_EXIT_RADIUS px clear of the light (hysteresis, so it doesn't stall at the edge).
const FLEE_EXIT_RADIUS = 152.0

enum State { IDLE, ROTATING, PRE_LUNGE, LUNGING, RETRACTING, COOLDOWN, STUNNED, FLEEING }

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
var _body: AnimatedSprite2D = null
var _legs: AnimatedSprite2D = null

@onready var _hitbox_col: CollisionShape2D = $HitboxArea/HitboxShape

func _ready() -> void:
	super._ready()
	hp = SPIDER_MAX_HP
	_sprite.centered = true
	_sprite.position = Vector2(16.0, 16.0 - _ground_offset())
	_sprite.rotation = _angle
	# _sprite becomes a transform-only container; the animation layers (children)
	# inherit its position/rotation. _normal_tex stays null (only the stun pose
	# ever puts a texture back on _sprite).
	_setup_anim_layers()
	_sprite.texture = null
	_normal_tex = null
	# Keep the hitbox node at the tile center despite the origin shift.
	$HitboxArea.position.y -= _ground_offset()
	_lunge_initial_speed = LUNGE_TRAVEL * LUNGE_DECAY / (1.0 - exp(-LUNGE_DECAY * LUNGE_DURATION))

func _add_spider_strip(frames: SpriteFrames, anim: String, path: String, count: int, fps: float, looped: bool) -> void:
	var tex: Texture2D = load(path)
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, looped)
	for i in range(count):
		var atlas = AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(i * _FRAME_SIZE, 0, _FRAME_SIZE, _FRAME_SIZE)
		frames.add_frame(anim, atlas)

func _setup_anim_layers() -> void:
	var legs_frames = SpriteFrames.new()
	legs_frames.remove_animation("default")
	_add_spider_strip(legs_frames, "legs", _SHEET_LEGS, _LEGS_FRAMES, _LEGS_FPS, true)
	_legs = AnimatedSprite2D.new()
	_legs.sprite_frames = legs_frames
	_legs.centered = true
	_legs.rotation = _SPRITE_ROT_OFFSET
	_legs.play("legs")
	_legs.pause()

	var body_frames = SpriteFrames.new()
	body_frames.remove_animation("default")
	_add_spider_strip(body_frames, "idle", _SHEET_IDLE, _BODY_IDLE_FRAMES, _BODY_IDLE_FPS, true)
	_add_spider_strip(body_frames, "pullback", _SHEET_PULLBACK, _PULLBACK_FRAMES, _PULLBACK_FPS, false)
	_add_spider_strip(body_frames, "pounce", _SHEET_POUNCE, _POUNCE_FRAMES, _POUNCE_FPS, false)
	_body = AnimatedSprite2D.new()
	_body.sprite_frames = body_frames
	_body.centered = true
	_body.rotation = _SPRITE_ROT_OFFSET
	_body.play("idle")

	# Legs added first so they draw underneath the body.
	_sprite.add_child(_legs)
	_sprite.add_child(_body)

# Applies the visuals for the current state. Idempotent — only (re)plays an
# animation when it isn't already the active one, so non-looping pullback/pounce
# play once and hold their last frame.
func _apply_animation() -> void:
	match _state:
		State.STUNNED:
			pass  # handled in _enter_stun / _wake_from_stun
		State.PRE_LUNGE:
			_legs.visible = false
			_body.offset.y = _PULLBACK_Y_OFFSET
			if _body.animation != "pullback":
				_body.play("pullback")
		State.LUNGING:
			_legs.visible = false
			_body.offset.y = _POUNCE_Y_OFFSET
			if _body.animation != "pounce":
				_body.play("pounce")
		_:
			# IDLE / ROTATING / RETRACTING / COOLDOWN: idle body over the legs.
			_legs.visible = true
			_body.offset.y = 0.0
			if _body.animation != "idle":
				_body.play("idle")
			# The body idle stays frozen until the player is within turning range
			# (any state past IDLE); it only breathes once the spider has woken.
			if _state == State.IDLE and _body.is_playing():
				_body.pause()
			elif _state != State.IDLE and not _body.is_playing():
				_body.play("idle")
			# Legs shuffle while the body is turning (ROTATING), crawling back in
			# (RETRACTING), or scurrying from light (FLEEING); else they freeze.
			var crawling = (_state == State.ROTATING and absf(_angle_velocity) > _LEGS_ROTATE_THRESHOLD) \
				or _state == State.RETRACTING or _state == State.FLEEING
			if crawling and not _legs.is_playing():
				_legs.play("legs")
			elif not crawling and _legs.is_playing():
				_legs.pause()

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
	_body.visible = false
	_legs.visible = false
	_sprite.texture = STUN_TEX

func _wake_from_stun() -> void:
	_sprite.texture = _normal_tex
	_body.visible = true
	_legs.visible = true
	_body.play("idle")
	_legs.play("legs")
	_legs.pause()
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

	# Light-averse: in a dark room a powered LightSource's light makes the spider flee,
	# overriding its hunt/lunge behaviour (it ignores the player's own light). It keeps
	# fleeing until FLEE_EXIT_RADIUS clear (hysteresis), then crawls home.
	var flee = _main.light_flee_vector(get_center(), FLEE_EXIT_RADIUS, _state == State.FLEEING) if _main.has_method("light_flee_vector") else Vector2.ZERO
	if _state != State.STUNNED:
		if flee != Vector2.ZERO and _state != State.FLEEING:
			_state = State.FLEEING
			_angle_velocity = 0.0
		elif flee == Vector2.ZERO and _state == State.FLEEING:
			# It got away — adopt the new spot as home (it hunts/retracts from here
			# now) instead of crawling back to where it started.
			_start_pos = position
			_visual_pos = position
			_state = State.COOLDOWN
			_cooldown_timer = COOLDOWN_TIME

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

		State.FLEEING:
			var dir = flee.normalized()
			# Turn to face away from the light (legs/body point in the flee direction).
			var target_angle = dir.angle()
			var diff = angle_difference(_angle, target_angle)
			_angle_velocity += (diff * ANGLE_STIFFNESS - _angle_velocity * ANGLE_DAMPING) * delta
			_angle += _angle_velocity * delta
			_sprite.rotation = _angle
			var move = dir * FLEE_SPEED * delta
			_move_x(move.x)
			_move_y(move.y)

		State.STUNNED:
			_stun_timer -= delta
			if _stun_timer <= PRE_WAKE_TIME and _shake_timer <= 0.0:
				_start_shake(1.5, PRE_WAKE_TIME)
			if _stun_timer <= 0.0:
				_wake_from_stun()

	_apply_animation()

	if _state != State.STUNNED:
		if not player.movement_locked and (player.get_body_center() - get_center()).length() < CONTACT_DIST:
			_main._reset_room()

func reset() -> void:
	super.reset()
	_sprite.centered = true
	_sprite.position = Vector2(16.0, 16.0 - _ground_offset())
	_sprite.rotation = _angle
	_sprite.texture = _normal_tex
	if _body != null:
		_body.visible = true
		_body.play("idle")
	if _legs != null:
		_legs.visible = true
		_legs.play("legs")
		_legs.pause()
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
