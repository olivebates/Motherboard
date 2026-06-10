extends Node

const BAR_MARGIN := 10.0
const BAR_H := 16.0
const BAR_OUTLINE := 2.0
const BAR_LAYER := 25

var _bars: Dictionary = {}

func create_boss_health_bar(boss: Node, main: Node) -> void:
	var key := boss.get_instance_id()
	if _bars.has(key):
		return
	var vp := main.get_viewport().get_visible_rect()
	var bar_w := vp.size.x - BAR_MARGIN * 2.0
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
	canvas.add_child(outer)
	canvas.add_child(inner)
	canvas.add_child(bg)
	canvas.add_child(fill)
	_bars[key] = {
		"canvas": canvas,
		"outer": outer,
		"fill": fill,
		"bar_w": bar_w,
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

func remove_boss_health_bar(boss: Node) -> void:
	var key := boss.get_instance_id()
	if not _bars.has(key):
		return
	var canvas: CanvasLayer = _bars[key]["canvas"]
	if is_instance_valid(canvas):
		canvas.queue_free()
	_bars.erase(key)

func _make_rect(x: float, y: float, w: float, h: float, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = Vector2(x, y)
	r.size = Vector2(w, h)
	r.color = color
	return r
