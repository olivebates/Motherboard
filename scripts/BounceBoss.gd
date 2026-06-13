extends "res://scripts/WaterEnemy.gd"

enum State { CHASE, WOBBLE, BIG_BOUNCE_WINDUP, BIG_BOUNCE, DYING }
enum HopState { IDLE, HOP, BIG_JUMP }

const BOSS_MAX_HP := 5
const BOSS_SCALE := 2.0
const SORT_Z := 64

const BASE_MOVE_SPEED := 0.30
const MAX_MOVE_SPEED := 0.75

const PATH_RECALC := 0.35
const SCALE_LERP := 15.0
const SPRITE_LAG_SPEED := 16.0

const WAIT_MIN := 0.5
const WAIT_MAX := 0.8
const HOP_DURATION := 0.28
const HOP_HEIGHT := 12.0
const HOP_STRETCH_X := 0.88
const HOP_STRETCH_Y := 1.12
const LANDING_SQUASH_X := 1.18
const LANDING_SQUASH_Y := 0.82

const BIG_BOUNCE_INTERVAL := 5.0
const BIG_BOUNCE_WINDUP_DUR := 0.8
const BIG_BOUNCE_DURATION := 0.7
const BIG_BOUNCE_HEIGHT := 90.0

const SPAWN_INTERVAL_MIN := 2.0
const SPAWN_INTERVAL_MAX := 4.0
const WOBBLE_DURATION := 1.0
const SPAWN_DIST := 96.0

const BOSS_CONTACT_DIST := 30.0

const _CARDINALS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]

const BounceEnemyScene = preload("res://scenes/enemies/BounceEnemy.tscn")
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

var _big_bounce_timer := BIG_BOUNCE_INTERVAL
var _spawn_timer := SPAWN_INTERVAL_MAX
var _pulse_time := 0.0

var _panel_a: Node2D = null
var _panel_b: Node2D = null
var _object_falling := false
var _falling_obj: Node2D = null

var _death_tween: Tween
var _arc_started := false

# ── Setup ─────────────────────────────────────────────────────────────────────

func get_max_hp() -> int:
	return BOSS_MAX_HP

func _ready() -> void:
	super._ready()
	add_to_group("bounce_boss")
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

func get_center() -> Vector2:
	return position + Vector2(16.0 * BOSS_SCALE, 16.0 * BOSS_SCALE)

# ── Panels ────────────────────────────────────────────────────────────────────

func _spawn_panels() -> void:
	_panel_a = BounceBossPanelScene.instantiate()
	_panel_b = BounceBossPanelScene.instantiate()
	_panel_a.positive = true
	_panel_b.positive = false
	_main.wall_tilemap.add_child(_panel_a)
	_main.wall_tilemap.add_child(_panel_b)
	_place_panels_randomly()

func _place_panels_randomly() -> void:
	var candidates := _get_valid_panel_positions()
	candidates.shuffle()
	if candidates.size() >= 1:
		_panel_a.position = Vector2(candidates[0].x * TILE_SIZE, candidates[0].y * TILE_SIZE)
	if candidates.size() >= 2:
		_panel_b.position = Vector2(candidates[1].x * TILE_SIZE, candidates[1].y * TILE_SIZE)

func _get_valid_panel_positions() -> Array[Vector2i]:
	var room := _get_home_room()
	var rx0 := room.x * 25
	var ry0 := room.y * 12
	var border := ceili(96.0 / float(TILE_SIZE))
	var result: Array[Vector2i] = []
	for ty in range(ry0 + border, ry0 + 12 - border):
		for tx in range(rx0 + border, rx0 + 25 - border):
			var gp := Vector2i(tx, ty)
			if not _main.is_blocked(gp):
				result.append(gp)
	return result

func _check_panels() -> void:
	if _object_falling:
		return
	if not is_instance_valid(_panel_a) or not is_instance_valid(_panel_b):
		return
	if _panel_a._active and _panel_b._active:
		_drop_object()

func _drop_object() -> void:
	_object_falling = true
	_place_panels_randomly()
	if is_instance_valid(_falling_obj):
		_falling_obj.queue_free()
	var obj := Sprite2D.new()
	obj.texture = load("res://Sprites/player/stake.png")
	obj.centered = false
	var room := _get_home_room()
	var ry0 := float(room.y * 12 * TILE_SIZE)
	var boss_center := get_center()
	obj.position = Vector2(boss_center.x - 8.0, ry0)
	_main.wall_tilemap.add_child(obj)
	_falling_obj = obj
	var t := obj.create_tween()
	t.tween_property(obj, "position:y", boss_center.y - 8.0, 0.45)
	t.tween_callback(_on_object_landed.bind(obj))

func _on_object_landed(obj: Node2D) -> void:
	if is_instance_valid(obj):
		obj.queue_free()
	if _falling_obj == obj:
		_falling_obj = null
	_object_falling = false
	if _dead:
		return
	hp -= 1
	_main._trigger_shake(3.0)
	Utils.shake_boss_health_bar(self)
	if hp <= 0:
		hp = 0
		_boss_die()

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
		if _dead and _arc_started:
			_visual_pos = position
			var sx := maxf(scale.x, 0.001)
			var sy := maxf(scale.y, 0.001)
			_sprite.position = Vector2(16.0 * BOSS_SCALE / sx - 16.0, 16.0 * BOSS_SCALE / sy - 16.0)
			var room := _get_home_room()
			var rx0 := room.x * 25 * TILE_SIZE
			var ry0 := room.y * 12 * TILE_SIZE
			var rx1 := rx0 + 25 * TILE_SIZE
			var ry1 := ry0 + 12 * TILE_SIZE
			if position.x < rx0 or position.x > rx1 or position.y < ry0 or position.y > ry1:
				_on_death_complete()
		return

	_check_panels()

	var player: Node2D = _main.player
	var target = player.get_body_center()

	match _state:
		State.CHASE:            _process_chase(delta, target)
		State.BIG_BOUNCE_WINDUP: _process_big_bounce_windup(delta, target)
		State.BIG_BOUNCE:       _process_big_bounce(delta)
		State.WOBBLE:           _process_wobble(delta)

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

	if hp < BOSS_MAX_HP * 0.8:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			var hp_ratio := float(hp) / float(BOSS_MAX_HP)
			_spawn_timer = lerpf(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX, clampf(hp_ratio / 0.8, 0.0, 1.0))
			_state = State.WOBBLE
			_state_timer = WOBBLE_DURATION
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
		_wait_duration = WAIT_MIN
		_wait_timer = _wait_duration
		_big_bounce_timer = BIG_BOUNCE_INTERVAL
		scale = Vector2(BOSS_SCALE * LANDING_SQUASH_X, BOSS_SCALE * LANDING_SQUASH_Y)

# ── Wobble / spawn ────────────────────────────────────────────────────────────

func _process_wobble(delta: float) -> void:
	_state_timer -= delta
	_pulse_time += delta
	var wobble := sin(_pulse_time * TAU * 4.5) * 0.11
	scale = Vector2(BOSS_SCALE * (1.0 + wobble), BOSS_SCALE * (1.0 - wobble))
	if _state_timer <= 0.0:
		scale = Vector2(BOSS_SCALE, BOSS_SCALE)
		_spawn_bounce_enemies()
		_state = State.CHASE

func _spawn_bounce_enemies() -> void:
	var player_center = _main.player.get_body_center()
	var dirs := _CARDINALS.duplicate()
	dirs.shuffle()
	dirs.pop_back()
	for d in dirs:
		var spawn_pos = player_center + Vector2(float(d.x), float(d.y)) * SPAWN_DIST
		var tile := Vector2i(floori(spawn_pos.x / TILE_SIZE), floori(spawn_pos.y / TILE_SIZE))
		if _main.is_blocked(tile):
			continue
		var e := BounceEnemyScene.instantiate()
		e.position = Vector2(float(tile.x) * TILE_SIZE, float(tile.y) * TILE_SIZE)
		e.boss_spawned = true
		_main.wall_tilemap.add_child(e)

# ── Pathfinding ───────────────────────────────────────────────────────────────

func _get_move_speed() -> float:
	var hp_ratio := float(hp) / float(BOSS_MAX_HP)
	return lerpf(MAX_MOVE_SPEED, BASE_MOVE_SPEED, hp_ratio)

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
	if absi(d.x) + absi(d.y) != 1:
		_path.clear()
		return
	_path.pop_front()
	_hop_from = position
	_hop_to = _grid_to_world(next_gp)
	_hop_time = 0.0
	_hop_t = 0.0
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
		_wait_duration = randf_range(WAIT_MIN, WAIT_MAX)
		_wait_timer = _wait_duration
		scale = Vector2(BOSS_SCALE * LANDING_SQUASH_X, BOSS_SCALE * LANDING_SQUASH_Y)

func _find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
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
	return result

func _is_walkable_boss(gp: Vector2i) -> bool:
	for dy in 2:
		for dx in 2:
			if _main.is_blocked(gp + Vector2i(dx, dy)):
				return false
	return true

func _world_to_grid(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE_SIZE), floori(pos.y / TILE_SIZE))

func _grid_to_world(gp: Vector2i) -> Vector2:
	return Vector2(float(gp.x) * TILE_SIZE, float(gp.y) * TILE_SIZE)

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
	if _state == State.DYING or _state == State.WOBBLE:
		return
	if not _can_hurt_player():
		return
	if not player.movement_locked and (target - get_center()).length() < BOSS_CONTACT_DIST:
		_main._reset_room()

# ── Beam override ─────────────────────────────────────────────────────────────

func _handle_beam() -> void:
	pass

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
	var home := _get_home_room()
	var rx0 := home.x * 25
	var ry0 := home.y * 12
	for e in get_tree().get_nodes_in_group("bounce_enemies"):
		if not is_instance_valid(e):
			continue
		var ep = e.get("boss_spawned")
		if not ep:
			continue
		var egp := Vector2i(floori(e._start_pos.x / TILE_SIZE), floori(e._start_pos.y / TILE_SIZE))
		if egp.x >= rx0 and egp.x < rx0 + 25 and egp.y >= ry0 and egp.y < ry0 + 12:
			e.queue_free()
	_death_tween = create_tween()
	_death_tween.tween_callback(_launch_death_arc).set_delay(1.5)

func _do_death_shakes() -> void:
	for i in 3:
		await get_tree().create_timer(0.5 * i).timeout
		if not is_instance_valid(self):
			return
		_main._trigger_shake(30.0)

func _launch_death_arc() -> void:
	_arc_started = true
	z_index = 100
	var start := position
	var dir := 1.0 if randf() > 0.5 else -1.0
	_death_tween = create_tween()
	_death_tween.tween_method(func(p: float) -> void:
		position.x = start.x + dir * 180.0 * p
		position.y = start.y - 480.0 * p + 780.0 * p * p
		rotation = dir * p * 0.8
	, 0.0, 2.5, 3.5)

func _on_death_complete() -> void:
	if not _arc_started:
		return
	_arc_started = false
	if _death_tween:
		_death_tween.kill()
	_sprite.visible = false
	_particles.restart()
	scale = Vector2(BOSS_SCALE, BOSS_SCALE)
	for door in get_tree().get_nodes_in_group("boss_doors"):
		if is_instance_valid(door):
			door.open()

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
	_spawn_timer = SPAWN_INTERVAL_MAX
	_pulse_time = 0.0
	_arc_started = false
	_object_falling = false
	scale = Vector2(BOSS_SCALE, BOSS_SCALE)
	rotation = 0.0
	z_index = SORT_Z
	if is_instance_valid(_falling_obj):
		_falling_obj.queue_free()
		_falling_obj = null
	if is_instance_valid(_panel_a) and is_instance_valid(_panel_b):
		_place_panels_randomly()

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		Utils.remove_boss_health_bar(self)
		if is_instance_valid(_panel_a):
			_panel_a.queue_free()
		if is_instance_valid(_panel_b):
			_panel_b.queue_free()
