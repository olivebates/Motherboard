extends Node2D

# NanoDroid — an actor that moves like the player but with reversed directions.
# It presses floor switches, drifts in fan airflow, and detonates when it
# crosses the electric beam: the blast breaks nearby breakable walls and resets
# the room if the player is caught in it.

const TILE_SIZE := 32
const ROOM_WIDTH := 25
const ROOM_HEIGHT := 12
const ROOM_BORDER := 16.0
const SPEED := 217.6
const WIND_FORCE := 60.0
const CONTACT_EPS := 0.1
const BEAM_RADIUS := 12.0
const BREAK_RADIUS := 64.0
const RESET_RADIUS := 48.0
const PUSH_HOLD_TIME := 0.15   # must press into a block this long before it moves (mirrors Player)
const PUSH_FREEZE := 0.15      # brief cooldown after a push before it can charge again
const SPRITE_SPEED := 20.0     # how fast the sprite eases back after a shove

var start_grid_pos: Vector2i = Vector2i.ZERO
var _home_room: Vector2i = Vector2i.ZERO
var _was_current := false
var _main: Node = null
var _destroyed := false

# Push state (mirrors Player): the droid presses into a pushable block in its
# movement direction and, after charging, shoves it one tile.
var _push_charge_time := 0.0
var _push_charge_dir := Vector2i.ZERO
var _push_charge_block: Node = null
var _push_lock_dir := Vector2i.ZERO
var _push_lock_time := 0.0

# Sprite lag: normally zero (the sprite sits exactly on the body). When the droid
# is shoved (push undo), this holds the sprite back and eases to zero so the body
# doesn't visibly teleport.
var _sprite_lag := Vector2.ZERO

# Position is the 32×32 sprite top-left (tile top-left, like blocks/enemies).
# The collision hitbox is a small box centered on the tile, mirroring the player.
var _half := 5.0
var _hitbox_offset := Vector2(16.0, 16.0)

@onready var sprite: Sprite2D = $Sprite2D

var grid_pos: Vector2i:
	get:
		return GridUtils.to_grid(position)

func _ready() -> void:
	add_to_group("nanodroids")
	_main = get_tree().current_scene
	start_grid_pos = GridUtils.to_grid(position)
	_home_room = Vector2i(
		floori(float(start_grid_pos.x) / ROOM_WIDTH),
		floori(float(start_grid_pos.y) / ROOM_HEIGHT)
	)
	position = Vector2(start_grid_pos.x * TILE_SIZE, start_grid_pos.y * TILE_SIZE)
	sprite.centered = false
	sprite.position = Vector2.ZERO
	_eject_from_solid()

func get_center() -> Vector2:
	return position + _hitbox_offset

# ── Push-back interface (mirrors Player) ─────────────────────────────────────

func get_push_hitbox() -> Rect2:
	return _hitbox_rect(position)

func push_out(displacement: Vector2) -> void:
	position += displacement
	# Hold the sprite at its old spot; _process eases the lag back to zero.
	_sprite_lag -= displacement

func _is_in_current_room() -> bool:
	var cr = _main.get("current_room")
	if cr == null:
		return true
	return cr == _home_room

func _clamp_to_room() -> void:
	var rx0 := _home_room.x * ROOM_WIDTH * TILE_SIZE
	var ry0 := _home_room.y * ROOM_HEIGHT * TILE_SIZE
	var c := get_center()
	var clamped := Vector2(
		clampf(c.x, rx0 + ROOM_BORDER, rx0 + ROOM_WIDTH * TILE_SIZE - ROOM_BORDER),
		clampf(c.y, ry0 + ROOM_BORDER, ry0 + ROOM_HEIGHT * TILE_SIZE - ROOM_BORDER)
	)
	position += clamped - c

func get_grid_pos() -> Vector2i:
	return GridUtils.to_grid(position)

func _process(delta: float) -> void:
	if _main == null:
		return
	# In the level editor the beam node only exists during a playtest; stay inert
	# (and visible at the placed tile) until then.
	var beam = _main.electric_beam
	if beam == null:
		return

	# Re-arm at the start position whenever the player enters this room.
	var is_current := _is_in_current_room()
	if is_current and not _was_current:
		reset()
	_was_current = is_current

	# Only active while the player is in this droid's room.
	if not is_current or _destroyed:
		return

	var pl = _main.get("player")
	if pl != null and pl.get("movement_locked") == true:
		return

	# Reversed player input.
	var raw := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	var input := -raw
	if input.length_squared() > 0.0:
		input = input.normalized()
	var velocity := input * SPEED
	if _push_lock_time > 0.0:
		_push_lock_time = maxf(0.0, _push_lock_time - delta)
		if _push_lock_time == 0.0:
			_push_lock_dir = Vector2i.ZERO
	var before_x := position.x
	position = _move_axis_x(position, velocity.x * delta)
	var moved_x := absf(position.x - before_x) > 0.001
	var before_y := position.y
	position = _move_axis_y(position, velocity.y * delta)
	var moved_y := absf(position.y - before_y) > 0.001

	# Shove a pushable block the droid is pressing against, just like the player.
	_try_push(input, moved_x, moved_y, delta)

	# Pushed by fan airflow, the same continuous drift the player receives.
	var wind := Vector2.ZERO
	for fan in get_tree().get_nodes_in_group("fans"):
		if fan.is_active() and fan.is_position_in_airflow(get_center()):
			wind += Vector2(fan.direction) * WIND_FORCE
	if wind.length_squared() > 0.0:
		position = _move_axis_x(position, wind.x * delta)
		position = _move_axis_y(position, wind.y * delta)

	# Keep it inside its room: a 16px inset border it cannot cross.
	_clamp_to_room()

	# Ease the sprite back after a shove so the body doesn't snap into place.
	if _sprite_lag != Vector2.ZERO:
		_sprite_lag = _sprite_lag.lerp(Vector2.ZERO, minf(1.0, SPRITE_SPEED * delta))
		if _sprite_lag.length() < 0.5:
			_sprite_lag = Vector2.ZERO
		sprite.position = _sprite_lag

	# Touching the player restarts the room.
	if pl != null and pl.has_method("get_body_center") and _touches(pl.get_body_center()):
		if _main.has_method("_reset_room"):
			_main._reset_room()
		return

	# Crossing the lightning beam makes it explode.
	if beam.active and beam.is_point_on_beam(get_center(), BEAM_RADIUS):
		_explode()

func _explode() -> void:
	if _destroyed:
		return
	_destroyed = true
	var center := get_center()
	_spawn_shockwave(center)
	_spawn_particles(center)
	sprite.visible = false
	if _main.has_method("_trigger_shake"):
		_main._trigger_shake(1.5)

	# Destroy any breakable blocks within the blast radius.
	for wall in get_tree().get_nodes_in_group("breakable_walls"):
		if wall._destroyed or wall._triggered:
			continue
		if wall.get_center().distance_to(center) <= BREAK_RADIUS:
			wall._triggered = true
			wall._shake_time = 0.0

	# Reset the room if the player is caught in the blast.
	var pl = _main.get("player")
	if pl != null and pl.has_method("get_body_center"):
		if pl.get_body_center().distance_to(center) <= RESET_RADIUS:
			if _main.has_method("_reset_room"):
				_main._reset_room()

func _circle_points(radius: float, segments: int, closed: bool) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var count := segments + 1 if closed else segments
	for i in range(count):
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts

func _spawn_shockwave(center: Vector2) -> void:
	# Expanding circular ring sized to the blast radius.
	var ring := Line2D.new()
	ring.position = center
	ring.z_index = 11
	ring.z_as_relative = false
	ring.width = 3.0
	ring.default_color = Color(1.0, 1.0, 1.0, 1.0)
	ring.joint_mode = Line2D.LINE_JOINT_ROUND
	ring.points = _circle_points(BREAK_RADIUS, 28, true)
	ring.scale = Vector2(0.12, 0.12)
	_main.add_child(ring)
	var ring_tw := ring.create_tween().set_parallel(true)
	ring_tw.tween_property(ring, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ring_tw.tween_property(ring, "modulate:a", 0.0, 0.45).set_ease(Tween.EASE_IN)
	ring_tw.finished.connect(ring.queue_free)

	# Quick filled circular flash at the core.
	var flash := Polygon2D.new()
	flash.position = center
	flash.z_index = 11
	flash.z_as_relative = false
	flash.color = Color(1.0, 1.0, 1.0, 0.9)
	flash.polygon = _circle_points(18.0, 24, false)
	flash.scale = Vector2(0.3, 0.3)
	_main.add_child(flash)
	var flash_tw := flash.create_tween().set_parallel(true)
	flash_tw.tween_property(flash, "scale", Vector2(1.6, 1.6), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flash_tw.tween_property(flash, "modulate:a", 0.0, 0.25).set_ease(Tween.EASE_IN)
	flash_tw.finished.connect(flash.queue_free)

func _spawn_particles(center: Vector2) -> void:
	EffectUtils.spawn_burst(_main, center, {
		"amount": 28, "lifetime": 0.6,
		"velocity_min": 60.0, "velocity_max": 160.0,
		"gravity": Vector2(0, 200), "scale_min": 2.0, "scale_max": 4.0,
	})

func reset() -> void:
	_destroyed = false
	position = Vector2(start_grid_pos.x * TILE_SIZE, start_grid_pos.y * TILE_SIZE)
	sprite.visible = true
	sprite.position = Vector2.ZERO
	_sprite_lag = Vector2.ZERO
	_reset_push_charge()
	_push_lock_dir = Vector2i.ZERO
	_push_lock_time = 0.0
	_eject_from_solid()

# ── Block pushing (mirrors Player._try_push) ─────────────────────────────────

func _cardinal_dir(input: Vector2) -> Vector2i:
	# Pure left/right/up/down only; diagonals don't push (matches the player).
	if input.x > 0.0 and input.y == 0.0:
		return Vector2i(1, 0)
	if input.x < 0.0 and input.y == 0.0:
		return Vector2i(-1, 0)
	if input.y > 0.0 and input.x == 0.0:
		return Vector2i(0, 1)
	if input.y < 0.0 and input.x == 0.0:
		return Vector2i(0, -1)
	return Vector2i.ZERO

func _reset_push_charge() -> void:
	_push_charge_time = 0.0
	_push_charge_dir = Vector2i.ZERO
	_push_charge_block = null

func _try_push(input: Vector2, moved_x: bool, moved_y: bool, delta: float) -> void:
	var dir := _cardinal_dir(input)
	if dir == Vector2i.ZERO or dir == _push_lock_dir:
		_reset_push_charge()
		return

	var block: Node = _main.get_push_block_at_face(_hitbox_rect(position), dir, get_center())
	if block == null:
		_reset_push_charge()
		return

	# If the droid still has room to move on the push axis it isn't flush against
	# the block yet, so don't begin charging.
	if (dir.x != 0 and moved_x) or (dir.y != 0 and moved_y):
		_reset_push_charge()
		return

	var dest: Vector2i = block.grid_pos + dir
	if not _main.can_push_block_to(dest):
		_reset_push_charge()
		return

	if dir == _push_charge_dir and block == _push_charge_block:
		_push_charge_time += delta
	else:
		_push_charge_dir = dir
		_push_charge_block = block
		_push_charge_time = delta

	if _push_charge_time < PUSH_HOLD_TIME:
		return

	_reset_push_charge()
	var push_from: Vector2i = block.grid_pos
	block.push(dir)
	_push_lock_dir = dir
	_push_lock_time = PUSH_FREEZE
	if _main.has_method("_trigger_shake"):
		_main._trigger_shake(0.8)
	if _main.has_method("record_push"):
		_main.record_push(block, push_from, dir)

# ── Collision (mirrors Player axis-separated AABB sweep) ──────────────────────

func _touches(world_point: Vector2) -> bool:
	# True when the player's body center falls inside the droid's hitbox (+ a small margin).
	var c := get_center()
	return absf(world_point.x - c.x) <= _half + 5.0 and absf(world_point.y - c.y) <= _half + 5.0

func _hitbox_rect(pos: Vector2) -> Rect2:
	var center := pos + _hitbox_offset
	return Rect2(center.x - _half, center.y - _half, _half * 2.0, _half * 2.0)

func _move_axis_x(pos: Vector2, dx: float) -> Vector2:
	if dx == 0.0:
		return pos
	var old_rect = _hitbox_rect(pos)
	var probe = old_rect.merge(_hitbox_rect(pos + Vector2(dx, 0.0)))
	var allowed = MoveUtils.sweep_x(old_rect, dx, _main.get_player_blocking_rects(probe, false), CONTACT_EPS)
	return Vector2(pos.x + allowed, pos.y)

func _move_axis_y(pos: Vector2, dy: float) -> Vector2:
	if dy == 0.0:
		return pos
	var old_rect = _hitbox_rect(pos)
	var probe = old_rect.merge(_hitbox_rect(pos + Vector2(0.0, dy)))
	var allowed = MoveUtils.sweep_y(old_rect, dy, _main.get_player_blocking_rects(probe, false), CONTACT_EPS)
	return Vector2(pos.x, pos.y + allowed)

func _is_inside_solid() -> bool:
	var rect = _hitbox_rect(position)
	return MoveUtils.rect_hits_any(rect, _main.get_player_blocking_rects(rect, false))

func _eject_from_solid() -> void:
	if _main == null or not _is_inside_solid():
		return
	var is_free = func(c):
		var rect = _hitbox_rect(Vector2(c.x * TILE_SIZE, c.y * TILE_SIZE))
		return not MoveUtils.rect_hits_any(rect, _main.get_player_blocking_rects(rect, false))
	var gp = MoveUtils.find_free_cell(grid_pos, is_free)
	if gp != null:
		position = Vector2(gp.x * TILE_SIZE, gp.y * TILE_SIZE)
