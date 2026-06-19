class_name PushUtils

## Stateless helpers for block pushing and for shoving an actor off a tile a
## block is moving onto. Geometry only — callers pass the relevant nodes/lists so
## there is no scene coupling (mirrors the YSortHitboxBottom static-helper pattern).
##
## Actors handled by actor_tile()/displace_actor() must implement:
##   get_push_hitbox() -> Rect2   (current world-space hitbox)
##   push_out(displacement: Vector2)

const TILE_SIZE = 32

static func rects_overlap_x(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.end.x and b.position.x < a.end.x

static func rects_overlap_y(a: Rect2, b: Rect2) -> bool:
	return a.position.y < b.end.y and b.position.y < a.end.y

## The push block whose tile is grid_pos, or null.
static func block_at(blocks: Array, grid_pos: Vector2i) -> Node:
	for block in blocks:
		if block.grid_pos == grid_pos:
			return block
	return null

## The nearest push block flush against actor_rect's face in direction dir, or
## null. Fans are excluded (they are wind sources, not shovable here).
static func block_at_face(blocks: Array, actor_rect: Rect2, dir: Vector2i, from_point: Vector2) -> Node:
	const FACE_EPS = 0.1
	var closest: Node = null
	var closest_dist = INF
	for block in blocks:
		if block.is_in_group("fans"):
			continue
		if not block.has_method("get_collision_rect"):
			continue
		var block_rect: Rect2 = block.get_collision_rect()
		if dir.x > 0:
			if absf(actor_rect.end.x - block_rect.position.x) > FACE_EPS:
				continue
		elif dir.x < 0:
			if absf(actor_rect.position.x - block_rect.end.x) > FACE_EPS:
				continue
		elif dir.y > 0:
			if absf(actor_rect.end.y - block_rect.position.y) > FACE_EPS:
				continue
		elif absf(actor_rect.position.y - block_rect.end.y) > FACE_EPS:
			continue
		var aligned = rects_overlap_y(actor_rect, block_rect) if dir.x != 0 else rects_overlap_x(actor_rect, block_rect)
		if not aligned:
			continue
		var dist = from_point.distance_squared_to(block_rect.get_center())
		if dist < closest_dist:
			closest_dist = dist
			closest = block
	return closest

## The tile an actor currently stands on, from its hitbox center.
static func actor_tile(actor: Node) -> Vector2i:
	var c: Vector2 = actor.get_push_hitbox().get_center()
	return Vector2i(floori(c.x / TILE_SIZE), floori(c.y / TILE_SIZE))

## Slide an actor flush against a block occupying block_rect, shoved in -dir.
static func displace_actor(actor: Node, block_rect: Rect2, dir: Vector2i) -> void:
	var hb: Rect2 = actor.get_push_hitbox()
	var displacement = Vector2.ZERO
	if dir.x > 0:
		displacement.x = block_rect.position.x - hb.end.x
	elif dir.x < 0:
		displacement.x = block_rect.end.x - hb.position.x
	elif dir.y > 0:
		displacement.y = block_rect.position.y - hb.end.y
	elif dir.y < 0:
		displacement.y = block_rect.end.y - hb.position.y
	if displacement != Vector2.ZERO:
		actor.push_out(displacement)
