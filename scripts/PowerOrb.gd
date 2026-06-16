extends Node2D

@export var ability: String = ""

var _collected = false
var _animating = false
var _anim_time = 0.0
var _anim_player: Node2D = null
var _anim_orb_offset = Vector2.ZERO
var _anim_radius = DRAW_RADIUS
var _anim_rot = 0.0

const PICKUP_RADIUS = 16.0
const DRAW_RADIUS = 10.0
const LINE_COUNT = 8
const LINE_INNER = 14.0
const LINE_OUTER = 38.0
const LINE_TIP_HALF_W = 3.5
const FLOAT_HEIGHT = 34.0
const TOTAL_DURATION = 3.5
const FLY_START = 3.0

func _ready() -> void:
	add_to_group("power_orbs")
	queue_redraw()

func _process(delta: float) -> void:
	if _animating:
		_update_animation(delta)
		return
	if _collected:
		return
	var player: Node2D = get_tree().get_first_node_in_group("players")
	if player == null:
		return
	var center = position + Vector2(16.0, 16.0)
	if center.distance_to(player.get_body_center()) <= PICKUP_RADIUS:
		_collect(player)

func _draw() -> void:
	if _collected and not _animating:
		return
	var draw_center = Vector2(16.0, 16.0) + _anim_orb_offset
	if _anim_radius > 0.05:
		draw_circle(draw_center, _anim_radius, Color.WHITE)
	if _animating and _anim_time < FLY_START:
		for i in LINE_COUNT:
			var angle = _anim_rot + i * TAU / LINE_COUNT
			var dir = Vector2(cos(angle), sin(angle))
			var perp = Vector2(-dir.y, dir.x)
			var tip = draw_center + dir * LINE_OUTER
			draw_polygon(
				[draw_center + dir * LINE_INNER,
				 tip + perp * LINE_TIP_HALF_W,
				 tip - perp * LINE_TIP_HALF_W],
				[Color.WHITE, Color.WHITE, Color.WHITE]
			)

func _collect(player: Node2D) -> void:
	_collected = true
	_animating = true
	_anim_time = 0.0
	_anim_orb_offset = Vector2.ZERO
	_anim_radius = DRAW_RADIUS
	_anim_rot = 0.0
	_anim_player = player

	if ability != "":
		GameManager.grant_ability(ability)

	var main: Node2D = get_tree().current_scene
	main.room_entry_positions[main.current_room] = player.grid_pos
	for p in GameManager.clear_prongs():
		p["node"].queue_free()
	main._update_beam()
	player.lock_movement()
	player.look_up()
	AudioManager.fade_out_music(0.4)
	queue_redraw()

func _update_animation(delta: float) -> void:
	_anim_time += delta
	_anim_rot += delta * TAU * 0.2

	if _anim_time < FLY_START:
		var t = _anim_time / FLY_START
		_anim_orb_offset = Vector2(0.0, -FLOAT_HEIGHT * t)
		_anim_radius = DRAW_RADIUS
	else:
		var fly_t = clamp((_anim_time - FLY_START) / (TOTAL_DURATION - FLY_START), 0.0, 1.0)
		var float_end = Vector2(0.0, -FLOAT_HEIGHT)
		var player_local = _anim_player.get_body_center() - position - Vector2(16.0, 16.0)
		_anim_orb_offset = float_end.lerp(player_local, fly_t)
		_anim_radius = DRAW_RADIUS * (1.0 - fly_t)

		if _anim_time >= TOTAL_DURATION:
			_animating = false
			_anim_player.unlock_movement()
			PowerOrbCounter.add_orb()
			AudioManager.fade_in_music(0.4)
			queue_redraw()
			return

	queue_redraw()

func reset() -> void:
	_collected = false
	_animating = false
	_anim_radius = DRAW_RADIUS
	_anim_orb_offset = Vector2.ZERO
	queue_redraw()
