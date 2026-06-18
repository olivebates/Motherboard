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

var start_grid_pos: Vector2i = Vector2i.ZERO
var _home_room: Vector2i = Vector2i.ZERO
var _was_current := false
var _main: Node = null
var _destroyed := false

# Position is the 32×32 sprite top-left (tile top-left, like blocks/enemies).
# The collision hitbox is a small box centered on the tile, mirroring the player.
var _half := 5.0
var _hitbox_offset := Vector2(16.0, 16.0)

@onready var sprite: Sprite2D = $Sprite2D

var grid_pos: Vector2i:
	get:
		return Vector2i(floori(position.x / TILE_SIZE), floori(position.y / TILE_SIZE))

func _ready() -> void:
	add_to_group("nanodroids")
	_main = get_tree().current_scene
	start_grid_pos = Vector2i(floori(position.x / TILE_SIZE), floori(position.y / TILE_SIZE))
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
	return Vector2i(floori(position.x / TILE_SIZE), floori(position.y / TILE_SIZE))

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
	position = _move_axis_x(position, velocity.x * delta)
	position = _move_axis_y(position, velocity.y * delta)

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
	var particles := CPUParticles2D.new()
	particles.position = center
	particles.z_index = 10
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 28
	particles.lifetime = 0.6
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 160.0
	particles.gravity = Vector2(0, 200)
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	particles.color = Color(1.0, 1.0, 1.0, 1.0)
	_main.add_child(particles)
	get_tree().create_timer(particles.lifetime + 0.1).timeout.connect(particles.queue_free)

func reset() -> void:
	_destroyed = false
	position = Vector2(start_grid_pos.x * TILE_SIZE, start_grid_pos.y * TILE_SIZE)
	sprite.visible = true
	sprite.position = Vector2.ZERO
	_eject_from_solid()

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
	var old_rect := _hitbox_rect(pos)
	var allowed := dx
	var probe := old_rect.merge(_hitbox_rect(pos + Vector2(dx, 0.0)))
	for solid in _main.get_player_blocking_rects(probe, false):
		if not _rects_overlap_y(old_rect, solid):
			continue
		if dx > 0.0:
			if old_rect.end.x <= solid.position.x + CONTACT_EPS:
				allowed = minf(allowed, solid.position.x - old_rect.end.x)
			else:
				allowed = 0.0
		elif old_rect.position.x >= solid.end.x - CONTACT_EPS:
			allowed = maxf(allowed, solid.end.x - old_rect.position.x)
		else:
			allowed = 0.0
	if dx > 0.0:
		allowed = clampf(allowed, 0.0, dx)
	else:
		allowed = clampf(allowed, dx, 0.0)
	return Vector2(pos.x + allowed, pos.y)

func _move_axis_y(pos: Vector2, dy: float) -> Vector2:
	if dy == 0.0:
		return pos
	var old_rect := _hitbox_rect(pos)
	var allowed := dy
	var probe := old_rect.merge(_hitbox_rect(pos + Vector2(0.0, dy)))
	for solid in _main.get_player_blocking_rects(probe, false):
		if not _rects_overlap_x(old_rect, solid):
			continue
		if dy > 0.0:
			if old_rect.end.y <= solid.position.y + CONTACT_EPS:
				allowed = minf(allowed, solid.position.y - old_rect.end.y)
			else:
				allowed = 0.0
		elif old_rect.position.y >= solid.end.y - CONTACT_EPS:
			allowed = maxf(allowed, solid.end.y - old_rect.position.y)
		else:
			allowed = 0.0
	if dy > 0.0:
		allowed = clampf(allowed, 0.0, dy)
	else:
		allowed = clampf(allowed, dy, 0.0)
	return Vector2(pos.x, pos.y + allowed)

func _rects_overlap_x(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.end.x and b.position.x < a.end.x

func _rects_overlap_y(a: Rect2, b: Rect2) -> bool:
	return a.position.y < b.end.y and b.position.y < a.end.y

func _is_inside_solid() -> bool:
	var rect := _hitbox_rect(position)
	for solid in _main.get_player_blocking_rects(rect, false):
		if rect.intersects(solid):
			return true
	return false

func _eject_from_solid() -> void:
	if _main == null or not _is_inside_solid():
		return
	var origin := grid_pos
	var visited := {origin: true}
	var queue: Array[Vector2i] = [origin]
	while queue.size() > 0:
		var gp: Vector2i = queue.pop_front()
		var candidate := Vector2(gp.x * TILE_SIZE, gp.y * TILE_SIZE)
		var rect := _hitbox_rect(candidate)
		var blocked := false
		for solid in _main.get_player_blocking_rects(rect, false):
			if rect.intersects(solid):
				blocked = true
				break
		if not blocked:
			position = candidate
			return
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next = gp + d
			if not visited.has(next):
				visited[next] = true
				queue.append(next)
