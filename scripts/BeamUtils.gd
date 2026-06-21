class_name BeamUtils

## Stateless electric-beam routing & blocker geometry shared by Main and
## LevelEditor (so editor playtests match the real game). Callers pass the
## lightning-blocker node list and nut list — no scene coupling (mirrors the
## PushUtils / YSortHitboxBottom static-helper pattern).
##
## Blocker nodes must implement get_grid_pos() -> Vector2i.
## Nut nodes must implement get_beam_point() -> Vector2.

const TILE_SIZE = 32

## Nearest-first DFS: at each hop, try candidates (nuts + target) sorted by
## distance from the current position, backtracking if a chosen nut dead-ends.
## Returns a path of Vector2 endpoints / Node2D nuts (so callers can re-resolve
## sliding nut positions each frame), or [] if no clear route exists.
static func nearest_first_beam(blockers: Array, current: Vector2, target: Vector2, remaining: Array, path: Array) -> Array:
	var candidates: Array = []
	if beam_blockers(blockers, current, target).is_empty():
		candidates.append({"dist": current.distance_to(target), "is_target": true, "idx": -1})
	for i in range(remaining.size()):
		var nut_pos: Vector2 = remaining[i].get_beam_point()
		if beam_blockers(blockers, current, nut_pos).is_empty():
			candidates.append({"dist": current.distance_to(nut_pos), "is_target": false, "idx": i})
	candidates.sort_custom(func(a, b): return a["dist"] < b["dist"])
	for c in candidates:
		if c["is_target"]:
			return path + [target]
		var i: int = c["idx"]
		var nut: Node2D = remaining[i]
		var nut_pos: Vector2 = nut.get_beam_point()
		var next_remaining = remaining.duplicate()
		next_remaining.remove_at(i)
		var result = nearest_first_beam(blockers, nut_pos, target, next_remaining, path + [nut])
		if not result.is_empty():
			return result
	return []

## Applies a freshly computed beam result — the shared body of Main and
## LevelEditor `_update_beam()`. `world_positions` is the prong world positions (0,
## 1 or 2 of them); `path` is the routed beam path (or [] when there is no clear
## route between two prongs). Toggles the beam node, flashes blockers, and updates
## GameManager puzzle state (beam_blocked / conductor points / evaluate_puzzle).
## Callers keep their own (divergent) path computation; only this tail is shared.
static func apply_beam_result(beam: Node, blockers: Array, world_positions: Array, path: Array) -> void:
	if world_positions.size() == 2:
		if path.is_empty():
			# No clear route — flash the blockers on the direct line so the player
			# sees what is in the way.
			GameManager.beam_blocked = true
			GameManager.beam_conductor_points.clear()
			GameManager.evaluate_puzzle()
			beam.deactivate()
			var blocking := beam_blockers(blockers, world_positions[0], world_positions[1])
			var flashing := expand_connected(blockers, blocking)
			for b in blockers:
				b.set_blocking(b in flashing)
		else:
			GameManager.beam_blocked = false
			GameManager.set_beam_conductors_from_path(path)
			GameManager.evaluate_puzzle()
			beam.activate(path)
			for b in blockers:
				b.set_blocking(false)
	else:
		GameManager.beam_blocked = false
		GameManager.beam_conductor_points.clear()
		GameManager.evaluate_puzzle()
		beam.deactivate()
		for b in blockers:
			b.set_blocking(false)

## Blockers whose tile the segment pos_a→pos_b passes through.
static func beam_blockers(blockers: Array, pos_a: Vector2, pos_b: Vector2) -> Array:
	var blocking: Array = []
	for b in blockers:
		var gp: Vector2i = b.get_grid_pos()
		var rect = Rect2(Vector2(gp.x * TILE_SIZE, gp.y * TILE_SIZE), Vector2(TILE_SIZE, TILE_SIZE))
		if segment_intersects_rect(pos_a, pos_b, rect):
			blocking.append(b)
	return blocking

## Flood-fill outward from seed blockers across 4-connected same-group neighbors.
static func expand_connected(blockers: Array, seed: Array) -> Array:
	if seed.is_empty():
		return []
	var blocker_by_pos: Dictionary = {}
	for b in blockers:
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
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor_pos = gp + offset
			if blocker_by_pos.has(neighbor_pos):
				var neighbor = blocker_by_pos[neighbor_pos]
				if not visited.has(neighbor):
					visited[neighbor] = true
					result.append(neighbor)
					queue.append(neighbor)
	return result

## True if segment a→b passes through (or starts/ends inside) rect.
static func segment_intersects_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var c = [rect.position,
			  Vector2(rect.end.x, rect.position.y),
			  rect.end,
			  Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, c[i], c[(i + 1) % 4]) != null:
			return true
	return false
