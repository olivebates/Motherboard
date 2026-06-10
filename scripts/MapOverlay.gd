extends CanvasLayer

signal teleport_requested(room: Vector2i)

const CELL_W := 24
const CELL_H := 12
const GAP_X := 6
const GAP_Y := 6
const STEP_X := CELL_W + GAP_X
const STEP_Y := CELL_H + GAP_Y
const ROOM_W := 25
const ROOM_H := 12

const SLIDE_DURATION := 0.15
const PULSE_INTERVAL := 0.5
const INSTR_FONT_SIZE := 11

var _visited: Dictionary = {}
var _cursor := Vector2i.ZERO
var _open := false
var _teleport_mode := false
var _open_panel_rooms: Array = []
var _main
var _wall_tilemap: TileMapLayer
var _draw_node: Node2D
var _slide_tween: Tween = null

# Pulsing hint state
var _pulse_timer := 0.0
var _pulse_large := false
var _space_hint_done := false
var _wasd_hint_done := false

# First-time-with-two-teleports delay
var _first_two_done := false
var _input_delay := 0.0

# The room of the first teleport panel the player activated
var _first_teleport_room := Vector2i(-9999, -9999)
var _first_teleport_room_set := false

func _ready() -> void:
	layer = 10
	_draw_node = Node2D.new()
	_draw_node.draw.connect(_on_draw)
	_draw_node.visible = false
	add_child(_draw_node)

func setup(main: Node, wall_tilemap: TileMapLayer) -> void:
	_main = main
	_wall_tilemap = wall_tilemap

func visit(room: Vector2i) -> void:
	_visited[room] = true
	_cursor = room
	if _open:
		_draw_node.queue_redraw()

func _process(delta: float) -> void:
	if not _open:
		return
	if _input_delay > 0.0:
		_input_delay -= delta
		_draw_node.queue_redraw()
		return
	var needs_pulse := (_teleport_mode and not _space_hint_done) or \
		(_teleport_mode and _open_panel_rooms.size() > 1 and not _wasd_hint_done)
	if needs_pulse:
		_pulse_timer += delta
		if _pulse_timer >= PULSE_INTERVAL:
			_pulse_timer -= PULSE_INTERVAL
			_pulse_large = not _pulse_large
			_draw_node.queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		if _open:
			_close_map()
		else:
			_open_panel_rooms = _main.get_open_teleport_panel_rooms() if _main != null else []
			_teleport_mode = _main != null and _main.can_teleport_from_panel()
			_open_map()
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	get_viewport().set_input_as_handled()
	if _input_delay > 0.0:
		return
	if not _teleport_mode:
		return
	if event.is_action_pressed("move_up"):
		_try_move_cursor(Vector2i(0, -1))
	elif event.is_action_pressed("move_down"):
		_try_move_cursor(Vector2i(0, 1))
	elif event.is_action_pressed("move_left"):
		_try_move_cursor(Vector2i(-1, 0))
	elif event.is_action_pressed("move_right"):
		_try_move_cursor(Vector2i(1, 0))
	elif event.is_action_pressed("place_prong"):
		if _open_panel_rooms.has(_cursor):
			_space_hint_done = true
			if not _wasd_hint_done and _cursor != _first_teleport_room:
				_wasd_hint_done = true
			teleport_requested.emit(_cursor)
			_close_map()

func _try_move_cursor(dir: Vector2i) -> void:
	var best: Vector2i = _cursor
	var best_score := INF
	for room in _open_panel_rooms:
		var rv: Vector2i = room
		if rv == _cursor:
			continue
		var delta := rv - _cursor
		var dot := delta.x * dir.x + delta.y * dir.y
		if dot <= 0:
			continue
		var forward := float(dot)
		var perp := absf(float(delta.x * dir.y - delta.y * dir.x))
		var score := perp * 3.0 + forward
		if score < best_score:
			best_score = score
			best = rv
	if best != _cursor:
		_cursor = best
		_draw_node.queue_redraw()

func _open_map() -> void:
	_open = true
	_pulse_timer = 0.0
	_pulse_large = true
	_draw_node.visible = true
	_draw_node.position.y = -384.0
	if _teleport_mode and not _open_panel_rooms.is_empty():
		var cur_room: Vector2i = _main.current_room if _main else Vector2i.ZERO
		if _open_panel_rooms.has(cur_room):
			_cursor = cur_room
		else:
			_cursor = _open_panel_rooms[0]
		# Record first teleport room
		if not _first_teleport_room_set:
			_first_teleport_room = cur_room if _open_panel_rooms.has(cur_room) else _open_panel_rooms[0]
			_first_teleport_room_set = true
		# 1-second delay on first opening with 2+ teleports
		if not _first_two_done and _open_panel_rooms.size() >= 2:
			_first_two_done = true
			_input_delay = 1.0
	_draw_node.queue_redraw()
	if _main:
		_main.player.lock_movement()
	if _slide_tween:
		_slide_tween.kill()
	_slide_tween = _draw_node.create_tween()
	_slide_tween.set_ease(Tween.EASE_OUT)
	_slide_tween.set_trans(Tween.TRANS_SINE)
	_slide_tween.tween_property(_draw_node, "position:y", 0.0, SLIDE_DURATION)

func _close_map() -> void:
	_open = false
	if _main:
		_main.player.unlock_movement()
	if _slide_tween:
		_slide_tween.kill()
	_slide_tween = _draw_node.create_tween()
	_slide_tween.set_ease(Tween.EASE_IN)
	_slide_tween.set_trans(Tween.TRANS_SINE)
	_slide_tween.tween_property(_draw_node, "position:y", -384.0, SLIDE_DURATION)
	_slide_tween.tween_callback(func() -> void: _draw_node.visible = false)

func _has_exit(room: Vector2i, dir: Vector2i) -> bool:
	if _wall_tilemap == null:
		return false
	var rx0 := room.x * ROOM_W
	var ry0 := room.y * ROOM_H
	if dir.x == 1:
		var col := rx0 + ROOM_W
		for row in range(ry0, ry0 + ROOM_H):
			if _wall_tilemap.get_cell_source_id(Vector2i(col, row)) == -1:
				return true
	elif dir.x == -1:
		var col := rx0
		for row in range(ry0, ry0 + ROOM_H):
			if _wall_tilemap.get_cell_source_id(Vector2i(col, row)) == -1:
				return true
	elif dir.y == 1:
		var row := ry0 + ROOM_H
		for col in range(rx0, rx0 + ROOM_W):
			if _wall_tilemap.get_cell_source_id(Vector2i(col, row)) == -1:
				return true
	elif dir.y == -1:
		var row := ry0
		for col in range(rx0, rx0 + ROOM_W):
			if _wall_tilemap.get_cell_source_id(Vector2i(col, row)) == -1:
				return true
	return false

func _room_to_screen(room: Vector2i, origin: Vector2, min_room: Vector2i) -> Vector2:
	return origin + Vector2((room.x - min_room.x) * STEP_X, (room.y - min_room.y) * STEP_Y)

func _on_draw() -> void:
	if _visited.is_empty():
		return

	var vp := Vector2(800.0, 384.0)
	var tint: Color = _main.modulate if _main else Color.WHITE

	var all_rooms: Dictionary = {}
	for r in _visited:
		all_rooms[r] = true
	for r in _open_panel_rooms:
		all_rooms[r] = true

	var keys := all_rooms.keys()
	var min_room: Vector2i = keys[0]
	var max_room: Vector2i = keys[0]
	for r in keys:
		var rv := r as Vector2i
		if rv.x < min_room.x: min_room.x = rv.x
		if rv.x > max_room.x: max_room.x = rv.x
		if rv.y < min_room.y: min_room.y = rv.y
		if rv.y > max_room.y: max_room.y = rv.y

	var total_w := float((max_room.x - min_room.x) * STEP_X + CELL_W)
	var total_h := float((max_room.y - min_room.y) * STEP_Y + CELL_H)
	var map_area_h := vp.y - 28.0
	var origin := Vector2((vp.x - total_w) * 0.5, (map_area_h - total_h) * 0.5)

	var map_bottom := origin.y + (max_room.y - min_room.y) * STEP_Y + CELL_H + 36.0
	const PAD := 20.0
	const NAME_FONT_SIZE := 16

	var pname := _get_panel_name_for_room(_cursor) if _teleport_mode else ""
	var font := ThemeDB.fallback_font

	# Build instruction parts: [{text, size}]
	var parts: Array = []
	var sep := "    "
	var pulse_size := INSTR_FONT_SIZE + (1 if _pulse_large else 0)

	if _teleport_mode:
		if _open_panel_rooms.size() > 1:
			var wasd_size := pulse_size if not _wasd_hint_done else INSTR_FONT_SIZE
			parts.append({"text": "WASD/Arrow Keys: Move", "size": wasd_size})
			parts.append({"text": sep, "size": INSTR_FONT_SIZE})
		var space_size := pulse_size if not _space_hint_done else INSTR_FONT_SIZE
		parts.append({"text": "Space: Teleport", "size": space_size})
		parts.append({"text": sep, "size": INSTR_FONT_SIZE})
	parts.append({"text": "TAB: Close", "size": INSTR_FONT_SIZE})

	var total_instr_w := 0.0
	for p in parts:
		total_instr_w += font.get_string_size(p["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, p["size"]).x

	var name_h := float(NAME_FONT_SIZE) + 8.0 if pname != "" else 0.0
	var content_top := origin.y - name_h
	var instr_h := float(INSTR_FONT_SIZE + 2)
	var content_bottom := map_bottom + instr_h

	var name_w := font.get_string_size(pname, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT_SIZE).x if pname != "" else 0.0
	var content_w := maxf(total_w, maxf(total_instr_w, name_w))

	# Minimum half-screen size
	content_w = maxf(content_w, vp.x * 0.5 - PAD * 2.0)
	var current_h := content_bottom - content_top + PAD * 2.0
	if current_h < vp.y * 0.5:
		var expand := (vp.y * 0.5 - current_h) * 0.5
		content_top -= expand
		content_bottom += expand

	var box_x := (vp.x - content_w) * 0.5 - PAD
	var box := Rect2(
		box_x,
		content_top - PAD,
		content_w + PAD * 2.0,
		content_bottom - content_top + PAD * 2.0
	)
	_draw_node.draw_rect(box, Color.BLACK)
	_draw_node.draw_rect(box, tint, false, 2.0)

	var cur_room: Vector2i = _main.current_room if _main else Vector2i.ZERO
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var origin_x_for_text := box.position.x

	for room in all_rooms:
		var rv := room as Vector2i
		var ca := _room_to_screen(rv, origin, min_room) + Vector2(CELL_W, CELL_H) * 0.5
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var n: Vector2i = rv + d
			if all_rooms.has(n) and _has_exit(rv, d):
				var cb := _room_to_screen(n, origin, min_room) + Vector2(CELL_W, CELL_H) * 0.5
				_draw_node.draw_line(ca, cb, tint, 1.0)

	for room in all_rooms:
		var rv := room as Vector2i
		var sp := _room_to_screen(rv, origin, min_room)
		var rect := Rect2(sp, Vector2(CELL_W, CELL_H))
		_draw_node.draw_rect(rect, tint)
		if _open_panel_rooms.has(rv):
			var center := sp + Vector2(CELL_W, CELL_H) * 0.5
			_draw_node.draw_circle(center, 2.0, Color.BLACK)

		for d in dirs:
			var n: Vector2i = rv + d
			if not all_rooms.has(n) and _has_exit(rv, d):
				var stub_from: Vector2
				var stub_to: Vector2
				if d.x == 1:
					stub_from = sp + Vector2(CELL_W, CELL_H * 0.5)
					stub_to = stub_from + Vector2(3, 0)
				elif d.x == -1:
					stub_from = sp + Vector2(0, CELL_H * 0.5)
					stub_to = stub_from + Vector2(-3, 0)
				elif d.y == 1:
					stub_from = sp + Vector2(CELL_W * 0.5, CELL_H)
					stub_to = stub_from + Vector2(0, 3)
				else:
					stub_from = sp + Vector2(CELL_W * 0.5, 0)
					stub_to = stub_from + Vector2(0, -3)
				_draw_node.draw_line(stub_from, stub_to, tint, 1.0)

	if _teleport_mode:
		var csp := _room_to_screen(_cursor, origin, min_room)
		_draw_node.draw_rect(Rect2(csp - Vector2(1, 1), Vector2(CELL_W + 3, CELL_H + 3)), tint, false, 1.0)
		if pname != "":
			_draw_node.draw_string(font, Vector2(origin_x_for_text, origin.y - 8.0),
					pname, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, NAME_FONT_SIZE, tint)

	# Draw instruction parts inline, centered as a group
	var instr_x := (vp.x - total_instr_w) * 0.5
	for p in parts:
		var sz: int = p["size"]
		# Align baseline: shift up if larger font so baseline matches INSTR_FONT_SIZE baseline
		var y_off := map_bottom - float(sz - INSTR_FONT_SIZE) * 0.5
		_draw_node.draw_string(font, Vector2(instr_x, y_off), p["text"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, sz, tint)
		instr_x += font.get_string_size(p["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x

	# Show input delay countdown as dim overlay text
	if _input_delay > 0.0:
		var remaining := ceilf(_input_delay)
		_draw_node.draw_string(font, Vector2(vp.x * 0.5 - 20.0, map_bottom + 18.0),
				"...", HORIZONTAL_ALIGNMENT_CENTER, 40.0, INSTR_FONT_SIZE,
				Color(tint.r, tint.g, tint.b, 0.5))

func _get_panel_name_for_room(room: Vector2i) -> String:
	var rx0 := room.x * ROOM_W
	var ry0 := room.y * ROOM_H
	for panel in _main.get_tree().get_nodes_in_group("teleport_panels"):
		if not panel.is_open:
			continue
		var gp: Vector2i = panel.get_grid_pos()
		if gp.x >= rx0 and gp.x < rx0 + ROOM_W and gp.y >= ry0 and gp.y < ry0 + ROOM_H:
			return panel.panel_name
	return ""
