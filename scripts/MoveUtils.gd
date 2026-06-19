class_name MoveUtils

## Stateless collision/movement primitives shared by the actors (Player,
## NanoDroid, Enemy and its boss subclasses). Callers pass their own hitbox rects
## and solid lists, so per-actor hitbox shape and include-holes choices stay local.

const CONTACT_EPS = 0.1

## Largest portion of dx that rect may move horizontally without entering any
## solid. Only solids overlapping rect vertically matter; result is clamped so the
## rect stops flush (within eps) and never reverses direction.
static func sweep_x(rect: Rect2, dx: float, solids: Array, eps: float = CONTACT_EPS) -> float:
	if dx == 0.0:
		return 0.0
	var allowed = dx
	for solid in solids:
		if rect.position.y >= solid.end.y or solid.position.y >= rect.end.y:
			continue
		if dx > 0.0:
			if rect.end.x <= solid.position.x + eps:
				allowed = minf(allowed, solid.position.x - rect.end.x)
			else:
				allowed = 0.0
		elif rect.position.x >= solid.end.x - eps:
			allowed = maxf(allowed, solid.end.x - rect.position.x)
		else:
			allowed = 0.0
	return clampf(allowed, minf(dx, 0.0), maxf(dx, 0.0))

## Vertical counterpart of sweep_x.
static func sweep_y(rect: Rect2, dy: float, solids: Array, eps: float = CONTACT_EPS) -> float:
	if dy == 0.0:
		return 0.0
	var allowed = dy
	for solid in solids:
		if rect.position.x >= solid.end.x or solid.position.x >= rect.end.x:
			continue
		if dy > 0.0:
			if rect.end.y <= solid.position.y + eps:
				allowed = minf(allowed, solid.position.y - rect.end.y)
			else:
				allowed = 0.0
		elif rect.position.y >= solid.end.y - eps:
			allowed = maxf(allowed, solid.end.y - rect.position.y)
		else:
			allowed = 0.0
	return clampf(allowed, minf(dy, 0.0), maxf(dy, 0.0))

## True if rect overlaps any solid in the list.
static func rect_hits_any(rect: Rect2, solids: Array) -> bool:
	for solid in solids:
		if rect.intersects(solid):
			return true
	return false

## BFS outward from origin over the 4-connected grid; returns the first cell for
## which is_free.call(cell) is true, or null if the search exhausts. is_free is a
## Callable(Vector2i) -> bool that the caller uses to map the cell to a world
## position and test its own hitbox there.
static func find_free_cell(origin: Vector2i, is_free: Callable) -> Variant:
	var visited = {origin: true}
	var queue: Array[Vector2i] = [origin]
	while not queue.is_empty():
		var gp = queue.pop_front()
		if is_free.call(gp):
			return gp
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next = gp + d
			if not visited.has(next):
				visited[next] = true
				queue.append(next)
	return null
