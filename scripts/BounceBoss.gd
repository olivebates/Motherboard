extends "res://scripts/WaterEnemy.gd"

enum State { CHASE, BIG_BOUNCE_WINDUP, BIG_BOUNCE, DYING }
enum HopState { IDLE, HOP, BIG_JUMP }

const BOSS_MAX_HP := 1800
const PANEL_SWITCH_STEP := 300
# Panels stay at least this many tiles away from the room edges.
const PANEL_BORDER := 3
# Both panels share this id; fans with the same id turn on while both are beam-lit.
const PANEL_ID := "bounceboss"
# Fixed seed so panel positions are identical on every room reset.
const PANEL_RNG_SEED := 0x420B055
const BOSS_SCALE := 2.0
const SORT_Z := 64

const BASE_MOVE_SPEED := 0.15
# At 0 hp the boss moves 4x its starting (full-hp) speed.
const MAX_MOVE_SPEED := BASE_MOVE_SPEED * 4.0

const PATH_RECALC := 0.35
const SCALE_LERP := 15.0
const SPRITE_LAG_SPEED := 16.0

const WAIT_MIN := 0.5
const WAIT_MAX := 0.8
const HOP_DURATION := 0.28
const HOP_HEIGHT := 12.0
# Leap that clears a single solid block: the block sits at the take-off cell + 1,
# the boss lands two tiles away (it paths as a single 32x32 tile).
const JUMP_TILES := 2
const JUMP_HOP_DURATION := 0.4
const JUMP_HOP_HEIGHT := 44.0
# Screen shake (px) on landing from a normal hop vs. a long (big bounce) jump.
const LAND_SHAKE := 2.0
const LONG_JUMP_SHAKE := 4.0
const HOP_STRETCH_X := 0.88
const HOP_STRETCH_Y := 1.12
const LANDING_SQUASH_X := 1.18
const LANDING_SQUASH_Y := 0.82

const BIG_BOUNCE_INTERVAL := 5.0
const BIG_BOUNCE_WINDUP_DUR := 0.8
const BIG_BOUNCE_DURATION := 0.7
const BIG_BOUNCE_HEIGHT := 90.0

const BOSS_CONTACT_DIST := 30.0

const _CARDINALS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]

const BounceBossPanelScene = preload("res://scenes/enemies/BounceBossPanel.tscn")

var _state: State = State.CHASE
var _state_timer := 0.0

var _hop_state: HopState = HopState.IDLE
var _hop_from := Vector2.ZERO
var _hop_to := Vector2.ZERO
var _hop_time := 0.0
var _hop_t := 0.0
var _hop_duration := 0.0
var _hop_height := 0.0
var _wait_timer := 0.0
var _wait_duration := 0.0
var _path: Array[Vector2i] = []
var _path_timer := 0.0
# Per-pathfind memo of _main.is_blocked() results. is_blocked() is expensive
# (it scans ~11 node groups across the whole scene tree per call), and BFS queries
# the same cells many times, so we evaluate each cell at most once per _find_path().
var _blocked_cache: Dictionary = {}
# Home-room tile bounds. Pathfinding is clamped here so a jump can't carry the
# search over the perimeter walls into open space, which would never terminate.
var _room_x0 := 0
var _room_y0 := 0

var _big_bounce_timer := BIG_BOUNCE_INTERVAL
var _pulse_time := 0.0

var _panel_a: Node2D = null
var _panel_b: Node2D = null
# Panels relocate each time hp drops past the next 100-hp threshold.
var _next_panel_hp := BOSS_MAX_HP - PANEL_SWITCH_STEP
# Seeded RNG drives panel placement so the sequence repeats on every reset.
var _panel_rng := RandomNumberGenerator.new()
# Counts placements (initial spawn = 1, then one per hp threshold).
var _panel_place_count := 0

# ── Setup ─────────────────────────────────────────────────────────────────────

func get_max_hp() -> int:
	return BOSS_MAX_HP

func _boss_scale() -> float:
	return BOSS_SCALE

func _ready() -> void:
	super._ready()
	add_to_group("bounce_boss")
	_panel_rng.seed = PANEL_RNG_SEED
	var room := _get_home_room()
	_room_x0 = room.x * 25
	_room_y0 = room.y * 12
	scale = Vector2(BOSS_SCALE, BOSS_SCALE)
	z_index = SORT_Z
	hp = BOSS_MAX_HP

func _register_health_bar() -> void:
	if _main == null:
		_main = get_tree().current_scene as Node2D
	if _main == null:
		call_deferred("_register_health_bar")
		return
	Utils.create_boss_health_bar(self, _main)
	_spawn_panels()

# ── Hitbox ────────────────────────────────────────────────────────────────────

# Boss keeps its origin at the tile top-left and sorts by its own rules.
func _ground_offset() -> float:
	return 0.0

func get_center() -> Vector2:
	return position + Vector2(16.0 * BOSS_SCALE, 16.0 * BOSS_SCALE)

# ── Panels ────────────────────────────────────────────────────────────────────

func _spawn_panels() -> void:
	_panel_a = BounceBossPanelScene.instantiate()
	_panel_b = BounceBossPanelScene.instantiate()
	_panel_a.positive = true
	_panel_b.positive = false
	_panel_a.id = PANEL_ID
	_panel_b.id = PANEL_ID
	_main.wall_tilemap.add_child(_panel_a)
	_main.wall_tilemap.add_child(_panel_b)
	_place_panels_randomly(false)

# Picks two distinct cells from the deterministic candidate list using the seeded
# RNG, so the same fight always produces the same panel positions. When animate is
# true the panels shrink/grow into place; otherwise they snap (initial / reset).
func _place_panels_randomly(animate: bool) -> void:
	if not is_instance_valid(_panel_a) or not is_instance_valid(_panel_b):
		return
	var candidates := _get_valid_panel_positions()
	if candidates.is_empty():
		return
	_panel_place_count += 1
	# The 5th/6th placements collide with earlier tiles under the base seed, so
	# nudge the stream by 1 to land them on different positions.
	if _panel_place_count == 5:
		_panel_rng.seed = PANEL_RNG_SEED + 1
	var i_a := _panel_rng.randi_range(0, candidates.size() - 1)
	var i_b := i_a
	if candidates.size() > 1:
		while i_b == i_a:
			i_b = _panel_rng.randi_range(0, candidates.size() - 1)
	var pos_a := Vector2(candidates[i_a].x * TILE_SIZE, candidates[i_a].y * TILE_SIZE)
	var pos_b := Vector2(candidates[i_b].x * TILE_SIZE, candidates[i_b].y * TILE_SIZE)
	if animate:
		_panel_a.move_to(pos_a)
		_panel_b.move_to(pos_b)
	else:
		_panel_a.snap_to(pos_a)
		_panel_b.snap_to(pos_b)

# Every cell at least PANEL_BORDER tiles from the room edges. Obstacles are
# ignored on purpose: panels may sit inside walls/objects, and the list must stay
# identical no matter what's in the room so placement is fully deterministic.
func _get_valid_panel_positions() -> Array[Vector2i]:
	var room := _get_home_room()
	var rx0 := room.x * 25
	var ry0 := room.y * 12
	var result: Array[Vector2i] = []
	for ty in range(ry0 + PANEL_BORDER, ry0 + 12 - PANEL_BORDER):
		for tx in range(rx0 + PANEL_BORDER, rx0 + 25 - PANEL_BORDER):
			result.append(Vector2i(tx, ty))
	return result

# Relocate the panels each time hp falls past the next 100-hp boundary.
func _check_panel_threshold() -> void:
	while hp <= _next_panel_hp and _next_panel_hp > 0:
		_next_panel_hp -= PANEL_SWITCH_STEP
		if is_instance_valid(_panel_a) and is_instance_valid(_panel_b):
			_place_panels_randomly(true)

# ── Main process ──────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	var in_room := _in_current_room()
	Utils.update_boss_health_bar(self, hp, BOSS_MAX_HP, in_room and not _dead, _main.modulate)
	if is_instance_valid(_panel_a):
		_panel_a.visible = in_room and not _dead
	if is_instance_valid(_panel_b):
		_panel_b.visible = in_room and not _dead
	if not in_room:
		return
	if _state == State.DYING:
		_process_death_arc()
		return

	_handle_beam()
	if _dead:
		return

	var player: Node2D = _main.player
	var target = player.get_body_center()

	match _state:
		State.CHASE:            _process_chase(delta, target)
		State.BIG_BOUNCE_WINDUP: _process_big_bounce_windup(delta, target)
		State.BIG_BOUNCE:       _process_big_bounce(delta)

	_sync_sprite(delta)
	_check_contact(player, target)

# ── Chase ─────────────────────────────────────────────────────────────────────

func _process_chase(delta: float, target: Vector2) -> void:
	_big_bounce_timer -= delta
	if _big_bounce_timer <= 0.0:
		_state = State.BIG_BOUNCE_WINDUP
		_state_timer = BIG_BOUNCE_WINDUP_DUR
		_pulse_time = 0.0
		_hop_state = HopState.IDLE
		_wait_timer = 0.0
		_path.clear()
		return

	if _hop_state == HopState.IDLE:
		_path_timer -= delta
		if _path_timer <= 0.0:
			_recalc_path(target)
			_path_timer = PATH_RECALC
		if _wait_timer > 0.0:
			_wait_timer -= delta
			var wait_t := 1.0 - (_wait_timer / maxf(_wait_duration, 0.001))
			var sq := sin(wait_t * PI)
			scale = scale.lerp(Vector2(BOSS_SCALE * LANDING_SQUASH_X, BOSS_SCALE * LANDING_SQUASH_Y), sq * 0.3)
		else:
			scale = scale.lerp(Vector2(BOSS_SCALE, BOSS_SCALE), SCALE_LERP * delta)
			_begin_next_hop()
	elif _hop_state == HopState.HOP:
		_process_hop(delta)

# ── Big bounce ────────────────────────────────────────────────────────────────

func _process_big_bounce_windup(delta: float, target: Vector2) -> void:
	_pulse_time += delta
	_state_timer -= delta
	var squeeze := sin(_pulse_time * TAU * 2.4) * 0.09
	scale = Vector2(BOSS_SCALE * (1.0 + squeeze), BOSS_SCALE * (1.0 - squeeze))
	if _state_timer <= 0.0:
		scale = Vector2(BOSS_SCALE, BOSS_SCALE)
		_hop_from = position
		var room := _get_home_room()
		var rx0 := float(room.x * 25 * TILE_SIZE)
		var ry0 := float(room.y * 12 * TILE_SIZE)
		_hop_to = Vector2(
			clampf(target.x - 32.0, rx0 + 16.0, rx0 + 25.0 * TILE_SIZE - 80.0),
			clampf(target.y - 32.0, ry0 + 16.0, ry0 + 12.0 * TILE_SIZE - 80.0)
		)
		_hop_time = 0.0
		_hop_t = 0.0
		_hop_duration = BIG_BOUNCE_DURATION
		_hop_height = BIG_BOUNCE_HEIGHT
		_hop_state = HopState.BIG_JUMP
		_state = State.BIG_BOUNCE

func _process_big_bounce(delta: float) -> void:
	_hop_time += delta * _get_move_speed()
	_hop_t = clampf(_hop_time / _hop_duration, 0.0, 1.0)
	position = _hop_from.lerp(_hop_to, _hop_t)
	var stretch := sin(_hop_t * PI)
	scale = Vector2(
		BOSS_SCALE * lerpf(1.0, 0.72, stretch),
		BOSS_SCALE * lerpf(1.0, 1.48, stretch)
	)
	if _hop_t >= 1.0:
		position = _hop_to
		_hop_state = HopState.IDLE
		_state = State.CHASE
		_wait_duration = WAIT_MIN * _wait_scale()
		_wait_timer = _wait_duration
		_big_bounce_timer = BIG_BOUNCE_INTERVAL
		scale = Vector2(BOSS_SCALE * LANDING_SQUASH_X, BOSS_SCALE * LANDING_SQUASH_Y)
		_main._trigger_shake(LONG_JUMP_SHAKE)

# ── Pathfinding ───────────────────────────────────────────────────────────────

func _get_move_speed() -> float:
	var hp_ratio := float(hp) / float(BOSS_MAX_HP)
	return lerpf(MAX_MOVE_SPEED, BASE_MOVE_SPEED, hp_ratio)

# Idle wait between hops shrinks as the boss speeds up — at 4x speed it pauses
# only a quarter as long.
func _wait_scale() -> float:
	return BASE_MOVE_SPEED / _get_move_speed()

func _recalc_path(target: Vector2) -> void:
	var from := _world_to_grid(position)
	var to := _world_to_grid(target)
	_path = _find_path(from, to)

func _begin_next_hop() -> void:
	if _path.is_empty():
		return
	var from_gp := _world_to_grid(position)
	var next_gp: Vector2i = _path[0]
	var d := next_gp - from_gp
	var dist := absi(d.x) + absi(d.y)
	var block_jump := dist == JUMP_TILES and (d.x == 0 or d.y == 0)
	if dist != 1 and not block_jump:
		_path.clear()
		return
	_path.pop_front()
	_hop_from = position
	_hop_to = _grid_to_world(next_gp)
	_hop_time = 0.0
	_hop_t = 0.0
	if block_jump:
		_hop_duration = JUMP_HOP_DURATION
		_hop_height = JUMP_HOP_HEIGHT
	else:
		_hop_duration = HOP_DURATION
		_hop_height = HOP_HEIGHT
	_hop_state = HopState.HOP

func _process_hop(delta: float) -> void:
	_hop_time += delta * _get_move_speed()
	_hop_t = clampf(_hop_time / _hop_duration, 0.0, 1.0)
	position = _hop_from.lerp(_hop_to, _hop_t)
	var stretch := sin(_hop_t * PI)
	scale = Vector2(
		BOSS_SCALE * lerpf(1.0, HOP_STRETCH_X, stretch),
		BOSS_SCALE * lerpf(1.0, HOP_STRETCH_Y, stretch)
	)
	if _hop_t >= 1.0:
		position = _hop_to
		_hop_state = HopState.IDLE
		_wait_duration = randf_range(WAIT_MIN, WAIT_MAX) * _wait_scale()
		_wait_timer = _wait_duration
		scale = Vector2(BOSS_SCALE * LANDING_SQUASH_X, BOSS_SCALE * LANDING_SQUASH_Y)
		_main._trigger_shake(LAND_SHAKE)

func _find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	_blocked_cache.clear()
	if from == to:
		return []
	var parents: Dictionary = {from: null}
	var queue: Array[Vector2i] = [from]
	var found := false
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == to:
			found = true
			break
		for nb in _path_neighbors(cur):
			if not parents.has(nb):
				parents[nb] = cur
				queue.append(nb)
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
		if _is_walkable_boss(step):
			result.append(step)
		elif _is_walkable_boss(gp + d * JUMP_TILES):
			# Step is blocked but there's clear ground beyond a single block —
			# the boss can leap over it.
			result.append(gp + d * JUMP_TILES)
	return result

func _cell_blocked(gp: Vector2i) -> bool:
	var cached: Variant = _blocked_cache.get(gp)
	if cached != null:
		return cached
	var result = _main.is_blocked(gp)
	_blocked_cache[gp] = result
	return result

func _is_walkable_boss(gp: Vector2i) -> bool:
	# The boss paths as a single 32x32 tile, clamped inside the home room.
	if gp.x < _room_x0 or gp.x >= _room_x0 + 25:
		return false
	if gp.y < _room_y0 or gp.y >= _room_y0 + 12:
		return false
	return not _cell_blocked(gp)

func _world_to_grid(pos: Vector2) -> Vector2i:
	return GridUtils.to_grid(pos)

func _grid_to_world(gp: Vector2i) -> Vector2:
	return GridUtils.to_world(gp)

# ── Visual ────────────────────────────────────────────────────────────────────

func _sync_sprite(delta: float) -> void:
	var arc_world := 0.0
	if _hop_state in [HopState.HOP, HopState.BIG_JUMP]:
		arc_world = sin(_hop_t * PI) * _hop_height
	_visual_pos = _visual_pos.lerp(position, minf(1.0, SPRITE_LAG_SPEED * delta))
	var sx := maxf(scale.x, 0.001)
	var sy := maxf(scale.y, 0.001)
	var center_offset := Vector2(16.0 * BOSS_SCALE / sx - 16.0, 16.0 * BOSS_SCALE / sy - 16.0)
	_sprite.position = Vector2(
		(_visual_pos.x - position.x) / sx,
		(_visual_pos.y - position.y) / sy
	) + center_offset + Vector2(0.0, -arc_world / sy)

# ── Contact ───────────────────────────────────────────────────────────────────

func _can_hurt_player() -> bool:
	return _state != State.BIG_BOUNCE

func _check_contact(player: Node2D, target: Vector2) -> void:
	if _state == State.DYING:
		return
	if not _can_hurt_player():
		return
	if not player.movement_locked and (target - get_center()).length() < BOSS_CONTACT_DIST:
		_main._reset_room()

# ── Wind damage ───────────────────────────────────────────────────────────────

# The boss is immune to the electric beam; it only takes damage from fan wind,
# the same way the bounce enemies do.
func _handle_beam() -> void:
	if _dead:
		return
	for fan in get_tree().get_nodes_in_group("fans"):
		if fan.is_active() and _fan_hits_boss(fan):
			hp -= 1
			_main._trigger_shake(2.0)
			Utils.shake_boss_health_bar(self)
			_check_panel_threshold()
			if hp <= 0:
				hp = 0
				_boss_die()
			return

# The boss is hit if any tile of its 2x2 footprint sits in the fan's airflow, a
# much larger wind hitbox than a single center-point check.
func _fan_hits_boss(fan) -> bool:
	var gp := _world_to_grid(position)
	for dy in 2:
		for dx in 2:
			var p := Vector2(
				float(gp.x + dx) * TILE_SIZE + 16.0,
				float(gp.y + dy) * TILE_SIZE + 16.0)
			if fan.is_position_in_airflow(p):
				return true
	return false

# ── Death ─────────────────────────────────────────────────────────────────────

func _boss_die() -> void:
	_state = State.DYING
	_dead = true
	if is_instance_valid(_panel_a):
		_panel_a.visible = false
	if is_instance_valid(_panel_b):
		_panel_b.visible = false
	SaveManager.notify_boss_defeated()
	_do_death_shakes()
	if _death_tween:
		_death_tween.kill()
	_death_tween = create_tween()
	_death_tween.tween_callback(_launch_death_arc).set_delay(1.5)

func _do_death_shakes() -> void:
	for i in 3:
		await get_tree().create_timer(0.5 * i).timeout
		if not is_instance_valid(self):
			return
		_main._trigger_shake(30.0)

# ── Reset ─────────────────────────────────────────────────────────────────────

func reset() -> void:
	if _death_tween:
		_death_tween.kill()
		_death_tween = null
	Engine.time_scale = 1.0
	super.reset()
	hp = BOSS_MAX_HP
	_state = State.CHASE
	_hop_state = HopState.IDLE
	_path.clear()
	_path_timer = 0.0
	_hop_time = 0.0
	_hop_t = 0.0
	_wait_timer = 0.0
	_wait_duration = 0.0
	_big_bounce_timer = BIG_BOUNCE_INTERVAL
	_pulse_time = 0.0
	_arc_started = false
	_next_panel_hp = BOSS_MAX_HP - PANEL_SWITCH_STEP
	# Re-seed so panel placement repeats identically every reset.
	_panel_rng.seed = PANEL_RNG_SEED
	_panel_place_count = 0
	scale = Vector2(BOSS_SCALE, BOSS_SCALE)
	rotation = 0.0
	z_index = SORT_Z
	if is_instance_valid(_panel_a) and is_instance_valid(_panel_b):
		_place_panels_randomly(false)

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		Utils.remove_boss_health_bar(self)
		if is_instance_valid(_panel_a):
			_panel_a.queue_free()
		if is_instance_valid(_panel_b):
			_panel_b.queue_free()
