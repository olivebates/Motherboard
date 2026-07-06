extends "res://scripts/Enemy.gd"

var boss_spawned := false

const MAX_HP := 25
const HEALTH_BAR_OFFSET_Y := -10.0

# Origin sits this far below the tile top-left so Y-sort orders by the ground
# line (roughly the sprite bottom), matching the player. Bosses override to 0.
const GROUND_OFFSET := 24.0

func _ground_offset() -> float:
	return GROUND_OFFSET

# Only chase once the player comes within this range; idle otherwise.
const CHASE_RADIUS := 128.0

func _chase_radius() -> float:
	return CHASE_RADIUS

const _ROOM_PX_W = 25 * 32
const _ROOM_PX_H = 12 * 32

var hp := MAX_HP

# Directional walk/idle animation. Null on the boss (its scene has no
# AnimatedSprite2D child), so every use is guarded.
@onready var _anim: AnimatedSprite2D = get_node_or_null("Sprite2D/AnimatedSprite2D")
var _facing := "front"

func _ready() -> void:
	super._ready()
	add_to_group("water_enemies")
	if boss_spawned:
		add_to_group("boss_spawned_enemies")
	_setup_animations()
	call_deferred("_register_health_bar")

# ── Directional animations ─────────────────────────────────────────────────────
# Four facings × {idle, run}. Idle sheets are 4 frames (128×32), run sheets are
# 6 frames (192×32); all frames 32×32 in a single horizontal strip. Left/right
# have their own sheets, so no flip_h is needed.
const _IDLE_FRAMES = 4
const _RUN_FRAMES = 6
const _IDLE_FPS = 8.0 / 3.0 * 1.2    # +20%
const _RUN_FPS = 12.0 / 3.0 * 1.2    # +20%

func _setup_animations() -> void:
	if _anim == null:
		return
	var frames = SpriteFrames.new()
	frames.remove_animation("default")
	_add_strip(frames, "front_idle", "res://Sprites/enemies/WaterGuy/Front_Idle-Sheet.webp", _IDLE_FRAMES, _IDLE_FPS)
	_add_strip(frames, "back_idle",  "res://Sprites/enemies/WaterGuy/Back_Idle-Sheet.webp",  _IDLE_FRAMES, _IDLE_FPS)
	_add_strip(frames, "left_idle",  "res://Sprites/enemies/WaterGuy/Left_Idle-Sheet.webp",  _IDLE_FRAMES, _IDLE_FPS)
	_add_strip(frames, "right_idle", "res://Sprites/enemies/WaterGuy/Right_Idle-Sheet.webp", _IDLE_FRAMES, _IDLE_FPS)
	_add_strip(frames, "front_run",  "res://Sprites/enemies/WaterGuy/Water_Front_Run-Sheet.webp",      _RUN_FRAMES, _RUN_FPS)
	_add_strip(frames, "back_run",   "res://Sprites/enemies/WaterGuy/Water_Back_Run-Sheet.webp",       _RUN_FRAMES, _RUN_FPS)
	_add_strip(frames, "left_run",   "res://Sprites/enemies/WaterGuy/Water_Side_Run_Left-Sheet.webp",  _RUN_FRAMES, _RUN_FPS)
	_add_strip(frames, "right_run",  "res://Sprites/enemies/WaterGuy/Water_Side_Run_Right-Sheet.webp", _RUN_FRAMES, _RUN_FPS)
	_anim.sprite_frames = frames
	_anim.play("front_idle")

func _add_strip(frames: SpriteFrames, anim: String, path: String, count: int, fps: float) -> void:
	var tex: Texture2D = load(path)
	frames.add_animation(anim)
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, true)
	for i in range(count):
		var atlas = AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(i * 32, 0, 32, 32)
		frames.add_frame(anim, atlas)

# Faces the player and switches between idle/run based on whether the enemy
# actually moved this frame.
func _update_animation(moved: Vector2, delta: float) -> void:
	if _anim == null:
		return
	var to_player = _main.player.get_body_center() - get_center()
	if absf(to_player.x) > absf(to_player.y):
		_facing = "right" if to_player.x > 0.0 else "left"
	else:
		_facing = "front" if to_player.y > 0.0 else "back"
	# Frame-rate independent: "moving" means it covered a meaningful fraction of a
	# full step this frame. A fixed pixel threshold breaks at high refresh rates,
	# where each frame's step is tiny and a moving enemy would read as idle.
	var is_moving = moved.length() > SPEED * delta * 0.5
	var anim = _facing + ("_run" if is_moving else "_idle")
	if _anim.animation != anim:
		_anim.play(anim)

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
	var prev = position
	super._process(delta)
	if not _dead:
		_update_animation(position - prev, delta)

func reset() -> void:
	super.reset()
	hp = get_max_hp()
	if _anim != null:
		_facing = "front"
		_anim.play("front_idle")
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
