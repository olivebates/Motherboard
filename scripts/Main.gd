extends Node2D

const TILE_SIZE := 32
const WORLD_OFFSET := 0
const ROOM_WIDTH := 25
const ROOM_HEIGHT := 12
const ROOM_PIXEL_WIDTH := ROOM_WIDTH * TILE_SIZE
const ROOM_PIXEL_HEIGHT := ROOM_HEIGHT * TILE_SIZE
const CAMERA_TWEEN_DURATION := 0.25
const CAMERA_MARGIN := Vector2(16.0, 16.0)

@onready var wall_tilemap: TileMapLayer = $Walls

var current_room := Vector2i(0, 0)
var room_entry_positions: Dictionary = {}
var _cam_tween: Tween = null
var _shake_amount := 0.0

@onready var player: Node2D = $Player
@onready var camera: Camera2D = $Camera2D
@onready var electric_beam: Node2D = $ElectricBeam

var reset_effect: Node
var map_overlay: Node
var _color_tween: Tween = null

const ProngScene = preload("res://scenes/Prong.tscn")

const ResetEffectScene = preload("res://scripts/ResetEffect.gd")
const SplashScreenScene = preload("res://scripts/SplashScreen.gd")
const MapOverlayScene = preload("res://scripts/MapOverlay.gd")

const Y_SORT_GROUPS := [
	"players",
	"prongs",
	"doors",
	"lightning_blockers",
	"key_doors",
	"push_blocks",
	"pass_blocks",
	"keys",
]

func _ready() -> void:
	_setup_y_sort_children()
	room_entry_positions[Vector2i(0, 0)] = Vector2i(2, 2)
	reset_effect = ResetEffectScene.new()
	add_child(reset_effect)
	reset_effect.color = modulate
	map_overlay = MapOverlayScene.new()
	add_child(map_overlay)
	map_overlay.setup(self, wall_tilemap)
	map_overlay.teleport_requested.connect(_on_teleport_requested)
	map_overlay.visit(current_room)
	camera.position = _room_center(Vector2i(0, 0))
	GameManager.shake_requested.connect(_trigger_shake)
	queue_redraw()
	var start_anchor := _get_anchor_for_room(current_room)
	if start_anchor != null:
		modulate = start_anchor.color
		reset_effect.color = modulate
	var splash := SplashScreenScene.new()
	add_child(splash)
	player.lock_movement()


func _setup_y_sort_children() -> void:
	if wall_tilemap == null:
		return
	wall_tilemap.y_sort_enabled = true
	y_sort_enabled = false
	var reparented := {}
	for group_name in Y_SORT_GROUPS:
		for node in get_tree().get_nodes_in_group(group_name):
			if not node is Node2D or node.get_parent() != self:
				continue
			if reparented.has(node):
				continue
			reparented[node] = true
			node.reparent(wall_tilemap, true)

func _process(delta: float) -> void:
	_shake_amount = lerpf(_shake_amount, 0.0, 20.0 * delta)
	camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_amount

func _trigger_shake(strength: float) -> void:
	_shake_amount = strength

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_room") and not player.movement_locked:
		_reset_room()

func _reset_room() -> void:
	player.lock_movement()
	reset_effect.play()
	await reset_effect.peaked
	var rx0 := current_room.x * ROOM_WIDTH
	var ry0 := current_room.y * ROOM_HEIGHT
	for p in GameManager.prongs.duplicate():
		var gp: Vector2i = p["grid_pos"]
		if gp.x >= rx0 and gp.x < rx0 + ROOM_WIDTH and gp.y >= ry0 and gp.y < ry0 + ROOM_HEIGHT:
			GameManager.remove_prong(p["node"])
			p["node"].queue_free()
	_update_beam()
	for block in get_tree().get_nodes_in_group("push_blocks"):
		var sgp: Vector2i = block.start_grid_pos
		if sgp.x >= rx0 and sgp.x < rx0 + ROOM_WIDTH and sgp.y >= ry0 and sgp.y < ry0 + ROOM_HEIGHT:
			block.reset()
	for door in get_tree().get_nodes_in_group("key_doors"):
		var dgp: Vector2i = door.get_grid_pos()
		if dgp.x >= rx0 and dgp.x < rx0 + ROOM_WIDTH and dgp.y >= ry0 and dgp.y < ry0 + ROOM_HEIGHT:
			door.reset()
	for key in get_tree().get_nodes_in_group("keys"):
		var kgp: Vector2i = key.start_grid_pos
		if kgp.x >= rx0 and kgp.x < rx0 + ROOM_WIDTH and kgp.y >= ry0 and kgp.y < ry0 + ROOM_HEIGHT:
			key.reset()
	player.reset_to(room_entry_positions.get(current_room, Vector2i(2, 2)))
	await reset_effect.done
	player.unlock_movement()

func tile_rect(grid_pos: Vector2i) -> Rect2:
	return Rect2(
		grid_pos.x * TILE_SIZE,
		grid_pos.y * TILE_SIZE,
		float(TILE_SIZE),
		float(TILE_SIZE)
	)

func _is_static_solid(grid_pos: Vector2i) -> bool:
	if wall_tilemap != null and wall_tilemap.get_cell_source_id(grid_pos) != -1:
		return true
	for door in get_tree().get_nodes_in_group("doors"):
		if not door.is_open and door.get_grid_pos() == grid_pos:
			return true
	for blocker in get_tree().get_nodes_in_group("lightning_blockers"):
		if blocker.get_grid_pos() == grid_pos:
			return true
	for door_block in get_tree().get_nodes_in_group("key_doors"):
		if door_block.get_grid_pos() == grid_pos:
			return true
	return false

func is_blocked(grid_pos: Vector2i) -> bool:
	if _is_static_solid(grid_pos):
		return true
	for block in get_tree().get_nodes_in_group("push_blocks"):
		if block.grid_pos == grid_pos:
			return true
	return false

func get_player_blocking_rects(area: Rect2) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var x0 := floori(area.position.x / TILE_SIZE)
	var x1 := floori((area.end.x - 0.001) / TILE_SIZE)
	var y0 := floori(area.position.y / TILE_SIZE)
	var y1 := floori((area.end.y - 0.001) / TILE_SIZE)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var gp := Vector2i(x, y)
			if _is_static_solid(gp):
				rects.append(tile_rect(gp))
	for block in get_tree().get_nodes_in_group("push_blocks"):
		var block_rect: Rect2 = block.get_collision_rect()
		if area.intersects(block_rect):
			rects.append(block_rect)
	return rects

func can_push_block_to(grid_pos: Vector2i) -> bool:
	if _is_static_solid(grid_pos):
		return false
	if get_push_block_at(grid_pos) != null:
		return false
	if has_pass_block_at(grid_pos):
		return false
	return true

func get_push_block_at_face(player_rect: Rect2, dir: Vector2i, from_point: Vector2) -> Node:
	const FACE_EPS := 0.1
	var closest: Node = null
	var closest_dist := INF
	for block in get_tree().get_nodes_in_group("push_blocks"):
		var block_rect: Rect2 = block.get_collision_rect()
		if dir.x > 0:
			if absf(player_rect.end.x - block_rect.position.x) > FACE_EPS:
				continue
		elif dir.x < 0:
			if absf(player_rect.position.x - block_rect.end.x) > FACE_EPS:
				continue
		elif dir.y > 0:
			if absf(player_rect.end.y - block_rect.position.y) > FACE_EPS:
				continue
		elif absf(player_rect.position.y - block_rect.end.y) > FACE_EPS:
			continue
		var aligned := _rects_overlap_y(player_rect, block_rect) if dir.x != 0 else _rects_overlap_x(player_rect, block_rect)
		if not aligned:
			continue
		var dist := from_point.distance_squared_to(block_rect.get_center())
		if dist < closest_dist:
			closest_dist = dist
			closest = block
	return closest

func _rects_overlap_x(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.end.x and b.position.x < a.end.x

func _rects_overlap_y(a: Rect2, b: Rect2) -> bool:
	return a.position.y < b.end.y and b.position.y < a.end.y

func has_pass_block_at(grid_pos: Vector2i) -> bool:
	for block in get_tree().get_nodes_in_group("pass_blocks"):
		if block.get_grid_pos() == grid_pos:
			return true
	return false

func get_push_block_at(grid_pos: Vector2i) -> Node:
	for block in get_tree().get_nodes_in_group("push_blocks"):
		if block.grid_pos == grid_pos:
			return block
	return null

func check_room_transition(player_grid: Vector2i) -> void:
	var player_room := Vector2i(
		floori(float(player_grid.x) / ROOM_WIDTH),
		floori(float(player_grid.y) / ROOM_HEIGHT)
	)
	if player_room != current_room:
		_transition_to_room(player_room)

func _transition_to_room(new_room: Vector2i) -> void:
	var direction := new_room - current_room
	room_entry_positions[new_room] = player.grid_pos + direction

	for p in GameManager.clear_prongs():
		p["node"].queue_free()
	_update_beam()

	current_room = new_room
	map_overlay.visit(current_room)

	var anchor := _get_anchor_for_room(new_room)
	if anchor != null and anchor.color != modulate:
		if _color_tween:
			_color_tween.kill()
		_color_tween = create_tween()
		_color_tween.tween_property(self, "modulate", anchor.color, CAMERA_TWEEN_DURATION)
		reset_effect.color = anchor.color

	player.lock_movement()
	if _cam_tween:
		_cam_tween.kill()
	var target := _room_center(new_room)
	_cam_tween = create_tween()
	_cam_tween.set_ease(Tween.EASE_IN_OUT)
	_cam_tween.set_trans(Tween.TRANS_SINE)
	_cam_tween.tween_property(camera, "position", target, CAMERA_TWEEN_DURATION)
	_cam_tween.finished.connect(func(): player.unlock_movement())

func _get_anchor_for_room(room: Vector2i) -> Node:
	var rx0 := room.x * ROOM_WIDTH
	var ry0 := room.y * ROOM_HEIGHT
	for anchor in get_tree().get_nodes_in_group("teleport_anchors"):
		var gp := Vector2i(floori(anchor.position.x / TILE_SIZE), floori(anchor.position.y / TILE_SIZE))
		if gp.x >= rx0 and gp.x < rx0 + ROOM_WIDTH and gp.y >= ry0 and gp.y < ry0 + ROOM_HEIGHT:
			return anchor
	return null

func _on_teleport_requested(room: Vector2i) -> void:
	var anchor := _get_anchor_for_room(room)
	if anchor == null:
		push_error("No TeleportAnchor in room %s" % str(room))
		return
	var spawn_grid := Vector2i(floori(anchor.position.x / TILE_SIZE), floori(anchor.position.y / TILE_SIZE))
	if _is_static_solid(spawn_grid):
		spawn_grid = _find_nearest_open_tile(spawn_grid)
	player.reset_to(spawn_grid)
	_transition_to_room(room)
	room_entry_positions[room] = spawn_grid

func _find_nearest_open_tile(start: Vector2i) -> Vector2i:
	var visited := { start: true }
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var current = queue.pop_front()
		if not _is_static_solid(current):
			return current
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n = current + d
			if not visited.has(n):
				visited[n] = true
				queue.append(n)
	return start

func _room_center(room: Vector2i) -> Vector2:
	return Vector2(
		WORLD_OFFSET + room.x * ROOM_PIXEL_WIDTH + ROOM_PIXEL_WIDTH / 2.0,
		WORLD_OFFSET + room.y * ROOM_PIXEL_HEIGHT + ROOM_PIXEL_HEIGHT / 2.0
	) + CAMERA_MARGIN

func spawn_prong(pixel_pos: Vector2) -> void:
	if GameManager.prongs.size() >= 2:
		# Third press: animate both out and clear
		for p in GameManager.clear_prongs():
			var node: Node2D = p["node"]
			var tween := node.create_tween()
			tween.tween_method(node.apply_clear_shrink, 1.0, 0.0, 0.15)
			tween.tween_callback(node.queue_free)
		_update_beam()
		_trigger_shake(6.0)
		return
	var prong := ProngScene.instantiate()
	wall_tilemap.add_child(prong)
	prong.setup(pixel_pos)
	GameManager.place_prong(prong, _world_to_grid(pixel_pos))
	_update_beam()
	_trigger_shake(5.0)

func _update_beam() -> void:
	var world_positions := GameManager.get_prong_world_positions()
	if world_positions.size() == 2:
		var path := _compute_beam_path(world_positions[0], world_positions[1])
		if path.is_empty():
			# No valid path — flash blockers on the direct line so the player sees what's in the way
			GameManager.beam_blocked = true
			GameManager.evaluate_puzzle()
			electric_beam.deactivate()
			var blocking := _get_beam_blockers(world_positions[0], world_positions[1])
			var flashing := _expand_connected_blockers(blocking)
			for b in get_tree().get_nodes_in_group("lightning_blockers"):
				b.set_blocking(b in flashing)
		else:
			GameManager.beam_blocked = false
			GameManager.evaluate_puzzle()
			electric_beam.activate(path)
			for b in get_tree().get_nodes_in_group("lightning_blockers"):
				b.set_blocking(false)
	else:
		GameManager.beam_blocked = false
		GameManager.evaluate_puzzle()
		electric_beam.deactivate()
		for b in get_tree().get_nodes_in_group("lightning_blockers"):
			b.set_blocking(false)

func _compute_beam_path(pos_a: Vector2, pos_b: Vector2) -> Array:
	var rx0 := current_room.x * ROOM_WIDTH
	var ry0 := current_room.y * ROOM_HEIGHT
	var nut_nodes: Array = []
	for nut in get_tree().get_nodes_in_group("nuts"):
		var gp: Vector2i = nut.grid_pos
		if gp.x >= rx0 and gp.x < rx0 + ROOM_WIDTH and gp.y >= ry0 and gp.y < ry0 + ROOM_HEIGHT:
			nut_nodes.append(nut)

	# Path stores Vector2 for prong endpoints and Node2D for nuts so ElectricBeam
	# can resolve nut positions each frame and follow the sliding sprite.
	var result := {"path": [], "len": INF}
	_search_beam(pos_a, pos_b, nut_nodes, [pos_a], 0.0, result)
	return result["path"]

func _search_beam(current: Vector2, target: Vector2, remaining: Array, path: Array, length: float, result: Dictionary) -> void:
	var to_target := current.distance_to(target)
	if length + to_target < result["len"] and _get_beam_blockers(current, target).is_empty():
		result["len"] = length + to_target
		result["path"] = path + [target]

	for i in range(remaining.size()):
		var nut: Node2D = remaining[i]
		var nut_pos: Vector2 = nut.get_beam_point()
		var to_nut := current.distance_to(nut_pos)
		if length + to_nut >= result["len"]:
			continue
		if not _get_beam_blockers(current, nut_pos).is_empty():
			continue
		var next_remaining := remaining.duplicate()
		next_remaining.remove_at(i)
		_search_beam(nut_pos, target, next_remaining, path + [nut], length + to_nut, result)

func _expand_connected_blockers(seed: Array) -> Array:
	if seed.is_empty():
		return []
	var all_blockers := get_tree().get_nodes_in_group("lightning_blockers")
	var blocker_by_pos: Dictionary = {}
	for b in all_blockers:
		blocker_by_pos[b.get_grid_pos()] = b
	var result: Array = []
	var visited: Dictionary = {}
	var queue: Array = seed.duplicate()
	for b in queue:
		visited[b] = true
		result.append(b)
	while not queue.is_empty():
		var current = queue.pop_front()
		var gp: Vector2i = current.get_grid_pos()
		for offset in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var neighbor_pos = gp + offset
			if blocker_by_pos.has(neighbor_pos):
				var neighbor = blocker_by_pos[neighbor_pos]
				if not visited.has(neighbor):
					visited[neighbor] = true
					result.append(neighbor)
					queue.append(neighbor)
	return result

func _get_beam_blockers(pos_a: Vector2, pos_b: Vector2) -> Array:
	var blocking: Array = []
	for b in get_tree().get_nodes_in_group("lightning_blockers"):
		var gp = b.get_grid_pos()
		var rect := Rect2(Vector2(gp.x * TILE_SIZE, gp.y * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE))
		if _segment_intersects_rect(pos_a, pos_b, rect):
			blocking.append(b)
	return blocking

func _segment_intersects_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var c := [rect.position,
			  Vector2(rect.end.x, rect.position.y),
			  rect.end,
			  Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, c[i], c[(i + 1) % 4]) != null:
			return true
	return false

func _world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori((world_pos.x - WORLD_OFFSET) / TILE_SIZE),
		floori((world_pos.y - WORLD_OFFSET) / TILE_SIZE)
	)
