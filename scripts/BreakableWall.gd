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
	return Vector2i(floori(position.x / 32.0), floori(position.y / 32.0))

func get_center() -> Vector2:
	return position + Vector2(16.0, 16.0)

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
	var particles := CPUParticles2D.new()
	particles.position = get_center()
	particles.z_index = 10
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 24
	particles.lifetime = 0.6
	particles.initial_velocity_min = 40.0
	particles.initial_velocity_max = 120.0
	particles.gravity = Vector2(0, 200)
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	particles.color = Color(1.0, 1.0, 1.0, 1.0)
	get_tree().current_scene.add_child(particles)
	get_tree().create_timer(particles.lifetime + 0.1).timeout.connect(particles.queue_free)

	_destroyed = true
	sprite.visible = false
	var main = get_tree().current_scene
	if main.has_method("_update_beam"):
		main._update_beam()
