class_name PushHistoryUtils

## Stateless push undo/redo shared by Main and LevelEditor (the editor playtest must
## match the real game). Each push is recorded as an entry dict {block, from, dir};
## the scene keeps the one-deep history pointers (_last_push / _undo_push) and calls
## these helpers to actually move the block. Mirrors the PushUtils / BeamUtils
## static-helper pattern — the scene (`ctx`) is passed in so there is no coupling.
##
## `ctx` must implement: is_blocked(Vector2i) -> bool, can_push_block_to(Vector2i) ->
## bool, _trigger_shake(float), _update_beam(), and expose `player` (the active actor)
## and get_tree().

const TILE_SIZE = 32

## Actors a returning/advancing block can shove: the player plus every live nanodroid
## and enemy. Built from groups + an explicit player ref so the two scenes' differing
## player accessors stay local.
static func push_actors(player: Node, tree: SceneTree) -> Array:
	var actors: Array = []
	if player != null and is_instance_valid(player):
		actors.append(player)
	for nd in tree.get_nodes_in_group("nanodroids"):
		if is_instance_valid(nd) and not nd._destroyed:
			actors.append(nd)
	for e in tree.get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.is_dead():
			actors.append(e)
	return actors

## Undo the push `entry` ({block, from, dir}): slide the block back to `from`, shoving
## any actor standing on that tile one step in `dir`. Refused (fail SFX, returns false)
## if a shoved actor would land in a solid. The caller swaps its history pointers only
## when this returns true. `entry.block` is assumed valid (caller drops stale entries).
static func apply_undo(ctx: Node, entry: Dictionary) -> bool:
	var block = entry.block
	var from_pos: Vector2i = entry.from
	var dir: Vector2i = entry.dir
	var shoved: Array = []
	for actor in push_actors(ctx.player, ctx.get_tree()):
		if PushUtils.actor_tile(actor) == from_pos:
			shoved.append(actor)
	if not shoved.is_empty() and ctx.is_blocked(from_pos - dir):
		AudioManager.play_sfx("electric_fail")
		return false
	var block_rect = Rect2(from_pos.x * TILE_SIZE, from_pos.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	for actor in shoved:
		PushUtils.displace_actor(actor, block_rect, dir)
	block.push_undo(from_pos)
	ctx._trigger_shake(0.8)
	ctx._update_beam()
	return true

## Redo the push `entry`: advance the block one tile in `dir` again. Refused (returns
## false) if the destination can't take a block, or fail SFX + false if any actor is
## standing on it. The caller swaps history pointers only when this returns true.
static func apply_redo(ctx: Node, entry: Dictionary) -> bool:
	var block = entry.block
	var from_pos: Vector2i = entry.from
	var dir: Vector2i = entry.dir
	var dest = from_pos + dir
	if not ctx.can_push_block_to(dest):
		return false
	for actor in push_actors(ctx.player, ctx.get_tree()):
		if PushUtils.actor_tile(actor) == dest:
			AudioManager.play_sfx("electric_fail")
			return false
	block.push(dir)
	ctx._trigger_shake(0.8)
	ctx._update_beam()
	return true
