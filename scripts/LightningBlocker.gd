extends Node2D

@onready var sprite: Sprite2D = $Sprite2D

var _is_blocking := false
var _time := 0.0
var _angle_seed := 0.0

const SPARK_COUNT := 5
const TEX_NORMAL := preload("res://Sprites/resistor_small.png")
const TEX_ACTIVE := preload("res://Sprites/resistor_small2.png")

func _ready() -> void:
	add_to_group("lightning_blockers")
	_angle_seed = randf() * TAU
	sprite.hide()
	queue_redraw()

func get_grid_pos() -> Vector2i:
	return Vector2i(floori(position.x / 32.0), floori(position.y / 32.0))

func set_blocking(blocking: bool) -> void:
	if _is_blocking == blocking:
		return
	_is_blocking = blocking
	if blocking:
		_time = 0.0
		AudioManager.play_sfx("electric_fail")
	queue_redraw()

func _process(delta: float) -> void:
	if not _is_blocking:
		return
	_time += delta
	queue_redraw()

func _draw() -> void:
	var tex := TEX_ACTIVE if (_is_blocking and int(_time / 0.5) % 2 == 1) else TEX_NORMAL
	draw_texture(tex, Vector2.ZERO)

	if not _is_blocking:
		return

	var fade_in := minf(1.0, _time / 0.08)
	var pulse = abs(sin(_time * 8.0))
	var c := Vector2(16.0, 16.0)

	for i in SPARK_COUNT:
		var stutter = floor(abs(sin(_time * 40.0 + i * 7.3)))
		if stutter < 0.5:
			continue

		var angle := _angle_seed + (TAU * i / SPARK_COUNT) + sin(_time * 15.0 + i * 1.9) * 0.7
		var length := maxf((3.0 + 7.0 * pulse) * abs(sin(_time * 22.0 + i * 2.7)), 2.0)

		var d := Vector2(cos(angle), sin(angle))
		var perp := Vector2(-d.y, d.x)
		var p0 := c + d * 7.0
		var p1 := c + d * (7.0 + length * 0.5) + perp * sin(_time * 19.0 + i) * 2.5
		var p2 := c + d * (7.0 + length)

		var alpha := fade_in
		draw_line(p0, p1, Color(1.0, 1.0, 0.4, 0.9 * alpha), 1.8)
		draw_line(p1, p2, Color(1.0, 1.0, 0.9, 0.95 * alpha), 0.8)
		draw_circle(p0, 1.5, Color(1.0, 1.0, 1.0, alpha))
