class_name RoomUtils

## Stateless room-grid math: the single definition of the room size (in tiles) and
## the "is this tile in that room?" / "which room owns this tile?" tests that Main,
## LevelEditor, and per-object scripts all need (mirrors the GridUtils / BeamUtils
## static-helper pattern). No scene coupling — callers pass tiles / room origins.
##
## A room is ROOM_WIDTH×ROOM_HEIGHT tiles; room (rx, ry) owns tiles
## [rx*ROOM_WIDTH .. +ROOM_WIDTH-1] × [ry*ROOM_HEIGHT .. +ROOM_HEIGHT-1].

const ROOM_WIDTH = 25
const ROOM_HEIGHT = 12

## True if tile `gp` lies within the room whose top-left tile is (rx0, ry0).
static func in_room(gp: Vector2i, rx0: int, ry0: int) -> bool:
	return gp.x >= rx0 and gp.x < rx0 + ROOM_WIDTH and gp.y >= ry0 and gp.y < ry0 + ROOM_HEIGHT

## The room coordinate that contains tile `gp`. Floors, so it is correct for
## negative coordinates (rooms left of / above the origin).
static func room_of(gp: Vector2i) -> Vector2i:
	return Vector2i(floori(float(gp.x) / ROOM_WIDTH), floori(float(gp.y) / ROOM_HEIGHT))

## Top-left tile of a room coordinate.
static func room_origin(room: Vector2i) -> Vector2i:
	return Vector2i(room.x * ROOM_WIDTH, room.y * ROOM_HEIGHT)

## The tile an Enemy was authored at, derived from its `_start_pos` (tile top-left
## world position). Enemies store a pixel start, not a grid one, so this floors it
## back to a tile — the recurring `floori(_start_pos / TILE_SIZE)` computation.
static func enemy_start_cell(enemy: Node) -> Vector2i:
	return GridUtils.to_grid(enemy._start_pos)
