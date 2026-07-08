class_name PushBlockUtils

## Stateless push/slide geometry shared by the near-identical pushable-block scripts
## (PushBlock, Nut, WindBlock), which previously kept copy-pasted push/push_undo/reset/
## get_collision_rect bodies that could drift apart. Each block keeps thin entry-point
## methods that forward here; the block node is passed in (mirrors the PushUtils /
## BeamUtils static-helper pattern) so there is no scene coupling.
##
## The node must expose: grid_pos: Vector2i, start_grid_pos: Vector2i, sprite: Sprite2D,
## _tween: Tween — and be inside the scene tree.

const TILE_SIZE = 32
const SLIDE_DURATION = 0.15
# No-gravity rooms slide the sprite at 1/3 speed (3× the duration). See GravityUtils /
# TeleportAnchor.no_gravity.
const SLIDE_DURATION_NO_GRAVITY = SLIDE_DURATION * 3.0
const SPRITE_OFFSET = Vector2.ZERO

static func grid_to_world(gp: Vector2i) -> Vector2:
	return Vector2(gp.x * TILE_SIZE, gp.y * TILE_SIZE)

static func collision_rect(grid_pos: Vector2i) -> Rect2:
	return Rect2(grid_pos.x * TILE_SIZE, grid_pos.y * TILE_SIZE, float(TILE_SIZE), float(TILE_SIZE))

## Advance the block by `direction` tiles: teleport grid_pos + node, set the sprite lag,
## shove any enemy standing on the destination tile, then slide the sprite to catch up.
## Returns the slide Tween so callers (Nut) can chain a callback.
static func push(node: Node, direction: Vector2i) -> Tween:
	var old_world := grid_to_world(node.grid_pos)
	node.grid_pos += direction
	var new_world := grid_to_world(node.grid_pos)
	node.position = new_world
	node.sprite.position = old_world - new_world + SPRITE_OFFSET
	for enemy in node.get_tree().get_nodes_in_group("enemies"):
		var ec = enemy.get_center()
		var enemy_tile := Vector2i(floori(ec.x / TILE_SIZE), floori(ec.y / TILE_SIZE))
		if enemy_tile == node.grid_pos:
			enemy.push(direction)
	return _start_slide(node)

## Slide the block back to `old_pos` (push undo). Deliberately no enemy shove — matches
## the original per-block bodies.
static func push_undo(node: Node, old_pos: Vector2i) -> Tween:
	var cur_world := grid_to_world(node.grid_pos)
	node.grid_pos = old_pos
	var old_world := grid_to_world(old_pos)
	node.position = old_world
	node.sprite.position = cur_world - old_world + SPRITE_OFFSET
	return _start_slide(node)

static func reset(node: Node) -> void:
	if node._tween:
		node._tween.kill()
	node.grid_pos = node.start_grid_pos
	node.position = grid_to_world(node.grid_pos)
	node.sprite.position = SPRITE_OFFSET
	node.sprite.scale = Vector2.ONE

static func _start_slide(node: Node) -> Tween:
	if node._tween:
		node._tween.kill()
	node._tween = node.create_tween()
	node._tween.set_ease(Tween.EASE_OUT)
	node._tween.set_trans(Tween.TRANS_SINE)
	node._tween.tween_property(node.sprite, "position", SPRITE_OFFSET, _slide_duration(node))
	return node._tween

# 1/3 speed (3× duration) while the block's room has no gravity.
static func _slide_duration(node: Node) -> float:
	var scene := node.get_tree().current_scene
	if scene != null and scene.has_method("is_current_room_no_gravity") and scene.is_current_room_no_gravity():
		return SLIDE_DURATION_NO_GRAVITY
	return SLIDE_DURATION
