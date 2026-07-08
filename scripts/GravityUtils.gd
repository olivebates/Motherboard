class_name GravityUtils

## Stateless helpers for the "no gravity" room toggle (TeleportAnchor.no_gravity).
## In a no-gravity room a pushed block slides until it hits a solid (several tiles at
## once) and every resting pushable block bobs ±1px to look like it's floating.
## Geometry only — the scene (`ctx`) is passed in so there is no coupling (mirrors the
## PushUtils / BeamUtils static-helper pattern).

const TILE_SIZE = 32
# Bob speed (rad/s) and amplitude (px) of the floating animation.
const FLOAT_SPEED = 2.2
const FLOAT_AMPLITUDE = 1.0

## The farthest displacement (unit `dir` × N tiles) `block` can slide from its current
## tile before a solid stops it. The caller must have already verified the first tile
## (block.grid_pos + dir) is pushable, so the result is at least `dir`.
static func slide_dir(ctx: Node, block: Node, dir: Vector2i) -> Vector2i:
	var tiles = 1
	while ctx.can_push_block_to(block.grid_pos + dir * (tiles + 1)):
		tiles += 1
	return dir * tiles

## ±1px bob offset (both axes) for a floating block. The x axis runs at a different
## frequency to the y so the block drifts in a slow ellipse rather than a diagonal line.
## Phase is keyed off the tile so neighbouring blocks don't bob in lockstep.
static func float_offset(grid_pos: Vector2i, time: float) -> Vector2:
	var phase = float(grid_pos.x + grid_pos.y) * 0.9
	var x = sin(time * FLOAT_SPEED * 0.7 + phase) * FLOAT_AMPLITUDE
	var y = sin(time * FLOAT_SPEED + phase) * FLOAT_AMPLITUDE
	return Vector2(x, y)
