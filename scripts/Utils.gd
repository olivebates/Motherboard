extends Node

const BAR_MARGIN := 10.0
const BAR_H := 16.0
const BAR_OUTLINE := 2.0
const BAR_LAYER := 25
const SPRITE_BAR_H := 6.0
const SPRITE_BAR_OUTLINE := 1.0
const SPRITE_BAR_Z := -1

var _bars: Dictionary = {}
var _sprite_bars: Dictionary = {}

func create_boss_health_bar(boss: Node, main: Node) -> void:
	var key := boss.get_instance_id()
	if _bars.has(key):
		return
	var bar_w = 800.0 - BAR_MARGIN * 2.0
	var m := BAR_MARGIN
	var h := BAR_H
	var o := BAR_OUTLINE
	var canvas := CanvasLayer.new()
	canvas.layer = BAR_LAYER
	main.add_child(canvas)
	var outer := _make_rect(m - o * 2.0, m - o * 2.0, bar_w + o * 4.0, h + o * 4.0, Color.WHITE)
	var inner := _make_rect(m - o, m - o, bar_w + o * 2.0, h + o * 2.0, Color.BLACK)
	var bg := _make_rect(m, m, bar_w, h, Color.BLACK)
	var fill := _make_rect(m, m, bar_w, h, Color.WHITE)
	var particles := CPUParticles2D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 8
	particles.lifetime = 0.35
	particles.direction = Vector2(1.0, -1.0).normalized()
	particles.spread = 45.0
	particles.initial_velocity_min = 120.0
	particles.initial_velocity_max = 220.0
	particles.gravity = Vector2(0.0, 200.0)
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	canvas.add_child(outer)
	canvas.add_child(inner)
	canvas.add_child(bg)
	canvas.add_child(fill)
	canvas.add_child(particles)
	_bars[key] = {
		"canvas": canvas,
		"outer": outer,
		"fill": fill,
		"bar_w": bar_w,
		"particles": particles,
	}

func update_boss_health_bar(boss: Node, hp: int, max_hp: int, visible: bool, tint: Color) -> void:
	var key := boss.get_instance_id()
	if not _bars.has(key):
		return
	var bar: Dictionary = _bars[key]
	var canvas: CanvasLayer = bar["canvas"]
	if not is_instance_valid(canvas):
		_bars.erase(key)
		return
	canvas.visible = visible
	if not visible:
		return
	var outer: ColorRect = bar["outer"]
	var fill: ColorRect = bar["fill"]
	var bar_w: float = bar["bar_w"]
	outer.color = tint
	fill.color = tint
	fill.size.x = bar_w * clampf(float(hp) / float(max_hp), 0.0, 1.0)
	var particles: CPUParticles2D = bar["particles"]
	particles.color = tint
	particles.position = Vector2(BAR_MARGIN + fill.size.x, BAR_MARGIN + BAR_H * 0.5)

func remove_boss_health_bar(boss: Node) -> void:
	var key := boss.get_instance_id()
	if not _bars.has(key):
		return
	var canvas = _bars[key]["canvas"]
	_bars.erase(key)
	if is_instance_valid(canvas):
		canvas.queue_free()

func shake_boss_health_bar(boss: Node) -> void:
	var key := boss.get_instance_id()
	if not _bars.has(key):
		return
	var entry: Dictionary = _bars[key]
	var canvas = entry["canvas"]
	if not is_instance_valid(canvas):
		return
	if entry.get("shaking", false):
		return
	entry["shaking"] = true
	var particles: CPUParticles2D = entry["particles"]
	if is_instance_valid(particles):
		particles.restart()
	var tween = canvas.create_tween()
	tween.tween_property(canvas, "offset", Vector2(2.0, randf_range(-2.0, 2.0)), 0.05)
	tween.tween_property(canvas, "offset", Vector2(-2.0, randf_range(-2.0, 2.0)), 0.05)
	tween.tween_property(canvas, "offset", Vector2.ZERO, 0.04)
	tween.tween_callback(func(): entry["shaking"] = false)

func create_sprite_health_bar(enemy: Node, bar_width: float = 32.0, offset_y: float = -10.0) -> void:
	var key := enemy.get_instance_id()
	if _sprite_bars.has(key):
		return
	var h := SPRITE_BAR_H
	var o := SPRITE_BAR_OUTLINE
	var w := bar_width
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.position = Vector2(0.0, offset_y)
	root.z_index = SPRITE_BAR_Z
	enemy.add_child(root)
	enemy.move_child(root, 0)
	var outer := _make_rect(-o * 2.0, -o * 2.0, w + o * 4.0, h + o * 4.0, Color.WHITE)
	var inner := _make_rect(-o, -o, w + o * 2.0, h + o * 2.0, Color.BLACK)
	var bg := _make_rect(0.0, 0.0, w, h, Color.BLACK)
	var fill := _make_rect(0.0, 0.0, w, h, Color.WHITE)
	root.add_child(outer)
	root.add_child(inner)
	root.add_child(bg)
	root.add_child(fill)
	_sprite_bars[key] = {
		"root": root,
		"outer": outer,
		"fill": fill,
		"bar_w": w,
	}

func update_sprite_health_bar(enemy: Node, hp: int, max_hp: int, visible: bool) -> void:
	var key := enemy.get_instance_id()
	if not _sprite_bars.has(key):
		return
	var bar: Dictionary = _sprite_bars[key]
	var root: Control = bar["root"]
	if not is_instance_valid(root):
		_sprite_bars.erase(key)
		return
	root.visible = visible
	if not visible:
		return
	var fill: ColorRect = bar["fill"]
	var bar_w: float = bar["bar_w"]
	fill.size.x = bar_w * clampf(float(hp) / float(max_hp), 0.0, 1.0)

func remove_sprite_health_bar(enemy: Node) -> void:
	var key := enemy.get_instance_id()
	if not _sprite_bars.has(key):
		return
	var root = _sprite_bars[key]["root"]
	_sprite_bars.erase(key)
	if is_instance_valid(root):
		root.get_parent().remove_child(root)
		root.queue_free()

func _make_rect(x: float, y: float, w: float, h: float, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = Vector2(x, y)
	r.size = Vector2(w, h)
	r.color = color
	return r
