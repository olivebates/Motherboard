# Motherboard — Project Context

## Game Description
Top-down 2D puzzle game built in Godot 4.5. Players move freely (pixel-level WASD) through grid-based rooms, place "prong" objects to complete electrical circuits, push blocks to solve spatial puzzles, and open doors. The world is divided into discrete rooms; walking to a room edge smoothly pans the camera. Pressing R resets the current room with a CRT static effect. A splash screen is shown on launch.

---

## Grid & Coordinate System

```
TILE_SIZE    = 32 px
WORLD_OFFSET = 0         (tile grid starts at world origin)
ROOM_WIDTH   = 25 tiles
ROOM_HEIGHT  = 12 tiles
CAMERA_MARGIN = Vector2(16, 16)   (camera center offset from exact room center)
```

- **Tile top-left** in world space: `Vector2(col * 32, row * 32)`
- **Tile center** in world space: `Vector2(col * 32 + 16, row * 32 + 16)`
- **Room** `(rx, ry)` occupies columns `[rx*25 .. rx*25+24]`, rows `[ry*12 .. ry*12+11]`
- **Camera center** for room `(rx, ry)`: `Vector2(rx*800 + 400 + 16, ry*384 + 192 + 16)`
- Viewport is 800×384 — one room fills the screen
- Rooms support negative coordinates (room y can be negative); room detection uses `floori` to handle this

**Node position conventions (all objects):**
- Player, Prong, PushBlock, Nut → positioned at **tile center** (`col*32+16, row*32+16`)
- Door, FloorPanel, LightningBlocker, WallTileMap, KeyDoor, Key → positioned at **tile top-left**

**Sprite origin convention:** All sprites use `centered = false` (top-left origin).
- For tile-center nodes: sprite has a `(-16, -16)` offset so it covers the tile correctly
- For tile-top-left nodes: sprite at `(0, 0)` fills the tile naturally

---

## File Structure

```
project.godot              — Godot project config, input map, autoload, window size (800×384)

scenes/
  Main.tscn                — Root scene
  Player.tscn              — Player character
  Prong.tscn               — Placeable prong object (stake sprite)
  PushBlock.tscn           — Pushable block (SD_Card_block.png)
  ElectricBeam.tscn        — Electricity effect (two Line2D children; glow hidden)
  Door.tscn                — Puzzle door (floor-panel activated)
  FloorPanel.tscn          — Floor trigger (positive.png or negative.png sprite)
  LightningBlocker.tscn    — Blocks the electric beam; resistor_small.png sprite
  Nut.tscn                 — Pushable conductor; beam routes through it
  KeyDoor.tscn             — Solid door that opens when all Keys in the room are collected
  Key.tscn                 — Collectible that unlocks the KeyDoor in the same room
  PassBlock.tscn           — Passable block; player walks through, push blocks cannot enter

scripts/
  GameManager.gd           — Autoload singleton (puzzle state)
  Main.gd                  — Root scene controller
  Player.gd                — Player movement and input
  Prong.gd                 — Prong placement logic
  PushBlock.gd             — Push block with sprite-lag animation
  ElectricBeam.gd          — Animated electricity beam (white, no transparency)
  Door.gd                  — Door open/close logic
  FloorPanel.gd            — Floor panel registration + circle-outline highlight
  LightningBlocker.gd      — Lightning blocker; alternates textures when active
  WallTileMap.gd           — TileMapLayer script for painting walls in-editor
  ResetEffect.gd           — CRT static CanvasLayer effect for room reset
  KeyDoor.gd               — Solid door; counts Keys in same room, opens when all collected
  Key.gd                   — Collectible; shrinks to center on pickup, notifies KeyDoor
  Nut.gd                   — Pushable conductor; beam routes through it
  PassBlock.gd             — Passthrough block; solid to push blocks, transparent to player
  SplashScreen.gd          — Launch splash; black bg + credit text, dismissed by any key

Sprites/
  placeholder.png          — 32×32 RGBA placeholder
  positive.png             — FloorPanel positive variant sprite
  negative.png             — FloorPanel negative variant sprite
  resistor_small.png       — LightningBlocker idle sprite
  resistor_small2.png      — LightningBlocker active (alternates with resistor_small every 0.5s)
  stake.png                — Prong sprite
  SD_Card_block.png        — PushBlock sprite
  washer_block.png         — Nut sprite
  locked_door1.png         — Door sprite (legacy name; scene uses switch_closed.png)
  switch_open2.png         — PassBlock sprite
  key_file3.png            — Key sprite
  electric_front.png       — ElectricBeam sprite (unused; beam drawn procedurally)
  wall1.png                — Wall tile sprite
```

---

## Scripts

### GameManager.gd (autoload singleton)
**Purpose:** Central puzzle state manager. `evaluate_puzzle()` is driven solely by `Main._update_beam()`.

**Key variables:**
- `prongs: Array` — up to 2 entries, each `{node: Node, grid_pos: Vector2i}`
- `beam_blocked: bool` — set by Main before `evaluate_puzzle()`
- `floor_panels: Dictionary` — `Vector2i → String id`
- `doors: Dictionary` — `String id → Array[Node]`
- `signal doors_update(id: String, open: bool)`
- `signal shake_requested(strength: float)`
- `const PANEL_ACTIVATION_RADIUS := 20.0` — radius (px) for prong-to-panel proximity check

**Key functions:**
- `place_prong(node, grid_pos)` — appends entry
- `remove_prong(node)` — removes by node reference
- `clear_prongs()` → `Array` — clears all, returns removed for animation
- `evaluate_puzzle()` — opens doors if: not beam_blocked, 2 prongs, each within 20px of panel centers sharing the same id, on different tiles
- `_panel_id_near(world_pos)` — returns panel id if world_pos is within 20px of a panel center
- `get_prong_positions()` → `Array[Vector2i]`
- `get_prong_world_positions()` → `Array[Vector2]`

---

### Main.gd (Node2D — root scene)
**Purpose:** Game world controller. Manages rooms, camera, prong spawning, reset, beam/blocker logic.

**Key constants:** `TILE_SIZE=32`, `WORLD_OFFSET=0`, `CAMERA_MARGIN=Vector2(16,16)`, `CAMERA_TWEEN_DURATION=0.25`

**Key variables:**
- `@onready var wall_tilemap: TileMapLayer` — assign in inspector; checked by `_is_static_solid()` / `get_player_blocking_rects()`
- `current_room: Vector2i`
- `room_entry_positions: Dictionary`
- `_shake_amount: float` — camera shake magnitude

**Key functions:**
- `_process(delta)` — shake decay → `camera.offset`
- `_trigger_shake(strength)` — sets `_shake_amount`; connected to `GameManager.shake_requested`
- `_update_beam()` — checks blockers, sets `GameManager.beam_blocked`, calls `evaluate_puzzle()`, activates/deactivates beam
- `spawn_prong(pixel_pos)` — 3rd press clears both (animate: shrink to top-center); otherwise instantiate and place
- `_reset_room()` — locks player → ResetEffect fades in → awaits `peaked` → resets room state → awaits `done` → unlocks player
- `_transition_to_room(new_room)` — clears prongs instantly, tweens camera 0.25s
- `check_room_transition(player_grid)` — uses `floori` division to support negative room coordinates
- `tile_rect(grid_pos)` → `Rect2` — 32×32 world rect for a grid tile
- `_is_static_solid(grid_pos)` — walls, closed doors, lightning blockers, key doors (NOT push blocks, NOT pass blocks)
- `is_blocked(grid_pos)` — static solids + push blocks (used for grid queries elsewhere)
- `get_player_blocking_rects(area)` → `Array[Rect2]` — static tile rects + push-block rects overlapping `area`; used by player AABB movement
- `can_push_block_to(grid_pos)` — false if static solid, push block, or pass block occupies tile
- `get_push_block_at_face(player_rect, dir, from_point)` → `Node` — among push blocks flush against `player_rect` on the given face, returns the one whose center is closest to `from_point`
- `has_pass_block_at(grid_pos)` — checks pass_blocks group
- `get_push_block_at(grid_pos)` → Node or null

---

### Player.gd (Node2D)
**Purpose:** Free pixel-based movement, push input, and prong placement.

**Constants:** `SPEED=272 px/s`, `SPRITE_SPEED=20.0`, `CONTACT_EPS=0.1`, `PUSH_FREEZE=0.15`

**Hitbox:** Defined by a `CollisionShape2D` child node named `Hitbox` with a `RectangleShape2D` shape. Size and offset are read in `_ready()` from the node — edit in the Godot editor to change collision dimensions. At runtime: `_half_w`, `_half_h`, `_hitbox_offset` store the derived values. Currently 10×10, offset (0, 11).

**Movement (AABB collision):** Input → normalized velocity → axis-separated movement (X then Y). Each axis uses `_move_axis_x` / `_move_axis_y` to clamp motion against `Main.get_player_blocking_rects()` so the hitbox stops exactly at solid edges (walls, doors, blockers, key doors, push blocks). Squash/stretch: `(1.15, 0.85)` or `(0.85, 1.15)` on dominant axis. Pass blocks are not solids for the player.

**Push detection:** Runs after movement each frame. Requires a single cardinal key (no diagonals). Player must be stopped on the push axis (`moved_x`/`moved_y` false for that axis) with hitbox flush against a push-block face (`FACE_EPS=0.1`). If multiple blocks qualify, `Main.get_push_block_at_face()` picks the one closest to the player sprite center (`_sprite_center()`). Destination must pass `can_push_block_to()`. On success: `block.push(dir)`, camera shake (0.8), and a directional push lock for `PUSH_FREEZE` seconds — only movement and re-push in the same direction are blocked; perpendicular movement is allowed immediately.

**Key functions:** `_hitbox_rect(pos)`, `_sprite_center()`, `_try_push()`, `_is_movement_locked_on_axis()`, `_start_push_lock(dir)`

---

### Prong.gd (Node2D)
- `grid_pos: Vector2i` — `floori(position.x / 32), floori(position.y / 32)`
- `setup(pixel_pos)` — sets position; sprite `centered=false`, offset `(-16,-16)`; tweens scale `0 → 1.3 → 1`
- **Max 2.** Third press clears both with a shrink-to-top-center animation (scale + sprite.position.x tweened together)

---

### Nut.gd (Node2D)
**Purpose:** Pushable conductor. Identical push/reset behaviour to PushBlock but also in `"nuts"` group. After its slide tween finishes, calls `Main._update_beam()`. `get_beam_point()` returns visual sprite center for beam routing. `get_collision_rect()` → 32×32 world `Rect2` for player collision/push queries.

---

### PushBlock.gd (Node2D)
**Purpose:** Instantly teleports one tile when pushed; sprite slides to simulate smooth movement.

- `_ready()` — infers `start_grid_pos` from editor placement position (like Nut); no need to set export manually
- `get_collision_rect()` → 32×32 world `Rect2` for player collision/push queries
- `push(direction)` — teleports node, slides sprite from old position
- `reset()` — restores `start_grid_pos`, snaps sprite

---

### PassBlock.gd (Node2D)
**Purpose:** Block the player can walk through freely, but push blocks and nuts cannot be pushed onto.

- Added to group `"pass_blocks"`; uses `switch_open2.png` sprite
- `get_grid_pos()` — used by `Main.has_pass_block_at()`
- NOT included in `Main.is_blocked()` — player passes through freely

---

### ElectricBeam.gd (Node2D)
**Purpose:** Animated electricity visual. `z_index = 10`.

- Beam is **white**, fully opaque. Glow Line2D is hidden (`line_glow.visible = false`)
- Beam width pulses via `sin(time * 8)`. Endpoint glow circles drawn white in `_draw()`
- `activate(points)` — ordered list: prong A → nuts → prong B
- `deactivate()` — hides beam

---

### Door.gd (Node2D)
- `@export var id: String` — matches FloorPanel IDs
- `set_open(open)` — on open: emits `GameManager.shake_requested(5.0)`, brief white flash, then shrinks sprite toward its center over `ANIM_DURATION=0.15s` (scale + position compensated via `_apply_shrink_scale`) and hides; on close: starts at scale 0 centered, grows back to full size over 0.15s
- Added to group `"doors"`

---

### FloorPanel.gd (Node2D)
- `@export var id: String`; `@export var positive: bool = true`
- Sprite is hidden; drawn manually via `_draw()` so circle can render on top
- `_process`: checks if any prong is within `PANEL_ACTIVATION_RADIUS` (20px) of panel center; calls `queue_redraw()` on state change
- `_draw()`: draws sprite texture, then draws white circle outline (radius 17px) when active
- Registers in GameManager with grid position

---

### LightningBlocker.gd (Node2D)
- Position = tile top-left; group `"lightning_blockers"`; solid (blocks player and push blocks)
- Sprite node hidden; texture drawn manually in `_draw()` with `draw_texture`
- `_draw()`: draws `resistor_small.png` normally; when blocking, alternates to `resistor_small2.png` every 0.5s using `int(_time / 0.5) % 2`
- Sparks drawn on top in same `_draw()` call
- `queue_redraw()` called in `_ready()` for initial render
- `get_grid_pos()` — `floori(position / 32)`

---

### KeyDoor.gd (Node2D)
- No id export — matches keys by room position (`floori(pos / 800 or 384)`)
- `_count_keys()` — deferred; counts all Keys in the same room
- `key_collected()` — increments counter; opens when all collected
- `_open()` — removes from group, flashes white, hides sprite (permanent)
- `reset()` — if opened, returns immediately; otherwise restores and re-adds to group

---

### Key.gd (Node2D)
- No `door_id` export — notifies KeyDoors in the same room on collect
- `_collect(player)` — immediately notifies all KeyDoors in room, then tweens: node flies to player while sprite shrinks toward its own center (scale + position.x/y compensated) over 0.15s
- `reset()` — only resets if a KeyDoor still exists in the same room (door not permanently opened); restores position, scale, sprite.position

---

### ResetEffect.gd (CanvasLayer, layer=20)
- Full-screen ColorRect with embedded GLSL shader: chunky 2px pixel noise, horizontal glitch bands, scanlines, bright flash bars
- `signal peaked` — emitted when static reaches 100% opacity
- `signal done` — emitted when fade-out completes
- `play()` — fades in over `FADE_IN=0.28s` → holds at 100% for 0.2s → emits `peaked` → fades out over `FADE_OUT=0.22s` → emits `done`
- Room state resets at `peaked`; player unlocks at `done`

---

### SplashScreen.gd (CanvasLayer, layer=30)
- Shown on game launch; black ColorRect + centered Label: "A Game By\nOliver T. Bates & CasterOil"
- Intercepts all input via `_input`; dismissed by any key/mouse/joypad press
- On dismiss: consumes the input event, unlocks player, frees self
- Player movement is locked in `Main._ready()` until dismissed

---

### WallTileMap.gd (TileMapLayer)
**Purpose:** Painted in the Godot editor to define wall tiles. Auto-configures its TileSet in `_ready()`.

---

## Scenes (Node Structures)

```
Player.tscn:
  Node2D [Player.gd]
  ├── Sprite2D [centered=false]
  └── Hitbox [CollisionShape2D, RectangleShape2D — edit size/position here to change push/collision box]

Prong.tscn:
  Node2D [Prong.gd]
  └── Sprite2D [stake.png, centered=false]

PushBlock.tscn:
  Node2D [PushBlock.gd]
  ├── Sprite2D [SD_Card_block.png, centered=false]
  ├── Area2DLeft  [Area2D] → CollisionShapeLeft  [CollisionShape2D] — legacy; push uses AABB collision
  ├── Area2DRight [Area2D] → CollisionShapeRight [CollisionShape2D]
  ├── Area2DUp    [Area2D] → CollisionShapeUp    [CollisionShape2D]
  └── Area2DDown  [Area2D] → CollisionShapeDown  [CollisionShape2D]

ElectricBeam.tscn:
  Node2D [ElectricBeam.gd]
  ├── LineGlow [Line2D — hidden]
  └── LineMain [Line2D — white, fully opaque]

Door.tscn:
  Node2D [Door.gd]
  └── Sprite2D [switch_closed.png, centered=false]

FloorPanel.tscn:
  Node2D [FloorPanel.gd]
  └── Sprite2D [positive.png default, centered=false, hidden — drawn via _draw()]

LightningBlocker.tscn:
  Node2D [LightningBlocker.gd]
  └── Sprite2D [resistor_small.png, centered=false, hidden — drawn via _draw()]

KeyDoor.tscn:
  Node2D [KeyDoor.gd]
  └── Sprite2D [centered=false]

Key.tscn:
  Node2D [Key.gd]
  └── Sprite2D [key_file3.png, centered=false]

PassBlock.tscn:
  Node2D [PassBlock.gd]
  └── Sprite2D [switch_open2.png, centered=false]

Nut.tscn:
  Node2D [Nut.gd]
  ├── Sprite2D [washer_block.png, centered=false]
  ├── Area2DLeft  [Area2D] → CollisionShapeLeft  [CollisionShape2D] — legacy; push uses AABB collision
  ├── Area2DRight [Area2D] → CollisionShapeRight [CollisionShape2D]
  ├── Area2DUp    [Area2D] → CollisionShapeUp    [CollisionShape2D]
  └── Area2DDown  [Area2D] → CollisionShapeDown  [CollisionShape2D]
```

---

## Sprites

All objects use `centered = false`.

| Object | Sprite | Node position |
|---|---|---|
| Player | (player sprite) | tile center |
| Prong | stake.png | exact pixel (placed by player) |
| PushBlock | SD_Card_block.png | tile center (inferred from editor placement) |
| Door | switch_closed.png | tile top-left |
| FloorPanel | positive.png / negative.png | tile top-left |
| LightningBlocker | resistor_small.png / resistor_small2.png | tile top-left |
| Nut | washer_block.png | tile center |
| KeyDoor | (door sprite) | tile top-left |
| Key | key_file3.png | tile top-left |
| PassBlock | switch_open2.png | tile top-left |

Floor: black `Color(0, 0, 0)` drawn in `Main._draw()`. Background: black.

---

## Puzzle Logic Flow

```
Player presses Space:
  → Main.spawn_prong(pixel_pos)
      if 2 prongs exist: clear both (shrink-to-top-center animation), deactivate beam, return
      else: place prong → _update_beam():
          → _compute_beam_path() via nuts
          → set GameManager.beam_blocked, call evaluate_puzzle()
          → activate or deactivate beam; flash blocking blockers
          → evaluate_puzzle(): each prong checked via _panel_id_near (20px radius)

Player presses R:
  → lock player → ResetEffect.play()
  → static fades in (0.28s) → holds at 100% (0.2s) → peaked signal
  → peaked: delete room prongs, reset push blocks, reset key doors/keys, teleport player
  → static fades out (0.22s) → done signal → unlock player

Room transition (player walks to edge):
  → clear prongs instantly → camera tweens 0.25s → player locked during tween
```

---

## Input Map

| Action | Keys |
|---|---|
| move_up | W, Up Arrow |
| move_down | S, Down Arrow |
| move_left | A, Left Arrow |
| move_right | D, Right Arrow |
| place_prong | Space |
| reset_room | R |

---

## Camera System

- One room fills the 800×384 viewport
- `Camera2D` initialized to `_room_center(0,0)` in `_ready()`
- **Shake:** decays via `lerpf(..., 0, 20*delta)`; triggered on prong events (5–6 strength), door open (5), block push (0.8)
- **Room transition:** 0.25s tween on `Camera2D.position` (EASE_IN_OUT SINE)
- `CAMERA_MARGIN` of `(16, 16)` added to all room center calculations
- No lean or zoom effects

---

## Feel / Juice Features

| Feature | Where |
|---|---|
| Camera shake on prong/door/push events | Main.gd `_trigger_shake()` |
| Player sprite squash/stretch | Player.gd `_process` |
| Prong pop animation (scale 0→1.3→1) | Prong.gd `setup()` |
| Prong clear animation (shrink to top-center) | Main.gd `spawn_prong()` |
| Push block sprite slide | PushBlock.gd `push()` |
| Push directional freeze (0.15s, push axis only) | Player.gd `_start_push_lock()` |
| Closest-block push selection | Main.gd `get_push_block_at_face()` |
| Beam thickness pulse | ElectricBeam.gd `_rebuild_points()` |
| Beam endpoint glow dots | ElectricBeam.gd `_draw()` |
| Pixelated beam (no anti-alias) | ElectricBeam.gd `_ready()` |
| Door flash + shrink-to-center on open | Door.gd `set_open()` |
| Door grow-from-center on close | Door.gd `set_open()` |
| Floor panel circle outline when active | FloorPanel.gd `_draw()` |
| Blocker texture alternation when blocking | LightningBlocker.gd `_draw()` |
| Blocker spark animation | LightningBlocker.gd `_draw()` |
| Connected blocker propagation | Main.gd `_expand_connected_blockers()` |
| Beam multi-hop through Nuts | Main.gd `_compute_beam_path()` |
| Key collect animation (shrink to center + fly to player) | Key.gd `_collect()` |
| KeyDoor white flash on open | KeyDoor.gd `_open()` |
| CRT static on room reset (fade-in → hold 0.2s → fade-out) | ResetEffect.gd |
| Splash screen on launch | SplashScreen.gd |
