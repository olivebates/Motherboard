class_name BeamUtils

## Stateless electric-beam routing & blocker geometry shared by Main and
## LevelEditor (so editor playtests match the real game). Callers pass the
## lightning-blocker node list and nut list — no scene coupling (mirrors the
## PushUtils / YSortHitboxBottom static-helper pattern).
##
## Blocker nodes must implement get_grid_pos() -> Vector2i.
## Nut nodes must implement get_beam_point() -> Vector2.

const TILE_SIZE = 32

## Best-route search: among every clear route from `start` to `target` through the
## chain nuts, returns the one that passes through the MOST nuts; ties are broken
## first by FEWEST self-crossings (a non-crossing route always beats a crossing one
## with the same nut count), then by shortest total beam length. A route is allowed
## to cross over itself only when no equal-nut route avoids it. The returned path is
## a list of Vector2 endpoints / Node2D nuts —
## [start, nut, nut, …, target] — so callers can re-resolve sliding nut positions
## each frame. Returns [] if no clear, non-self-crossing route exists.
##
## To keep the (worst-case factorial) search cheap, all geometry is precomputed
## once: node beam-points, a pairwise "segment is clear of blockers" matrix, and a
## pairwise distance matrix. The DFS then works purely on indices + cached floats —
## no get_beam_point()/Rect2/segment-vs-rect calls in the inner loop.
static func best_beam_path(blockers: Array, start: Vector2, target: Vector2, nuts: Array) -> Array:
	var n: int = nuts.size()
	# Index layout: 0 = start, 1..n = nuts, n+1 = target.
	var count: int = n + 2
	var target_idx: int = n + 1
	var coords: Array = []
	coords.resize(count)
	coords[0] = start
	for i in range(n):
		coords[i + 1] = nuts[i].get_beam_point()
	coords[target_idx] = target

	# Pairwise visibility (clear of all blockers) and distance, computed once.
	var clear: Array = []
	var dist: Array = []
	for i in range(count):
		var crow: Array = []
		crow.resize(count)
		crow.fill(false)
		clear.append(crow)
		var drow: Array = []
		drow.resize(count)
		drow.fill(0.0)
		dist.append(drow)
	for i in range(count):
		for j in range(i + 1, count):
			var ok: bool = beam_blockers(blockers, coords[i], coords[j]).is_empty()
			clear[i][j] = ok
			clear[j][i] = ok
			var d: float = coords[i].distance_to(coords[j])
			dist[i][j] = d
			dist[j][i] = d

	# best: most nuts wins; tie → fewest self-crossings; tie → shortest total length.
	# `order` is a list of coord indices (a complete route ends with target_idx).
	var best: Dictionary = {"order": [], "nuts": -1, "crosses": true, "len": INF}
	_search_best(0, target_idx, n, coords, clear, dist, [0], 0.0, false, best)

	var order: Array = best["order"]
	if order.is_empty():
		return []
	# Rebuild the path with original entries (Node2D nuts so callers re-resolve them).
	var path: Array = []
	for idx in order:
		if idx == 0:
			path.append(start)
		elif idx == target_idx:
			path.append(target)
		else:
			path.append(nuts[idx - 1])
	return path

static func _search_best(current: int, target_idx: int, n: int, coords: Array, clear: Array, dist: Array, order: Array, length: float, crosses: bool, best: Dictionary) -> void:
	# Completing the route here: run the final hop to the target prong.
	if clear[current][target_idx]:
		var seg_crosses: bool = crosses or _order_self_crosses(order, coords, coords[current], coords[target_idx])
		var nut_count: int = order.size() - 1  # order = [start, nut, nut, …]
		var total_len: float = length + dist[current][target_idx]
		if _is_better_route(nut_count, seg_crosses, total_len, best):
			best["nuts"] = nut_count
			best["crosses"] = seg_crosses
			best["len"] = total_len
			best["order"] = order + [target_idx]
	# Or visit another reachable, unvisited nut and keep going. Crossing routes are no
	# longer pruned — they stay in the running but lose the crossings tiebreaker.
	for j in range(1, n + 1):
		if not clear[current][j] or order.has(j):
			continue
		var next_crosses: bool = crosses or _order_self_crosses(order, coords, coords[current], coords[j])
		_search_best(j, target_idx, n, coords, clear, dist, order + [j], length + dist[current][j], next_crosses, best)

## Ranking: more nuts beats fewer; tie → a non-crossing route beats a crossing one;
## tie → shorter total length wins.
static func _is_better_route(nut_count: int, crosses: bool, total_len: float, best: Dictionary) -> bool:
	if nut_count != best["nuts"]:
		return nut_count > best["nuts"]
	if crosses != best["crosses"]:
		return not crosses
	return total_len < best["len"]

## Resolves a path entry (Vector2 endpoint or Node2D nut) to its world point.
static func _beam_point_of(entry) -> Vector2:
	if entry is Vector2:
		return entry
	return entry.get_beam_point()

## True if the new segment `seg_a`→`seg_b` (where `seg_a == coords[order.back()]`)
## crosses any earlier segment of the route. The immediately preceding segment is
## skipped — it shares `seg_a`, so they only touch, not cross.
static func _order_self_crosses(order: Array, coords: Array, seg_a: Vector2, seg_b: Vector2) -> bool:
	if order.size() < 2:
		return false
	# Segments are coords[order[i]]→coords[order[i+1]]; the last (index order.size()-2)
	# is adjacent — skip it.
	for i in range(order.size() - 2):
		if Geometry2D.segment_intersects_segment(seg_a, seg_b, coords[order[i]], coords[order[i + 1]]) != null:
			return true
	return false

## Number of nuts a returned path passes through (path = [start, …nuts, target]).
static func _path_nut_count(path: Array) -> int:
	if path.size() < 2:
		return -1
	return path.size() - 2

## Blockers to blink as a "you could thread more nuts" hint. Recomputes the best
## route ignoring blockers (`best_beam_path` with no blockers always at least
## connects start→target). If that ideal route passes through more nuts than the
## actual `clear_path`, returns the blockers lying on the ideal route (expanded to
## their connected groups, matching the blocked-beam flash). Otherwise [].
static func better_nut_hint_blockers(blockers: Array, start: Vector2, target: Vector2, nuts: Array, clear_path: Array) -> Array:
	if blockers.is_empty() or nuts.is_empty():
		return []
	# If the live beam already threads every nut, no route can beat it — skip the
	# (factorial) second search entirely. This is the common case.
	if _path_nut_count(clear_path) >= nuts.size():
		return []
	var ideal := best_beam_path([], start, target, nuts)
	if _path_nut_count(ideal) <= _path_nut_count(clear_path):
		return []
	var on_route: Array = []
	var seen: Dictionary = {}
	for i in range(ideal.size() - 1):
		var a := _beam_point_of(ideal[i])
		var b := _beam_point_of(ideal[i + 1])
		for blk in beam_blockers(blockers, a, b):
			if not seen.has(blk):
				seen[blk] = true
				on_route.append(blk)
	return expand_connected(blockers, on_route)

## Applies a freshly computed beam result — the shared body of Main and
## LevelEditor `_update_beam()`. `world_positions` is the prong world positions (0,
## 1 or 2 of them); `path` is the routed beam path (or [] when there is no clear
## route between two prongs); `nuts` is the full list of in-room chain nuts (used to
## hint when a higher-nut route is being blocked). Toggles the beam node, flashes
## blockers, and updates GameManager puzzle state (beam_blocked / conductor points /
## evaluate_puzzle). Callers keep their own (divergent) path computation; only this
## tail is shared.
static func apply_beam_result(beam: Node, blockers: Array, world_positions: Array, path: Array, nuts: Array = []) -> void:
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
			# The beam works, but if a route through MORE nuts exists and is only
			# being held back by lightning blockers, blink those blockers as a hint.
			var hint := better_nut_hint_blockers(blockers, world_positions[0], world_positions[1], nuts, path)
			for b in blockers:
				b.set_blocking(b in hint)
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
