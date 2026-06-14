extends Node2D

const TILE_SIZE := 32
const WORLD_OFFSET := 0
const SPEED := 217.6
const WIND_FORCE := 60.0
const SPRITE_SPEED := 24.0
const CONTACT_EPS := 0.1
const PUSH_FREEZE := 0.15
const PUSH_HOLD_TIME := 0.15

@export var start_with_push: bool = false
@export var start_with_chain: bool = false
@export var save_system_enabled: bool = false
@export var room_teleport_enabled: bool = false

var movement_locked := false
var visual_pos: Vector2
var speed_multiplier := 1.0
var _push_lock_dir := Vector2i.ZERO
var _push_tween: Tween
var _push_charge_time := 0.0
var _push_charge_dir := Vector2i.ZERO
var _push_charge_block: Node = null
var _main: Node2D

@onready var _body: Node2D = $Body
@onready var _sprite: AnimatedSprite2D = $Body/AnimatedSprite2D
@onready var _hitbox: CollisionShape2D = $Body/Hitbox

var _facing := "front"
var _facing_right := true

# Root position is hitbox bottom (Y-sort). Body holds sprite + hitbox at tile-center layout.
var _half_w := 5.0
var _half_h := 5.0
var _hitbox_offset := Vector2(0.0, 8.0)
var _body_offset := Vector2.ZERO

var grid_pos: Vector2i:
	get:
		return _world_to_grid(position)

func _ready() -> void:
	$Sprite2D.visible = false
	_main = get_tree().current_scene as Node2D
	add_to_group("players")
	_setup_animations()
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

func _setup_animations() -> void:
	var frames = SpriteFrames.new()
	frames.remove_animation("default")
	_add_sheet(frames, "front_idle", "res://Sprites/player/Spark_Front_Idle.webp", 4, 2, 8, 8.0)
	_add_sheet(frames, "front_run",  "res://Sprites/player/Spark_Front_Run.webp",  3, 2, 6, 12.0)
	_add_sheet(frames, "side_idle",  "res://Sprites/player/Spark_Side_Idle.webp",  3, 2, 6, 8.0)
	_add_sheet(frames, "side_run",   "res://Sprites/player/Spark_Side_Run.webp",   3, 2, 6, 12.0)
	_add_sheet(frames, "back_idle",  "res://Sprites/player/Spark_Back_Idle.webp",  4, 2, 8, 8.0)
	_add_sheet(frames, "back_run",   "res://Sprites/player/Spark_Back_Run.webp",   3, 2, 6, 12.0)
	_add_sheet(frames, "teleport",   "res://Sprites/player/Teleport_Spritesheet.webp", 2, 2, 4, 12.0, false)
	_sprite.sprite_frames = frames
	_sprite.play("front_idle")

func _add_sheet(frames: SpriteFrames, anim: String, path: String, cols: int, rows: int, count: int, fps: float, loop: bool = true) -> void:
	var tex: Texture2D = load(path)
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, loop)
	var f = 0
	for row in range(rows):
		for col in range(cols):
			if f >= count:
				break
			var atlas = AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(col * 32, row * 32, 32, 32)
			frames.add_frame(anim, atlas)
			f += 1

func _update_animation(raw: Vector2, moved_x: bool, moved_y: bool) -> void:
	var is_moving = moved_x or moved_y
	if raw.x > 0.0:
		_facing = "side"
		_facing_right = true
	elif raw.x < 0.0:
		_facing = "side"
		_facing_right = false
	elif raw.y < 0.0:
		_facing = "back"
	elif raw.y > 0.0:
		_facing = "front"
	var anim = _facing + ("_run" if is_moving else "_idle")
	if _sprite.animation != anim:
		_sprite.play(anim)
	_sprite.flip_h = (_facing == "side" and not _facing_right)

func get_body_center() -> Vector2:
	return YSortHitboxBottom.hitbox_center_from_root(position, _body_offset, _hitbox_offset)

func _process(delta: float) -> void:
	eject_from_solid()
	var body_center := position + _body_offset
	visual_pos = visual_pos.lerp(body_center, minf(1.0, SPRITE_SPEED * delta))
	var lag := visual_pos - body_center
	# Anchor squash/stretch at bottom-center of the 32×32 sprite
	_sprite.position = lag + Vector2(-16.0 * _sprite.scale.x, 16.0 - 32.0 * _sprite.scale.y)

	if movement_locked:
		_sprite.scale = _sprite.scale.lerp(Vector2.ONE, 15.0 * delta)
		if _sprite.animation.ends_with("_run"):
			_sprite.play(_facing + "_idle")
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

	var pushed := _try_push(raw, moved_x, moved_y, main, delta)

	_update_animation(raw, moved_x, moved_y)

	var target_scale := Vector2.ONE
	if pushed:
		target_scale = Vector2.ONE
	elif moved_x and absf(velocity.x) >= absf(velocity.y):
		target_scale = Vector2(1.15, 0.85)
	elif moved_y:
		target_scale = Vector2(0.85, 1.15)
	_sprite.scale = _sprite.scale.lerp(target_scale, 15.0 * delta)

	var wind := Vector2.ZERO
	for fan in get_tree().get_nodes_in_group("fans"):
		if fan == _push_charge_block:
			continue
		if fan.is_active() and fan.is_position_in_airflow(get_body_center()):
			wind += Vector2(fan.direction) * WIND_FORCE
	if wind.length_squared() > 0.0:
		var xw = _move_axis_x(position, wind.x * delta, main)
		position = xw.pos
		var yw = _move_axis_y(position, wind.y * delta, main)
		position = yw.pos

	if moved_x or moved_y:
		main.check_room_transition(grid_pos, position)

func _unhandled_input(event: InputEvent) -> void:
	if movement_locked:
		return
	if event.is_action_pressed("place_prong"):
		_main.spawn_prong(get_body_center())
	if room_teleport_enabled and event is InputEventKey and event.pressed and not event.echo:
		var shift = event.shift_pressed
		if shift:
			var dir := Vector2i.ZERO
			if event.keycode == KEY_UP:
				dir = Vector2i(0, -1)
			elif event.keycode == KEY_DOWN:
				dir = Vector2i(0, 1)
			elif event.keycode == KEY_LEFT:
				dir = Vector2i(-1, 0)
			elif event.keycode == KEY_RIGHT:
				dir = Vector2i(1, 0)
			elif event.keycode == KEY_P:
				GameManager.grant_ability("push")
			elif event.keycode == KEY_O:
				GameManager.grant_ability("chain")
			elif event.keycode == KEY_I:
				GameManager.grant_ability("break")
			if dir != Vector2i.ZERO:
				_try_room_teleport(dir)

func _try_room_teleport(dir: Vector2i) -> void:
	var target_room = _main.current_room + dir
	var anchor: Node = null
	for node in get_tree().get_nodes_in_group("teleport_anchors"):
		var room := Vector2i(
			floori(node.global_position.x / (25 * TILE_SIZE)),
			floori(node.global_position.y / (12 * TILE_SIZE))
		)
		if room == target_room:
			anchor = node
			break
	if anchor == null:
		return
	position = _grid_to_world(Vector2i(
		floori(anchor.global_position.x / TILE_SIZE),
		floori(anchor.global_position.y / TILE_SIZE)
	))
	visual_pos = position + _body_offset
	eject_from_solid()
	_main.check_room_transition(grid_pos, position)

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

func _try_push(raw: Vector2, moved_x: bool, moved_y: bool, main: Node, delta: float) -> bool:
	if not GameManager.has_ability("push"):
		_push_charge_time = 0.0
		_push_charge_dir = Vector2i.ZERO
		_push_charge_block = null
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
		_push_charge_time = 0.0
		_push_charge_dir = Vector2i.ZERO
		_push_charge_block = null
		return false

	if dir == _push_lock_dir:
		return false

	var block: Node = main.get_push_block_at_face(_hitbox_rect(position), dir, _sprite_center())
	if block == null:
		_push_charge_time = 0.0
		_push_charge_dir = Vector2i.ZERO
		_push_charge_block = null
		return false

	var pushing_fan_in_airflow = block.is_in_group("fans") and block.is_active() and block.is_position_in_airflow(get_body_center())
	if dir.x != 0 and moved_x and not pushing_fan_in_airflow:
		_push_charge_time = 0.0
		_push_charge_dir = Vector2i.ZERO
		_push_charge_block = null
		return false
	if dir.y != 0 and moved_y and not pushing_fan_in_airflow:
		_push_charge_time = 0.0
		_push_charge_dir = Vector2i.ZERO
		_push_charge_block = null
		return false

	if not block.is_in_group("fans"):
		var wind_dir := _get_fan_airflow_direction()
		if wind_dir != Vector2i.ZERO and dir == -wind_dir:
			_push_charge_time = 0.0
			_push_charge_dir = Vector2i.ZERO
			_push_charge_block = null
			return false

	var dest: Vector2i = block.grid_pos + dir
	if not main.can_push_block_to(dest):
		_push_charge_time = 0.0
		_push_charge_dir = Vector2i.ZERO
		_push_charge_block = null
		return false

	if dir == _push_charge_dir and block == _push_charge_block:
		_push_charge_time += delta
	else:
		_push_charge_dir = dir
		_push_charge_block = block
		_push_charge_time = delta

	if _push_charge_time < PUSH_HOLD_TIME:
		return false

	_push_charge_time = 0.0
	_push_charge_dir = Vector2i.ZERO
	_push_charge_block = null
	block.push(dir)
	_start_push_lock(dir)
	main._trigger_shake(0.8)
	return true

func _sprite_center() -> Vector2:
	return global_position + _body_offset + _sprite.position + Vector2(16.0, 16.0)

func _is_in_fan_airflow() -> bool:
	return _get_fan_airflow_direction() != Vector2i.ZERO

func _get_fan_airflow_direction() -> Vector2i:
	for fan in get_tree().get_nodes_in_group("fans"):
		if fan.is_active() and fan.is_position_in_airflow(get_body_center()):
			return fan.direction
	return Vector2i.ZERO

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

func play_teleport(reverse: bool = false) -> void:
	if reverse:
		_sprite.speed_scale = 0.5
		_sprite.play_backwards("teleport")
	else:
		_sprite.speed_scale = 1.0
		_sprite.play("teleport")
	await _sprite.animation_finished
	_sprite.speed_scale = 1.0
	_sprite.play(_facing + "_idle")

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
