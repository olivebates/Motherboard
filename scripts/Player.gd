extends Node2D

const TILE_SIZE := 32
const WORLD_OFFSET := 0
const SPEED := 272.0
const SPRITE_SPEED := 20.0
const CONTACT_EPS := 0.1
const PUSH_FREEZE := 0.15

var movement_locked := false
var visual_pos: Vector2
var _push_lock_dir := Vector2i.ZERO
var _push_tween: Tween

# Derived from the Hitbox node in _ready — edit the CollisionShape2D in the editor
var _half_w := 8.0
var _half_h := 8.0
var _hitbox_offset := Vector2(0.0, 8.0)

var grid_pos: Vector2i:
	get:
		return _world_to_grid(position)

func _ready() -> void:
	visual_pos = position
	$Sprite2D.centered = false
	add_to_group("players")
	var hitbox := $Hitbox as CollisionShape2D
	var rect := hitbox.shape as RectangleShape2D
	_half_w = rect.size.x * 0.5
	_half_h = rect.size.y * 0.5
	_hitbox_offset = hitbox.position

func _process(delta: float) -> void:
	visual_pos = visual_pos.lerp(position, minf(1.0, SPRITE_SPEED * delta))
	$Sprite2D.position = visual_pos - position + Vector2(-16.0, -16.0)

	if movement_locked:
		$Sprite2D.scale = $Sprite2D.scale.lerp(Vector2.ONE, 15.0 * delta)
		return

	var raw := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	var input := raw
	if input.length_squared() > 0.0:
		input = input.normalized()

	var velocity := input * SPEED
	var main: Node = get_parent()

	var dx := velocity.x * delta
	var dy := velocity.y * delta
	if _is_movement_locked_on_axis(true, dx):
		dx = 0.0
	if _is_movement_locked_on_axis(false, dy):
		dy = 0.0

	var x_move := _move_axis_x(position, dx, main)
	position = x_move.pos
	var moved_x: bool = x_move.moved

	var y_move := _move_axis_y(position, dy, main)
	position = y_move.pos
	var moved_y: bool = y_move.moved

	var pushed := _try_push(raw, moved_x, moved_y, main)

	var target_scale := Vector2.ONE
	if pushed:
		target_scale = Vector2.ONE
	elif moved_x and absf(velocity.x) >= absf(velocity.y):
		target_scale = Vector2(1.15, 0.85)
	elif moved_y:
		target_scale = Vector2(0.85, 1.15)
	$Sprite2D.scale = $Sprite2D.scale.lerp(target_scale, 15.0 * delta)

	if moved_x or moved_y:
		main.check_room_transition(grid_pos)

func _unhandled_input(event: InputEvent) -> void:
	if movement_locked:
		return
	if event.is_action_pressed("place_prong"):
		get_parent().spawn_prong(position)

func _hitbox_rect(pos: Vector2) -> Rect2:
	var center := pos + _hitbox_offset
	return Rect2(center.x - _half_w, center.y - _half_h, _half_w * 2.0, _half_h * 2.0)

func _move_axis_x(pos: Vector2, dx: float, main: Node) -> Dictionary:
	if dx == 0.0:
		return {"pos": pos, "moved": false}

	var old_rect := _hitbox_rect(pos)
	var allowed := dx
	var probe := old_rect.merge(_hitbox_rect(pos + Vector2(dx, 0.0)))

	for solid in main.get_player_blocking_rects(probe):
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

	var moved := absf(allowed) > 0.001
	return {"pos": Vector2(pos.x + allowed, pos.y), "moved": moved}

func _move_axis_y(pos: Vector2, dy: float, main: Node) -> Dictionary:
	if dy == 0.0:
		return {"pos": pos, "moved": false}

	var old_rect := _hitbox_rect(pos)
	var allowed := dy
	var probe := old_rect.merge(_hitbox_rect(pos + Vector2(0.0, dy)))

	for solid in main.get_player_blocking_rects(probe):
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

	var moved := absf(allowed) > 0.001
	return {"pos": Vector2(pos.x, pos.y + allowed), "moved": moved}

func _try_push(raw: Vector2, moved_x: bool, moved_y: bool, main: Node) -> bool:
	var dir := Vector2i.ZERO
	if raw.x > 0.0 and raw.y == 0.0:
		dir = Vector2i(1, 0)
	elif raw.x < 0.0 and raw.y == 0.0:
		dir = Vector2i(-1, 0)
	elif raw.y > 0.0 and raw.x == 0.0:
		dir = Vector2i(0, 1)
	elif raw.y < 0.0 and raw.x == 0.0:
		dir = Vector2i(0, -1)
	else:
		return false

	if dir == _push_lock_dir:
		return false

	if dir.x != 0 and moved_x:
		return false
	if dir.y != 0 and moved_y:
		return false

	var block: Node = main.get_push_block_at_face(_hitbox_rect(position), dir)
	if block == null:
		return false

	var dest: Vector2i = block.grid_pos + dir
	if not main.can_push_block_to(dest):
		return false

	block.push(dir)
	_start_push_lock(dir)
	main._trigger_shake(0.8)
	return true

func _is_movement_locked_on_axis(is_x: bool, delta_axis: float) -> bool:
	if _push_lock_dir == Vector2i.ZERO or delta_axis == 0.0:
		return false
	if is_x and _push_lock_dir.x != 0:
		return signf(delta_axis) == signf(float(_push_lock_dir.x))
	if not is_x and _push_lock_dir.y != 0:
		return signf(delta_axis) == signf(float(_push_lock_dir.y))
	return false

func _start_push_lock(dir: Vector2i) -> void:
	_push_lock_dir = dir
	if _push_tween:
		_push_tween.kill()
	_push_tween = create_tween()
	_push_tween.tween_interval(PUSH_FREEZE)
	_push_tween.tween_callback(func(): _push_lock_dir = Vector2i.ZERO)

func _rects_overlap_x(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.end.x and b.position.x < a.end.x

func _rects_overlap_y(a: Rect2, b: Rect2) -> bool:
	return a.position.y < b.end.y and b.position.y < a.end.y

func _world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori((world_pos.x - WORLD_OFFSET) / TILE_SIZE),
		floori((world_pos.y - WORLD_OFFSET) / TILE_SIZE)
	)

func _grid_to_world(gp: Vector2i) -> Vector2:
	return Vector2(
		WORLD_OFFSET + gp.x * TILE_SIZE + TILE_SIZE / 2,
		WORLD_OFFSET + gp.y * TILE_SIZE + TILE_SIZE / 2
	)

func lock_movement() -> void:
	movement_locked = true

func unlock_movement() -> void:
	movement_locked = false

func reset_to(gp: Vector2i) -> void:
	position = _grid_to_world(gp)
	visual_pos = position
