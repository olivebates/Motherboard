extends Node2D

@onready var sprite: Sprite2D = $Sprite2D

const SHAKE_DURATION := 0.4
const SHAKE_MAGNITUDE := 2.5
const BEAM_RADIUS := 18.0

var _triggered := false
var _shake_time := 0.0
var _destroyed := false

func _ready() -> void:
	add_to_group("breakable_walls")

func get_grid_pos() -> Vector2i:
	return GridUtils.to_grid(position)

func get_center() -> Vector2:
	return GridUtils.tile_center(position)

func reset() -> void:
	if SaveManager.is_breakable_destroyed(get_grid_pos()):
		return
	_destroyed = false
	_triggered = false
	_shake_time = 0.0
	sprite.position = Vector2.ZERO
	sprite.visible = true

func _process(delta: float) -> void:
	if _destroyed:
		return

	if _triggered:
		_shake_time += delta
		var t := _shake_time / SHAKE_DURATION
		var intensity := SHAKE_MAGNITUDE * (1.0 - t)
		sprite.position = Vector2(
			sin(_shake_time * 80.0) * intensity,
			cos(_shake_time * 65.0) * intensity
		)
		if _shake_time >= SHAKE_DURATION:
			_explode()
		return

	if not GameManager.has_ability("break"):
		return
	var beam = get_tree().current_scene.electric_beam
	if beam != null and beam.active and beam.is_point_on_beam(get_center(), BEAM_RADIUS):
		_triggered = true
		_shake_time = 0.0
		for node in get_tree().get_nodes_in_group("break_highlight"):
			node.queue_free()

func _explode() -> void:
	EffectUtils.spawn_burst(get_tree().current_scene, get_center(), {
		"amount": 24, "lifetime": 0.6,
		"velocity_min": 40.0, "velocity_max": 120.0,
		"gravity": Vector2(0, 200), "scale_min": 2.0, "scale_max": 4.0,
	})

	_destroyed = true
	sprite.visible = false
	var main = get_tree().current_scene
	if main.has_method("_update_beam"):
		main._update_beam()
