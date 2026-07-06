extends Node2D

const TILE_SIZE := 32
const WORLD_OFFSET := 0
const SPEED := 217.6
const WIND_FORCE := 60.0
const SPRITE_SPEED := 24.0
const CONTACT_EPS := 0.1
const PUSH_FREEZE := 0.15
const PUSH_HOLD_TIME := 0.15
const PUSH_KICK_TIME := 0.2
const PUSH_STRAIN_FRAME_TIME = 0.4   # while pushing an immovable block, advance the pose one frame per this

@export var start_with_push: bool = false
@export var start_with_chain: bool = false
@export var start_with_break: bool = false
@export var save_system_enabled: bool = false
@export var room_teleport_enabled: bool = false

signal death_static_cue

var movement_locked := false
var visual_pos: Vector2
var speed_multiplier := 1.0
var _push_lock_dir := Vector2i.ZERO
var _push_tween: Tween
var _push_charge_time := 0.0
var _push_charge_dir := Vector2i.ZERO
var _push_charge_block: Node = null
var _push_pose_dir := Vector2i.ZERO   # direction of the "pressing against a block" pose (0 = none)
var _push_kick_dir := Vector2i.ZERO   # direction of the "block just moved" kick frame
var _push_kick_time := 0.0            # remaining time to show the kick frame
var _push_blocked = false             # pressing into a block that can't move (object behind it)
var _push_strain_time = 0.0           # accumulates while blocked; cycles the strain pose frame
var _main: Node2D

@onready var _body: Node2D = $Body
@onready var _sprite: AnimatedSprite2D = $Body/AnimatedSprite2D
@onready var _hitbox: CollisionShape2D = $Body/Hitbox

var _facing := "front"
var _facing_right := true

# Height (px) of the current sprite frame, used to anchor the sprite by its feet.
# Normal frames are 32×32; the prong-plant frames are 32×64 (the raised hammer
# bleeds upward) so they need a taller anchor while planting.
var _sprite_h := 32.0
# Extra vertical offset applied to the sprite (downward positive); used to nudge the
# prong-plant animation down a few pixels while it plays.
var _sprite_y_offset := 0.0
const PLANT_FRAME_H := 64.0
const PLANT_FPS := 12.0
const PLANT_Y_OFFSET := 6.0

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
	if start_with_break:
		GameManager.grant_ability("break")
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
	# Push poses: 2 frames each, controlled manually (frame 0 = pressing, frame 1 = block moved).
	# push_up frames are 32×36 (4px taller); the extra height bleeds upward (handled in _play_push).
	_add_strip(frames, "push_side", "res://Sprites/player/Push_side-Sheet.webp", 32, 32, 2)
	_add_strip(frames, "push_up",   "res://Sprites/player/Push_up-Sheet.webp",   32, 36, 2)
	_add_strip(frames, "push_down", "res://Sprites/player/Push_down-Sheet.webp", 32, 32, 2)
	# Prong-plant: 4 frames of 32×64 (a hammer-swing); played once when planting a
	# prong. The extra 32px of height bleeds upward (anchored by the feet via _sprite_h).
	_add_strip(frames, "plant", "res://Sprites/player/Hammer_Stake1-Sheet.webp", 32, 64, 4)
	frames.set_animation_speed("plant", PLANT_FPS)
	# Death animation: 16 frames in a 4×4 grid, played once on room reset.
	_add_sheet(frames, "death", "res://Sprites/player/Death-Sheet.webp", 4, 4, 16, 11.2, false)
	# Happy jump: 4 frames in a 2×2 grid, played once on a victory beat (boss off-screen, orb collected).
	_add_sheet(frames, "happy_jump", "res://Sprites/player/Spark_Happy_Jump.webp", 2, 2, 4, 10.0, false)
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

func _add_strip(frames: SpriteFrames, anim: String, path: String, fw: int, fh: int, count: int) -> void:
	var tex: Texture2D = load(path)
	frames.add_animation(anim)
	frames.set_animation_loop(anim, false)
	for i in range(count):
		var atlas = AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(i * fw, 0, fw, fh)
		frames.add_frame(anim, atlas)

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
	# Push poses override the normal walk/idle animations.
	if _push_kick_time > 0.0 and _push_kick_dir != Vector2i.ZERO:
		_play_push(_push_kick_dir, 1)
		return
	if _push_pose_dir != Vector2i.ZERO:
		var pose_frame = 0
		if _push_blocked:
			pose_frame = int(_push_strain_time / PUSH_STRAIN_FRAME_TIME) % 2
		_play_push(_push_pose_dir, pose_frame)
		return
	var anim = _facing + ("_run" if is_moving else "_idle")
	if _sprite.animation != anim:
		_sprite.play(anim)
	_sprite.flip_h = (_facing == "side" and not _facing_right)

func _play_push(dir: Vector2i, frame_idx: int) -> void:
	var anim := "push_down"
	var flip := false
	if dir.x != 0:
		anim = "push_side"
		flip = dir.x < 0
	elif dir.y < 0:
		anim = "push_up"
	if _sprite.animation != anim:
		_sprite.play(anim)
	_sprite.pause()
	_sprite.frame = frame_idx
	_sprite.flip_h = (anim == "push_side" and flip)
	# push_up frames are 4px taller; shift up so the extra height bleeds above the tile.
	if anim == "push_up":
		_sprite.position.y -= 4.0

func get_body_center() -> Vector2:
	return YSortHitboxBottom.hitbox_center_from_root(position, _body_offset, _hitbox_offset)

func _process(delta: float) -> void:
	eject_from_solid()
	var body_center := position + _body_offset
	visual_pos = visual_pos.lerp(body_center, minf(1.0, SPRITE_SPEED * delta))
	var lag := visual_pos - body_center
	# Anchor squash/stretch at bottom-center of the 32×32 sprite
	_sprite.position = lag + Vector2(-16.0 * _sprite.scale.x, 16.0 - _sprite_h * _sprite.scale.y + _sprite_y_offset)

	if movement_locked:
		_push_pose_dir = Vector2i.ZERO
		_push_kick_time = 0.0
		_push_blocked = false
		_push_strain_time = 0.0
		_sprite.scale = _sprite.scale.lerp(Vector2.ONE, 15.0 * delta)
		if _sprite.animation.ends_with("_run") or _sprite.animation.begins_with("push"):
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

	if _push_blocked:
		_push_strain_time += delta
	else:
		_push_strain_time = 0.0

	if _push_kick_time > 0.0:
		_push_kick_time = maxf(0.0, _push_kick_time - delta)

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
	if event.is_action_pressed("prong_teleport"):
		_try_prong_teleport()
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

func _try_prong_teleport() -> bool:
	var stops := _build_teleport_cycle()
	if stops.size() < 2:
		return false
	var my_center = get_body_center()
	for i in range(stops.size()):
		if my_center.distance_to(stops[i]) < 24.0:
			_main.teleport_between_prongs(stops[(i - 1 + stops.size()) % stops.size()])
			return true
	return false

# Ordered ring of teleport stops (player body-center targets): prong A, then each
# screw / nut-filled hole the active beam chains through in beam order, then prong B.
# Pressing prong_teleport while standing on any stop hops to the PREVIOUS one
# (wrapping) — i.e. the ring is ridden in reverse beam order. With no active chained
# route this is just the two prongs — i.e. the classic prong-to-prong hop.
func _build_teleport_cycle() -> Array:
	var prongs = get_tree().get_nodes_in_group("prongs")
	if prongs.size() != 2:
		return []
	var path: Array = GameManager.beam_path
	if path.size() < 2:
		return [prongs[0].hitbox_center(), prongs[1].hitbox_center()]
	var stops: Array = [_nearest_prong_center(prongs, path[0])]
	for k in range(1, path.size() - 1):
		var entry = path[k]
		# Only screws and nut-filled holes are ridable stops; plain pushable nuts
		# conduct but are not teleport targets.
		if entry is Node2D and (entry.is_in_group("screws") or entry.is_in_group("holes")):
			stops.append(GridUtils.tile_center(GridUtils.to_world(entry.get_grid_pos())))
	stops.append(_nearest_prong_center(prongs, path[path.size() - 1]))
	return stops

func _nearest_prong_center(prongs: Array, point: Vector2) -> Vector2:
	var best = prongs[0]
	var best_d = best.circuit_pos.distance_to(point)
	for p in prongs:
		var d = p.circuit_pos.distance_to(point)
		if d < best_d:
			best_d = d
			best = p
	return best.hitbox_center()

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
	var old_rect = _hitbox_rect(pos)
	var probe = old_rect.merge(_hitbox_rect(pos + Vector2(dx, 0.0)))
	var allowed = MoveUtils.sweep_x(old_rect, dx, main.get_player_blocking_rects(probe), CONTACT_EPS)
	return {"pos": Vector2(pos.x + allowed, pos.y), "moved": absf(allowed) > 0.001}

func _move_axis_y(pos: Vector2, dy: float, main: Node) -> Dictionary:
	if dy == 0.0:
		return {"pos": pos, "moved": false}
	var old_rect = _hitbox_rect(pos)
	var probe = old_rect.merge(_hitbox_rect(pos + Vector2(0.0, dy)))
	var allowed = MoveUtils.sweep_y(old_rect, dy, main.get_player_blocking_rects(probe), CONTACT_EPS)
	return {"pos": Vector2(pos.x, pos.y + allowed), "moved": absf(allowed) > 0.001}

func _try_push(raw: Vector2, moved_x: bool, moved_y: bool, main: Node, delta: float) -> bool:
	_push_pose_dir = Vector2i.ZERO
	_push_blocked = false
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

	# Flush against a pushable block and pressing into it → show the pressing pose.
	_push_pose_dir = dir

	if not block.is_in_group("fans"):
		var wind_dir := _get_fan_airflow_direction()
		if wind_dir != Vector2i.ZERO and dir == -wind_dir:
			_push_charge_time = 0.0
			_push_charge_dir = Vector2i.ZERO
			_push_charge_block = null
			return false

	var dest: Vector2i = block.grid_pos + dir
	if not main.can_push_block_to(dest):
		# Block is immovable (an object is behind it) — keep the straining push pose,
		# which _update_animation cycles one frame every PUSH_STRAIN_FRAME_TIME.
		_push_blocked = true
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
	var push_from = block.grid_pos
	block.push(dir)
	_start_push_lock(dir)
	main._trigger_shake(0.8)
	main.record_push(block, push_from, dir)
	_push_kick_dir = dir
	_push_kick_time = PUSH_KICK_TIME
	_push_pose_dir = Vector2i.ZERO
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

# Freezes the player and plays the hammer-swing "plant" animation once. Awaited by
# Main.spawn_prong() so the prong is only placed after the swing finishes.
func play_plant() -> void:
	movement_locked = true
	_push_pose_dir = Vector2i.ZERO
	_push_kick_time = 0.0
	_push_blocked = false
	_push_strain_time = 0.0
	_sprite.scale = Vector2.ONE
	_sprite.flip_h = false
	_sprite.speed_scale = 1.0
	_sprite.visible = true
	_sprite_h = PLANT_FRAME_H
	_sprite_y_offset = PLANT_Y_OFFSET
	_sprite.play("plant")
	await _sprite.animation_finished
	_sprite_h = 32.0
	_sprite_y_offset = 0.0
	_facing = "front"
	_sprite.speed_scale = 1.0
	_sprite.play("front_idle")
	movement_locked = false

func lock_movement() -> void:
	movement_locked = true

func unlock_movement() -> void:
	movement_locked = false

# Plays the death animation in place on room reset, emitting death_static_cue once the
# 3rd frame has played (the cue for the static screen effect). The animation is cut
# short by reset_to() when the player is respawned at the room start.
const DEATH_STATIC_CUE_FRAME := 3   # static starts after the 3rd frame (frames 0-2) has played

func play_death() -> void:
	movement_locked = true
	_push_pose_dir = Vector2i.ZERO
	_push_kick_time = 0.0
	_sprite.scale = Vector2.ONE
	_sprite.flip_h = false
	_sprite.speed_scale = 1.0
	_sprite.visible = true
	_sprite.play("death")
	while _sprite.frame < DEATH_STATIC_CUE_FRAME:
		await _sprite.frame_changed
	death_static_cue.emit()

func reset_to(gp: Vector2i) -> void:
	position = _grid_to_world(gp)
	visual_pos = position + _body_offset
	eject_from_solid()
	_facing = "front"
	_sprite.speed_scale = 1.0
	_sprite.play("front_idle")
	_sprite.visible = true

# Plays the death animation in reverse at 1× speed (starting from frame 8) to
# reassemble the player after a room reset, then settles back into the idle pose.
# Awaited before control resumes.
func play_revive() -> void:
	_facing = "front"
	_sprite.flip_h = false
	_sprite.scale = Vector2.ONE
	_sprite.visible = true
	_sprite.speed_scale = 1.0
	_sprite.play_backwards("death")
	_sprite.frame = 8
	await _sprite.animation_finished
	_sprite.speed_scale = 1.0
	_sprite.play("front_idle")

func _is_inside_solid() -> bool:
	var rect = _hitbox_rect(position)
	return MoveUtils.rect_hits_any(rect, _main.get_player_blocking_rects(rect))

func move_to_center(world_center: Vector2) -> void:
	position = YSortHitboxBottom.root_pos_from_hitbox_center(world_center, _body_offset, _hitbox_offset)
	visual_pos = position + _body_offset
	_eject_from_solid_fine()

func _eject_from_solid_fine() -> void:
	if not _is_inside_solid():
		return
	const STEP = 4
	var origin = Vector2i(int(round(position.x / STEP)), int(round(position.y / STEP)))
	var is_free = func(c):
		var rect = _hitbox_rect(Vector2(c.x * STEP, c.y * STEP))
		return not MoveUtils.rect_hits_any(rect, _main.get_player_blocking_rects(rect))
	var gp = MoveUtils.find_free_cell(origin, is_free)
	if gp != null:
		position = Vector2(gp.x * STEP, gp.y * STEP)
		visual_pos = position + _body_offset

func get_push_hitbox() -> Rect2:
	return _hitbox_rect(position)

func push_out(displacement: Vector2) -> void:
	position += displacement
	# Leave visual_pos where it was so the sprite lags behind and eases to the new
	# position, instead of teleporting with the body.

func look_up() -> void:
	_facing = "back"
	_sprite.play("back_idle")

# Freezes the player and plays the one-shot "happy jump" celebration, then settles
# back into the front idle and unlocks. Used after a boss flies off screen and after
# the power-orb pickup animation.
func play_happy_jump() -> void:
	movement_locked = true
	_push_pose_dir = Vector2i.ZERO
	_push_kick_time = 0.0
	_push_blocked = false
	_push_strain_time = 0.0
	_sprite.scale = Vector2.ONE
	_sprite.flip_h = false
	_sprite.speed_scale = 1.0
	_sprite.visible = true
	_sprite.play("happy_jump")
	await _sprite.animation_finished
	_facing = "front"
	_sprite.speed_scale = 1.0
	_sprite.play("front_idle")
	movement_locked = false

func eject_from_solid() -> void:
	if not _is_inside_solid():
		return
	var is_free = func(c):
		var rect = _hitbox_rect(_grid_to_world(c))
		return not MoveUtils.rect_hits_any(rect, _main.get_player_blocking_rects(rect))
	var gp = MoveUtils.find_free_cell(grid_pos, is_free)
	if gp != null:
		position = _grid_to_world(gp)
		visual_pos = position + _body_offset
