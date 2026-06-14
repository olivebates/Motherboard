extends "res://scripts/WaterEnemy.gd"

enum MoveState { IDLE, HOP, JUMP_WINDUP, JUMP }

const BOUNCE_MAX_HP := 50
const MOVE_SPEED := 0.286
const SORT_ABOVE_WALLS_Z := 64
const SPRITE_LAG_SPEED := 24.0
const WAIT_MIN := 0.5
const WAIT_MAX := 0.8
const LANDING_SQUASH := Vector2(1.18, 0.82)
const HOP_STRETCH := Vector2(0.88, 1.12)
const JUMP_STRETCH := Vector2(0.78, 1.35)
const HOP_DURATION := 0.28
const HOP_HEIGHT := 10.0
const JUMP_WINDUP := 0.38
const JUMP_DURATION := 0.52
const JUMP_HEIGHT := 56.0
const PATH_RECALC := 0.35
const SCALE_LERP := 15.0

const ROOM_WIDTH := 25
const ROOM_HEIGHT := 12

const _CARDINALS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]

var _room_x0 := 0
var _room_y0 := 0

var _path: Array[Vector2i] = []
var _path_timer := 0.0
var _move_state: MoveState = MoveState.IDLE
var _hop_from := Vector2.ZERO
var _hop_to := Vector2.ZERO
var _hop_time := 0.0
var _hop_duration := 0.0
var _hop_height := 0.0
var _windup_time := 0.0
var _wait_timer := 0.0
var _wait_duration := 0.0
var _hop_t := 0.0
var _sprite_scale := Vector2.ONE
var _idle_time := 0.0

func get_max_hp() -> int:
	return BOUNCE_MAX_HP

func _handle_beam() -> void:
	for fan in get_tree().get_nodes_in_group("fans"):
		if fan.is_active() and fan.is_position_in_airflow(get_center()):
			hp -= 1
			_main._trigger_shake(2.0)
			if hp <= 0:
				hp = 0
				_die()
			return

func _ready() -> void:
	super._ready()
	z_index = SORT_ABOVE_WALLS_Z
	add_to_group("bounce_enemies")
	hp = get_max_hp()
	var start_gp := _world_to_grid(_start_pos)
	_room_x0 = floori(float(start_gp.x) / ROOM_WIDTH) * ROOM_WIDTH
	_room_y0 = floori(float(start_gp.y) / ROOM_HEIGHT) * ROOM_HEIGHT

func _process(delta: float) -> void:
	_update_health_bar()
	if _dead:
		return
	if not _in_current_room():
		return
	if _main.map_overlay._open:
		_sync_sprite(delta)
		return

	_check_beam_and_contact()

	if _move_state == MoveState.IDLE:
		_path_timer -= delta
		if _path_timer <= 0.0:
			_recalc_path()
			_path_timer = PATH_RECALC
		if _wait_timer > 0.0:
			_wait_timer -= delta
			var wait_t := 1.0 - (_wait_timer / _wait_duration)
			_apply_scale_target(Vector2.ONE.lerp(LANDING_SQUASH, sin(wait_t * PI)), delta)
		else:
			_idle_time += delta
			var bob := sin(_idle_time * TAU * 1.1) * 0.05
			_apply_scale_target(Vector2(1.0 + bob, 1.0 - bob), delta)
			_begin_next_step()
	elif _move_state == MoveState.JUMP_WINDUP:
		_process_windup(delta)
	elif _move_state in [MoveState.HOP, MoveState.JUMP]:
		_process_hop(delta)

	_sync_sprite(delta)

func _eject_from_solid() -> void:
	pass

func _check_beam_and_contact() -> void:
	_handle_beam()
	if _dead:
		return
	var player: Node2D = _main.player
	if _can_hurt_player() and not player.movement_locked \
			and (player.get_body_center() - get_center()).length() < CONTACT_DIST:
		_main._reset_room()

func _can_hurt_player() -> bool:
	return _move_state != MoveState.JUMP

func _apply_scale_target(target: Vector2, delta: float) -> void:
	_sprite_scale = _sprite_scale.lerp(target, minf(1.0, SCALE_LERP * delta))

func _sync_sprite(delta: float) -> void:
	var arc := 0.0
	if _move_state in [MoveState.HOP, MoveState.JUMP]:
		arc = sin(_hop_t * PI) * _hop_height
	_visual_pos = _visual_pos.lerp(position, minf(1.0, SPRITE_LAG_SPEED * delta))
	var lag := _visual_pos - position
	var pivot := Vector2(16.0 * (1.0 - _sprite_scale.x), 32.0 * (1.0 - _sprite_scale.y))
	_sprite.position = lag + pivot + Vector2(0.0, -arc)
	_sprite.scale = _sprite.scale.lerp(_sprite_scale, SCALE_LERP * delta)

func _recalc_path() -> void:
	var from := _world_to_grid(position)
	var to := _world_to_grid(_main.player.get_body_center())
	_path = _find_path(from, to)

func _begin_next_step() -> void:
	if _path.is_empty():
		return
	var from_gp := _world_to_grid(position)
	var next_gp: Vector2i = _path[0]
	var delta_gp := next_gp - from_gp
	if absi(delta_gp.x) + absi(delta_gp.y) != 1 and not _is_jump_delta(from_gp, next_gp):
		_path.clear()
		return
	_path.pop_front()
	_idle_time = 0.0
	_hop_from = position
	_hop_to = _grid_to_world(next_gp)
	if _is_jump_delta(from_gp, next_gp):
		_move_state = MoveState.JUMP_WINDUP
		_windup_time = 0.0
	else:
		_move_state = MoveState.HOP
		_hop_time = 0.0
		_hop_t = 0.0
		_hop_duration = HOP_DURATION
		_hop_height = HOP_HEIGHT

func _is_jump_delta(from_gp: Vector2i, to_gp: Vector2i) -> bool:
	var d := to_gp - from_gp
	if absi(d.x) == 2 and d.y == 0:
		var wall_gp := from_gp + Vector2i(signi(d.x), 0)
		return _main.is_blocked(wall_gp) and _is_walkable(to_gp)
	if absi(d.y) == 2 and d.x == 0:
		var wall_gp := from_gp + Vector2i(0, signi(d.y))
		return _main.is_blocked(wall_gp) and _is_walkable(to_gp)
	return false

func _process_windup(delta: float) -> void:
	_windup_time += delta * MOVE_SPEED
	var t := clampf(_windup_time / JUMP_WINDUP, 0.0, 1.0)
	var squeeze := sin(_windup_time * TAU * 3.0) * 0.06
	var target := Vector2(1.0 + squeeze + t * 0.12, 1.0 - squeeze - t * 0.22)
	if t >= 1.0:
		target = Vector2(0.82, 1.28)
	_apply_scale_target(target, delta)
	if _windup_time >= JUMP_WINDUP:
		_move_state = MoveState.JUMP
		_hop_time = 0.0
		_hop_t = 0.0
		_hop_duration = JUMP_DURATION
		_hop_height = JUMP_HEIGHT

func _process_hop(delta: float) -> void:
	_hop_time += delta * MOVE_SPEED
	_hop_t = clampf(_hop_time / _hop_duration, 0.0, 1.0)
	position = _hop_from.lerp(_hop_to, _hop_t)
	var stretch := sin(_hop_t * PI)
	var target: Vector2
	if _move_state == MoveState.JUMP:
		target = Vector2(
			lerpf(1.0, JUMP_STRETCH.x, stretch),
			lerpf(1.0, JUMP_STRETCH.y, stretch))
	else:
		target = Vector2(
			lerpf(1.0, HOP_STRETCH.x, stretch),
			lerpf(1.0, HOP_STRETCH.y, stretch))
	_apply_scale_target(target, delta)
	if _hop_t >= 1.0:
		position = _hop_to
		_move_state = MoveState.IDLE
		_wait_duration = randf_range(WAIT_MIN, WAIT_MAX)
		_wait_timer = _wait_duration

func _world_to_grid(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE_SIZE), floori(pos.y / TILE_SIZE))

func _grid_to_world(gp: Vector2i) -> Vector2:
	return Vector2(gp.x * TILE_SIZE, gp.y * TILE_SIZE)

func _is_walkable(gp: Vector2i) -> bool:
	if gp.x < _room_x0 or gp.x >= _room_x0 + ROOM_WIDTH:
		return false
	if gp.y < _room_y0 or gp.y >= _room_y0 + ROOM_HEIGHT:
		return false
	return not _main.is_blocked(gp)

func _find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if from == to:
		return []
	# A* with Manhattan heuristic
	var g_cost: Dictionary = { from: 0 }
	var parents: Dictionary = { from: null }
	# open set stored as [f_cost, Vector2i] pairs; we use a simple array and pop the min
	var open: Array = [[absi(to.x - from.x) + absi(to.y - from.y), from]]
	var found := false
	while not open.is_empty():
		# find and remove the entry with the lowest f_cost
		var best_idx := 0
		for i in range(1, open.size()):
			if open[i][0] < open[best_idx][0]:
				best_idx = i
		var entry = open[best_idx]
		open.remove_at(best_idx)
		var cur: Vector2i = entry[1]
		if cur == to:
			found = true
			break
		var cur_g: int = g_cost[cur]
		for neighbor in _path_neighbors(cur):
			var step_cost := (absi((neighbor - cur).x) + absi((neighbor - cur).y))
			var new_g := cur_g + step_cost
			if not g_cost.has(neighbor) or new_g < g_cost[neighbor]:
				g_cost[neighbor] = new_g
				parents[neighbor] = cur
				var h := absi(to.x - neighbor.x) + absi(to.y - neighbor.y)
				open.append([new_g + h, neighbor])
	if not found:
		return []
	var path: Array[Vector2i] = []
	var node: Variant = to
	while node != from:
		path.push_front(node)
		node = parents[node]
	return path

func _path_neighbors(gp: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in _CARDINALS:
		var step := gp + d
		if _is_walkable(step):
			result.append(step)
		var wall := gp + d
		var land := gp + d * 2
		if _main.is_blocked(wall) and _is_walkable(land):
			result.append(land)
	return result

func push(dir: Vector2i) -> void:
	super.push(dir)
	_path.clear()
	_move_state = MoveState.IDLE
	_wait_timer = 0.0
	_wait_duration = 0.0
	_hop_t = 0.0
	_idle_time = 0.0
	_sprite_scale = Vector2.ONE

func reset() -> void:
	super.reset()
	_path.clear()
	_path_timer = 0.0
	_move_state = MoveState.IDLE
	_hop_time = 0.0
	_hop_t = 0.0
	_windup_time = 0.0
	_wait_timer = 0.0
	_wait_duration = 0.0
	_idle_time = 0.0
	_sprite_scale = Vector2.ONE
	_sprite.scale = Vector2.ONE
