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

var _visited: Dictionary = {}
var _cursor := Vector2i.ZERO
var _open := false
var _main
var _wall_tilemap: TileMapLayer
var _draw_node: Node2D

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

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		if _open:
			_close_map()
		else:
			_open_map()
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("move_up"):
		_try_move_cursor(Vector2i(0, -1))
	elif event.is_action_pressed("move_down"):
		_try_move_cursor(Vector2i(0, 1))
	elif event.is_action_pressed("move_left"):
		_try_move_cursor(Vector2i(-1, 0))
	elif event.is_action_pressed("move_right"):
		_try_move_cursor(Vector2i(1, 0))
	elif event.is_action_pressed("place_prong"):
		if _visited.has(_cursor):
			teleport_requested.emit(_cursor)
			_close_map()

func _try_move_cursor(dir: Vector2i) -> void:
	var next := _cursor + dir
	if _visited.has(next):
		_cursor = next
		_draw_node.queue_redraw()

func _open_map() -> void:
	_open = true
	_draw_node.visible = true
	_draw_node.queue_redraw()
	if _main:
		_main.player.lock_movement()

func _close_map() -> void:
	_open = false
	_draw_node.visible = false
	if _main:
		_main.player.unlock_movement()

func _has_exit(room: Vector2i, dir: Vector2i) -> bool:
	if _wall_tilemap == null:
		return false
	var rx0 := room.x * ROOM_W
	var ry0 := room.y * ROOM_H
	if dir.x == 1:
		var col := rx0 + ROOM_W - 1
		for row in range(ry0, ry0 + ROOM_H):
			if _wall_tilemap.get_cell_source_id(Vector2i(col, row)) == -1:
				return true
	elif dir.x == -1:
		var col := rx0
		for row in range(ry0, ry0 + ROOM_H):
			if _wall_tilemap.get_cell_source_id(Vector2i(col, row)) == -1:
				return true
	elif dir.y == 1:
		var row := ry0 + ROOM_H - 1
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
	var vp := Vector2(800.0, 384.0)
	_draw_node.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.0, 0.0, 0.0, 0.92))

	if _visited.is_empty():
		return

	# Bounding box over visited rooms only
	var keys := _visited.keys()
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

	var cur_room: Vector2i = _main.current_room if _main else Vector2i.ZERO
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	# Connections between visited rooms
	for room in _visited:
		var rv := room as Vector2i
		var ca := _room_to_screen(rv, origin, min_room) + Vector2(CELL_W, CELL_H) * 0.5
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var n: Vector2i = rv + d
			if _visited.has(n):
				var cb := _room_to_screen(n, origin, min_room) + Vector2(CELL_W, CELL_H) * 0.5
				_draw_node.draw_line(ca, cb, Color(0.5, 0.5, 0.5), 1.0)

	# Visited rooms
	var font := ThemeDB.fallback_font
	for room in _visited:
		var rv := room as Vector2i
		var sp := _room_to_screen(rv, origin, min_room)
		var rect := Rect2(sp, Vector2(CELL_W, CELL_H))
		_draw_node.draw_rect(rect, Color(0.28, 0.28, 0.28))
		if rv == cur_room:
			_draw_node.draw_rect(rect, Color(0.4, 0.8, 1.0, 0.25))

		# Exit stubs toward undiscovered rooms
		for d in dirs:
			var n: Vector2i = rv + d
			if not _visited.has(n) and _has_exit(rv, d):
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
				_draw_node.draw_line(stub_from, stub_to, Color(0.4, 0.4, 0.4), 1.0)

	# Cursor
	var csp := _room_to_screen(_cursor, origin, min_room)
	_draw_node.draw_rect(Rect2(csp, Vector2(CELL_W, CELL_H)), Color(1.0, 1.0, 0.3), false, 2.0)

	# Bottom label — centered X, below the lowest room
	var map_bottom := origin.y + (max_room.y - min_room.y) * STEP_Y + CELL_H + 36.0
	_draw_node.draw_string(font, Vector2(0.0, map_bottom),
			"WASD: Move    Space: Teleport",
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 11, Color.WHITE)
