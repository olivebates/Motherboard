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
- **Player, Prong** — root `Node2D` position is the **hitbox bottom** (Y-sort key). A `Body` child is offset upward so sprites stay tile-centered; see Y-Sorting below.
- **PushBlock, Nut** → positioned at **tile top-left** (`col*32, row*32`); sprite at `(0, 0)`
- Door, FloorPanel, LightningBlocker, KeyDoor, Key, PassBlock → positioned at **tile top-left**

**Sprite origin convention:** All sprites use `centered = false` (top-left origin).
- Player / Prong: sprite on `Body` at `(-16, -16)` so it covers the tile when the body origin is at tile center
- PushBlock / Nut: sprite at `(0, 0)` on the root node
- Tile-top-left objects: sprite at `(0, 0)` fills the tile naturally

---

## Y-Sorting (depth)

Godot Y-sorts by each node's `position.y` (higher Y = drawn in front). Walls use per-tile sort at **tile top** (`y_sort_origin = 0` on wall tiles).

**Setup (`Main._setup_y_sort_children()`):**
- `Walls` `TileMapLayer` has `y_sort_enabled = true`; `Main` does not
- At startup, gameplay nodes in `Y_SORT_GROUPS` are reparented under `Walls` (global transform preserved) so they sort in the same pass as wall tiles
- New prongs are spawned as children of `wall_tilemap` directly

**`Y_SORT_GROUPS`:** `players`, `prongs`, `doors`, `lightning_blockers`, `key_doors`, `push_blocks`, `pass_blocks`, `keys`, `teleport_panels`

**Depth rule:** compare actor **hitbox bottom** vs solid **tile top**.
- Hitbox bottom below tile top (larger Y) → actor in front
- Hitbox bottom above tile top (smaller Y) → actor behind

**Player & Prong (`YSortHitboxBottom.gd`):**
- Root position = hitbox bottom (movement / Y-sort for player)
- `Body` child at `(0, -(hitbox_offset.y + half_h))` keeps sprite + hitbox in the original tile-centered layout
- `SPRITE_OFFSET = (-16, -16)` on `Body`
- Player hitbox: 10×10 on `Body`, offset `(0, 8)` → `_body_offset = (0, -13)`
- Prong hitbox: 8×8 on `Body`, offset `(0, 0)` → `_body_offset = (0, -4)`; placed via `setup(hitbox_center)`

**Other solids (doors, blockers, key doors, push blocks, etc.):** node at tile top-left; sort Y = tile top (same as walls).

**Not Y-sorted with walls:** `ElectricBeam` (`z_index = 10`), `FloorPanel` (`z_index = -10`), UI sprites, camera, overlays.

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
  Nut.tscn                 — Pushable conductor; beam routes through it when chain ability active
  Screw.tscn               — Static conductor; like Nut but cannot be pushed
  KeyDoor.tscn             — Solid door that opens when all Keys in the room are collected
  Key.tscn                 — Collectible that unlocks the KeyDoor in the same room
  PassBlock.tscn           — Passable block; player walks through, push blocks cannot enter
  AbilityPickup.tscn       — Ability unlock pickup (white circle); exports: ability, message
  AbilityGate.tscn         — Object hidden until a required ability is unlocked; TAB.png sprite
  TeleportPanel.tscn       — Interactive teleport panel; closed=solid, open=passable; exports: panel_name, one_way
  OnewayPanel.tscn         — TeleportPanel with one_way=true pre-set; player can teleport from it but not to it

scripts/
  GameManager.gd           — Autoload singleton (puzzle state + ability tracking)
  Main.gd                  — Root scene controller
  Player.gd                — Player movement and input; exports start_with_push, start_with_chain
  Prong.gd                 — Prong placement logic
  PushBlock.gd             — Push block with sprite-lag animation
  ElectricBeam.gd          — Animated electricity beam (white, no transparency)
  Door.gd                  — Door open/close logic
  FloorPanel.gd            — Floor panel registration + circle-outline highlight + pulsing border highlight
  LightningBlocker.gd      — Lightning blocker; alternates textures when active
  WallTileMap.gd           — TileMapLayer script for painting walls in-editor
  ResetEffect.gd           — CRT static CanvasLayer effect for room reset
  KeyDoor.gd               — Solid door; counts Keys in same room, opens with shrink-to-center animation
  Key.gd                   — Collectible; shrinks to center on pickup, notifies KeyDoor
  Nut.gd                   — Pushable conductor; beam routes through it when chain ability active
  Screw.gd                 — Static conductor; beam routes through it when chain ability active; cannot be pushed
  PassBlock.gd             — Passthrough block; solid to push blocks, transparent to player
  SplashScreen.gd          — Launch splash; black bg + credit text, dismissed by any key
  YSortHitboxBottom.gd     — Hitbox-bottom Y-sort helpers (Player, Prong)
  MapOverlay.gd            — Map overlay UI (TAB to open); slides in/out from top; teleport mode requires push ability
  TeleportAnchor.gd        — Room teleport anchor markers (legacy fallback; TeleportPanel is now the primary teleport mechanic)
  TeleportPanel.gd         — Interactive teleport panel; closed=solid (player pushes 0.2s to open); open=passable floor; screenshake on open; exports panel_name (shown on map) and one_way (excludes from destinations)
  OnewayPanel.gd           — (uses TeleportPanel.gd) TeleportPanel with one_way=true; source-only teleporter
  AbilityPickup.gd         — Pickup that grants an ability and triggers the ability intro via AbilityTutorial
  AbilityMessage.gd        — CanvasLayer message overlay (layer 25); prompt appears after 2s
  AbilityGate.gd           — Node2D that hides its sprite until required_ability is granted
  AbilityTutorial.gd       — Autoload singleton; plays per-ability intro animations (sphere arcs, block/panel highlights)

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
  TAB.png                  — AbilityGate sprite
  teleport_closed.gif      — TeleportPanel closed/solid sprite
  teleport_open.png        — TeleportPanel open/passable sprite
```

---

## Scripts

### GameManager.gd (autoload singleton)
**Purpose:** Central puzzle state manager. `evaluate_puzzle()` is driven solely by `Main._update_beam()`.

**Key variables:**
- `prongs: Array` — up to 2 entries, each `{node: Node, grid_pos: Vector2i}`
- `beam_blocked: bool` — set by Main before `evaluate_puzzle()`
- `floor_panels: Dictionary` — `Vector2i → Array[String]` (one or two IDs per panel)
- `doors: Dictionary` — `String id → Array[Node]`
- `_abilities: Dictionary` — `String → bool`; tracks granted abilities
- `signal doors_update(id: String, open: bool)`
- `signal shake_requested(strength: float)`
- `const PANEL_ACTIVATION_RADIUS := 24.0` — radius (px) for prong-to-panel proximity check

**Key functions:**
- `place_prong(node, grid_pos)` — appends entry
- `remove_prong(node)` — removes by node reference
- `clear_prongs()` → `Array` — clears all, returns removed for animation
- `evaluate_puzzle()` — opens doors if: not beam_blocked, 2 prongs on **different** panels sharing at least one id; two prongs on the same panel never open doors
- `register_floor_panel(grid_pos, id, id2="")` — stores 1–2 IDs for a panel
- `_panel_near(world_pos)` → `Vector2i` — returns panel grid pos within activation radius, or `(-999999,-999999)`
- `grant_ability(ability)` — marks ability as acquired
- `has_ability(ability)` → `bool`
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
- `ability_message: Node` — `AbilityMessage` CanvasLayer instance; exposed for `AbilityPickup` to call `show_message()`

**Key functions:**
- `_setup_y_sort_children()` — enables Y-sort on `Walls`, reparents `Y_SORT_GROUPS` nodes under `wall_tilemap`. Screws are NOT in `Y_SORT_GROUPS` and are not reparented; they are static solids checked via `_is_static_solid()` using the `"screws"` group
- `_process(delta)` — shake decay → `camera.offset`
- `_trigger_shake(strength)` — sets `_shake_amount`; connected to `GameManager.shake_requested`
- `_update_beam()` — checks blockers, sets `GameManager.beam_blocked`, calls `evaluate_puzzle()`, activates/deactivates beam
- `spawn_prong(pixel_pos)` — `pixel_pos` is hitbox center; if 2 prongs already exist, oldest is removed with shrink animation before placing new one (no "clear both" behaviour)
- `_reset_room()` — locks player → ResetEffect fades in → awaits `peaked` → resets room state → awaits `done` → unlocks player
- `_transition_to_room(new_room)` — clears prongs instantly, tweens camera 0.25s
- `check_room_transition(player_grid, player_pixel)` — uses `floori` division; downward and rightward transitions require player pixel position to be 24px past the boundary before firing
- `tile_rect(grid_pos)` → `Rect2` — 32×32 world rect for a grid tile
- `_is_static_solid(grid_pos)` — walls, closed doors, lightning blockers, key doors, closed teleport panels, screws (NOT push blocks, NOT pass blocks)
- `is_blocked(grid_pos)` — static solids + push blocks (used for grid queries elsewhere)
- `can_teleport_from_panel()` → `bool` — true if player is on an open panel, at least 2 total open panels exist (including one-ways), and at least one non-one-way destination exists; used for TAB prompt and teleport mode activation
- `get_open_teleport_panel_rooms()` — returns rooms with open non-one-way TeleportPanels (destinations only)
- `get_player_blocking_rects(area)` → `Array[Rect2]` — static tile rects + push-block rects overlapping `area`; used by player AABB movement
- `can_push_block_to(grid_pos)` — false if static solid, push block, or pass block occupies tile
- `get_push_block_at_face(player_rect, dir, from_point)` → `Node` — among push blocks flush against `player_rect` on the given face, returns the one whose center is closest to `from_point`
- `has_pass_block_at(grid_pos)` — checks pass_blocks group
- `get_push_block_at(grid_pos)` → Node or null
- `_find_nearest_open_tile(start)` — BFS for nearest unblocked tile; uses `is_blocked` (includes push blocks)
- `is_player_on_active_teleport_panel()` → `bool` — true if player hitbox overlaps any open TeleportPanel
- `get_open_teleport_panel_rooms()` → `Array` — list of room coords that contain an open TeleportPanel
- `_get_open_panel_for_room(room)` → `Node` — finds the open TeleportPanel in a given room (used by `_on_teleport_requested`)
- `_on_teleport_requested(room)` — teleports to the open TeleportPanel in target room; falls back to TeleportAnchor if none
- `_update_tab_label()` — shows "TAB" Label above player sprite when on open panel with ≥2 open panels; color matches `modulate`; position tracks `player.visual_pos`

---

### Player.gd (Node2D)
**Purpose:** Free pixel-based movement, push input, and prong placement.

**Constants:** `SPEED=272 px/s`, `SPRITE_SPEED=20.0`, `CONTACT_EPS=0.1`, `PUSH_FREEZE=0.15`

**Scene structure:** Root `Node2D` (script) → `Body` → `Sprite2D` + `Hitbox`. Root `position` = **hitbox bottom** (Y-sort + movement anchor). `Body` holds visuals/collision at tile-centered layout.

**Hitbox:** `Body/Hitbox` `CollisionShape2D`, `RectangleShape2D` 10×10 at `(0, 8)`. Read in `_ready()` via `YSortHitboxBottom.read_hitbox()`; `_body_offset` computed so hitbox bottom sits on root origin.

**Movement (AABB collision):** Root `position` is hitbox bottom. `_hitbox_rect(pos)` = `pos + _body_offset + _hitbox_offset`. Axis-separated movement against `Main.get_player_blocking_rects()`. Squash/stretch on dominant axis. Pass blocks are not solids.

**Push detection:** After movement; single cardinal input; flush against push-block face. Closest block by `_sprite_center()`. On success: `block.push(dir)`, shake (0.8), `PUSH_FREEZE` axis lock. Push is **gated** by `GameManager.has_ability("push")` — no pushing until that ability is acquired.

**Startup ability grants:** `@export var start_with_push: bool` and `@export var start_with_chain: bool` — if true, the corresponding ability is granted via `GameManager.grant_ability()` in `_ready()` without requiring a pickup.

**Key functions:** `get_body_center()` → hitbox center world pos; `_hitbox_rect(pos)`, `_sprite_center()`, `_grid_to_world()` / `_world_to_grid()`, `reset_to(gp)`, `_try_push()`, `_start_push_lock(dir)`

**References `Main` via `get_tree().current_scene`** (not `get_parent()`), because the player is reparented under `Walls` at runtime.

---

### Prong.gd (Node2D)
- Group `"prongs"`; same `Body` / hitbox-bottom layout as Player (8×8 hitbox on `Body`)
- `grid_pos: Vector2i` — `floori(position.x / 32), floori(position.y / 32)` (root = hitbox bottom)
- `setup(pixel_pos)` — `pixel_pos` is hitbox center; root placed via `YSortHitboxBottom.root_pos_from_hitbox_center()`; sprite `(-16,-16)`; tweens scale `0 → 1.3 → 1`
- `apply_clear_shrink(s)` — shrink-to-center clear animation (called from `Main.spawn_prong()`)
- **Max 2.** Third press clears both, then deactivates beam

---

### Nut.gd (Node2D)
**Purpose:** Pushable conductor. Identical push/reset behaviour to PushBlock (tile top-left node, `SPRITE_OFFSET = (0, 0)`) but also in `"nuts"` group. After slide tween, calls `Main._update_beam()` via `get_tree().current_scene`. `get_beam_point()` returns sprite center. `get_collision_rect()` → 32×32 world `Rect2`. Beam routes through Nuts only when `GameManager.has_ability("chain")`.

---

### Screw.gd (Node2D)
**Purpose:** Static conductor. Like Nut but cannot be pushed. In `"nuts"` group (beam routes through it when chain ability is acquired) and `"screws"` group (used by `Main._is_static_solid()` to block player and push blocks). Has `get_grid_pos()`, `get_beam_point()`, `get_collision_rect()`, `reset()`. Does NOT have a `push()` method and is NOT in `"push_blocks"` group.

---

### PushBlock.gd (Node2D)
**Purpose:** Instantly teleports one tile when pushed; sprite slides to simulate smooth movement.

- Node at **tile top-left**; `SPRITE_OFFSET = (0, 0)`; `_grid_to_world(gp)` → `(gp.x * 32, gp.y * 32)`
- `_ready()` — infers `start_grid_pos` from editor placement, snaps to tile top-left
- `get_collision_rect()` → 32×32 world `Rect2` for player collision/push queries
- `push(direction)` — teleports node, slides sprite from old position; if highlighted, clears all highlights first
- `reset()` — restores `start_grid_pos`, snaps sprite, clears highlight
- `set_highlight(val)` — enables/disables the pulsing white border drawn via `_draw()`
- `_draw()` — when highlighted, draws an unfilled white rectangle around the block with a ±1px oscillating offset (`sin(time * PI)`, one cycle/s)
- `_clear_all_highlights()` — iterates `"push_blocks"` group; guards with `has_method("set_highlight")` to safely skip Nut nodes

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
- All waypoint positions are offset by `Vector2(0, -4)` in `_resolve_waypoints()` so the beam renders 4px above each node's origin
- `activate(points)` — ordered list: prong A → nuts → prong B
- `deactivate()` — hides beam

---

### Door.gd (Node2D)
- `@export var id: String` — matches FloorPanel IDs
- `set_open(open)` — on open: emits `GameManager.shake_requested(5.0)`, brief white flash, then shrinks sprite toward its center over `ANIM_DURATION=0.15s` (scale + position compensated via `_apply_shrink_scale`) and hides; on close: starts at scale 0 centered, grows back to full size over 0.15s
- Added to group `"doors"`

---

### FloorPanel.gd (Node2D)
- `@export var id: String`; `@export var id2: String = ""`; `@export var positive: bool = true`
- Supports up to two IDs; both registered with `GameManager.register_floor_panel(gp, id, id2)`
- Added to group `"floor_panels"` in `_ready()`
- Sprite is hidden; drawn manually via `_draw()` so circle can render on top
- `_process`: checks if any prong is within `PANEL_ACTIVATION_RADIUS` (24px) of panel center; calls `queue_redraw()` on state change; ticks `_highlight_time` when highlighted
- `_draw()`: draws sprite texture; draws white circle outline (radius 17px) when active; draws pulsing white border (same as PushBlock) when highlighted
- `set_highlight(val)` — enables/disables the pulsing border
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
- `_open()` — removes from group, emits `shake_requested(5.0)`, runs shrink-to-center tween (same as Door: scale+position compensated via `_apply_shrink_scale`, `ANIM_DURATION=0.15s`), then hides sprite permanently
- `reset()` — if opened, returns immediately; kills any in-flight tween, restores sprite scale/position/visibility, re-adds to group

---

### Key.gd (Node2D)
- No `door_id` export — notifies KeyDoors in the same room on collect
- Pickup range uses `player.get_body_center()` (hitbox center), not root position
- `_collect(player)` — notifies KeyDoors, then tweens toward `player.get_body_center()`
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

### AbilityPickup.gd (Node2D)
- Group `"ability_pickups"`; positioned at tile top-left like other collectibles
- `@export var ability: String` — ability name to grant (e.g. `"push"`)
- `@export var message: String` — text shown in the message overlay on collect (used for non-push abilities)
- Draws a white filled circle (radius 10px) at `(16, 16)` via `_draw()`; hidden after collect
- On collect: grants ability via `GameManager.grant_ability()`, sets `room_entry_positions[current_room]` to player's grid pos, locks player, calls `AbilityTutorial.play_intro(ability, player, main)`
- `reset()` — re-shows pickup (does not revoke ability)

---

### AbilityMessage.gd (CanvasLayer, layer=25)
- Instantiated by Main on `_ready()`; exposed as `main.ability_message`
- Starts hidden (`visible = false`)
- `show_message(text)` — shows overlay immediately; after 2 seconds shows "Press any key to continue..." prompt at the bottom
- Input is only accepted once the prompt is visible; any key/button press dismisses and emits `dismissed`
- `dismissed` signal used by `AbilityPickup` to unlock player movement

---

### AbilityTutorial.gd (autoload singleton, Node)
**Purpose:** Plays per-ability intro animations when an ability pickup is collected. Keeps animation logic decoupled from `AbilityPickup`.

**Key constants:** `ARC_HEIGHT=48`, `SPHERE_DURATION=1.2`, `SPHERE_RADIUS=4`

**Inner class `SphereOverlay` (Node2D):** Temporary node added to the main scene during the push intro. Holds `_spheres: Array` of `{pos: Vector2, done: bool}` entries; draws undone spheres as white circles in `_draw()` via `to_local()`. Freed automatically when all spheres arrive.

**Key functions:**
- `play_intro(ability, player, main)` — dispatches to the correct intro by ability name; for unknown abilities falls back to `AbilityMessage` overlay
- `_play_push_intro(player, main)` — freezes player; finds all PushBlocks (with `has_method("set_highlight")` guard to exclude Nuts) in the current room; spawns a `SphereOverlay`; tweens one sphere per block along a parabolic arc (`sin(t*PI)*ARC_HEIGHT`); on each arrival calls `block.set_highlight(true)`; unlocks player and frees overlay when the last sphere lands
- `_play_chain_intro(player, main)` — same arc animation targeting FloorPanel nodes (group `"floor_panels"`) with `id == "chain1"` in the current room; on arrival calls `panel.set_highlight(true)`; unlocks player when last sphere lands

---

### AbilityGate.gd (Node2D)
- `@export var required_ability: String = "push"`
- Sprite starts hidden; `_process` shows it as soon as `GameManager.has_ability(required_ability)` returns true
- Uses `TAB.png` sprite (`centered = false`)

---

### TeleportPanel.gd (Node2D)
- Group `"teleport_panels"`; positioned at tile top-left; in `Y_SORT_GROUPS` so Y-sorted under `Walls`
- `@export var panel_name: String` — displayed above the cursor room on the map in teleport mode
- `@export var one_way: bool = false` — if true, excluded from `get_open_teleport_panel_rooms()` (can't be teleported to, only from)
- `OPEN_HOLD_TIME = 0.2s` — player must push against it continuously to open
- Closed: solid (included in `_is_static_solid`); draws `teleport_closed.png` via `_draw()`
- Open: passable; draws `teleport_open.png`; emits `GameManager.shake_requested(8.0)` on open
- `is_player_standing_on(player)` — true when open and player hitbox overlaps panel rect
- `get_grid_pos()`, `get_collision_rect()`, `reset()` — standard tile accessors; reset closes the panel
- Scene has a hidden `Sprite2D` child; drawing is done entirely via `_draw()`

### OnewayPanel (Node2D — uses TeleportPanel.gd)
- Identical to TeleportPanel but `one_way = true` pre-set in scene data (`scenes/OnewayPanel.tscn`)
- Player can open and teleport *from* it; it never appears as a destination in the map menu

---

### MapOverlay.gd (CanvasLayer, layer=10)
**Purpose:** Map/teleport overlay opened by TAB. Slides in/out from the top of the screen (0.15s SINE tween). Mode is determined at open time based on player state.

**Modes:**
- **Teleport mode** — player is on an open TeleportPanel and at least one non-one-way destination exists (`Main.can_teleport_from_panel()`). Cursor navigates between destination rooms; WASD snaps cursor to nearest destination; Space teleports. Instructions always show "WASD: Move  Space: Teleport  TAB: Close".
- **Map-only mode** — TAB pressed elsewhere (or no destinations). No cursor, no navigation. Instructions: "TAB: Close"

**Key variables:** `_teleport_mode: bool`, `_open_panel_rooms: Array` (destinations only), `_visited: Dictionary`, `_cursor: Vector2i`, `_slide_tween: Tween`

**Visual style:** Background is a fitted solid-black box with a tint-colored 2px border. Box width expands to fit the widest of: room grid, instruction text, or panel name text. Box top expands upward when a panel name is present. All rooms, connections, and stubs drawn in `Main.modulate` tint. Rooms with an open destination panel show a black dot at center. In teleport mode, cursor room has a 1px tint outline offset 1px outward on all sides (2px extra on right/bottom). Panel name drawn in tint above rooms; instructions in tint below. TAB prompt and teleport mode require ≥2 total open panels (any type) and ≥1 non-one-way destination. Unvisited rooms with open panels are shown on the map. All text uses tint color.

**Connections:** `_has_exit(room, dir)` — checks for at least one non-wall tile on the border; right/down checks the first column/row of the neighbour room. Connections only drawn between visited rooms that have an exit between them.

---

### WallTileMap.gd (TileMapLayer)
**Purpose:** Painted in the Godot editor to define wall tiles. Auto-configures its TileSet in `_ready()`. `y_sort_enabled = true`; parent layer for all Y-sorted gameplay entities (see Y-Sorting).

---

### YSortHitboxBottom.gd (class_name)
**Purpose:** Shared math for Player and Prong hitbox-bottom Y-sort layout.

- `SPRITE_OFFSET` — `Vector2(-16, -16)`
- `read_hitbox(hitbox)` → `{half_w, half_h, offset}`
- `body_offset_from_hitbox(offset, half_h)` → `Vector2(0, -(offset.y + half_h))`
- `hitbox_center_from_root(root_pos, body_offset, hitbox_offset)`
- `root_pos_from_hitbox_center(center, body_offset, hitbox_offset)`

---

## Scenes (Node Structures)

```
Main.tscn (runtime Y-sort):
  Main [Main.gd, y_sort_enabled=false]
  ├── Walls [TileMapLayer, y_sort_enabled=true, y_sort_origin=0 per tile]
  │     ├── Player, Prong(s), Door(s), LightningBlocker(s), KeyDoor(s),
  │     │   PushBlock(s), Nut(s), PassBlock(s), Key(s)  ← reparented at _ready
  │     └── (wall tile cells)
  ├── Camera2D, ElectricBeam, FloorPanel(s), UI sprites, …

Player.tscn:
  Node2D [Player.gd]  ← root position = hitbox bottom
  └── Body [Node2D, offset (0, -13) at runtime]
      ├── Sprite2D [electric_front.png, centered=false, offset (-16,-16)]
      └── Hitbox [CollisionShape2D, 10×10 at (0, 8)]

Prong.tscn:
  Node2D [Prong.gd]  ← root position = hitbox bottom
  └── Body [Node2D, offset (0, -4) at runtime]
      ├── Sprite2D [stake.png, centered=false, offset (-16,-16)]
      └── Hitbox [CollisionShape2D, 8×8 at (0, 0)]

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

AbilityPickup.tscn:
  Node2D [AbilityPickup.gd]  ← no sprite child; circle drawn via _draw()

AbilityGate.tscn:
  Node2D [AbilityGate.gd]
  └── Sprite2D [TAB.png, centered=false, visible=false]

TeleportPanel.tscn:
  Node2D [TeleportPanel.gd]  ← position at tile top-left; drawing via _draw()
  └── Sprite2D [centered=false, visible=false — hidden; draw done in _draw()]

OnewayPanel.tscn:
  Node2D [TeleportPanel.gd, one_way=true]  ← same structure as TeleportPanel
  └── Sprite2D [centered=false, visible=false]

Nut.tscn:
  Node2D [Nut.gd]
  ├── Sprite2D [washer_block.png, centered=false]
  ├── Area2DLeft  [Area2D] → CollisionShapeLeft  [CollisionShape2D] — legacy; push uses AABB collision
  ├── Area2DRight [Area2D] → CollisionShapeRight [CollisionShape2D]
  ├── Area2DUp    [Area2D] → CollisionShapeUp    [CollisionShape2D]
  └── Area2DDown  [Area2D] → CollisionShapeDown  [CollisionShape2D]

Screw.tscn:
  Node2D [Screw.gd]
  ├── Sprite2D [screw.png, centered=false]
  ├── Area2DLeft  [Area2D] → CollisionShapeLeft  [CollisionShape2D]
  ├── Area2DRight [Area2D] → CollisionShapeRight [CollisionShape2D]
  ├── Area2DUp    [Area2D] → CollisionShapeUp    [CollisionShape2D]
  └── Area2DDown  [Area2D] → CollisionShapeDown  [CollisionShape2D]
```

---

## Sprites

All objects use `centered = false`.

| Object | Sprite | Node position |
|---|---|---|
| Player | electric_front.png | hitbox bottom (body/visual at tile center) |
| Prong | stake.png | hitbox bottom (placed at hitbox center from player) |
| PushBlock | SD_Card_block.png | tile top-left |
| Nut | washer_block.png | tile top-left |
| Door | switch_closed.png | tile top-left |
| FloorPanel | positive.png / negative.png | tile top-left |
| LightningBlocker | resistor_small.png / resistor_small2.png | tile top-left |
| KeyDoor | (door sprite) | tile top-left |
| Key | key_file3.png | tile top-left |
| PassBlock | switch_open2.png | tile top-left |
| AbilityPickup | (drawn via _draw) | tile top-left |
| AbilityGate | TAB.png | tile top-left |

Floor: black `Color(0, 0, 0)` drawn in `Main._draw()`. Background: black.

---

## Puzzle Logic Flow

```
Player presses Space:
  → Main.spawn_prong(player.get_body_center())
      if 2 prongs exist: clear both (Prong.apply_clear_shrink), deactivate beam, return
      else: place prong under Walls tilemap → _update_beam():
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
| Prong clear animation (shrink to top-center) | Prong.gd `apply_clear_shrink()`, Main.gd `spawn_prong()` |
| Y-sort depth (hitbox bottom vs tile top) | Main.gd `_setup_y_sort_children()`, YSortHitboxBottom.gd |
| Sprite lag on player move | Player.gd `visual_pos` lerp on `Body/Sprite2D` |
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
| KeyDoor shrink-to-center on open (same as Door) | KeyDoor.gd `_open()` |
| CRT static on room reset (fade-in → hold 0.2s → fade-out) | ResetEffect.gd |
| Splash screen on launch | SplashScreen.gd |
| Map overlay slides in/out from top (0.15s SINE) | MapOverlay.gd `_open_map()` / `_close_map()` |
| Floor panel pulsing border highlight (chain tutorial) | FloorPanel.gd `set_highlight()` |
| Ability intro sphere arcs (push → blocks, chain → panels) | AbilityTutorial.gd |
