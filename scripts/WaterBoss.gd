extends "res://scripts/WaterEnemy.gd"

enum State { CHASE, WINDUP, CHARGE, SPAWN_TELEGRAPH, DYING }

const BOSS_MAX_HP := 1000
const BASE_SPEED = 40.0
const MAX_SPEED = 70.0
const MINION_CAP = 2
const MINION_CAP_LOW_HP = 4
const BOSS_SCALE = 2.0

const SPAWN_INTERVAL = 4.0
const CHARGE_INTERVAL = 3.0
const CHARGE_WINDUP = 1.0
const CHARGE_SPEED = 240.0
const CHARGE_RANGE = 5.0 * 32.0
const TELEGRAPH_DURATION = 0.7
const BOSS_SPRITE_SPEED = 10.0

const WaterEnemyScene = preload("res://scenes/enemies/WaterEnemy.tscn")

@export var debug_low_hp: bool = false

var _spawn_timer = SPAWN_INTERVAL
var _charge_timer = CHARGE_INTERVAL
var _charge_speed_current := 0.0
var _beam_time := 0.0
var _was_in_beam := false
var _phase2_triggered := false
var _in_phase_transition := false
var _state: State = State.CHASE
var _state_timer := 0.0
var _charge_dir := Vector2.ZERO
var _pulse_time := 0.0

func get_max_hp() -> int:
	return BOSS_MAX_HP

func _boss_scale() -> float:
	return BOSS_SCALE

func _ready() -> void:
	super._ready()
	add_to_group("water_boss")
	scale = Vector2(BOSS_SCALE, BOSS_SCALE)
	hp = get_max_hp()
	if debug_low_hp:
		hp = 10
	call_deferred("_register_health_bar")

func _register_health_bar() -> void:
	if _main == null:
		_main = get_tree().current_scene as Node2D
	if _main == null:
		call_deferred("_register_health_bar")
		return
	Utils.create_boss_health_bar(self, _main)

# ── Hitbox ────────────────────────────────────────────────────────────────────

# Boss keeps its origin at the tile top-left and sorts by its own rules.
func _ground_offset() -> float:
	return 0.0

func get_center() -> Vector2:
	return position + Vector2(16.0, 16.0) * scale.x

func _get_radius() -> float:
	return 16.0 * scale.x - 4.0

func _scaled_hitbox() -> Rect2:
	return Rect2(position + Vector2(2.0, 2.0) * scale.x, Vector2(28.0, 28.0) * scale.x)

func _move_x(dx: float) -> void:
	if dx == 0.0:
		return
	var rect = _scaled_hitbox()
	var probe = rect.merge(Rect2(rect.position + Vector2(dx, 0.0), rect.size))
	position.x += MoveUtils.sweep_x(rect, dx, _main.get_player_blocking_rects(probe), CONTACT_EPS)

func _move_y(dy: float) -> void:
	if dy == 0.0:
		return
	var rect = _scaled_hitbox()
	var probe = rect.merge(Rect2(rect.position + Vector2(0.0, dy), rect.size))
	position.y += MoveUtils.sweep_y(rect, dy, _main.get_player_blocking_rects(probe), CONTACT_EPS)

# ── Main process ──────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	Utils.update_boss_health_bar(self, hp, BOSS_MAX_HP, _in_current_room() and not _dead, _main.modulate)
	if not _in_current_room():
		return
	if _state == State.DYING:
		_process_death_arc()
		return

	var player: Node2D = _main.player
	var target = player.get_body_center()

	# Beam damage
	var in_beam = _main.electric_beam.active and \
		_main.electric_beam.is_point_on_beam(get_center(), _get_radius())
	if in_beam:
		hp -= 1
		_beam_time += delta
		_main._trigger_shake(1.0)
		Utils.shake_boss_health_bar(self)
		if not _was_in_beam:
			_do_freeze_frame()
		if _beam_time >= 1.5:
			_teleport_from_beam()
		if hp <= 0:
			hp = 0
			_boss_die()
			return
	else:
		_beam_time = 0.0
	_was_in_beam = in_beam

	# Phase 2 at 50% HP
	if not _phase2_triggered and hp < BOSS_MAX_HP * 0.5:
		_phase2_triggered = true
		_trigger_phase2()

	if _in_phase_transition:
		_visual_pos = _visual_pos.lerp(position, minf(1.0, BOSS_SPRITE_SPEED * delta))
		var _sx = maxf(scale.x, 0.001)
		var _sy = maxf(scale.y, 0.001)
		_sprite.position = Vector2((_visual_pos.x - position.x) / _sx, (_visual_pos.y - position.y) / _sy) + Vector2(16.0 * BOSS_SCALE / _sx - 16.0, 16.0 * BOSS_SCALE / _sy - 16.0)
		return

	match _state:
		State.CHASE:           _process_chase(delta, player, target)
		State.WINDUP:          _process_windup(delta)
		State.CHARGE:          _process_charge(delta, player, target)
		State.SPAWN_TELEGRAPH: _process_telegraph(delta)

	_visual_pos = _visual_pos.lerp(position, minf(1.0, BOSS_SPRITE_SPEED * delta))
	# Offset sprite so squash/stretch and scale-pulse originate from the sprite center
	var sx = maxf(scale.x, 0.001)
	var sy = maxf(scale.y, 0.001)
	var center_offset = Vector2(16.0 * BOSS_SCALE / sx - 16.0, 16.0 * BOSS_SCALE / sy - 16.0)
	_sprite.position = Vector2((_visual_pos.x - position.x) / sx, (_visual_pos.y - position.y) / sy) + center_offset

	if _state != State.SPAWN_TELEGRAPH:
		if not player.movement_locked and (target - get_center()).length() < _get_radius() + 7.0:
			_main._reset_room()

# ── States ────────────────────────────────────────────────────────────────────

func _process_chase(delta: float, player: Node2D, target: Vector2) -> void:
	var hp_ratio = float(hp) / float(BOSS_MAX_HP)
	var spd = BASE_SPEED + (MAX_SPEED - BASE_SPEED) * (1.0 - hp_ratio)
	var to_player = target - get_center()
	if to_player.length() > 1.0:
		var vel = to_player.normalized() * spd * delta
		_move_x(vel.x)
		_move_y(vel.y)

	if hp < BOSS_MAX_HP * 0.8:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			#var hp_ratio = float(hp) / float(BOSS_MAX_HP)
			var phase_ratio = clampf(hp_ratio / 0.8, 0.0, 1.0)
			_spawn_timer = lerpf(2.0, 4.0, phase_ratio)
			_state = State.SPAWN_TELEGRAPH
			_state_timer = TELEGRAPH_DURATION
			_pulse_time = 0.0
			return

	# Charge triggers when cooldown is ready and player is within range
	_charge_timer = maxf(_charge_timer - delta, 0.0)
	if _charge_timer == 0.0 and to_player.length() <= CHARGE_RANGE:
		_state = State.WINDUP
		_state_timer = CHARGE_WINDUP
		_pulse_time = 0.0

func _process_windup(delta: float) -> void:
	_pulse_time += delta
	_state_timer -= delta
	var squeeze = sin(_pulse_time * TAU * 2.4) * 0.075
	scale = Vector2(BOSS_SCALE * (1.0 + squeeze), BOSS_SCALE * (1.0 - squeeze))
	if _state_timer <= 0.0:
		scale = Vector2(BOSS_SCALE, BOSS_SCALE)
		_charge_dir = (_main.player.get_body_center() - get_center()).normalized()
		_charge_speed_current = CHARGE_SPEED
		_pulse_time = 0.0
		_state = State.CHARGE

func _process_charge(delta: float, player: Node2D, _target: Vector2) -> void:
	var hp_ratio = float(hp) / float(BOSS_MAX_HP)
	var normal_speed = BASE_SPEED + (MAX_SPEED - BASE_SPEED) * (1.0 - hp_ratio)
	_charge_speed_current = lerpf(_charge_speed_current, normal_speed, 5.0 * delta)
	_move_x(_charge_dir.x * _charge_speed_current * delta)
	_move_y(_charge_dir.y * _charge_speed_current * delta)
	if absf(_charge_speed_current - normal_speed) < 2.0:
		_charge_speed_current = normal_speed
		_charge_timer = CHARGE_INTERVAL
		_state = State.CHASE

func _process_telegraph(delta: float) -> void:
	_state_timer -= delta
	_pulse_time += delta
	var pulse = 1.0 + sin(_pulse_time * TAU * 5.0) * 0.12
	scale = Vector2(BOSS_SCALE * pulse, BOSS_SCALE * pulse)
	if _state_timer <= 0.0:
		scale = Vector2(BOSS_SCALE, BOSS_SCALE)
		_spawn_minions()
		_state = State.CHASE

# ── Effects ───────────────────────────────────────────────────────────────────

func _do_death_shakes() -> void:
	for i in 3:
		await get_tree().create_timer(0.5 * i).timeout
		if not is_instance_valid(self):
			return
		_main._trigger_shake(30.0)

func _do_freeze_frame() -> void:
	Engine.time_scale = 0.05
	get_tree().create_timer(0.06, true, false, true).timeout.connect(
		func(): Engine.time_scale = 1.0)

func _screen_flash() -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 28
	_main.add_child(canvas)
	var rect = ColorRect.new()
	rect.color = Color(1.0, 1.0, 1.0, 0.85)
	rect.size = Vector2(800.0, 384.0)
	canvas.add_child(rect)
	var t = create_tween()
	t.tween_property(rect, "color:a", 0.0, 0.4)
	t.tween_callback(canvas.queue_free)

func _trigger_phase2() -> void:
	_in_phase_transition = true
	_main._trigger_shake(2.5)
	await get_tree().create_timer(0.6).timeout
	_in_phase_transition = false

func _boss_die() -> void:
	_state = State.DYING
	_dead = true
	SaveManager.notify_boss_defeated()
	_do_death_shakes()
	if _death_tween:
		_death_tween.kill()
	# Delete water enemies immediately
	var home = _get_home_room()
	var rx0 = home.x * 25
	var ry0 = home.y * 12
	for e in get_tree().get_nodes_in_group("water_enemies"):
		if not is_instance_valid(e) or e == self:
			continue
		var egp = Vector2i(floori(e._start_pos.x / TILE_SIZE), floori(e._start_pos.y / TILE_SIZE))
		if egp.x >= rx0 and egp.x < rx0 + 25 and egp.y >= ry0 and egp.y < ry0 + 12:
			e.queue_free()
	# Freeze for 1.0s then arc off screen
	_death_tween = create_tween()
	_death_tween.tween_callback(_launch_death_arc).set_delay(1.5)

# ── Teleport ──────────────────────────────────────────────────────────────────

func _teleport_from_beam() -> void:
	_beam_time = 0.0
	# Abort wind-up — reset cooldown so it doesn't immediately re-trigger
	if _state == State.WINDUP:
		_state = State.CHASE
		_charge_timer = CHARGE_INTERVAL
		_pulse_time = 0.0
	var player_tile = Vector2i(
		floori(_main.player.get_body_center().x / TILE_SIZE),
		floori(_main.player.get_body_center().y / TILE_SIZE))
	var room = _get_home_room()
	var rx0 = room.x * 25
	var ry0 = room.y * 12
	var border_tiles = ceili(64.0 / TILE_SIZE)
	var size_tiles = ceili(float(BOSS_SCALE))
	var candidates: Array = []
	for ty in range(ry0 + border_tiles, ry0 + 12 - size_tiles + 1 - border_tiles):
		for tx in range(rx0 + border_tiles, rx0 + 25 - size_tiles + 1 - border_tiles):
			var tile = Vector2i(tx, ty)
			if (Vector2(tile) - Vector2(player_tile)).length() < 5.0:
				continue
			var fits = true
			for oy in range(size_tiles):
				for ox in range(size_tiles):
					if _main.is_blocked(tile + Vector2i(ox, oy)):
						fits = false
						break
				if not fits:
					break
			if fits:
				candidates.append(tile)
	if candidates.is_empty():
		return
	var chosen: Vector2i = candidates[randi() % candidates.size()]
	position = Vector2(chosen.x * TILE_SIZE, chosen.y * TILE_SIZE)
	# _visual_pos intentionally not updated — sprite slides from old position to new

# ── Minions ───────────────────────────────────────────────────────────────────

func _count_minions() -> int:
	var home = _get_home_room()
	var rx0 = home.x * 25
	var ry0 = home.y * 12
	var count = 0
	for e in get_tree().get_nodes_in_group("water_enemies"):
		if not is_instance_valid(e) or e == self:
			continue
		# Dead minions still linger in the tree (Enemy._die() only hides them), so
		# skip them — a slot frees up the moment a spawned minion is killed, letting
		# the boss replace it while still honouring the cap.
		if e._dead:
			continue
		var egp = Vector2i(floori(e._start_pos.x / TILE_SIZE), floori(e._start_pos.y / TILE_SIZE))
		if egp.x >= rx0 and egp.x < rx0 + 25 and egp.y >= ry0 and egp.y < ry0 + 12:
			count += 1
	return count

func _spawn_minions() -> void:
	var cap = MINION_CAP_LOW_HP if hp < BOSS_MAX_HP * 0.2 else MINION_CAP
	var slots = cap - _count_minions()
	if slots <= 0:
		return
	var c = get_center()
	var offsets = [Vector2(-TILE_SIZE * 3, 0.0), Vector2(TILE_SIZE * 3, 0.0)]
	for off in offsets:
		if slots <= 0:
			break
		_spawn_water_enemy(c + off)
		slots -= 1

func _spawn_water_enemy(spawn_pos: Vector2) -> void:
	var tile_pos = Vector2(floori(spawn_pos.x / TILE_SIZE) * TILE_SIZE,
		floori(spawn_pos.y / TILE_SIZE) * TILE_SIZE)
	if (tile_pos - _main.player.get_body_center()).length() < 96.0:
		return
	var e = WaterEnemyScene.instantiate()
	e.position = tile_pos
	e.boss_spawned = true
	_main.wall_tilemap.add_child(e)

# ── Reset / cleanup ───────────────────────────────────────────────────────────

func reset() -> void:
	if _death_tween:
		_death_tween.kill()
		_death_tween = null
	Engine.time_scale = 1.0
	_in_phase_transition = false
	super.reset()
	hp = BOSS_MAX_HP
	_spawn_timer = SPAWN_INTERVAL
	_charge_timer = CHARGE_INTERVAL
	_charge_speed_current = 0.0
	_beam_time = 0.0
	_was_in_beam = false
	_phase2_triggered = false
	_arc_started = false
	_state = State.CHASE
	_state_timer = 0.0
	_pulse_time = 0.0
	scale = Vector2(BOSS_SCALE, BOSS_SCALE)
	rotation = 0.0
	z_index = 0

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		Utils.remove_boss_health_bar(self)
