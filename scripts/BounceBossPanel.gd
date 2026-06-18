extends Node2D

@export var positive: bool = true
@export var id: String = "bounceboss"

const RELOCATE_DURATION := 0.4

var _active := false
# Visual scale used by _draw(); animated 1→0→1 when the panel relocates so it
# shrinks out of its old tile and grows back in at the new one.
var _scale_factor := 1.0
var _move_tween: Tween
# Tile this panel is currently registered at in GameManager.floor_panels (or null).
var _registered_gp = null

func _ready() -> void:
	if positive:
		$Sprite2D.texture = load("res://Sprites/objects/positive.png")
	else:
		$Sprite2D.texture = load("res://Sprites/objects/negative.png")
	$Sprite2D.hide()
	# TEMPORARY: draw above everything else. Revert to drawing under everything later.
	z_as_relative = false
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	queue_redraw()

func _process(_delta: float) -> void:
	var my_center := position + Vector2(16.0, 16.0)
	var was_active := _active
	# Active only while a prong is planted in this tile — not when the beam
	# merely passes over it.
	_active = false
	for prong_pos in GameManager.get_prong_world_positions():
		if prong_pos.distance_to(my_center) <= GameManager.PANEL_ACTIVATION_RADIUS:
			_active = true
			break
	if _active != was_active:
		queue_redraw()

# Shrink out at the current tile, jump to the target at scale 0, then grow back.
func move_to(target: Vector2) -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.tween_method(_set_scale_factor, _scale_factor, 0.0, RELOCATE_DURATION)
	_move_tween.tween_callback(func() -> void:
		position = target
		_register_panel())
	_move_tween.tween_method(_set_scale_factor, 0.0, 1.0, RELOCATE_DURATION)

# Instant placement used for the initial spawn and room resets (no animation).
func snap_to(target: Vector2) -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	position = target
	_set_scale_factor(1.0)
	_register_panel()

# Register as a floor panel at the current tile (re-registering when relocated) so
# the prongs/beam drive the "bounceboss" id through the normal puzzle evaluation.
func _register_panel() -> void:
	var gp := Vector2i(floori(position.x / 32.0), floori(position.y / 32.0))
	if _registered_gp == gp:
		return
	if _registered_gp != null:
		GameManager.unregister_floor_panel(_registered_gp)
	GameManager.register_floor_panel(gp, id)
	_registered_gp = gp
	GameManager.evaluate_puzzle()

func _exit_tree() -> void:
	if _registered_gp != null:
		GameManager.unregister_floor_panel(_registered_gp)
		_registered_gp = null
		GameManager.evaluate_puzzle()

func _set_scale_factor(v: float) -> void:
	_scale_factor = v
	queue_redraw()

func _draw() -> void:
	var tex = $Sprite2D.texture
	if tex:
		var sz: Vector2 = tex.get_size() * _scale_factor
		draw_texture_rect(tex, Rect2(Vector2(16.0, 16.0) - sz * 0.5, sz), false)
	if _active:
		draw_arc(Vector2(16.0, 16.0), 17.0 * _scale_factor, 0.0, TAU, 32, Color.WHITE, 1.5)
