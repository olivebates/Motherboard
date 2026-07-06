extends "res://scripts/WaterEnemy.gd"

enum State { CHASE, SPAWN_TELEGRAPH, DYING }

const BOSS_MAX_HP := 1200
const BASE_SPEED = 40.0
const MAX_SPEED = 70.0
const MINION_CAP = 2               # cap before the boss has spawned any minions
const MINION_CAP_AFTER_FIRST = 6   # cap after the 1st spawn wave
const MINION_CAP_AFTER_SECOND = 8  # cap after the 2nd (and every later) spawn wave
const LAND_SHAKE = 2.0             # screen shake thud on each bounce landing
# The boss occupies a 2×2-tile footprint. Its sprite sheets are now authored at
# this size natively, so the node itself is NOT scaled up (scale stays 1); this
# constant only drives the logical geometry (hitbox / center / radius / teleport).
const LOGICAL_SCALE = 2.0

const SPAWN_INTERVAL = 15.0
const BOSS_SPRITE_SPEED = 10.0

const WaterEnemyScene = preload("res://scenes/enemies/WaterEnemy.tscn")

# ── Sprite animation sheets ────────────────────────────────────────────────────
# Bounce locomotion. 27 frames (~92×92, sheet 2489×92). The boss only translates
# during the airborne middle frames: the first 5 (windup) and last 7 (landing) hold.
const JUMP_TEX = preload("res://Sprites/enemies/WaterGuy/Water_Boss_Jump-Sheet.webp")
const JUMP_FRAMES = 27
const JUMP_FW = 2489.0 / 27.0    # ~92.2px per cell (sheet width isn't an exact ×27)
const JUMP_DURATION = 1.125    # 0.9 / 0.8 — 20% slower
const JUMP_FPS = JUMP_FRAMES / JUMP_DURATION
const JUMP_MOVE_START = 5        # first frame that moves
const JUMP_MOVE_END = 20         # exclusive — frames [5,20) move, last 7 hold
const JUMP_MOVE_MULT = 2.0       # distance covered per hop (×base chase speed)
# Plays once before minions appear; the boss is frozen in place while it runs.
const SPAWN_TEX = preload("res://Sprites/enemies/WaterGuy/Water_Spawn_Enemies_Large-Sheet.webp")
const SPAWN_FRAMES = 16
const SPAWN_FW = 96.0            # sheet 1536×96 → 96px square cells
const SPAWN_DURATION = 1.0     # 0.8 / 0.8 — 20% slower
const SPAWN_FPS = SPAWN_FRAMES / SPAWN_DURATION
# Only chases (and animates) when the player is within this range; idles otherwise.
const BOSS_MOVE_RADIUS = 256.0

@export var debug_low_hp: bool = false

var _spawn_timer = SPAWN_INTERVAL
var _beam_time := 0.0
var _was_in_beam := false
var _phase2_triggered := false
var _in_phase_transition := false
var _state: State = State.CHASE
var _jump_time := 0.0
var _spawn_time := 0.0
var _anim_frame := 0
var _spawn_count := 0    # number of minion-spawn waves completed (drives the cap)
var _frame_half := JUMP_FW / 2.0

func get_max_hp() -> int:
	return BOSS_MAX_HP

func _ready() -> void:
	super._ready()
	add_to_group("water_boss")
	scale = Vector2(1.0, 1.0)   # sprites are authored at full size; no node scaling
	hp = get_max_hp()
	if debug_low_hp:
		hp = 10
	_apply_frame(JUMP_TEX, JUMP_FRAMES, 0, JUMP_FW)
	call_deferred("_register_health_bar")

# Swaps the sprite sheet / selected cell and records the frame half-size so the
# sprite stays centered on the boss regardless of the sheet's frame dimensions.
func _apply_frame(tex: Texture2D, hframes_count: int, frame: int, fw: float) -> void:
	if _sprite.texture != tex:
		_sprite.texture = tex
		_sprite.hframes = hframes_count
	_sprite.frame = clampi(frame, 0, hframes_count - 1)
	_frame_half = fw / 2.0

# Keeps the (centered=false) sprite's center pinned to the boss center as the node
# scale pulses and the frame size changes; also applies the visual-lag slide.
func _position_sprite() -> void:
	var sx = maxf(scale.x, 0.001)
	var sy = maxf(scale.y, 0.001)
	var center_offset = Vector2(16.0 * LOGICAL_SCALE / sx - _frame_half, 16.0 * LOGICAL_SCALE / sy - _frame_half)
	_sprite.position = Vector2((_visual_pos.x - position.x) / sx, (_visual_pos.y - position.y) / sy) + center_offset

# Advances the looping bounce animation and records the current frame.
func _advance_jump(delta: float) -> void:
	var prev = _anim_frame
	_jump_time = fmod(_jump_time + delta, JUMP_DURATION)
	_anim_frame = mini(int(_jump_time * JUMP_FPS), JUMP_FRAMES - 1)
	# Thud: shake the moment the hop leaves the airborne frames and lands.
	if prev < JUMP_MOVE_END and _anim_frame >= JUMP_MOVE_END:
		_main._trigger_shake(LAND_SHAKE)
	_apply_frame(JUMP_TEX, JUMP_FRAMES, _anim_frame, JUMP_FW)

# True on the grounded bounce frames (windup / landing / idle) — the boss can only
# start a dash or an enemy spawn while it isn't mid-hop.
func _is_still() -> bool:
	return _anim_frame < JUMP_MOVE_START or _anim_frame >= JUMP_MOVE_END

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
	return position + Vector2(16.0, 16.0) * LOGICAL_SCALE

func _get_radius() -> float:
	return 16.0 * LOGICAL_SCALE - 4.0

func _scaled_hitbox() -> Rect2:
	# Wall-collision box (used only by _move_x/_move_y so the boss doesn't walk into
	# solids). Top edge lowered 32px; bottom edge at the 2×2-tile footprint bottom.
	var top_left = position + Vector2(2.0, 2.0) * LOGICAL_SCALE + Vector2(0.0, 32.0)
	var size = Vector2(28.0, 28.0) * LOGICAL_SCALE - Vector2(0.0, 32.0)
	return Rect2(top_left, size)

# The player dies when its body center enters this box — a band around the boss's
# lower body / feet, kept low so the player isn't killed "too high up". Separate from
# _scaled_hitbox (wall collision) and get_center()/_get_radius() (beam detection).
func _player_death_rect() -> Rect2:
	# Identical to the wall-collision box (_scaled_hitbox).
	return _scaled_hitbox()

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

# Draws the boss in front of the player when the bottom of its sprite sits lower on
# screen (larger y) than the bottom of the player's sprite, and behind it otherwise —
# feet-based ordering. The boss's own y-sort key is its tile-top origin (well above its
# feet), so it can't rely on plain y-sort against the player; z_index forces the order.
func _update_player_zsort(player: Node2D) -> void:
	var boss_sprite_bottom = get_center().y + _frame_half
	var player_sprite_bottom = player.position.y   # player root sits at its hitbox/feet
	z_index = 1 if boss_sprite_bottom > player_sprite_bottom else 0

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
		_position_sprite()
		return

	match _state:
		State.CHASE:           _process_chase(delta, player, target)
		State.SPAWN_TELEGRAPH: _process_telegraph(delta)

	_visual_pos = _visual_pos.lerp(position, minf(1.0, BOSS_SPRITE_SPEED * delta))
	_position_sprite()
	_update_player_zsort(player)

	if _state != State.SPAWN_TELEGRAPH:
		if not player.movement_locked and _player_death_rect().has_point(target):
			_main._reset_room()

# ── States ────────────────────────────────────────────────────────────────────

func _process_chase(delta: float, player: Node2D, target: Vector2) -> void:
	var hp_ratio = float(hp) / float(BOSS_MAX_HP)
	var spd = BASE_SPEED + (MAX_SPEED - BASE_SPEED) * (1.0 - hp_ratio)
	var to_player = target - get_center()
	if to_player.length() <= BOSS_MOVE_RADIUS:
		# Bounce toward the player, only translating during the airborne frames.
		_advance_jump(delta)
		if _anim_frame >= JUMP_MOVE_START and _anim_frame < JUMP_MOVE_END and to_player.length() > 1.0:
			var vel = to_player.normalized() * spd * JUMP_MOVE_MULT * delta
			_move_x(vel.x)
			_move_y(vel.y)
	else:
		# Player too far: rest on the first frame, motionless.
		_jump_time = 0.0
		_anim_frame = 0
		_apply_frame(JUMP_TEX, JUMP_FRAMES, 0, JUMP_FW)

	# Spawn can only be initiated while grounded (not mid-hop), and only when the
	# minion cap isn't already reached — otherwise it doesn't attempt to spawn.
	if hp < BOSS_MAX_HP * 0.8:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0 and _is_still():
			var phase_ratio = clampf(hp_ratio / 0.8, 0.0, 1.0)
			_spawn_timer = lerpf(12.0, 15.0, phase_ratio)
			if _count_minions() < _minion_cap():
				_state = State.SPAWN_TELEGRAPH
				_spawn_time = 0.0
				scale = Vector2(1.0, 1.0)
				return

func _process_telegraph(delta: float) -> void:
	# Play the spawn animation once (no movement); spawn the minions when it ends.
	_spawn_time += delta
	var frame = int(_spawn_time * SPAWN_FPS)
	if frame >= SPAWN_FRAMES:
		_spawn_minions()
		_state = State.CHASE
		_jump_time = 0.0
		_anim_frame = 0
		_apply_frame(JUMP_TEX, JUMP_FRAMES, 0, JUMP_FW)
		return
	_apply_frame(SPAWN_TEX, SPAWN_FRAMES, frame, SPAWN_FW)

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
	var player_tile = Vector2i(
		floori(_main.player.get_body_center().x / TILE_SIZE),
		floori(_main.player.get_body_center().y / TILE_SIZE))
	var room = _get_home_room()
	var rx0 = room.x * 25
	var ry0 = room.y * 12
	var border_tiles = ceili(64.0 / TILE_SIZE)
	var size_tiles = ceili(float(LOGICAL_SCALE))
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

func _minion_cap() -> int:
	if _spawn_count >= 2:
		return MINION_CAP_AFTER_SECOND
	if _spawn_count >= 1:
		return MINION_CAP_AFTER_FIRST
	return MINION_CAP

func _spawn_minions() -> void:
	# As long as we're under the cap, always spawn the full pair (one to each
	# side, 32px out and 32px down) — even if that pushes the count past the cap.
	if _count_minions() >= _minion_cap():
		return
	_spawn_count += 1
	var c = get_center()
	var offsets = [Vector2(-TILE_SIZE, TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE)]
	for off in offsets:
		_spawn_water_enemy(c + off)

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
	_beam_time = 0.0
	_was_in_beam = false
	_phase2_triggered = false
	_arc_started = false
	_state = State.CHASE
	_jump_time = 0.0
	_spawn_time = 0.0
	_anim_frame = 0
	_spawn_count = 0
	_apply_frame(JUMP_TEX, JUMP_FRAMES, 0, JUMP_FW)
	scale = Vector2(1.0, 1.0)
	rotation = 0.0
	z_index = 0

func _exit_tree() -> void:
	Engine.time_scale = 1.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		Utils.remove_boss_health_bar(self)
