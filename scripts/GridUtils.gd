class_name GridUtils

## Stateless world<->tile-grid conversion. Single definition of the 32px grid
## convention so every object's get_grid_pos() agrees (mirrors the PushUtils /
## BeamUtils static-helper pattern).
##
## Always floors (not int-truncation), so it is correct for negative coordinates
## — i.e. rooms left of / above the origin.

const TILE_SIZE = 32

## World position -> the tile (col,row) that contains it.
static func to_grid(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE_SIZE), floori(pos.y / TILE_SIZE))

## Tile (col,row) -> its top-left world position.
static func to_world(gp: Vector2i) -> Vector2:
	return Vector2(gp.x * TILE_SIZE, gp.y * TILE_SIZE)

## The 32x32 world rect of a tile.
static func tile_rect(gp: Vector2i) -> Rect2:
	return Rect2(gp.x * TILE_SIZE, gp.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)

## Center of the 32x32 tile whose top-left is at world position pos.
static func tile_center(pos: Vector2) -> Vector2:
	return pos + Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)
