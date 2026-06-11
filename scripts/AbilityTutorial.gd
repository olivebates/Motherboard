extends Node

const ARC_HEIGHT := 48.0
const SPHERE_DURATION := 1.2
const SPHERE_RADIUS := 4.0

# Inner node that lives temporarily in the scene to draw arcing spheres
class BoundingHighlight extends Node2D:
	var world_rect: Rect2
	var _time := 0.0
	const COLOR := Color.WHITE
	const LINE_WIDTH := 1.5
	const BASE_PADDING := 4.0

	func _ready() -> void:
		add_to_group("break_highlight")
		z_index = 5

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var pad := BASE_PADDING + sin(_time * PI) * 1.0
		var r := Rect2(world_rect.position - Vector2(pad, pad),
			world_rect.size + Vector2(pad * 2.0, pad * 2.0))
		draw_rect(r, COLOR, false, LINE_WIDTH)


class SphereOverlay extends Node2D:
	var _spheres: Array = []

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		for s in _spheres:
			if not s.get("done", false):
				draw_circle(to_local(s["pos"]), AbilityTutorial.SPHERE_RADIUS, Color.WHITE)


func play_intro(ability: String, player: Node2D, main: Node2D) -> void:
	match ability:
		"push":
			_play_push_intro(player, main)
		"chain":
			_play_chain_intro(player, main)
		"break":
			_play_break_intro(player, main)
		_:
			var msg_overlay = main.ability_message
			msg_overlay.show_message("")
			msg_overlay.dismissed.connect(func(): player.unlock_movement(), CONNECT_ONE_SHOT)


func _play_push_intro(player: Node2D, main: Node2D) -> void:
	var room = main.current_room
	var room_blocks: Array = []
	for b in get_tree().get_nodes_in_group("push_blocks"):
		if not b.has_method("set_highlight"):
			continue
		var block_room := Vector2i(floori(b.grid_pos.x / 25), floori(b.grid_pos.y / 12))
		if block_room == room:
			room_blocks.append(b)

	if room_blocks.is_empty():
		player.unlock_movement()
		return

	var overlay := SphereOverlay.new()
	main.add_child(overlay)

	var start = player.get_body_center()
	var arrived_count := [0]
	var total := room_blocks.size()

	for i in range(total):
		var block: Node2D = room_blocks[i]
		var target := block.position + Vector2(16.0, 16.0)
		overlay._spheres.append({"pos": start, "done": false})
		var idx := i

		var tween := overlay.create_tween()
		tween.tween_method(
			func(t: float) -> void:
				var p = start.lerp(target, t)
				p.y -= sin(t * PI) * ARC_HEIGHT
				overlay._spheres[idx]["pos"] = p,
			0.0, 1.0, SPHERE_DURATION
		)
		tween.tween_callback(func() -> void:
			overlay._spheres[idx]["done"] = true
			block.set_highlight(true)
			arrived_count[0] += 1
			if arrived_count[0] >= total:
				player.unlock_movement()
				overlay.queue_free()
		)


func _play_chain_intro(player: Node2D, main: Node2D) -> void:
	var room = main.current_room
	var rx0 = room.x * 25
	var ry0 = room.y * 12
	var target_panels: Array = []
	for panel in main.get_tree().get_nodes_in_group("floor_panels"):
		if panel.id == "chain1" or panel.get("id2") == "chain1":
			var gp := Vector2i(floori(panel.position.x / 32), floori(panel.position.y / 32))
			if gp.x >= rx0 and gp.x < rx0 + 25 and gp.y >= ry0 and gp.y < ry0 + 12:
				target_panels.append(panel)

	if target_panels.is_empty():
		var msg_overlay = main.ability_message
		msg_overlay.show_message("")
		msg_overlay.dismissed.connect(func(): player.unlock_movement(), CONNECT_ONE_SHOT)
		return

	var overlay := SphereOverlay.new()
	main.add_child(overlay)

	var start = player.get_body_center()
	var arrived_count := [0]
	var total := target_panels.size()

	for i in range(total):
		var panel: Node2D = target_panels[i]
		var target := panel.position + Vector2(16.0, 16.0)
		overlay._spheres.append({"pos": start, "done": false})
		var idx := i

		var tween := overlay.create_tween()
		tween.tween_method(
			func(t: float) -> void:
				var p = start.lerp(target, t)
				p.y -= sin(t * PI) * ARC_HEIGHT
				overlay._spheres[idx]["pos"] = p,
			0.0, 1.0, SPHERE_DURATION
		)
		tween.tween_callback(func() -> void:
			overlay._spheres[idx]["done"] = true
			panel.set_highlight(true)
			arrived_count[0] += 1
			if arrived_count[0] >= total:
				player.unlock_movement()
				overlay.queue_free()
		)


func _play_break_intro(player: Node2D, main: Node2D) -> void:
	var room = main.current_room
	var rx0 = room.x * 25
	var ry0 = room.y * 12
	var room_walls: Array = []
	for wall in main.get_tree().get_nodes_in_group("breakable_walls"):
		var gp = wall.get_grid_pos()
		if gp.x >= rx0 and gp.x < rx0 + 25 and gp.y >= ry0 and gp.y < ry0 + 12:
			room_walls.append(wall)

	if room_walls.is_empty():
		player.unlock_movement()
		return

	var overlay := SphereOverlay.new()
	main.add_child(overlay)

	var start = player.get_body_center()
	var arrived_count := [0]
	var total := room_walls.size()

	for i in range(total):
		var wall: Node2D = room_walls[i]
		var target = wall.get_center()
		overlay._spheres.append({"pos": start, "done": false})
		var idx := i

		var tween := overlay.create_tween()
		tween.tween_method(
			func(t: float) -> void:
				var p = start.lerp(target, t)
				p.y -= sin(t * PI) * ARC_HEIGHT
				overlay._spheres[idx]["pos"] = p,
			0.0, 1.0, SPHERE_DURATION
		)
		tween.tween_callback(func() -> void:
			overlay._spheres[idx]["done"] = true
			arrived_count[0] += 1
			if arrived_count[0] >= total:
				var min_pos = room_walls[0].position
				var max_pos = room_walls[0].position + Vector2(32.0, 32.0)
				for w in room_walls:
					min_pos.x = minf(min_pos.x, w.position.x)
					min_pos.y = minf(min_pos.y, w.position.y)
					max_pos.x = maxf(max_pos.x, w.position.x + 32.0)
					max_pos.y = maxf(max_pos.y, w.position.y + 32.0)
				var bh := BoundingHighlight.new()
				bh.world_rect = Rect2(min_pos, max_pos - min_pos)
				main.add_child(bh)
				player.unlock_movement()
				overlay.queue_free()
		)
