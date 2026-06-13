extends Node2D

const SHAKE_DURATION := 0.5
const SHAKE_MAGNITUDE := 2.0

var _triggered := false
var _shake_time := 0.0
var _destroyed := false
var _wind_dir := Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("dust_piles")

func get_grid_pos() -> Vector2i:
	return Vector2i(floori(position.x / 32.0), floori(position.y / 32.0))

func get_center() -> Vector2:
	return position + Vector2(16.0, 16.0)

func _get_room() -> Vector2i:
	var gp = get_grid_pos()
	return Vector2i(floori(float(gp.x) / 25.0), floori(float(gp.y) / 12.0))

func reset() -> void:
	if SaveManager.is_room_solved(_get_room()):
		return
	_destroyed = false
	_triggered = false
	_shake_time = 0.0
	_wind_dir = Vector2.ZERO
	sprite.position = Vector2.ZERO
	sprite.visible = true

func _process(delta: float) -> void:
	if _destroyed:
		return

	if _triggered:
		_shake_time += delta
		var intensity := SHAKE_MAGNITUDE * (1.0 - _shake_time / SHAKE_DURATION)
		sprite.position = Vector2(
			sin(_shake_time * 80.0) * intensity,
			cos(_shake_time * 65.0) * intensity
		)
		if _shake_time >= SHAKE_DURATION:
			_dissolve()
		return

	for fan in get_tree().get_nodes_in_group("fans"):
		if fan.is_active() and fan.is_position_in_airflow(get_center()):
			_triggered = true
			_shake_time = 0.0
			_wind_dir = Vector2(fan.direction)
			break

func _dissolve() -> void:
	var particles := CPUParticles2D.new()
	particles.position = get_center()
	particles.z_index = 10
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 0.8
	particles.amount = 20
	particles.lifetime = 0.9
	particles.direction = _wind_dir if _wind_dir.length_squared() > 0.0 else Vector2(1.0, 0.0)
	particles.spread = 22.0
	particles.initial_velocity_min = 25.0
	particles.initial_velocity_max = 70.0
	particles.gravity = Vector2.ZERO
	particles.scale_amount_min = 1.5
	particles.scale_amount_max = 3.5
	particles.color = Color(0.82, 0.72, 0.52, 1.0)
	get_tree().current_scene.add_child(particles)
	get_tree().create_timer(particles.lifetime + 0.1).timeout.connect(particles.queue_free)

	_destroyed = true
	sprite.visible = false
