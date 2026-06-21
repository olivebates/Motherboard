extends "res://scripts/Enemy.gd"

var boss_spawned := false

const MAX_HP := 25
const HEALTH_BAR_OFFSET_Y := -10.0

# Origin sits this far below the tile top-left so Y-sort orders by the ground
# line (roughly the sprite bottom), matching the player. Bosses override to 0.
const GROUND_OFFSET := 24.0

func _ground_offset() -> float:
	return GROUND_OFFSET

const _ROOM_PX_W = 25 * 32
const _ROOM_PX_H = 12 * 32

var hp := MAX_HP

func _ready() -> void:
	super._ready()
	add_to_group("water_enemies")
	if boss_spawned:
		add_to_group("boss_spawned_enemies")
	call_deferred("_register_health_bar")

func get_max_hp() -> int:
	return MAX_HP

func _register_health_bar() -> void:
	if is_in_group("water_boss"):
		return
	if _main == null:
		_main = get_tree().current_scene as Node2D
	if _main == null:
		call_deferred("_register_health_bar")
		return
	Utils.create_sprite_health_bar(self, TILE_SIZE, HEALTH_BAR_OFFSET_Y - _ground_offset())

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		Utils.remove_sprite_health_bar(self)

func _get_home_room() -> Vector2i:
	return Vector2i(floori(_start_pos.x / _ROOM_PX_W), floori(_start_pos.y / _ROOM_PX_H))

func _in_current_room() -> bool:
	return _get_home_room() == _main.current_room

func _health_bar_visible() -> bool:
	var overlay = _main.get("map_overlay")
	return not _dead and _in_current_room() and (overlay == null or not overlay._open)

func _update_health_bar() -> void:
	if _main == null:
		return
	Utils.update_sprite_health_bar(self, hp, get_max_hp(), _health_bar_visible())

func _handle_beam() -> void:
	var beam = _main.electric_beam
	if beam == null:
		return
	if beam.active and beam.is_point_on_beam(get_center(), BEAM_RADIUS):
		hp -= 1
		_main._trigger_shake(2.0)
		if hp <= 0:
			hp = 0
			_die()

func _die() -> void:
	super._die()
	AudioManager.play_sfx("water_death")

func _process(delta: float) -> void:
	_update_health_bar()
	if not _in_current_room():
		return
	_eject_from_solid()
	var overlay = _main.get("map_overlay")
	if overlay != null and overlay._open:
		return
	if _main.electric_beam == null:
		return
	super._process(delta)

func reset() -> void:
	super.reset()
	hp = get_max_hp()
	_arc_started = false
	_vanished = false

# ── Boss death arc (shared by WaterBoss / BounceBoss) ──────────────────────────
# A defeated boss freezes briefly then flies off screen in a parabola; once it
# leaves its home-room bounds it vanishes and the player does a victory jump. Plain
# enemies never enter this path (they never set _arc_started). Boss subclasses scale
# up and override _boss_scale().
var _death_tween: Tween
var _arc_started := false
# True only after the death arc has carried the boss off screen and it has
# vanished. BossDoor waits for this (not just `_dead`) before opening.
var _vanished := false

func _boss_scale() -> float:
	return 1.0

# Launches the parabolic fly-off-screen arc. Called from each boss's _boss_die().
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

# Drives the arc each frame while DYING; fires _on_death_complete once the boss
# leaves its home-room bounds. Bosses call this from their DYING-state branch.
func _process_death_arc() -> void:
	if not (_dead and _arc_started):
		return
	_visual_pos = position
	var bs := _boss_scale()
	var sx := maxf(scale.x, 0.001)
	var sy := maxf(scale.y, 0.001)
	_sprite.position = Vector2(16.0 * bs / sx - 16.0, 16.0 * bs / sy - 16.0)
	var room := _get_home_room()
	var rx0 := room.x * 25 * TILE_SIZE
	var ry0 := room.y * 12 * TILE_SIZE
	var rx1 := rx0 + 25 * TILE_SIZE
	var ry1 := ry0 + 12 * TILE_SIZE
	if position.x < rx0 or position.x > rx1 or position.y < ry0 or position.y > ry1:
		_on_death_complete()

# How long the player stays frozen in place after the boss vanishes, before the
# victory jump.
const BOSS_DEATH_FREEZE := 1.5

func _on_death_complete() -> void:
	if not _arc_started:
		return
	_arc_started = false
	if _death_tween:
		_death_tween.kill()
	_sprite.visible = false
	_particles.restart()
	scale = Vector2(_boss_scale(), _boss_scale())
	# The boss has now fully disappeared off screen — let BossDoor open.
	_vanished = true
	# Boss doors open themselves once their room has no living boss (see BossDoor).
	# Now that the boss has vanished off screen, the player freezes in place for a
	# beat and then does a victory jump.
	if _main != null and is_instance_valid(_main.player) and _main.player.has_method("play_happy_jump"):
		var p: Node = _main.player
		p.lock_movement()
		await get_tree().create_timer(BOSS_DEATH_FREEZE).timeout
		if is_instance_valid(p):
			p.play_happy_jump()
