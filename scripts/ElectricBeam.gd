extends Node2D

@onready var line_main: Line2D = $LineMain
@onready var line_glow: Line2D = $LineGlow

const POINT_COUNT := 12
const WOBBLE_AMPLITUDE := 8.0
const WOBBLE_SPEED := 6.0
const PHASE_POOL := POINT_COUNT * 20  # enough for many segments

var waypoints: Array = []
var active := false
var time_elapsed := 0.0
var phase_offsets: Array = []

func _ready() -> void:
	z_index = 10
	for line in [line_main, line_glow]:
		line.joint_mode = Line2D.LINE_JOINT_SHARP
		line.begin_cap_mode = Line2D.LINE_CAP_BOX
		line.end_cap_mode = Line2D.LINE_CAP_BOX
		line.antialiased = false
	line_main.default_color = Color(1.0, 1.0, 1.0, 1.0)
	line_glow.visible = false

	for i in range(PHASE_POOL):
		phase_offsets.append(randf() * TAU)

	visible = false

func activate(points: Array) -> void:
	waypoints = points
	active = true
	visible = true

func deactivate() -> void:
	active = false
	visible = false
	waypoints = []
	line_main.clear_points()
	line_glow.clear_points()

func _process(delta: float) -> void:
	if not active:
		return
	time_elapsed += delta
	_rebuild_points()
	queue_redraw()

func _resolve_waypoints() -> Array:
	var out: Array = []
	for w in waypoints:
		var pt: Vector2 = w.get_beam_point() if w is Node2D else w
		out.append(pt + Vector2(0.0, -4.0))
	return out

func _rebuild_points() -> void:
	line_main.clear_points()
	line_glow.clear_points()

	var resolved := _resolve_waypoints()
	if resolved.size() < 2:
		return

	var pulse := 1.5 + sin(time_elapsed * 8.0) * 0.75
	line_main.width = pulse
	line_glow.width = pulse * 4.0

	var first := true
	for seg in range(resolved.size() - 1):
		var a: Vector2 = resolved[seg]
		var b: Vector2 = resolved[seg + 1]
		var beam_dir := b - a
		if beam_dir.length_squared() < 0.001:
			continue

		var beam_norm := beam_dir.normalized()
		var perp := Vector2(-beam_norm.y, beam_norm.x)

		if not first:
			# Remove the junction duplicate added by the previous segment's endpoint
			line_main.remove_point(line_main.get_point_count() - 1)
			line_glow.remove_point(line_glow.get_point_count() - 1)
		first = false

		line_main.add_point(a)
		line_glow.add_point(a)

		for i in range(1, POINT_COUNT + 1):
			var t := float(i) / float(POINT_COUNT + 1)
			var base_pos := a + beam_dir * t
			var phase_idx := (seg * POINT_COUNT + i - 1) % phase_offsets.size()
			var wobble := sin(time_elapsed * WOBBLE_SPEED + phase_offsets[phase_idx]) * WOBBLE_AMPLITUDE
			var envelope := sin(t * PI)
			var pt := (base_pos + perp * wobble * envelope).round()
			line_main.add_point(pt)
			line_glow.add_point(pt)

		line_main.add_point(b)
		line_glow.add_point(b)

func _draw() -> void:
	if not active:
		return
	var r := 4.0 + sin(time_elapsed * 8.0) * 1.5
	for pt in _resolve_waypoints():
		draw_circle(pt, r, Color(1.0, 1.0, 1.0, 1.0))
