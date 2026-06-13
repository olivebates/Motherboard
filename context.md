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
- **Enemy** → positioned at **tile top-left** (`col*32, row*32`); moves continuously from there

**Sprite origin convention:** All sprites use `centered = false` (top-left origin).
- Player / Prong: sprite on `Body` at `(-16, -16)` so it covers the tile when the body origin is at tile center
- PushBlock / Nut: sprite at `(0, 0)` on the root node
- Tile-top-left objects: sprite at `(0, 0)` fills the tile naturally
- Enemy: sprite at `(0, 0)`; visual lag tracked via `_visual_pos` lerp (sprite offset applied each frame)

---

## Y-Sorting (depth)

Godot Y-sorts by each node's `position.y` (higher Y = drawn in front). Walls use per-tile sort at **tile top** (`y_sort_origin = 0` on wall tiles).

**Setup (`Main._setup_y_sort_children()`):**
- `Walls` `TileMapLayer` has `y_sort_enabled = true`; `Main` does not
- At startup, gameplay nodes in `Y_SORT_GROUPS` are reparented under `Walls` (global transform preserved) so they sort in the same pass as wall tiles
- New prongs are spawned as children of `wall_tilemap` directly

**`Y_SORT_GROUPS`:** `players`, `prongs`, `doors`, `lightning_blockers`, `key_doors`, `push_blocks`, `pass_blocks`, `keys`, `teleport_panels`, `screws`, `enemies`, `breakable_walls`, `fans`, `dust_piles`, `wind_turbines`

> **Rule:** Every new solid or interactive object added to the game must be added to `Y_SORT_GROUPS` (and `add_to_group` with a matching group name in its script) so it is reparented under `Walls` at startup and depth-sorts correctly against the player.

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

  player/
    Player.tscn            — Player character
    Prong.tscn             — Placeable prong object (stake sprite)
    ElectricBeam.tscn      — Electricity effect (two Line2D children; glow hidden)

  objects/
    Door.tscn              — Puzzle door (floor-panel activated)
    FloorPanel.tscn        — Floor trigger (positive.png or negative.png sprite)
    LightningBlocker.tscn  — Blocks the electric beam; resistor_small.png sprite
    PushBlock.tscn         — Pushable block (SD_Card_block.png)
    Nut.tscn               — Pushable conductor; beam routes through it when chain ability active
    Screw.tscn             — Static conductor; like Nut but cannot be pushed
    KeyDoor.tscn           — Solid door that opens when all Keys in the room are collected
    Key.tscn               — Collectible that unlocks the KeyDoor in the same room
    PassBlock.tscn         — Passable block; player walks through, push blocks cannot enter
    BreakableWall.tscn     — Solid block destroyed by the electric beam (requires "break" ability); wall_breakable.png sprite; shakes 0.4s then particle burst; resets on room reset
    BossDoor.tscn          — Solid door that permanently disappears when the boss dies; uses locked_door1.png; in "boss_doors" group only (NOT push_blocks — has no push() method); solid to player while visible (included in _is_static_solid)
    AbilityPickup.tscn     — Ability unlock pickup (white circle); exports: ability, message
    AbilityGate.tscn       — Object hidden until a required ability is unlocked; TAB.png sprite
    TeleportPanel.tscn     — Interactive teleport panel; closed=solid, open=passable; exports: panel_name, one_way
    OnewayPanel.tscn       — TeleportPanel with one_way=true pre-set; player can teleport from it but not to it
    TeleportAnchor.tscn    — Room teleport anchor marker (legacy fallback)
    RoomSolvedTile.tscn    — Invisible floor tile; if multiple tiles exist in a room the player must step on each one; only after all are stepped on does the snap SFX + 2px shake fire and the room get marked solved; solved rooms: doors permanently open, broken breakable walls stay broken; state saved per-room in SaveManager
    TimedObject.tscn       — Object that appears after 2 minutes in its room (chain upgrade not yet acquired); blinks every 0.5s while visible; slows player speed to 80% while visible; hides, restores speed, and resets timer on each room entry; always hidden once chain is acquired; uses arrow_up.png sprite
    FanDown.tscn / FanUp.tscn / FanLeft.tscn / FanRight.tscn — Fan objects (Fan_Front/Back/Left/Right.png); @export id: String turns fan on/off via GameManager doors_update (same as Door); @export direction: Vector2i pre-set per scene; in `"fans"` and `"push_blocks"` groups — solid to player via push-block collision; pushable from any direction (sprite-lag slide like PushBlock); when on: player in LOS of airflow receives +60px/s wind push; LOS = same row/column as fan, airflow passes through all solids and ends at room boundary; opaque white dust particles (CPUParticles2D child of Sprite2D, local_coords, z_index=10 above walls) flow along the 32px airflow band; particle color inherits Main.modulate; emitting stops when fan turns off (existing particles ride sprite during slide); push_blocks in airflow are pushed every 0.8s after continuously occupying the stream for 0.8s if the destination tile is free; reset() on room reset
    DustPile.tscn          — Destructible dust pile (Dust_Pile_Alternate.png); solid to player when visible (_destroyed=false); shakes 0.5s when a fan blows on it, then disappears with dust particles flowing in the fan direction; reset() restores it unless SaveManager.is_room_solved() for its room
    WindTurbine.tscn       — Wind-powered turbine (placeholder.png); @export id: String; when any active fan blows on it, calls GameManager.set_wind_power(id, true) to open doors with matching id; glows yellow ring when powered; resets on room reset

  enemies/
    Enemy.tscn             — Enemy that walks toward the player; Front_Idle1.png sprite; CPUParticles2D death burst
    WaterEnemy.tscn        — WaterEnemy variant; uses WaterEnemy.gd; 25 HP + sprite-width health bar; beam −1 HP/frame (2px shake); freezes when not in current room or when map overlay is open; ejects from solids each frame; supports boss_spawned flag
    BounceEnemy.tscn       — BounceEnemy variant; extends WaterEnemy.gd; 100 HP; tile-to-tile pathfinding with 1-tile wall jumps; bounces instead of sliding; no wall collision; z_index=64 draws above walls
    WaterBoss.tscn         — Boss enemy; uses WaterBoss.gd; 1000 HP at 2× scale; place at tile top-left in any room
    BounceBoss.tscn        — Boss enemy; uses BounceBoss.gd; 5 HP at 2× scale (64×64); place at tile top-left in any room
    BounceBossPanel.tscn   — Interactive panel spawned dynamically by BounceBoss; positive/negative variants; activated when electric beam passes through it

  ui/
    TabButton.tscn         — Mute toggle button (used by Main for ♪/SFX buttons)

scripts/
  GameManager.gd           — Autoload singleton (puzzle state + ability tracking)
  AudioManager.gd          — Autoload singleton; manages all SFX and background music; SFX keys: character_death, electric_fail, electric_noise (loops while beam active, -26.1dB), electric_spawn, plant_stake, water_death, snap (-14dB, plays on room solved tile trigger); music keys: "Orange"=Motherboard_Level_Loop, "Yellow"=Motherboard_Title_Loop; all music streams start at -80dB and play immediately; set_music(key) crossfades over 1s (EASE_IN sine fade-out, EASE_OUT sine fade-in, both starting at -30dB so overlap is audible); first set_music call fades in over 3s (MUSIC_START_FADE); start_beam_noise()/stop_beam_noise() control the looping beam SFX; set_music() captures old key in local var before tween to avoid stale closure bug; toggle_music_mute()/toggle_sfx_mute() return new bool state and save pref; is_music_muted()/is_sfx_muted() getters; mute prefs saved to user://audio_prefs.json (separate from save slots), loaded at _ready() before first set_music(); set_music() and start_beam_noise() are no-ops when muted
  Main.gd                  — Root scene controller; on room reset: plays character_death SFX; on prong spawn: plays plant_stake SFX; on room transition: plays music for new room anchor's music key; on teleport: fades static in over 0.4s then teleports (plays electric_spawn) and instantly hides static; boss_spawned_enemies in current room are queue_freed instead of reset; skips splash screen when SaveManager.skip_splash is true; TAB label above player has black outline (outline_size=2); resets breakable_walls in current room on room reset; shoot_door_ball(from, to, callback) spawns a DoorBall node that flies to the door and calls callback on arrival; ♪/SFX mute buttons in top-right corner (CanvasLayer layer=60); buttons styled with 1px StyleBoxFlat border+padding, tint-colored border/text matching Main.modulate (updated each frame), white bg on hover, same minimum size via _equalize_button_sizes() (deferred); muted buttons dim to 35% modulate
  Player.gd                — Player movement and input; exports start_with_push, start_with_chain, save_system_enabled; calls SaveManager.on_player_ready() at end of _ready(); var speed_multiplier: float = 1.0 scales movement (set by TimedObject); active fan airflow applies +60px/s wind after movement; push requires holding against a block for PUSH_HOLD_TIME=0.15s before it fires (_push_charge_time/_push_charge_dir/_push_charge_block track the charge; resets if direction/block changes or player moves freely); cannot push non-fan blocks while standing in active fan airflow (fans remain pushable); debug ability shortcuts (room_teleport_enabled only): Shift+P=push, Shift+O=chain, Shift+I=break
  SaveManager.gd           — Autoload singleton; save/load system; autosaves every 5s to active slot; slot 1 selected by default; number-key input only active when Player.save_system_enabled=true: 1–9 selects+loads slot, Shift+1–9 deletes, Alt+1–9 selects without loading; save_system_enabled=false auto-activates slot 1 for autosave but never loads on start; reloads scene on load (skip_splash=true); tracks key_doors_opened, boss_doors_opened, boss_defeated, rooms_solved (Array of [rx,ry]), breakables_destroyed (Array of [gx,gy]) for permanently-freed/persistent nodes; notify_room_solved(room) also snapshots all currently-destroyed breakable walls in that room; is_room_solved()/is_breakable_destroyed() queried by Door and BreakableWall; on load: restores destroyed breakables silently and re-opens doors in solved rooms after beam sync; status label (top-left, fades after 1.5s) for slot feedback; save files at user://save_slot_N.json
  Prong.gd                 — Prong placement logic
  PushBlock.gd             — Push block with sprite-lag animation; pushes enemies on contact
  Fan.gd                   — Pushable fan; groups "fans" + "push_blocks"; tile top-left grid_pos/start_grid_pos; sprite-lag push(); is_position_in_airflow() for wind LOS; dust particle emitter; _push_blocks_in_airflow() with 0.8s dwell + 0.8s push interval; reset() restores grid_pos and stops particles
  DustPile.gd              — Destructible dust pile; shakes then dissolves when fan airflow hits center; reset() skipped in solved rooms
  WindTurbine.gd           — Wind-powered switch; set_wind_power(id) when any active fan blows on it; yellow ring when powered; reset() clears power state
  ElectricBeam.gd          — Animated electricity beam (white, no transparency); calls AudioManager.start_beam_noise() on activate and stop_beam_noise() on deactivate
  Door.gd                  — Door open/close logic; set_open(false) is ignored when SaveManager.is_room_solved() for the door's room (permanently open in solved rooms); set_open(true) fires a DoorBall from the player to the door center — door stays solid and sprite hidden until ball arrives, then _do_open() runs the shrink animation; _opening flag prevents duplicate opens; set_open(false) cancels any in-flight open
  FloorPanel.gd            — Floor panel registration + circle-outline highlight + pulsing border highlight; when a highlighted chain1 panel becomes active, checks if all other chain1 panels in the room are also active — if so, clears highlight on all of them
  LightningBlocker.gd      — Lightning blocker; alternates textures when active; plays electric_fail SFX when set_blocking(true)
  WallTileMap.gd           — TileMapLayer script for painting walls in-editor
  ResetEffect.gd           — CRT static CanvasLayer effect for room reset; play_teleport_buildup() fades in over 0.4s and stays; cancel() instantly hides
  KeyDoor.gd               — Solid door; counts Keys in same room, opens with shrink-to-center animation; opens immediately on _count_keys() if room has zero keys; _open() fires a DoorBall then calls _do_open() on arrival (same ball pattern as Door.gd); _opening flag guards against duplicate opens; reset() cancels any in-flight open
  Key.gd                   — Collectible; shrinks to center on pickup, notifies KeyDoor
  Nut.gd                   — Pushable conductor; beam routes through it when chain ability active; pushes enemies on contact
  Screw.gd                 — Static conductor; beam routes through it when chain ability active; cannot be pushed
  PassBlock.gd             — Passthrough block; solid to push blocks, transparent to player
  BreakableWall.gd         — Solid block in "breakable_walls" group; requires "break" ability to be destroyed by beam; shakes 0.4s then hides + spawns particle burst; reset() restores it unless SaveManager.is_breakable_destroyed() (permanently destroyed when room is solved); destroyed walls removed from _is_static_solid so player can walk through; first beam contact frees all nodes in "break_highlight" group
  SplashScreen.gd          — Launch splash; black bg + credit text, dismissed by any key
  YSortHitboxBottom.gd     — Hitbox-bottom Y-sort helpers (Player, Prong)
  MapOverlay.gd            — Map overlay UI (TAB to open); slides in/out from top; teleport mode requires push ability; title always shows "The Map" in both modes; pressing Space on the player's current room does nothing
  TeleportAnchor.gd        — Room teleport anchor markers (legacy fallback; TeleportPanel is now the primary teleport mechanic); @export var color: Color; @export var music: String = "" — "Orange" fades in Motherboard_Level_Loop, "Yellow" fades in Motherboard_Title_Loop on room entry
  TeleportPanel.gd         — Interactive teleport panel; closed=solid (player pushes 0.2s to open); open=passable floor; screenshake on open; exports panel_name (shown on map) and one_way (excludes from destinations)
  OnewayPanel.gd           — (uses TeleportPanel.gd) TeleportPanel with one_way=true; source-only teleporter
  AbilityPickup.gd         — Pickup that grants an ability and triggers the ability intro via AbilityTutorial; clears all prongs (with shrink animation) and deactivates beam before playing intro
  AbilityMessage.gd        — CanvasLayer message overlay (layer 25); prompt appears after 2s
  AbilityGate.gd           — Node2D that hides its sprite until required_ability is granted
  AbilityTutorial.gd       — Autoload singleton; plays per-ability intro animations (sphere arcs, block/panel highlights); inner class BoundingHighlight (group "break_highlight") draws a single pulsing rect around all breakable walls; inner class SphereOverlay draws arcing spheres
  Utils.gd                 — Autoload singleton; shared helpers — boss health bar HUD (top of screen) + per-enemy sprite health bars; remove_boss_health_bar uses untyped canvas var + erases dict entry before queue_free to avoid freed-instance crash on scene reload; shake_boss_health_bar() tweens canvas offset ±2px horizontally + random ±2px vertically (debounced); CPUParticles2D at fill tip bursts top-right on each shake; create/update/remove_sprite_health_bar() — 32px-wide, 6px-tall boss-style bar above sprite (offset_y=−10), z_index=−1 (draws behind enemy sprite), inherits Main.modulate from scene tree
  Enemy.gd                 — Enemy; walks toward player, blocked by walls/solids, instant beam kill via _handle_beam(), resets player on contact; _eject_from_solid() BFS-finds nearest free tile when inside a solid
  WaterEnemy.gd            — Extends Enemy.gd; MAX_HP=25, hp var, sprite health bar via Utils; overrides _handle_beam() for −1 HP/frame + _trigger_shake(2.0); get_max_hp() overridable; freezes movement when not in current room or when map overlay is open; calls _eject_from_solid() each frame; boss_spawned flag auto-adds to "boss_spawned_enemies" group (deleted on room exit/reset instead of reset); overrides _die() to play water_death SFX; reset() restores hp
  BounceEnemy.gd           — Extends WaterEnemy.gd; BOUNCE_MAX_HP=100; tile BFS pathfinding (walk + jump over 1-tile static walls); hop/jump movement on flat position with arc on sprite only; MOVE_SPEED=0.286; random wait 0.5–0.8s between bounces with landing squash (sin curve); stretch squash/stretch on hop/jump peaks; SPRITE_LAG_SPEED=24 (matches player); no _eject_from_solid; no wall AABB collision; z_index=64; player contact disabled during JUMP arc (wall jump); group "bounce_enemies"
  WaterBoss.gd             — Extends WaterEnemy.gd; BOSS_MAX_HP=1000, 2× scale; overrides get_max_hp(); uses top-screen boss bar (not sprite bar); @export var debug_low_hp: bool sets HP to 10 at start if true; boss health bar via Utils (visible in boss home room when alive); takes 1 dmg/frame from beam (shake 1.0 + health bar shake+particles) + freeze-frame on first contact each exposure; teleports to random free tile (≥5 tiles from player, ≥2 tiles from room border) after 1.5s in beam; sprite slides to new position on teleport; speed scales with HP loss (BASE=40→MAX=100); spawns two WaterEnemy minions 3 tiles out below 80% HP with 0.7s scale-pulse telegraph (interval scales 4s→2s as HP drops, skips spawn if within 96px of player); charge attack: cooldown 3s, triggers when player within 5 tiles — 1s squash/stretch wind-up, then lunges at 240 px/s decelerating to normal speed; teleport mid-windup resets cooldown; phase 2 at 50% HP: screen shake + brief pause; death: series of 3 extreme shakes (0.5s apart), minion water_enemies in room deleted immediately (boss skips self in that loop), boss freezes 1s then arcs off screen in a parabola at z_index=100 with a slight rotation (dir * p * 0.8 rad) — doors open and particles fire once boss exits room bounds; sprite lag at half enemy speed (BOSS_SPRITE_SPEED=10); no modulation effects
  BounceBoss.gd            — Extends WaterEnemy.gd; BOSS_MAX_HP=5, 2× scale (64×64); tile BFS pathfinding with 2×2 walkability checks; hop movement (HOP_DURATION=0.28s) + big bounce attack (5s interval, 0.8s windup, locks target at jump start, tall arc, can't hurt player mid-air); speed scales with HP loss (BASE=0.30→MAX=0.75 move speed multiplier); below 80% HP: wobble telegraph (1s) then spawns BounceEnemies in 3 of 4 random cardinal directions at 96px from player (skips if tile solid); NO beam damage — instead two BounceBossPanel nodes (positive + negative) are spawned in the room at random positions ≥96px from borders when boss registers; when beam passes through BOTH panels simultaneously a stake sprite falls from the top of the screen onto the boss (0.45s tween) dealing 1 damage; panels relocate immediately when object is launched; only one object can fall at a time; on death: clears boss-spawned bounce enemies, arc parabola off screen, opens boss doors; panels hidden when boss is dead or player leaves the room
  BounceBossPanel.gd       — Node2D spawned by BounceBoss; positive/negative variants (positive.png / negative.png, drawn via _draw()); activated (_active=true) when the electric beam passes through the panel center (beam.is_point_on_beam(center, 16px)); draws a white arc outline when active; no GameManager registration; visibility controlled by BounceBoss._process each frame
  BossDoor.gd              — Solid tile object in "boss_doors" group only (NOT push_blocks — has no push() method); provides grid_pos/start_grid_pos/get_grid_pos() computed from position; included in Main._is_static_solid() so it blocks player while visible; open() calls SaveManager.notify_boss_door_opened() then queue_free(); reset() also frees if already opened (permanent removal)
  SaveManager.notify_boss_defeated() — also called by BounceBoss._boss_die()
  RoomSolvedTile.gd        — Invisible floor tile (z_index=-10, group "room_solved_tiles"); positioned at tile top-left; _triggered marks this tile stepped on; _trigger() checks all room_solved_tiles in the same room — only fires SaveManager.notify_room_solved(), snap SFX, and shake_requested(2.0) once every tile in the room has been stepped on; auto-triggers on _ready() if room already solved (loaded from save)
  DoorBall.gd              — Short-lived Node2D (z_index=20) spawned by Main.shoot_door_ball(); draws a white filled circle (radius 5px) at its own origin; launch(from, to, on_arrive) tweens position from→to over 0.28s (EASE_IN SINE) then calls on_arrive and queue_free()s itself
  TimedObject.gd           — Node2D that tracks per-room-visit time; sprite (arrow_up.png) appears after 120s if player lacks chain ability; blinks every 0.5s while visible; sets player.speed_multiplier=0.8 while showing; resets (hides, restores speed, clears timer) each time the player enters its room; always hidden after chain ability granted; requires Sprite2D child named "Sprite2D"

Sprites/
  player/
    electric_front.png     — Player/ElectricBeam sprite (beam drawn procedurally; unused visually)
    stake.png              — Prong sprite

  enemies/
    Front_Idle1.png        — Enemy/WaterEnemy/BounceEnemy/Boss sprite

  objects/
    positive.png           — FloorPanel positive variant sprite; also BounceBossPanel positive
    negative.png           — FloorPanel negative variant sprite; also BounceBossPanel negative
    resistor_small.png     — LightningBlocker idle sprite
    resistor_small2.png    — LightningBlocker active (alternates with resistor_small every 0.5s)
    SD_Card_block.png      — PushBlock sprite
    washer_block.png       — Nut sprite
    switch_closed.png      — Door sprite
    locked_door1.png       — BossDoor sprite
    switch_open2.png       — PassBlock sprite
    key_file3.png          — Key sprite
    wall_breakable.png     — BreakableWall sprite
    TAB.png                — AbilityGate sprite
    teleport_closed.png    — TeleportPanel closed/solid sprite
    teleport_open.png      — TeleportPanel open/passable sprite
    arrow_up.png           — TimedObject sprite
    screw.png              — Screw sprite
    Dust_Pile_Alternate.png — DustPile sprite
    Fan_Front.png          — FanDown sprite
    Fan_Back.png           — FanUp sprite
    Fan_Left.png           — FanLeft sprite
    Fan_Right.png          — FanRight sprite
    placeholder.png        — 32×32 RGBA placeholder (WindTurbine)

  environment/
    wall1.png              — Wall tile sprite

  ui/
    Title_Screen_WIP.png         — Title screen image
    reset_button.png             — Reset button icon
    directions.png               — Directions icon
    Circuit_Sprite_Sheet.webp    — Wall tileset atlas (used by TileSetAtlasSource in Main.tscn)
    Dotted_Line_Sprite_Sheet_Final.png — Dotted line tileset atlas

Sounds/
  sfx/
    Character_Death.ogg    — character_death SFX
    Electric_Fail.ogg      — electric_fail SFX (plays when beam is blocked)
    Electric_Noise1.ogg    — electric_noise SFX (loops while beam active, −26.1dB)
    Electric_Spawn.ogg     — electric_spawn SFX (plays on teleport)
    Plant_Stake1.ogg       — plant_stake SFX (plays on prong placement)
    Water_Death.ogg        — water_death SFX (WaterEnemy/boss death)
    Snap.ogg               — snap SFX (−14dB, plays on room solved tile trigger)

  music/
    Motherboard_Level_Loop.ogg   — "Orange" music key; main level loop
    Motherboard_Title_Loop.ogg   — "Yellow" music key; title/hub loop
    Motherboard_Level_Intro.ogg  — (unused by AudioManager; reserved)
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
- `wind_powered_ids: Array` — ids currently powered by WindTurbine nodes; merged with beam-solved ids in evaluate_puzzle(); cleared by clear_scene_state()
- `const PANEL_ACTIVATION_RADIUS := 24.0` — radius (px) for prong-to-panel proximity check

**Key functions:**
- `place_prong(node, grid_pos)` — appends entry
- `remove_prong(node)` — removes by node reference
- `clear_prongs()` → `Array` — clears all, returns removed for animation
- `clear_scene_state()` — clears prongs, doors, floor_panels, resets beam_blocked; called by SaveManager before scene reload to prevent stale node refs
- `evaluate_puzzle()` — opens doors if: not beam_blocked, 2 prongs on **different** panels sharing at least one id; guards prong node refs with `is_instance_valid()`
- `set_wind_power(id, powered)` — adds/removes id from wind_powered_ids then calls evaluate_puzzle(); used by WindTurbine
- `register_floor_panel(grid_pos, id, id2="")` — stores 1–2 IDs for a panel
- `_panel_near(world_pos)` → `Vector2i` — returns panel grid pos within activation radius, or `(-999999,-999999)`
- `grant_ability(ability)` — marks ability as acquired
- `has_ability(ability)` → `bool`
- `get_abilities()` → `Dictionary` — returns duplicate of `_abilities`; used by SaveManager
- `set_abilities(d)` — replaces `_abilities` from a dictionary; used by SaveManager on load
- `get_prong_positions()` → `Array[Vector2i]` — skips invalid nodes
- `get_prong_world_positions()` → `Array[Vector2]` — skips invalid nodes

---

### Main.gd (Node2D — root scene)
**Purpose:** Game world controller. Manages rooms, camera, prong spawning, reset, beam/blocker logic.

**Key constants:** `TILE_SIZE=32`, `WORLD_OFFSET=0`, `CAMERA_MARGIN=Vector2(16,16)`, `CAMERA_TWEEN_DURATION=0.25`

**Key variables:**
- `@onready var wall_tilemap: TileMapLayer` — assign in inspector; checked by `_is_static_solid()` / `get_player_blocking_rects()`
- `@export var pass_tilemap: TileMapLayer` — assign in inspector; tiles block push blocks (`can_push_block_to`) but are passable to the player
- `current_room: Vector2i`
- `room_entry_positions: Dictionary`
- `_shake_amount: float` — camera shake magnitude
- `ability_message: Node` — `AbilityMessage` CanvasLayer instance; exposed for `AbilityPickup` to call `show_message()`

**Key functions:**
- `_setup_y_sort_children()` — enables Y-sort on `Walls`, reparents `Y_SORT_GROUPS` nodes under `wall_tilemap`. Screws are in `Y_SORT_GROUPS` and are reparented like other solids; they are also checked via `_is_static_solid()` using the `"screws"` group
- `_process(delta)` — shake decay → `camera.offset`
- `_trigger_shake(strength)` — sets `_shake_amount`; connected to `GameManager.shake_requested`
- `_update_beam()` — checks blockers, sets `GameManager.beam_blocked`, calls `evaluate_puzzle()`, activates/deactivates beam
- `_nearest_first_beam(current, target, remaining, path)` → `Array` — nearest-first DFS beam path search; at each hop tries candidates (nuts + target) sorted by distance from `current`, backtracking if a nut leads to a dead end; replaces the old shortest-path `_search_beam`
- `spawn_prong(pixel_pos)` — `pixel_pos` is hitbox center; if 2 prongs already exist, oldest is removed with shrink animation before placing new one (no "clear both" behaviour)
- `_reset_room()` — locks player → ResetEffect fades in → awaits `peaked` → resets room state (prongs, push blocks, fans, breakable walls, key doors, keys, enemies, dust piles, wind turbines) → awaits `done` → unlocks player
- `_transition_to_room(new_room)` — clears prongs instantly, resets enemies in new room, tweens camera 0.25s
- `check_room_transition(player_grid, player_pixel)` — uses `floori` division; downward and rightward transitions require player pixel position to be 24px past the boundary before firing
- `tile_rect(grid_pos)` → `Rect2` — 32×32 world rect for a grid tile
- `_is_static_solid(grid_pos)` — walls, closed doors, lightning blockers, key doors, closed teleport panels, screws, visible dust piles, wind turbines (NOT push blocks, NOT pass blocks, NOT fans — fans block via push_blocks collision)
- `is_blocked(grid_pos)` — static solids + push blocks (used for grid queries elsewhere)
- `can_teleport_from_panel()` → `bool` — true if player is on an open panel, at least 2 total open panels exist (including one-ways), and at least one non-one-way destination exists; used for TAB prompt and teleport mode activation
- `get_open_teleport_panel_rooms()` — returns rooms with open non-one-way TeleportPanels (destinations only)
- `get_player_blocking_rects(area)` → `Array[Rect2]` — static tile rects + push-block rects overlapping `area`; used by player and enemy AABB movement
- `can_push_block_to(grid_pos)` — false if static solid, push block, pass block, or pass_tilemap tile occupies tile
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

**Constants:** `SPEED=217.6 px/s` (20% reduced from original 272), `SPRITE_SPEED=24.0`, `CONTACT_EPS=0.1`, `PUSH_FREEZE=0.15`, `PUSH_HOLD_TIME=0.15`, `WIND_FORCE=60.0`

**Scene structure:** Root `Node2D` (script) → `Body` → `Sprite2D` + `Hitbox`. Root `position` = **hitbox bottom** (Y-sort + movement anchor). `Body` holds visuals/collision at tile-centered layout.

**Hitbox:** `Body/Hitbox` `CollisionShape2D`, `RectangleShape2D` 10×10 at `(0, 8)`. Read in `_ready()` via `YSortHitboxBottom.read_hitbox()`; `_body_offset` computed so hitbox bottom sits on root origin.

**Movement (AABB collision):** Root `position` is hitbox bottom. `_hitbox_rect(pos)` = `pos + _body_offset + _hitbox_offset`. Axis-separated movement against `Main.get_player_blocking_rects()`. Squash/stretch on dominant axis. Pass blocks are not solids. After player input movement, active fan airflow (`is_position_in_airflow(get_body_center())`) applies an additional axis-separated wind displacement at `WIND_FORCE` px/s.

**Push detection:** After movement; single cardinal input; flush against push-block face. Closest block by `_sprite_center()`. On success: `block.push(dir)`, shake (0.8), `PUSH_FREEZE` axis lock. Push is **gated** by `GameManager.has_ability("push")` — no pushing until that ability is acquired. While `_is_in_fan_airflow()` is true, push charge is blocked for all blocks **except** nodes in the `"fans"` group (fans remain pushable in wind).

**Startup ability grants:** `@export var start_with_push: bool` and `@export var start_with_chain: bool` — if true, the corresponding ability is granted via `GameManager.grant_ability()` in `_ready()` without requiring a pickup.

**Save system:** `@export var save_system_enabled: bool = false`. If `false`, SaveManager auto-activates slot 1 and loads it on start. If `true`, the player manually picks a slot with 1–9. `SaveManager.on_player_ready(save_system_enabled)` is called at the end of `_ready()`.

**Key variables:** `speed_multiplier: float = 1.0` — scales movement velocity; set to `0.8` by TimedObject while it is visible, restored to `1.0` when it hides. `_push_charge_time`, `_push_charge_dir`, `_push_charge_block` — track how long the player has held against a specific block; charge resets if direction/block changes or player moves freely; push fires only after `PUSH_HOLD_TIME=0.15s`.

**Key functions:** `get_body_center()` → hitbox center world pos; `_hitbox_rect(pos)`, `_sprite_center()`, `_grid_to_world()` / `_world_to_grid()`, `reset_to(gp)`, `_try_push()`, `_is_in_fan_airflow()`, `_start_push_lock(dir)`, `eject_from_solid()` — BFS from current grid pos to nearest free tile; called every frame in `_process` and at end of `reset_to`

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

**Enemy interaction:** `push(direction)` checks for enemies whose center tile matches the new `grid_pos` and calls `enemy.push(direction)` on them, same as PushBlock.

---

### Screw.gd (Node2D)
**Purpose:** Static conductor. Like Nut but cannot be pushed. In `"nuts"` group (beam routes through it when chain ability is acquired) and `"screws"` group (used by `Main._is_static_solid()` to block player and push blocks). Has `get_grid_pos()`, `get_beam_point()`, `get_collision_rect()`, `reset()`. Does NOT have a `push()` method and is NOT in `"push_blocks"` group.

---

### PushBlock.gd (Node2D)
**Purpose:** Instantly teleports one tile when pushed; sprite slides to simulate smooth movement.

- Node at **tile top-left**; `SPRITE_OFFSET = (0, 0)`; `_grid_to_world(gp)` → `(gp.x * 32, gp.y * 32)`
- `_ready()` — infers `start_grid_pos` from editor placement, snaps to tile top-left
- `get_collision_rect()` → 32×32 world `Rect2` for player collision/push queries
- `push(direction)` — teleports node, slides sprite from old position; checks for enemies in new tile and pushes them; if highlighted, clears all highlights first
- `reset()` — restores `start_grid_pos`, snaps sprite, clears highlight
- `set_highlight(val)` — enables/disables the pulsing white border drawn via `_draw()`
- `_draw()` — when highlighted, draws an unfilled white rectangle around the block with a ±1px oscillating offset (`sin(time * PI)`, one cycle/s)
- `_clear_all_highlights()` — iterates `"push_blocks"` group; guards with `has_method("set_highlight")` to safely skip Nut nodes

---

### Fan.gd (Node2D)
**Purpose:** Directional fan switch + pushable block. Turns on/off via `GameManager.doors_update` like a door. Blows wind, shows dust particles, and pushes other push blocks in its airflow.

**Groups:** `"fans"`, `"push_blocks"`

**Constants:** `PUSH_INTERVAL=0.8`, `SLIDE_DURATION=0.15`, `PARTICLE_Z_INDEX=10`, `AIRFLOW_HALF_BAND=16` (32px tile band), `PARTICLE_SPEED_MIN=40`, `PARTICLE_SPEED_MAX=65`

**Grid/push:** `grid_pos` / `start_grid_pos` at tile top-left (same pattern as PushBlock). `push(dir)` teleports node and slides sprite. `get_collision_rect()` → 32×32 world `Rect2`. Pushable from any direction.

**Airflow:** `is_position_in_airflow(world_pos)` — same row/column LOS from fan tile; passes through solids; ends at room boundary. `is_active()` reflects door id state.

**Particles:** Persistent `CPUParticles2D` child of `Sprite2D` at runtime. `local_coords=true` so particles ride the sprite during push slide. `z_as_relative=false`, `z_index=10` (above walls). `color=Color.WHITE` (inherits `Main.modulate`). Opaque, no alpha fade. Rectangle emission along airflow corridor. `_stop_particles()` sets `emitting=false` when fan off; emitter is not destroyed. Particle config skipped while `_sliding`.

**Airflow push:** `_push_blocks_in_airflow()` — tracks blocks continuously in stream via `_blocks_in_airflow`; first push allowed after `PUSH_INTERVAL` dwell; subsequent pushes gated by static `_block_last_pushed` per instance id.

**Key functions:** `reset()` — restores `grid_pos`, kills slide tween, stops particles; `get_grid_pos()`, `is_active()`, `is_position_in_airflow()`, `push(dir)`

---

### DustPile.gd (Node2D)
**Purpose:** Destructible dust pile blown away by fan airflow.

**Group:** `"dust_piles"`

**Behaviour:** When an active fan's airflow covers `get_center()`, shakes for `SHAKE_DURATION=0.5s` then `_dissolve()` spawns one-shot CPUParticles2D on Main and hides sprite. `reset()` restores unless `SaveManager.is_room_solved()` for the pile's room. Solid while visible via `Main._is_static_solid()`.

---

### WindTurbine.gd (Node2D)
**Purpose:** Wind-powered puzzle switch.

**Group:** `"wind_turbines"`

**Behaviour:** Each frame checks whether any active fan's airflow covers `get_center()`. On state change calls `GameManager.set_wind_power(id, powered)`. Draws yellow ring when powered. `reset()` clears powered state. Solid via `Main._is_static_solid()`.

---

### PassBlock.gd (Node2D)
**Purpose:** Block the player can walk through freely, but push blocks and nuts cannot be pushed onto.

- Added to group `"pass_blocks"`; uses `switch_open2.png` sprite
- `get_grid_pos()` — used by `Main.has_pass_block_at()`
- NOT included in `Main.is_blocked()` — player passes through freely

---

### BreakableWall.gd (Node2D)
**Purpose:** Solid block destroyed by the electric beam once the `"break"` ability is acquired.

- Added to group `"breakable_walls"`; in `Y_SORT_GROUPS`; `y_sort_origin=1` so it sorts in front of same-tile Keys
- Position at tile top-left; `get_grid_pos()`, `get_center()`
- Solid to player and push blocks via `Main._is_static_solid()` — skipped when `_destroyed=true` so the gap is walkable after breaking
- `_process()` checks `GameManager.has_ability("break")`; if beam is active and `ElectricBeam.is_point_on_beam(get_center(), BEAM_RADIUS)` returns true, triggers shake and frees all `"break_highlight"` nodes
- Shake: sprite offset oscillates for `SHAKE_DURATION=0.4s` with decaying `SHAKE_MAGNITUDE=2.5`
- `_explode()` — spawns 24-particle `CPUParticles2D` burst, hides sprite, sets `_destroyed=true`, calls `Main._update_beam()`; does NOT `queue_free` (reset restores it)
- `reset()` — restores sprite visibility, clears all state; called by `Main._reset_room()`

---

### ElectricBeam.gd (Node2D)
**Purpose:** Animated electricity visual. `z_index = 10`.

- Beam is **white**, fully opaque. Glow Line2D is hidden (`line_glow.visible = false`)
- Beam width pulses via `sin(time * 8)`. Endpoint glow circles drawn white in `_draw()`. `WOBBLE_SPEED = 19` (oscillates fast)
- All waypoint positions are offset by `Vector2(0, -4)` in `_resolve_waypoints()` so the beam renders 4px above each node's origin
- `activate(points)` — ordered list: prong A → nuts → prong B
- `deactivate()` — hides beam
- `is_point_on_beam(point, radius)` → `bool` — returns true if `point` is within `radius` pixels of any beam segment; used by Enemy to detect beam contact

---

### Door.gd (Node2D)
- `@export var id: String` — matches FloorPanel IDs
- `set_open(true)` — fires a DoorBall from the player to the door center via `Main.shoot_door_ball()`; door stays solid (`is_open` remains false) until ball arrives; `_opening` flag blocks duplicate calls; on arrival `_do_open()` sets `is_open=true`, emits `shake_requested(5.0)`, shrinks sprite toward center over `ANIM_DURATION=0.15s` and hides
- `set_open(false)` — sets `_opening=false` (cancels in-flight open), then grows sprite from scale 0 back to full over 0.15s; ignored when room is solved
- Added to group `"doors"`

---

### FloorPanel.gd (Node2D)
- `@export var id: String`; `@export var id2: String = ""`; `@export var positive: bool = true`
- Supports up to two IDs; both registered with `GameManager.register_floor_panel(gp, id, id2)`
- Added to group `"floor_panels"` in `_ready()`
- Sprite is hidden; drawn manually via `_draw()` so circle can render on top
- `_process`: checks if any prong is within `PANEL_ACTIVATION_RADIUS` (24px) of panel center; calls `queue_redraw()` on state change; ticks `_highlight_time` when highlighted; on transition to active while highlighted calls `_check_all_chain_activated()`
- `_draw()`: draws sprite texture; draws white circle outline (radius 17px) when active; draws pulsing white border (same as PushBlock) when highlighted
- `set_highlight(val)` — enables/disables the pulsing border
- `_check_all_chain_activated()` — if this panel has id/id2 `"chain1"`, scans all `"floor_panels"` in the group; if every chain1 panel is active, calls `set_highlight(false)` on all of them
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
- `key_collected()` — increments counter; calls `_open()` when all collected
- `_open()` — guarded by `_opening` flag; fires a DoorBall via `Main.shoot_door_ball()`; on arrival `_do_open()` sets `_opened=true`, calls `SaveManager.notify_key_door_opened()`, removes from group, emits `shake_requested(5.0)`, runs shrink-to-center tween (`ANIM_DURATION=0.15s`), then hides sprite permanently
- `reset()` — if opened, returns immediately; sets `_opening=false` to cancel in-flight open; kills any in-flight tween, restores sprite scale/position/visibility, re-adds to group

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

**Inner class `SphereOverlay` (Node2D):** Temporary node added to the main scene during intro animations. Holds `_spheres: Array` of `{pos: Vector2, done: bool}` entries; draws undone spheres as white circles in `_draw()` via `to_local()`. Freed automatically when all spheres arrive.

**Inner class `BoundingHighlight` (Node2D):** Temporary node in group `"break_highlight"`; `z_index=5`. Holds a `world_rect: Rect2` covering all breakable walls in the room. Draws a single pulsing white rect outline (padding oscillates ±1px around `BASE_PADDING=4`). Persists until the player triggers the first breakable wall, which frees all `"break_highlight"` nodes.

**Key functions:**
- `play_intro(ability, player, main)` — dispatches to the correct intro by ability name; for unknown abilities falls back to `AbilityMessage` overlay
- `_play_push_intro(player, main)` — freezes player; finds all PushBlocks (with `has_method("set_highlight")` guard to exclude Nuts) in the current room; spawns a `SphereOverlay`; tweens one sphere per block along a parabolic arc (`sin(t*PI)*ARC_HEIGHT`); on each arrival calls `block.set_highlight(true)`; unlocks player and frees overlay when the last sphere lands
- `_play_chain_intro(player, main)` — same arc animation targeting FloorPanel nodes (group `"floor_panels"`) with `id == "chain1"` in the current room; on arrival calls `panel.set_highlight(true)`; unlocks player when last sphere lands
- `_play_break_intro(player, main)` — same arc animation targeting all BreakableWall nodes in the current room; when the last sphere lands, computes the bounding rect of all walls (min/max positions + 32px tile size), spawns a `BoundingHighlight`, then unlocks player

---

### Utils.gd (autoload singleton, Node)
**Purpose:** Shared helpers used across the project. Provides boss health bar HUD and per-enemy sprite health bars.

**Constants:** `BAR_MARGIN=10`, `BAR_H=16`, `BAR_OUTLINE=2`, `BAR_LAYER=25`, `SPRITE_BAR_H=6`, `SPRITE_BAR_OUTLINE=1`, `SPRITE_BAR_Z=-1`

**Key variables:**
- `_bars: Dictionary` — keyed by boss `get_instance_id()`; each entry holds `{canvas, outer, fill, bar_w, particles, shaking}`
- `_sprite_bars: Dictionary` — keyed by enemy `get_instance_id()`; each entry holds `{root, outer, fill, bar_w}`

**Boss health bar:** `CanvasLayer` (layer 25) with four stacked `ColorRect`s (colored outer frame, black inner frame, black background, colored fill) plus a `CPUParticles2D` at the fill tip. Bar width = viewport width minus `2 × BAR_MARGIN`. Tint color is passed in per update (bosses use `Main.modulate`). Canvas is parented to `Main`, not the boss node, so it survives Y-sort reparenting under `Walls`.

**Sprite health bar:** `Control` child on enemy (inserted at index 0, `z_index=-1` so sprite draws in front). Positioned `offset_y=-10` (above sprite). 32px wide, 6px tall, 1px outline — same white/black frame structure as boss bar. White outer/fill inherit room tint via `Main.modulate` on the scene tree (no explicit bar modulate).

**Key functions:**
- `create_boss_health_bar(boss, main)` — registers a bar for `boss`; call deferred from boss `_ready()` after reparent
- `update_boss_health_bar(boss, hp, max_hp, visible, tint)` — sets visibility, fill ratio, tints particles, and repositions particles to the fill tip
- `shake_boss_health_bar(boss)` — debounced shake: tweens canvas offset ±2px horizontal + random ±2px vertical over ~0.14s, then bursts the tip particles; no-ops if already shaking
- `remove_boss_health_bar(boss)` — frees canvas; call from boss `NOTIFICATION_PREDELETE`
- `create_sprite_health_bar(enemy, bar_width, offset_y)` — attaches bar Control to enemy
- `update_sprite_health_bar(enemy, hp, max_hp, visible)` — updates fill width and visibility
- `remove_sprite_health_bar(enemy)` — frees bar; call from enemy `NOTIFICATION_PREDELETE`

**Boss integration pattern:** `_ready()` → `call_deferred("_register_health_bar")` → `Utils.create_boss_health_bar(self, _main)`; `_process()` → `Utils.update_boss_health_bar(...)`; `_notification(PREDELETE)` → `Utils.remove_boss_health_bar(self)`.

**Water enemy integration:** `WaterEnemy._register_health_bar()` → `Utils.create_sprite_health_bar()`; `_update_health_bar()` each frame; `NOTIFICATION_PREDELETE` → `Utils.remove_sprite_health_bar()`.

---

### TimedObject.gd (Node2D)
- Positioned at tile top-left; requires a `Sprite2D` child named `"Sprite2D"`
- Tracks how long the player has been in the same room; uses `_was_in_room` edge detection to reset on each entry
- After `APPEAR_TIME = 120.0s` (if `GameManager.has_ability("chain")` is false): shows sprite, starts blinking every `BLINK_INTERVAL = 0.5s`, sets `_main.player.speed_multiplier = 0.8`
- On room exit or re-entry: calls `_hide()` — hides sprite, resets blink state and timer, restores `speed_multiplier = 1.0`
- If chain ability is already granted when the timer would fire, the object stays hidden permanently

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
- **Teleport mode** — player is on an open TeleportPanel and at least one non-one-way destination exists (`Main.can_teleport_from_panel()`). Cursor navigates between destination rooms; WASD/Arrow keys snap cursor to nearest destination; Space teleports (pressing Space on the player's current room does nothing).
- **Map-only mode** — TAB pressed elsewhere (or no destinations). No cursor, no navigation. Instructions: "TAB: Close"

**Title:** "The Map" is always drawn at the top of the overlay in both modes (replaces the per-panel name that was shown only in teleport mode).

**Key variables:** `_teleport_mode: bool`, `_open_panel_rooms: Array` (destinations only), `_visited: Dictionary`, `_cursor: Vector2i`, `_slide_tween: Tween`, `_pulse_timer: float`, `_pulse_large: bool`, `_space_hint_done: bool`, `_wasd_hint_done: bool`, `_first_two_done: bool`, `_input_delay: float`, `_first_teleport_room: Vector2i`, `_first_teleport_room_set: bool`

**Save/load helpers:** `get_visited()` → duplicate of `_visited`; `set_visited(d)` — replaces `_visited` and redraws if open; both used by SaveManager.

**Hint pulsing:** "Space: Teleport" pulses font size 11↔12 every 0.5s until the player teleports. "WASD/Arrow Keys: Move" pulses the same way until the player teleports to any room that is not `_first_teleport_room`. Both start at large size (`_pulse_large = true`) when the map opens. Pulsing is driven in `_process`; hints are drawn as inline segments so each can have an independent font size.

**First-open delay:** The first time the map opens with ≥2 teleport destinations, all input is blocked for 1 second (`_input_delay = 1.0`). A faint `...` is shown below the instructions during the delay.

**Visual style:** Background is a solid-black box with a tint-colored 2px border. Minimum size is half the viewport (400×192). Box expands to fit the widest of: room grid, instruction text, or panel name text, and expands symmetrically in height if needed. All rooms, connections, stubs, and text drawn in `Main.modulate` tint. Rooms with an open destination panel show a black dot at center. Cursor room has a 1px tint outline. Panel name drawn above rooms; instruction segments drawn inline below, centered as a group. All text uses tint color.

**Connections:** `_has_exit(room, dir)` — checks for at least one non-wall tile on the border. Connections drawn between visited rooms that have an exit between them.

---

---

### SaveManager.gd (autoload singleton)
**Purpose:** Persistent save/load system. Autosaves the active slot every 5 seconds. Reloads the scene when loading to guarantee a clean world state.

**Key constants:** `AUTOSAVE_INTERVAL = 5.0`, `SAVE_DIR = "user://"`

**Key variables:**
- `active_slot: int` — currently active save slot (1–9); default `1`; `-1` = none (e.g. after deleting the active slot)
- `_save_system_enabled: bool` — mirrors `Player.save_system_enabled`; set by `on_player_ready()`; gates number-key input handling
- `skip_splash: bool` — set `true` before scene reload so `Main._ready()` skips the splash screen
- `_pending_data: Dictionary` — save data waiting to be applied after the reloaded scene is ready
- `_key_doors_opened / _boss_doors_opened / _boss_defeated` — accumulated state for permanently-freed nodes that can't be queried after death

**Input (only active when `_save_system_enabled` is true):**
- **1–9**: select slot and load immediately if file exists, otherwise just activates the slot
- **Shift+1–9**: delete that slot's save file; deactivates slot if it was active
- **Alt+1–9**: select slot without loading (even if a save file exists)

**Save data (JSON at `user://save_slot_N.json`):** player world position, current room, abilities dict, push block/nut grid positions (keyed by `start_grid_pos`), collected keys (by `start_grid_pos`), opened KeyDoors, open TeleportPanels, removed BossDoors, boss defeated flag, enemy positions + dead flags, map visited rooms.

**Load flow:** `load_slot()` → `GameManager.clear_scene_state()` + `reload_current_scene()` → `_process()` detects new scene is ready → `call_deferred("_apply_load", data)` → restores all state silently (no animations/shakes) → calls `Main._update_beam()`.

**Auto-slot mode** (`Player.save_system_enabled = false`): `on_player_ready(false)` activates slot 1 for autosaving but does not load any save file — game starts from the scene's default state. Number-key input is disabled. Manual mode (`Player.save_system_enabled = true`): slot 1 is pre-selected by default; user can switch/load/delete slots with number keys.

**Notification hooks** (called by game objects before self-destruction):
- `notify_key_door_opened(gp)` — called from `KeyDoor._open()`
- `notify_boss_door_opened(gp)` — called from `BossDoor.open()`
- `notify_boss_defeated()` — called from `WaterBoss._boss_die()`

**Status HUD:** fading top-left Label (layer 50) shown on slot select, load, and delete events.

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

### Enemy.gd (Node2D)
**Purpose:** Enemy that slowly walks toward the player in a straight line, blocked by walls and solids, killed instantly by the electric beam, and resets the room on player contact.

**Constants:** `SPEED=40.0 px/s`, `SPRITE_SPEED=20.0`, `CONTACT_DIST=14.0`, `BEAM_RADIUS=14.0`, `TILE_SIZE=32`, `CONTACT_EPS=0.1`

**Hitbox:** 20×20, offset `(6, 6)` from position (slightly inset from the 32×32 sprite). Used for AABB wall collision via `Main.get_player_blocking_rects()`.

**Sprite lag:** `_visual_pos` lerps toward `position` each frame; `_sprite.position = _visual_pos - position` applies the lag offset. When pushed by a block, `position` teleports instantly while `_visual_pos` slides to catch up.

**Key functions:**
- `get_center()` → `position + Vector2(16, 16)`
- `_move_x(dx)` / `_move_y(dy)` — axis-separated AABB movement against `Main.get_player_blocking_rects()`
- `push(dir)` — displaces `position` by `dir * TILE_SIZE`; sprite lag produces the slide visual
- `_handle_beam()` — instant `_die()` when beam active and center on beam; override in subclasses for HP-based damage
- `_die()` — hides sprite, fires particle burst (`one_shot=true`, `explosiveness=1.0` set in `_ready()`); enemy stays dead until `reset()` is called
- `reset()` — restores position, visual pos, sprite visibility; called by `Main._reset_room()` and `Main._transition_to_room()`
- `_eject_from_solid()` — BFS from current tile outward; teleports `position` (and snaps `_visual_pos`) to the nearest tile where the hitbox doesn't intersect any solid; no-ops if already clear

**Reset triggers:** room restart (R / player contact), room entry (transition to the enemy's room).

**Group:** `"enemies"`; in `Y_SORT_GROUPS` so reparented under `Walls` at startup.

---

### WaterEnemy.gd (Node2D)
**Purpose:** Water-themed enemy extending `Enemy.gd` with room/map freeze, HP + sprite health bar, and gradual beam damage.

**Constants:** `MAX_HP=25`, `HEALTH_BAR_OFFSET_Y=-10.0`

**Key variables:** `hp`, `boss_spawned`

**Key functions:**
- `get_max_hp()` → `25` (override in subclasses for different max HP)
- `_register_health_bar()` — deferred; skips `water_boss` group; calls `Utils.create_sprite_health_bar()`
- `_update_health_bar()` — each frame; hidden when dead, off-room, or map open
- `_handle_beam()` — −1 HP/frame in beam, `_trigger_shake(2.0)`, `_die()` at 0 HP
- `_in_current_room()` / `_get_home_room()` — room-scoped activation
- `_process()` — updates health bar, ejects from solids, skips movement when map open, else `super._process()`
- `reset()` — restores `hp = get_max_hp()`

**Groups:** `"water_enemies"`, optionally `"boss_spawned_enemies"`

---

### BounceEnemy.gd (Node2D)
**Purpose:** Water enemy that pathfinds toward the player and moves in tile-to-tile bounces instead of continuous walking.

**Constants:** `BOUNCE_MAX_HP=100`, `MOVE_SPEED=0.286`, `SORT_ABOVE_WALLS_Z=64`, `SPRITE_LAG_SPEED=24.0`, `WAIT_MIN=0.5`, `WAIT_MAX=0.8`, hop/jump durations and heights, `PATH_RECALC=0.35`

**States:** `IDLE`, `HOP`, `JUMP_WINDUP`, `JUMP`

**Movement:** BFS pathfinding with 4-directional walks and jumps over 1-tile `_is_static_solid` walls; `position` follows flat tile lerp, bounce arc applied as sprite Y offset; no wall AABB collision or `_eject_from_solid()`

**Juice:** stretch on hop/jump peaks (`HOP_STRETCH`, `JUMP_STRETCH`); landing wait with `sin`-curve squash; `_apply_scale_target()` lerps scale continuously between phases; player-style sprite lag

**Combat:** overrides `_check_beam_and_contact()` — uses inherited `_handle_beam()`; player contact blocked during `JUMP` state (wall-jump arc)

**Group:** `"bounce_enemies"` (also `"enemies"`, `"water_enemies"`)

---

## Scenes (Node Structures)

```
Main.tscn (runtime Y-sort):
  Main [Main.gd, y_sort_enabled=false]
  ├── Walls [TileMapLayer, y_sort_enabled=true, y_sort_origin=0 per tile]
  │     ├── Player, Prong(s), Door(s), LightningBlocker(s), KeyDoor(s),
  │     │   PushBlock(s), Nut(s), PassBlock(s), Key(s), Enemy(s)  ← reparented at _ready
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

Enemy.tscn:
  Node2D [Enemy.gd]  ← position at tile top-left; moves continuously
  ├── Sprite2D [Front_Idle1.png, centered=false]
  └── Particles [CPUParticles2D — one_shot, explosiveness=1.0, white arc burst on death]

WaterEnemy.tscn / BounceEnemy.tscn:
  Node2D [WaterEnemy.gd / BounceEnemy.gd]  ← same structure as Enemy.tscn
  ├── HealthBar [Control, z_index=-1, offset_y=-10]  ← added at runtime by Utils; 32×6 boss-style bar
  ├── Sprite2D [Front_Idle1.png, centered=false]
  └── Particles [CPUParticles2D — one_shot, water_death burst]

BounceBoss.tscn:
  Node2D [BounceBoss.gd, z_index=64]  ← position at tile top-left; 2× scale = 64×64
  ├── Sprite2D [Front_Idle1.png, centered=false]
  └── Particles [CPUParticles2D — one_shot, death burst]

BounceBossPanel.tscn:
  Node2D [BounceBossPanel.gd]  ← spawned dynamically; position set by BounceBoss
  └── Sprite2D [centered=false, hidden — drawn via _draw()]

BreakableWall.tscn:
  Node2D [BreakableWall.gd, y_sort_origin=1]  ← position at tile top-left
  └── Sprite2D [wall_breakable.png, centered=false]

BossDoor.tscn:
  Node2D [BossDoor.gd]
  └── Sprite2D [locked_door1.png, centered=false]

TimedObject.tscn:
  Node2D [TimedObject.gd]
  └── Sprite2D [arrow_up.png, centered=false]

RoomSolvedTile.tscn:
  Node2D [RoomSolvedTile.gd, z_index=-10]  ← position at tile top-left; no visible sprite
  └── Sprite2D [visible=false — no visual]
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
| BreakableWall | wall_breakable.png | tile top-left |
| AbilityPickup | (drawn via _draw) | tile top-left |
| AbilityGate | TAB.png | tile top-left |
| Enemy | Front_Idle1.png | tile top-left (moves continuously) |
| WaterEnemy / BounceEnemy / WaterBoss | Front_Idle1.png | tile top-left (moves continuously) |
| BounceBoss | Front_Idle1.png (2× scale) | tile top-left (moves via hops) |
| BounceBossPanel | positive.png / negative.png (drawn via _draw) | set dynamically by BounceBoss |
| BossDoor | locked_door1.png | tile top-left |
| TimedObject | arrow_up.png | tile top-left |

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
  → peaked: delete room prongs, reset push blocks, reset key doors/keys, reset enemies, teleport player
  → static fades out (0.22s) → done signal → unlock player

Room transition (player walks to edge):
  → clear prongs instantly → reset enemies in new room → camera tweens 0.25s → player locked during tween

Enemy touches player:
  → _reset_room() triggered (same as pressing R)

Enemy enters beam:
  → base Enemy: instant death (_handle_beam → _die())
  → WaterEnemy / BounceEnemy: −1 HP/frame, 2px screen shake; _die() at 0 HP
  → dead enemy hides sprite, plays one-shot particle burst + water_death SFX; stays dead until room reset or re-entry
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
| Sprite lag on enemy move | Enemy.gd `_visual_pos` lerp on `Sprite2D` |
| Push block sprite slide | PushBlock.gd `push()` |
| Fan sprite slide + dust particles ride sprite | Fan.gd `push()`, `local_coords` particles on `Sprite2D` |
| Fan airflow dust particles (32px band, above walls) | Fan.gd `_update_particles()` |
| Fan airflow pushes blocks (0.8s dwell + interval) | Fan.gd `_push_blocks_in_airflow()` |
| Player wind displacement (+60px/s in fan LOS) | Player.gd `_process()` |
| Wind blocks player push (fans exempt) | Player.gd `_try_push()`, `_is_in_fan_airflow()` |
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
| Beam multi-hop through Nuts (nearest-first) | Main.gd `_compute_beam_path()` / `_nearest_first_beam()` |
| Key collect animation (shrink to center + fly to player) | Key.gd `_collect()` |
| KeyDoor shrink-to-center on open (same as Door) | KeyDoor.gd `_open()` |
| CRT static on room reset (fade-in → hold 0.2s → fade-out) | ResetEffect.gd |
| Splash screen on launch | SplashScreen.gd |
| Map overlay slides in/out from top (0.15s SINE) | MapOverlay.gd `_open_map()` / `_close_map()` |
| Floor panel pulsing border highlight (chain tutorial) | FloorPanel.gd `set_highlight()` |
| Ability intro sphere arcs (push → blocks, chain → panels, break → breakable walls) | AbilityTutorial.gd |
| Break ability: bounding highlight rect around all breakable walls until first break | AbilityTutorial.gd `BoundingHighlight`, BreakableWall.gd |
| Breakable wall shake + particle burst on beam contact | BreakableWall.gd `_explode()` |
| Boss health bar HUD (top of screen, room-tinted) | Utils.gd `create/update_boss_health_bar()`; WaterBoss.gd |
| Boss health bar shake + particle burst on damage | Utils.gd `shake_boss_health_bar()`; WaterBoss.gd beam damage block |
| Enemy sprite health bar (32px wide, 6px tall, above sprite, behind sprite draw) | Utils.gd `create/update/remove_sprite_health_bar()`; WaterEnemy.gd |
| Water/bounce enemy beam damage screen shake (2px) | WaterEnemy.gd `_handle_beam()` |
| Bounce enemy pathfinding + tile hops + wall jumps | BounceEnemy.gd |
| Bounce enemy stretch/squash + landing wait | BounceEnemy.gd `_process_hop()`, idle wait |
| Bounce enemy sprite lag (matches player) | BounceEnemy.gd `SPRITE_LAG_SPEED=24` |
| Enemy particle burst on beam death | Enemy.gd `_die()`, CPUParticles2D one-shot burst |
| Water enemies freeze while map overlay is open | WaterEnemy.gd `_process` |
| Water enemies eject from solids | Enemy.gd `_eject_from_solid()`; WaterEnemy.gd `_process` (BounceEnemy overrides to no-op) |
| TimedObject: slow + blink after 2min in room | TimedObject.gd; Player.gd `speed_multiplier` |
| TAB label black outline above player | Main.gd `_ready()` outline_size=2 |
| Door-open ball animation (flies from player to door before it opens) | DoorBall.gd; Main.gd `shoot_door_ball()`; Door.gd `_do_open()`; KeyDoor.gd `_do_open()` |
| Push hold delay (0.15s press before block moves) | Player.gd `_try_push()` charge accumulator |
| ♪/SFX mute buttons (top-right, tint-colored, hover-inverts) | Main.gd `_setup_mute_buttons()`; AudioManager.gd `toggle_music_mute()`/`toggle_sfx_mute()` |
| Bounce boss hop squash/stretch + big bounce windup pulse | BounceBoss.gd `_process_hop()`, `_process_big_bounce_windup()` |
| Bounce boss wobble telegraph before minion spawn | BounceBoss.gd `_process_wobble()` |
| Bounce boss falling object (stake drops from top of screen onto boss) | BounceBoss.gd `_drop_object()` |
| Bounce boss panels relocate on object launch (not on hit) | BounceBoss.gd `_drop_object()` calls `_place_panels_randomly()` immediately |
| Bounce boss panel beam activation indicator (white arc outline) | BounceBossPanel.gd `_draw()` |
