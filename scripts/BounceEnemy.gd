extends "res://scripts/WaterEnemy.gd"

const WIND_BLOCK_SCENE = preload("res://scenes/objects/WindBlock.tscn")

# Visuals: a dust pile that blinks while dormant, plays a one-shot transform when
# the player wakes it, then becomes the bunny.
const BUNNY_TEX = preload("res://Sprites/enemies/BounceFront.png")
const BLINK_TEX = preload("res://Sprites/enemies/DustBunnies/Dust_Blink-Sheet.webp")
const TRANSFORM_TEX = preload("res://Sprites/enemies/DustBunnies/Dust_Transform_into_Bunny.webp")
const TRANSFORM_FRAMES := 16
# 16 frames over 1.3s.
const TRANSFORM_FPS := TRANSFORM_FRAMES / 1.3
# Idle blink: hold frame 0, occasionally flick to frame 1 for half a second.
const BLINK_HOLD := 0.2
const BLINK_MIN := 1.5
const BLINK_MAX := 4.0

enum MoveState { IDLE, HOP, JUMP_WINDUP, JUMP }

const BOUNCE_MAX_HP := 50
const MOVE_SPEED := 0.286
# Stays stationary until the player comes within this distance, then activates
# and keeps pathfinding toward the player for the rest of its life.
const ACTIVATION_RADIUS := 96.0
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
# Per-pathfind memo of _main.is_blocked() results. is_blocked() is expensive
# (it scans ~11 node groups across the whole scene tree per call), and A* queries
# the same cells many times, so we evaluate each cell at most once per _find_path().
var _blocked_cache: Dictionary = {}
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
var _activated := false
var _transforming := false
# Dust-pile idle + wake-up transform visuals.
var _dust_blink: Sprite2D
var _activating := false
var _transform_time := 0.0
var _blink_timer := 0.0
var _blink_hold := 0.0
var _blinking := false

@onready var _hitbox_shape: CollisionShape2D = $HitboxArea/HitboxShape

func get_max_hp() -> int:
	return BOUNCE_MAX_HP

# Immune to fan wind. The electric beam no longer kills it outright — instead it
# turns into a WindBlock (a fan-pushable block). If the beam catches it mid-jump
# over a wall it doesn't transform on the wall tile; it finishes the hop and only
# becomes a block once it has landed on the far side (a tile that can hold a block).
func _handle_beam() -> void:
	var beam = _main.electric_beam
	if beam == null:
		return
	if beam.active and beam.is_point_on_beam(get_center(), BEAM_RADIUS):
		_begin_transform()

func _begin_transform() -> void:
	if _transforming or _dead:
		return
	_transforming = true
	# Transforms right away if already settled on a free tile; otherwise the hop
	# finishes first (driven from _process) and it transforms on landing.
	_try_finish_transform()

# Returns true (and turns into a WindBlock) only when settled on a tile that can
# actually hold a block; otherwise it keeps the pending transform and waits.
func _try_finish_transform() -> bool:
	if _move_state != MoveState.IDLE:
		return false
	var cell := _self_cell()
	if _main.is_blocked(cell):
		return false
	_dead = true
	var wb = WIND_BLOCK_SCENE.instantiate()
	wb.position = GridUtils.to_world(cell)
	# Parent under the same node the enemy lives in (the Walls TileMapLayer in Main,
	# y_sort_root in the editor) so the new block depth-sorts correctly.
	get_parent().add_child(wb)
	# Tag the block so the room can revert it to a fresh BounceEnemy at this enemy's
	# start tile when re-entered (uncompleted) or reset.
	wb.add_to_group("bounce_wind_blocks")
	wb.set_meta("bounce_start_pos", _start_pos - Vector2(0.0, _ground_offset()))
	_main._trigger_shake(4.0)
	queue_free()
	return true

func _ready() -> void:
	super._ready()
	add_to_group("bounce_enemies")
	# Keep the dragged hitbox at its authored world spot despite the origin shift.
	$HitboxArea.position.y -= _ground_offset()
	# Park the sprite at its resting pose so it sits correctly in the editor,
	# where _sync_sprite() never runs — matches the first playtest frame.
	_sprite.position = _rest_sprite_position()
	_sprite.scale = Vector2.ONE
	hp = get_max_hp()
	var start_gp := _world_to_grid(_start_pos - Vector2(0.0, _ground_offset()))
	_room_x0 = floori(float(start_gp.x) / ROOM_WIDTH) * ROOM_WIDTH
	_room_y0 = floori(float(start_gp.y) / ROOM_HEIGHT) * ROOM_HEIGHT
	_setup_dust_visuals()
	_show_dust_idle()

# Builds the 32×32 dust-pile sprite shown while dormant. Sits bottom-centered on
# the tile (its bottom line matches the bunny's, accounting for the origin shift).
func _setup_dust_visuals() -> void:
	_dust_blink = Sprite2D.new()
	_dust_blink.texture = BLINK_TEX
	_dust_blink.hframes = 2
	_dust_blink.centered = false
	_dust_blink.position = Vector2(0.0, -_ground_offset())
	add_child(_dust_blink)

func _process(delta: float) -> void:
	_update_health_bar()
	if _dead:
		return
	if not _in_current_room():
		return
	var overlay = _main.get("map_overlay")
	if overlay != null and overlay._open:
		_sync_sprite(delta)
		return
	if _main.electric_beam == null:
		return

	if _transforming:
		# Beam already caught it — finish the in-progress hop so it lands on the far
		# side of any wall, then become a WindBlock. No more pathing/contact.
		if _move_state == MoveState.JUMP_WINDUP:
			_process_windup(delta)
		elif _move_state in [MoveState.HOP, MoveState.JUMP]:
			_process_hop(delta)
		if _try_finish_transform():
			return
		_sync_sprite(delta)
		return

	_check_beam_and_contact()

	if _move_state == MoveState.IDLE:
		if not _activated:
			# Dust pile: blink in place until the player gets close enough to wake it.
			if (_main.player.get_body_center() - get_center()).length() <= ACTIVATION_RADIUS:
				_activated = true
				_begin_activation()
			else:
				_process_blink(delta)
				return
		if _activating:
			# Play the wake-up transform once before any movement.
			if _process_activation(delta):
				return
		_path_timer -= delta
		if _path_timer <= 0.0:
			_recalc_path()
			_path_timer = PATH_RECALC
		if _wait_timer > 0.0:
			_wait_timer -= delta
			var wait_t := 1.0 - (_wait_timer / _wait_duration)
			_apply_scale_target(Vector2.ONE.lerp(LANDING_SQUASH, sin(wait_t * PI)), delta)
		else:
			_idle_bob(delta)
			_begin_next_step()
	elif _move_state == MoveState.JUMP_WINDUP:
		_process_windup(delta)
	elif _move_state in [MoveState.HOP, MoveState.JUMP]:
		_process_hop(delta)

	_sync_sprite(delta)

func _eject_from_solid() -> void:
	pass

# Contact hitbox center follows the HitboxShape node, which can be dragged
# around in the editor to tune where the enemy collides with the player/beam.
func get_center() -> Vector2:
	return position + _hitbox_shape.global_position - global_position

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

func _idle_bob(delta: float) -> void:
	_idle_time += delta
	var bob := sin(_idle_time * TAU * 1.1) * 0.05
	_apply_scale_target(Vector2(1.0 + bob, 1.0 - bob), delta)

# Dormant dust pile: shows the bunny-less blink sprite, hides everything else.
func _show_dust_idle() -> void:
	_activating = false
	_transform_time = 0.0
	_blinking = false
	_blink_hold = 0.0
	_blink_timer = randf_range(BLINK_MIN, BLINK_MAX)
	_sprite_scale = Vector2.ONE
	_sprite.scale = Vector2.ONE
	# Restore the bunny on the base sprite for when it later activates.
	_sprite.texture = BUNNY_TEX
	_sprite.hframes = 1
	_sprite.frame = 0
	_sprite.visible = false
	if _dust_blink != null:
		_dust_blink.frame = 0
		_dust_blink.visible = true

# Holds blink frame 0, flicking to frame 1 (eyes shut) for BLINK_HOLD seconds at
# random intervals.
func _process_blink(delta: float) -> void:
	if _dust_blink == null:
		return
	if _blinking:
		_blink_hold -= delta
		if _blink_hold <= 0.0:
			_blinking = false
			_dust_blink.frame = 0
			_blink_timer = randf_range(BLINK_MIN, BLINK_MAX)
	else:
		_blink_timer -= delta
		if _blink_timer <= 0.0:
			_blinking = true
			_blink_hold = BLINK_HOLD
			_dust_blink.frame = 1

# Swaps the dust pile out for the one-shot transform sheet on the base sprite.
func _begin_activation() -> void:
	_activating = true
	_transform_time = 0.0
	_sprite_scale = Vector2.ONE
	_sprite.scale = Vector2.ONE
	if _dust_blink != null:
		_dust_blink.visible = false
	_sprite.texture = TRANSFORM_TEX
	_sprite.hframes = TRANSFORM_FRAMES
	_sprite.frame = 0
	_sprite.visible = true

# Steps the transform animation. Returns true while it is still playing; on the
# frame it finishes it swaps in the bunny and returns false so movement can begin.
func _process_activation(delta: float) -> bool:
	_transform_time += delta
	var idx := int(_transform_time * TRANSFORM_FPS)
	if idx >= TRANSFORM_FRAMES:
		_activating = false
		_sprite.texture = BUNNY_TEX
		_sprite.hframes = 1
		_sprite.frame = 0
		return false
	_sprite.frame = idx
	_sync_sprite(delta)
	return true

# Resting sprite offset (scale 1, no hop arc, no lag) — the value _sync_sprite()
# produces at rest, so the editor-placed sprite lands where it sits on the first
# playtest frame.
func _rest_sprite_position() -> Vector2:
	var pivot := Vector2(16.0 - 32.0, 32.0 - 64.0)
	return pivot + Vector2(0.0, -_ground_offset())

func _sync_sprite(delta: float) -> void:
	var arc := 0.0
	if _move_state in [MoveState.HOP, MoveState.JUMP]:
		arc = sin(_hop_t * PI) * _hop_height
	_visual_pos = _visual_pos.lerp(position, minf(1.0, SPRITE_LAG_SPEED * delta))
	var lag := _visual_pos - position
	# 64x64 sprite drawn with its bottom-center anchored at the tile's
	# bottom-center (16, 32); scaling pivots around that bottom-center.
	var pivot := Vector2(16.0 - 32.0 * _sprite_scale.x, 32.0 - 64.0 * _sprite_scale.y)
	_sprite.position = lag + pivot + Vector2(0.0, -arc - _ground_offset())
	_sprite.scale = _sprite.scale.lerp(_sprite_scale, SCALE_LERP * delta)

func _recalc_path() -> void:
	var from := _self_cell()
	var to := _world_to_grid(_main.player.get_body_center())
	_path = _find_path(from, to)

func _begin_next_step() -> void:
	if _path.is_empty():
		return
	var from_gp := _self_cell()
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
	return GridUtils.to_grid(pos)

# Cell the enemy currently occupies (accounts for the ground-line origin shift).
func _self_cell() -> Vector2i:
	return _world_to_grid(position - Vector2(0.0, _ground_offset()))

func _grid_to_world(gp: Vector2i) -> Vector2:
	return GridUtils.to_world(gp) + Vector2(0.0, _ground_offset())

func _cell_blocked(gp: Vector2i) -> bool:
	var cached: Variant = _blocked_cache.get(gp)
	if cached != null:
		return cached
	var result = _main.is_blocked(gp)
	_blocked_cache[gp] = result
	return result

func _is_walkable(gp: Vector2i) -> bool:
	if gp.x < _room_x0 or gp.x >= _room_x0 + ROOM_WIDTH:
		return false
	if gp.y < _room_y0 or gp.y >= _room_y0 + ROOM_HEIGHT:
		return false
	return not _cell_blocked(gp)

func _find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	_blocked_cache.clear()
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
		if _cell_blocked(wall) and _is_walkable(land):
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
	_activated = false
	_transforming = false
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
	_sprite.position = _rest_sprite_position()
	_show_dust_idle()
