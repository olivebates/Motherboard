extends Node2D

const TILE_SIZE := 32
const WORLD_OFFSET := 0
const SPEED := 217.6
const SPRITE_SPEED := 24.0
const CONTACT_EPS := 0.1
const PUSH_FREEZE := 0.15

@export var start_with_push: bool = false
@export var start_with_chain: bool = false
@export var save_system_enabled: bool = false

var movement_locked := false
var visual_pos: Vector2
var speed_multiplier := 1.0
var _push_lock_dir := Vector2i.ZERO
var _push_tween: Tween
var _main: Node2D

@onready var _body: Node2D = $Body
@onready var _sprite: Sprite2D = $Body/Sprite2D
@onready var _hitbox: CollisionShape2D = $Body/Hitbox

# Root position is hitbox bottom (Y-sort). Body holds sprite + hitbox at tile-center layout.
var _half_w := 5.0
var _half_h := 5.0
var _hitbox_offset := Vector2(0.0, 8.0)
var _body_offset := Vector2.ZERO

var grid_pos: Vector2i:
	get:
		return _world_to_grid(position)

func _ready() -> void:
	_main = get_tree().current_scene as Node2D
	_sprite.centered = false
	add_to_group("players")
	var cfg := YSortHitboxBottom.read_hitbox(_hitbox)
	_half_w = cfg.half_w
	_half_h = cfg.half_h
	_hitbox_offset = cfg.offset
	_body_offset = YSortHitboxBottom.body_offset_from_hitbox(_hitbox_offset, _half_h)
	_body.position = _body_offset
	visual_pos = position + _body_offset
	if start_with_push:
		GameManager.grant_ability("push")
	if start_with_chain:
		GameManager.grant_ability("chain")
	eject_from_solid()
	SaveManager.on_player_ready(save_system_enabled)

func get_body_center() -> Vector2:
	return YSortHitboxBottom.hitbox_center_from_root(position, _body_offset, _hitbox_offset)

func _process(delta: float) -> void:
	eject_from_solid()
	var body_center := position + _body_offset
	visual_pos = visual_pos.lerp(body_center, minf(1.0, SPRITE_SPEED * delta))
	_sprite.position = visual_pos - body_center + YSortHitboxBottom.SPRITE_OFFSET

	if movement_locked:
		_sprite.scale = _sprite.scale.lerp(Vector2.ONE, 15.0 * delta)
		return

	var raw := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	var input := raw
	if input.length_squared() > 0.0:
		input = input.normalized()

	var velocity := input * SPEED * speed_multiplier
	var main: Node = _main

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
	_sprite.scale = _sprite.scale.lerp(target_scale, 15.0 * delta)

	if moved_x or moved_y:
		main.check_room_transition(grid_pos, position)

func _unhandled_input(event: InputEvent) -> void:
	if movement_locked:
		return
	if event.is_action_pressed("place_prong"):
		_main.spawn_prong(get_body_center())

func _hitbox_rect(pos: Vector2) -> Rect2:
	var center := pos + _body_offset + _hitbox_offset
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
	if not GameManager.has_ability("push"):
		return false
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

	var block: Node = main.get_push_block_at_face(_hitbox_rect(position), dir, _sprite_center())
	if block == null:
		return false

	var dest: Vector2i = block.grid_pos + dir
	if not main.can_push_block_to(dest):
		return false

	block.push(dir)
	_start_push_lock(dir)
	main._trigger_shake(0.8)
	return true

func _sprite_center() -> Vector2:
	if _sprite.texture:
		return global_position + _body_offset + _sprite.position + _sprite.texture.get_size() * 0.5
	return global_position + _body_offset

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
	var hitbox_center_y := world_pos.y + _body_offset.y + _hitbox_offset.y
	return Vector2i(
		floori((world_pos.x - WORLD_OFFSET) / TILE_SIZE),
		floori((hitbox_center_y - WORLD_OFFSET) / TILE_SIZE)
	)

func _grid_to_world(gp: Vector2i) -> Vector2:
	var hitbox_center := Vector2(
		WORLD_OFFSET + gp.x * TILE_SIZE + TILE_SIZE / 2,
		WORLD_OFFSET + gp.y * TILE_SIZE + TILE_SIZE / 2
	)
	return YSortHitboxBottom.root_pos_from_hitbox_center(hitbox_center, _body_offset, _hitbox_offset)

func lock_movement() -> void:
	movement_locked = true

func unlock_movement() -> void:
	movement_locked = false

func reset_to(gp: Vector2i) -> void:
	position = _grid_to_world(gp)
	visual_pos = position + _body_offset
	eject_from_solid()

func _is_inside_solid() -> bool:
	var rect := _hitbox_rect(position)
	for solid in _main.get_player_blocking_rects(rect):
		if rect.intersects(solid):
			return true
	return false

func eject_from_solid() -> void:
	if not _is_inside_solid():
		return
	var origin := grid_pos
	var visited := {}
	var queue: Array[Vector2i] = [origin]
	visited[origin] = true
	while queue.size() > 0:
		var gp: Vector2i = queue.pop_front()
		var candidate := _grid_to_world(gp)
		var rect := _hitbox_rect(candidate)
		var blocked := false
		for solid in _main.get_player_blocking_rects(rect):
			if rect.intersects(solid):
				blocked = true
				break
		if not blocked:
			position = candidate
			visual_pos = position + _body_offset
			return
		for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var next = gp + d
			if not visited.has(next):
				visited[next] = true
				queue.append(next)
