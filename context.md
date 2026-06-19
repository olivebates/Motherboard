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

**`Y_SORT_GROUPS`:** `players`, `prongs`, `doors`, `lightning_blockers`, `key_doors`, `push_blocks`, `pass_blocks`, `keys`, `teleport_panels`, `screws`, `enemies`, `breakable_walls`, `fans`, `dust_piles`, `wind_turbines`, `enemy_doors`, `nanodroids`, `capacitors`

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

**Enemies (`Enemy.gd._ground_offset()`):** node origin is authored at tile top-left (grid/save/editor placement) but shifted **down by `_ground_offset()`** in `_ready()` so the Y-sort key sits on the enemy's ground line (≈ sprite bottom) instead of the tile top — this makes the player draw in front of / behind enemies based on the **bottom of the sprites**, matching the player. Static children (sprite, particles, hitbox area) are compensated back up by the same offset so visuals don't move, and `get_center()` / `_hitbox()` / `_eject_from_solid()` / grid conversions all treat `position` as origin-conv via `_ground_offset()`. `WaterEnemy.GROUND_OFFSET = 24` (inherited by water/spider/bounce); **bosses override `_ground_offset()` to `0`** (they keep tile-top origin and sort by their own rules). Tune `WaterEnemy.GROUND_OFFSET` to shift the crossover (higher = enemies go behind the player sooner; `32` = literal tile/sprite bottom).

**Other solids (doors, blockers, key doors, push blocks, etc.):** node at tile top-left; sort Y = tile top (same as walls).

**Not Y-sorted with walls:** `ElectricBeam` (`z_index = 10`), `FloorPanel` (`z_index = -10`), `FloorSwitch`/`Hole` (`z_index = -10`, floor level), UI sprites, camera, overlays.

---

## File Structure

```
project.godot              — Godot project config, input map, autoload, window size (800×384)

scenes/
  Main.tscn                — Root scene
  LevelEditor.tscn         — Standalone level editor scene (opened via K+C in Main)
  (NOTE: the old duplicate object scenes that used to live directly under scenes/ — Player, Door, Key, Nut, PushBlock, FloorPanel, etc. — were deleted; the canonical copies live under scenes/objects, scenes/enemies, and scenes/player. Main.tscn references those.)

  player/
    Player.tscn            — Player character
    Prong.tscn             — Placeable prong object (stake sprite)
    ElectricBeam.tscn      — Electricity effect (two Line2D children; glow hidden)

  objects/
    Door.tscn              — Puzzle door (floor-panel activated); uses AnimatedSprite2D with door.webp (5 frames × 32×32px, built at runtime); sprite always visible; frame 0 = closed state, frame 4 = open state; "open" animation plays forward (0→4) and freezes on frame 4; "close" animation plays in reverse (4→0) and freezes on frame 0; _anim_version guards against stale callbacks when animations are interrupted; @export id + @export id2 (optional second id) — the door opens when EITHER id is active (OR logic, like a floor panel's two ids)
    FloorPanel.tscn        — Floor trigger (positive.png or negative.png sprite)
    LightningBlocker.tscn  — Blocks the electric beam; resistor_small.png sprite
    PushBlock.tscn         — Pushable block (SD_Card_block.png)
    Nut.tscn               — Pushable conductor; beam routes through it when chain ability active
    Screw.tscn             — Static conductor; like Nut but cannot be pushed
    KeyDoor.tscn           — Solid door that opens when all Keys in the room are collected; uses AnimatedSprite2D with KeyDoor.webp (10 frames × 32×42px, built at runtime); frozen on frame 0 until all keys collected, then plays the "open" animation before disappearing; sprite offset y=−10
    Key.tscn               — Collectible that unlocks the KeyDoor in the same room
    PassBlock.tscn         — Passable block; player walks through, push blocks cannot enter
    BreakableWall.tscn     — Solid block destroyed by the electric beam (requires "break" ability); wall_breakable.png sprite; shakes 0.4s then particle burst; resets on room reset
    BossDoor.tscn          — Solid door that seals a boss room; opens (permanently disappears) once its room has no living boss; uses locked_door1.png; in "boss_doors" group only (NOT push_blocks — has no push() method); solid to player while visible (included in _is_static_solid)
    PowerOrb.tscn          — Ability unlock pickup (white circle + rotating spike lines); @export ability: String; in "power_orbs" group; z_index default; no sprite child
    OrbDisplay.tscn        — Floor decoration tracking collected PowerOrbs; drawn via _draw(); z_index=-10; in "orb_displays" group; not in Y_SORT_GROUPS
    AbilityGate.tscn       — Object hidden until a required ability is unlocked; TAB.png sprite
    TeleportPanel.tscn     — Interactive teleport panel; closed=solid, open=passable; exports: panel_name, one_way
    ExitPoint.tscn         — EDITOR-ONLY object (only in LevelEditor SCENE_MAP, never in Main.tscn); same sprites/open-on-push behaviour as TeleportPanel (teleport_closed.png / teleport_open.png, closed=solid, open=passable) but in group "exit_points"; while standing on an OPEN ExitPoint, pressing Space ends the editor playtest and returns to BUILD/palette (LevelEditor._input KEY_SPACE → _player_on_exit_point() → _exit_play_mode())
    OnewayPanel.tscn       — TeleportPanel with one_way=true pre-set; player can teleport from it but not to it
    TeleportAnchor.tscn    — Room teleport anchor marker (legacy fallback)
    RoomSolvedTile.tscn    — Invisible floor tile; if multiple tiles exist in a room the player must step on each one; only after all are stepped on does the snap SFX + 2px shake fire and the room get marked solved; solved rooms: doors permanently open, broken breakable walls stay broken; state saved per-room in SaveManager
    TimedObject.tscn       — Object that appears after 2 minutes in its room (chain upgrade not yet acquired); blinks every 0.5s while visible; slows player speed to 80% while visible; hides, restores speed, and resets timer on each room entry; always hidden once chain is acquired; uses arrow_up.png sprite
    FanDown.tscn / FanUp.tscn / FanLeft.tscn / FanRight.tscn — Fan objects (Fan_Front/Back/Left/Right.png); @export id: String turns fan on/off via GameManager doors_update (same as Door); @export direction: Vector2i pre-set per scene; in `"fans"`, `"push_blocks"`, and `"nuts"` groups — solid to player via push-block collision; NOT pushable (get_push_block_at_face skips the "fans" group, so the player cannot push a fan; they stay in "push_blocks" only for collision/solidity); beam chains through fans when chain ability is active (same as Nut/Screw); when on: player in LOS of airflow receives +60px/s wind push; LOS = same row/column as fan, airflow passes through all solids and ends at room boundary; opaque white dust particles (CPUParticles2D child of Sprite2D, local_coords, z_index=10 above walls) flow along the 32px airflow band; particle color inherits Main.modulate; when fan turns off, _clear_particles() destroys and recreates the emitter so particles vanish instantly; wind_pushable objects in airflow are pushed every 0.4s (PUSH_INTERVAL) after continuously occupying the stream for 0.4s if the destination tile is free (PushBlocks and Nuts are NOT pushed by fans — use WindBlock for fan-pushable objects); reset() on room reset; particles are destroyed and recreated (_clear_particles()) on room transition so they don't persist into the next room
    DustPile.tscn          — Destructible dust pile (Dust_Pile_Alternate.png); solid to player when visible (_destroyed=false); shakes 0.8s (SHAKE_DURATION) when a fan blows on it, then disappears with dust particles flowing in the fan direction; reset() restores it unless SaveManager.is_room_solved() for its room
    NanoDroid.tscn         — Actor that moves like the player but with REVERSED directions (Nanobot_Back_Idle.png, 32×32); group "nanodroids" (in Y_SORT_GROUPS); positioned at tile top-left, continuous WASD-driven movement using the player's axis-separated AABB sweep (`Main.get_player_blocking_rects`); 10×10 hitbox centered on the tile; presses FloorSwitches (FloorSwitch checks the "nanodroids" group via get_center()); drifts in fan airflow via the same continuous +60px/s wind push the player gets (NOT the grid-based wind_pushable group); when it crosses the active electric beam it explodes (expanding circular shockwave ring sized to the blast radius + a filled white flash + debris particles) — destroys every BreakableWall whose center is within 64px (sets their `_triggered`) and resets the room if the player's body center is within 48px; not solid to the player (not in _is_static_solid) but TOUCHING the player restarts the room (its hitbox vs the player's body center); only active while the player is in its home room (derived from start tile) — frozen otherwise, and re-armed/reset to its start position each time the player enters the room; confined to its room by a 16px inset border (clamped each frame, so it can't slip through doorways into adjacent rooms); stays exploded (sprite hidden, `_destroyed`) until reset(); reset() restores it at start_grid_pos; inert in the level editor until a playtest (bails while `electric_beam` is null)
    Hole.tscn              — Pit in the floor (hole1.png); floor-level (z_index=-10, z_as_relative=false), NOT in Y_SORT_GROUPS; group "holes". EMPTY = solid wall. Push a pushable object onto it (can_push_block_to allows it) and after 0.4s the object sinks in and the tile becomes passable to player/enemies/push blocks; a Nut swaps the hole to hole_nut.png, a regular PushBlock to hole_filled.png, anything else is drawn on top of hole1.png via the Overlay child. A NanoDroid that walks in falls down it (the droid is destroyed/hidden, its sprite drawn in the Overlay) but the hole stays SOLID — a pushable object can still be pushed in afterward, clearing the droid sprite. Absorbed pushables are pulled from "push_blocks"/"nuts" groups (not freed) and restored by reset(); droids are restored by the normal nanodroids reset. See Hole.gd
    WindBlock.tscn         — Fan-pushable block (Dust_Pile.png); in "push_blocks" and "wind_pushable" groups (Dust_Pile.png); in "push_blocks" (player can push, collision checks, save/load) and "wind_pushable" (fan airflow pushes it); same sprite-lag slide mechanics as PushBlock; pushes enemies on contact; reset() restores start position; fans only push objects in "wind_pushable" — PushBlocks and Nuts are no longer pushed by fans
    WindTurbine.tscn       — Wind-powered turbine (placeholder.png); @export id: String; when any active fan blows on it, sets GameManager.last_activator_pos to its center then calls GameManager.set_wind_power(id, true) to open doors with matching id; glows yellow ring when powered; resets on room reset
    FloorSwitch.tscn       — Pressure-sensitive floor switch; @export id: String; opens doors with matching id while the player, any push block, or a NanoDroid occupies the switch tile; z_index=-10 (floor level, not Y-sorted); Sprite2D uses Switch-Sheet.webp (hframes=2: frame 0 = unpressed, frame 1 = pressed down); reset() on room reset; group "floor_switches"; sets GameManager.last_activator_pos to its tile center then calls GameManager.set_floor_switch(id, active) which merges into evaluate_puzzle() alongside wind_powered_ids
    Capacitor.tscn         — Beam-charged powered object; @export id: String; uses Capaciter-Sheet.webp (256×48 = 8 frames of 32×48, hframes=8); Sprite2D positioned at (0,−16) so its bottom 32px fill the tile and the top 16px bleed into the tile above; hitbox/grid tile is the bottom 32×32; static-solid (group "capacitors", in Main/LevelEditor _is_static_solid and Y_SORT_GROUPS) but does NOT block the beam (only lightning_blockers do — the beam passes over its tile); frozen on frame 0 (idle) until the electric beam passes through its bottom 32×32 hitbox tile (via electric_beam.is_rect_on_beam(tile_rect) — a segment-vs-rect test, so any crossing of the tile counts), then charges forward toward the last frame and holds (CHARGE_TIME=0.7s); when the beam leaves it slowly discharges back to frame 0 (DISCHARGE_TIME=8.0s) — stops/reverses from wherever it was if the beam comes and goes; while it is off frame 0 it powers every object with the same id via GameManager.set_capacitor(id) (merged into evaluate_puzzle alongside floor switches/wind/panels); reset() on room reset; inert in the level editor BUILD (electric_beam is null)
    EnemyDoor.tscn         — Door that opens when all enemies with a matching enemy_id are dead; @export id: String matches enemy enemy_id; polls each frame — opens once ≥1 matching enemy exists and all are dead; same DoorBall + shrink-to-center animation as Door.gd; solid while closed (_is_static_solid); reset() closes it; group "enemy_doors" (in Y_SORT_GROUPS)

  enemies/
    Enemy.tscn             — Enemy that walks toward the player; Front_Idle1.png sprite; CPUParticles2D death burst
    WaterEnemy.tscn        — WaterEnemy variant; uses WaterEnemy.gd; 25 HP + sprite-width health bar; beam −1 HP/frame (2px shake); freezes when not in current room or when map overlay is open; ejects from solids each frame; supports boss_spawned flag
    BounceEnemy.tscn       — BounceEnemy variant; extends WaterEnemy.gd; 50 HP; takes damage only from active fan airflow (−1 HP/frame, immune to electric beam); tile A* pathfinding (Manhattan heuristic) with 1-tile wall/push-block jumps, constrained to home room; bounces instead of sliding; idle rhythmic squish/squash animation; no wall collision; 64×64 sprite anchored bottom-center at the tile bottom-center; 32×32 hitbox via draggable HitboxArea/HitboxShape child nodes (get_center() reads the shape's world offset); Y-sorts by its ground line like other enemies (no forced z_index)
    SpiderEnemy.tscn       — SpiderEnemy variant; extends WaterEnemy.gd; 10 HP; stands still, rotates toward player within 3 tiles (96px), lunges within 2 tiles (64px); 8s stun when HP reaches 0 (sprite→switch_open2.png, no contact kill); hitbox editable via HitboxArea/HitboxShape child nodes; Y-sorts by its ground line (no forced z_index)
    WaterBoss.tscn         — Boss enemy; uses WaterBoss.gd; 1000 HP at 2× scale; place at tile top-left in any room
    BounceBoss.tscn        — Boss enemy; uses BounceBoss.gd; 1800 HP at 2× scale (64×64); place at tile top-left in any room
    BounceBossPanel.tscn   — Interactive panel spawned dynamically by BounceBoss; positive/negative variants; registers as a "bounceboss" floor panel and activates when a prong is planted in it

  ui/
    TabButton.tscn         — Mute toggle button (used by Main for ♪/SFX buttons)

scripts/
  LevelEditor.gd           — Level editor controller. **See the full "## Level Editor" section below for the authoritative reference** (modes, palette, placement rules, object/wall drag, undo, eyedropper, ExitPoint, play mode). Quick notes: plays "LevelEditor" music on _ready(); ♪ mute button top-right of EditorUI reflects/toggles AudioManager music mute; provides Main-compatibility stubs (record_push() no-op, player getter, _is_static_solid, etc.) so placed object scripts and the playtest Player run without a real Main
  GameManager.gd           — Autoload singleton (puzzle state + ability tracking)
  AudioManager.gd          — Autoload singleton; manages all SFX and background music; `process_mode = PROCESS_MODE_ALWAYS` set on itself and every AudioStreamPlayer so music continues while the tree is paused (e.g. Settings menu); creates two audio buses programmatically in `_setup_buses()`: `GameMusic` and `GameSFX` (both send to Master); all SFX players use bus `"GameSFX"`, all music players use bus `"GameMusic"`; SFX keys: character_death (-12dB), electric_fail, electric_noise (loops while beam active, -29.1dB), electric_spawn, plant_stake (-8dB), water_death, snap (-14dB, plays on room solved tile trigger); `play_sfx(key, volume_db := INF)` — passing a volume_db overrides that player's volume for this play (the shared player keeps the new value, so callers that want the base volume must pass it explicitly); INF (default) leaves the player's configured base volume untouched; e.g. the teleport-pad teleport plays electric_spawn at -3.1dB (~30% quieter) while the prong teleport passes 0.0dB; music keys: "Orange"=Motherboard_Level_Loop.ogg, "Yellow"=PlaceholderMusic/Yellow.mp3, "Blue"=PlaceholderMusic/Blue.mp3, "Red"=PlaceholderMusic/Red.mp3, "LevelEditor"=PlaceholderMusic/LevelEditor.mp3, "Boss"=PlaceholderMusic/Boss.mp3; supports both OGG and MP3 streams (sets loop on whichever type is loaded); all music streams start at -80dB and play immediately; set_music(key) crossfades over 1s — kills all in-progress tweens first (_music_tweens dict tracks one tween per key), silences any track that is neither outgoing nor incoming, fades old to -80dB and new from -30dB to target volume (_MUSIC_VOLUME dict default 0dB; Boss=−6dB, Red=−7dB); first set_music call fades in over 3s (MUSIC_START_FADE); start_beam_noise()/stop_beam_noise() control the looping beam SFX; fade_out_music(duration) tweens current track to -80dB without changing _current_music; fade_in_music(duration) tweens current track back to its target volume — both kill any in-progress tween on that track first and no-op when muted; user volume vars: `_music_user_volume=0.35` (35%), `_sfx_user_volume=0.5` (50%) — applied to bus dB via `linear_to_db()`; public API: `get_music_volume()/set_music_volume(v)`, `get_sfx_volume()/set_sfx_volume(v)` (save prefs on set); `_apply_music_volume(v)`/`_apply_sfx_volume(v)` set bus dB without saving; toggle_music_mute()/toggle_sfx_mute() return new bool state and save pref; is_music_muted()/is_sfx_muted() getters; prefs saved to user://audio_prefs.json (`_PREFS_VERSION=2`); `_load_prefs()` applies defaults first then only restores saved volumes if version ≥ 2 (version 1 prefs ignore volume fields, ensuring new defaults apply); `_save_prefs()` writes version, music_muted, sfx_muted, music_volume, sfx_volume; set_music() and start_beam_noise() are no-ops when muted
  Main.gd                  — Root scene controller; on _ready(): derives current_room from the player's actual scene position (not hardcoded to (0,0)) and sets camera + room_entry_positions accordingly; on room reset (`_reset_room()`): plays character_death SFX, then `player.play_death()` (death animation in place); awaits `player.death_static_cue` (fires after the death animation's 3rd frame) then `reset_effect.play()` (static fades in); at `reset_effect.peaked` resets all room objects and respawns the player via `player.reset_to()` (which cuts the death animation short); then `await player.play_revive()` (death animation reversed at the new location) before unlocking control — the static fades out (`done`) during the revive; on prong spawn: plays plant_stake SFX; on room transition: tweens Main.modulate to anchor.color over CAMERA_TWEEN_DURATION and updates reset_effect.color immediately (_color_tween); plays music for new room anchor's music key; calls _clear_particles() on all fans in the room being left; resets all push_blocks in the destination room; on teleport-pad teleport (_complete_teleport): fades static in over 0.4s then teleports, plays electric_spawn at -3.1dB (~30% quieter than the prong teleport), and instantly hides static; boss_spawned_enemies in current room are queue_freed instead of reset; skips splash screen when SaveManager.skip_splash is true; TAB label above player has black outline (outline_size=2); resets breakable_walls in current room on room reset; shoot_door_ball(from, to, callback) spawns a DoorBall node that flies to the door and calls callback on arrival; Settings button in top-right corner (CanvasLayer layer=60); opens a slide-in settings panel centered on screen; panel uses triple border (outer 2px main color → middle 1px black → inner 2px main color), black background; all UI colors update live each frame to match Main.modulate; Escape key toggles settings open/closed via inner class `_EscapeHandler` (PROCESS_MODE_ALWAYS); tree paused while settings is open (music continues — AudioManager uses PROCESS_MODE_ALWAYS); panel contains: music volume slider, SFX volume slider (releasing fires `plant_stake` SFX), Export/Import Save buttons, Delete Save File button anchored to bottom; during splash screen Main.modulate is forced white and restored to room color via `tree_exited` signal after dismiss; enemy_doors in Y_SORT_GROUPS, _reset_room(), and _is_static_solid(); ability_message: Node is instantiated in _ready() but currently has no callers (AbilityPickup.gd was removed); teleport_between_prongs(target_center) — prong-to-prong teleport: locks player, plays depart teleport anim, plays electric_spawn SFX at 0.0dB (base volume), calls player.move_to_center(target_center), plays arrive anim, unlocks player
  Player.gd                — Player movement and input; exports start_with_push, start_with_chain, start_with_break, save_system_enabled; all three start_with_* exports set to true in Main.tscn so the player begins the game with all abilities; calls SaveManager.on_player_ready() at end of _ready(); var speed_multiplier: float = 1.0 scales movement (set by TimedObject); active fan airflow applies +60px/s wind after movement; push requires holding against a block for PUSH_HOLD_TIME=0.15s before it fires (_push_charge_time/_push_charge_dir/_push_charge_block track the charge; resets if direction/block changes or player moves freely); push pose animations: while flush against a pushable block and pressing into it the sprite shows the push pose frame 0 (`_push_pose_dir`, direction-specific: push_side/push_up/push_down via `_play_push()`); when a push actually fires (block moves) it shows frame 1 for PUSH_KICK_TIME=0.2s (`_push_kick_dir`/`_push_kick_time`) then returns to normal walk/idle; when pressing into a block that CANNOT move (an object is behind it — `can_push_block_to(dest)` is false), `_try_push()` sets `_push_blocked=true` and the pose animates instead of holding frame 0: `_update_animation()` cycles the 2-frame pose one frame every PUSH_STRAIN_FRAME_TIME=0.4s (`int(_push_strain_time / 0.4) % 2`), a straining loop; `_push_strain_time` accumulates in `_process` while blocked and resets otherwise; push poses override walk/idle in `_update_animation`, are cleared when movement is locked, and `_add_strip()` builds the 2-frame sheets (push_up frames are 32×36, shifted up 4px); cannot push non-fan blocks while standing in active fan airflow (fans remain pushable); look_up() sets _facing="back" and plays "back_idle" — called by PowerOrb on collect; death/revive (room reset): the "death" animation is a 16-frame 4×4 sheet (Death-Sheet.webp, 11.2fps, non-looping); `signal death_static_cue`; `play_death()` locks movement, plays "death" in place, and emits death_static_cue once `_sprite.frame >= DEATH_STATIC_CUE_FRAME` (=3) — i.e. after the 3rd frame; `play_revive()` plays "death" in reverse at 1× speed starting from frame 8 (`play_backwards("death")` then `_sprite.frame = 8`), awaited, then settles to front_idle; `reset_to(gp)` repositions, ejects from solids, makes the sprite visible, and plays front_idle (cutting any in-progress death animation short); debug ability shortcuts (room_teleport_enabled only): Shift+P=push, Shift+O=chain, Shift+I=break; pressing X (prong_teleport action) when 2 prongs are placed and player is within 24px of one calls Main.teleport_between_prongs() with the other prong's hitbox center
  SaveManager.gd           — Autoload singleton; save/load system; autosaves every 5s to active slot; slot 1 selected by default; number-key input only active when Player.save_system_enabled=true: 1–9 selects+loads slot, Shift+1–9 deletes, Alt+1–9 selects without loading; save_system_enabled=false auto-activates slot 1 for autosave but never loads on start; reloads scene on load (skip_splash=true); tracks key_doors_opened, boss_doors_opened, boss_defeated, rooms_solved (Array of [rx,ry]), breakables_destroyed (Array of [gx,gy]) for permanently-freed/persistent nodes; notify_room_solved(room) snapshots all currently-destroyed breakable walls in that room and immediately calls force_open(true) on all closed doors in the room so they animate open (in-session permanent open); the load path uses force_open() (no animation) to restore solved-room doors; is_room_solved()/is_breakable_destroyed() queried by Door and BreakableWall; on load: restores destroyed breakables silently, restores collected power orbs (orbs_collected array of [x,y] pixel positions; sets PowerOrbCounter.count and emits count_changed), and calls force_open() on all doors in solved rooms after beam sync; status label (top-left, fades after 1.5s) for slot feedback; save files at user://save_slot_N.json; save data format also includes orbs_collected: Array of [x,y]
  Prong.gd                 — Prong placement logic
  PushBlock.gd             — Push block with sprite-lag animation; pushes enemies on contact
  Fan.gd                   — Directional fan (NOT pushable — get_push_block_at_face skips the "fans" group); groups "fans" + "push_blocks" + "nuts"; tile top-left grid_pos/start_grid_pos; still has push()/push_undo() (now unused dead code); is_position_in_airflow() for wind LOS; is_position_in_airflow() for wind LOS; get_beam_point() returns sprite center (enables beam chaining through fans); dust particle emitter — _clear_particles() destroys and recreates CPUParticles2D instantly (called on fan power-off and on room transition); _push_blocks_in_airflow() with 0.4s dwell + 0.4s push interval (PUSH_INTERVAL=0.4); reset() restores grid_pos and clears particles
  DustPile.gd              — Destructible dust pile; shakes 0.8s (SHAKE_DURATION) then dissolves when fan airflow hits center; reset() skipped in solved rooms
  WindTurbine.gd           — Wind-powered switch; on state change sets GameManager.last_activator_pos to get_center() then calls set_wind_power(id); yellow ring when powered; reset() clears power state
  ElectricBeam.gd          — Animated electricity beam (white, no transparency); calls AudioManager.start_beam_noise() on activate and stop_beam_noise() on deactivate; is_point_on_beam(point, radius) and is_rect_on_beam(rect) test whether the beam touches a point (within radius) or passes through a rect (segment-vs-rect; used by Capacitor for its tile hitbox)
  Door.gd                  — Door open/close logic; sprite is ALWAYS visible (never hidden); @export id + @export id2 — the door registers under each of its ids (`_door_ids()` = id, plus id2 when set and distinct) so GameManager.evaluate_puzzle() emits doors_update for both; `_on_doors_update(door_id, open)` records each id's state in `_id_active` and calls set_open(`_any_id_active()`) so the door opens when ANY of its ids is active (OR logic, mirroring floor panels); @export starts_open: bool — when true the door begins on frame 4 (open state, passable) and CLOSES (plays "close" animation 4→0, freezes on frame 0, is_open=false → solid) when the puzzle activates; when the puzzle deactivates a starts_open door re-opens via DoorBall fired from GameManager.last_activator_pos; force_open(animate=false): when animate=false, silently snaps to frame=4 + is_open=true (stop() is called BEFORE setting frame 4, since stop() resets the frame to 0 — used by SaveManager on save LOAD); when animate=true, plays the open animation 0→4 with a shake (used by SaveManager.notify_room_solved when a room is first completed, so doors animate open); for normal doors set_open(false) is ignored when SaveManager.is_room_solved() (permanently open in solved rooms); set_open(true) fires a DoorBall from the player to the door center — door stays solid until ball arrives, then _do_open() plays the "open" animation (0→4) and freezes on frame 4; _opening flag prevents duplicate transitions; set_open(false) cancels any in-flight open; _anim_version int incremented on each _play_anim() call or force_open() to invalidate stale animation_finished callbacks
  FloorPanel.gd            — Floor panel registration + circle-outline highlight + pulsing border highlight; when a highlighted chain1 panel becomes active, checks if all other chain1 panels in the room are also active — if so, clears highlight on all of them
  LightningBlocker.gd      — Lightning blocker; alternates textures when active; plays electric_fail SFX when set_blocking(true)
  WallTileMap.gd           — TileMapLayer script for painting walls in-editor
  ResetEffect.gd           — CRT static CanvasLayer effect for room reset; play() fades in (FADE_IN=0.56s), emits `peaked`, holds at full opacity (HOLD=0.3s), fades out (FADE_OUT=0.22s), then emits `done`; play_teleport_buildup() fades in over 0.4s and stays; cancel() instantly hides
  KeyDoor.gd               — Solid door; counts Keys in same room; _setup_animations() builds a 10-frame "open" AnimatedSprite2D animation from KeyDoor.webp (32×42 frames, 10fps, non-looping) at runtime; sprite frozen on frame 0 until triggered; opens immediately on _count_keys() if room has zero keys; _open() fires a DoorBall then _do_open() plays the "open" animation, awaits animation_finished, then hides — no shrink tween; _opening flag guards against duplicate opens; reset() stops animation, restores frame 0 and visibility
  Key.gd                   — Collectible; notifies KeyDoor on pickup, plays "vanish" animation then hides; reset() only restores if a KeyDoor still exists in the same room; has a hidden Sprite2D child (key_file4.png at (16,16)) that is immediately hidden in _ready() — used as a palette icon placeholder; z_index set to -5 in _ready() (overrides tscn z_index=5); _setup_animations() null-guards the AnimatedSprite2D — creates it dynamically if $AnimatedSprite2D resolves to null (defensive fallback)
  Nut.gd                   — Pushable conductor; beam routes through it when chain ability active; pushes enemies on contact
  Screw.gd                 — Static conductor; beam routes through it when chain ability active; cannot be pushed
  PassBlock.gd             — Passthrough block; solid to push blocks, transparent to player
  BreakableWall.gd         — Solid block in "breakable_walls" group; requires "break" ability to be destroyed by beam; shakes 0.4s then hides + spawns particle burst; reset() restores it unless SaveManager.is_breakable_destroyed() (permanently destroyed when room is solved); destroyed walls removed from _is_static_solid so player can walk through; first beam contact frees all nodes in "break_highlight" group
  NanoDroid.gd             — Autonomous actor (group "nanodroids") that mirrors the player with REVERSED input; pushes blocks like the player, drifts in fan airflow, and detonates on the beam (breaks nearby walls + resets room if player is close). See the full NanoDroid.gd section under "## Scripts"
  SplashScreen.gd          — Launch splash; black bg + credit text, dismissed by any key
  YSortHitboxBottom.gd     — Hitbox-bottom Y-sort helpers (Player, Prong)
  PushUtils.gd             — Stateless block-push & actor-shove geometry (Main, LevelEditor)
  BeamUtils.gd             — Stateless beam routing/blocker geometry (Main, LevelEditor, ElectricBeam)
  GridUtils.gd             — Stateless world<->tile-grid conversion (all objects' get_grid_pos, etc.)
  SerializeUtils.gd        — DEFLATE+base64 (de)serialization of a dict (SaveManager, LevelEditor)
  PlayerUtils.gd           — Stateless player-vs-world queries (ExitPoint, TeleportPanel)
  MoveUtils.gd             — Axis-sweep / overlap / eject-BFS primitives (Player, NanoDroid, Enemy, bosses)
  EffectUtils.gd           — One-shot particle burst factory (BreakableWall, DustPile, NanoDroid)
  MapOverlay.gd            — Map overlay UI (TAB to open); slides in/out from top; teleport mode requires push ability; title always shows "The Map" in both modes; pressing Space on the player's current room does nothing
  TeleportAnchor.gd        — Room teleport anchor markers (legacy fallback; TeleportPanel is now the primary teleport mechanic); @export var color: Color; @export var music: String = "" — valid keys: "Orange", "Yellow", "Blue", "Red", "Boss", "LevelEditor"; crossfades to the keyed track on room entry
  TeleportPanel.gd         — Interactive teleport panel; closed=solid (player pushes 0.2s to open); open=passable floor; screenshake on open; exports panel_name (shown on map) and one_way (excludes from destinations)
  ExitPoint.gd             — EDITOR-ONLY; group "exit_points"; mirrors TeleportPanel open-on-push logic (OPEN_HOLD_TIME=0.1) but _process guards with player.has_method("_hitbox_rect") so it stays inert in the editor's non-play stub-player state; closed=solid via LevelEditor._is_static_solid; is_player_standing_on()/reset(); ending the playtest is driven by LevelEditor (Space), not this script
  OnewayPanel.gd           — (uses TeleportPanel.gd) TeleportPanel with one_way=true; source-only teleporter
  PowerOrb.gd              — Ability unlock pickup; @export ability: String; group "power_orbs"; draws white filled circle (radius 10px) at (16,16) via _draw(); on collect: grants ability immediately, locks player, calls player.look_up(), fades out music over 0.4s, plays 3.5s animation — orb floats 34px upward over 3.0s while 8 tapered spike lines rotate slowly (TAU*0.2 rad/s, inner radius 14px, outer 38px, tip width 7px), then shrinks to zero while flying to player body center over 0.5s — on animation end calls PowerOrbCounter.add_orb(), fades music back in over 0.4s, and unlocks player; reset() restores visibility
  OrbDisplay.gd            — Floor indicator for PowerOrb collection count; group "orb_displays"; z_index=-10; draws at tile top-left, all visuals centered at (16,16); inner circle radius 8px (outline when unfilled, filled white when filled); filled = rank < PowerOrbCounter.count where rank is this node's index in all "orb_displays" sorted by position.y then position.x (topmost = index 0 fills first); outer pulsing ring (radius ≈11px, ±1px, one cycle/s via sin(time*TAU)) drawn only when filled; connects to PowerOrbCounter.count_changed signal for immediate redraw
  PowerOrbCounter.gd       — Autoload singleton; var count: int; signal count_changed(new_count: int); add_orb() increments count and emits signal; count is persisted via SaveManager (restored from orbs_collected in save data)
  AbilityMessage.gd        — CanvasLayer message overlay (layer 25); show_message(text) shows overlay, prompt after 2s, dismissed by any key; currently instantiated in Main but has no active callers (was used by the now-deleted AbilityPickup.gd)
  AbilityGate.gd           — Node2D that hides its sprite until required_ability is granted
  AbilityTutorial.gd       — Autoload singleton (registered in project.godot); contains inner classes BoundingHighlight and SphereOverlay for per-ability intro animations; currently not called from any active game script — legacy code left as autoload
  Utils.gd                 — Autoload singleton; shared helpers — boss health bar HUD (top of screen) + per-enemy sprite health bars; remove_boss_health_bar uses untyped canvas var + erases dict entry before queue_free to avoid freed-instance crash on scene reload; shake_boss_health_bar() tweens canvas offset ±2px horizontally + random ±2px vertically (debounced); CPUParticles2D at fill tip bursts top-right on each shake; create/update/remove_sprite_health_bar() — 32px-wide, 6px-tall boss-style bar above sprite (offset_y=−10), z_index=−1 (draws behind enemy sprite), inherits Main.modulate from scene tree
  Enemy.gd                 — Base Enemy; walks toward player, blocked by walls/solids, instant beam kill via _handle_beam(), resets player on contact; _eject_from_solid() BFS-finds nearest free tile when inside a solid; @export var enemy_id: String = "" — used by EnemyDoor to track kills; is_dead() → bool public accessor; virtual `_ground_offset()` (default 0) shifts the node origin to the Y-sort ground line in _ready() — get_center()/_hitbox()/_eject_from_solid()/sprite placement/reset() are all offset-aware (see Y-Sorting)
  WaterEnemy.gd            — Extends Enemy.gd; defines `GROUND_OFFSET=24` and overrides `_ground_offset()` so water/spider/bounce shift their Y-sort origin to the ground line (see Y-Sorting); passes `HEALTH_BAR_OFFSET_Y - _ground_offset()` so the health bar stays put; MAX_HP=25, hp var, sprite health bar via Utils; overrides _handle_beam() for −1 HP/frame + _trigger_shake(2.0) — guards against null electric_beam (safe in level editor); get_max_hp() overridable; freezes movement when not in current room or when map overlay is open; _process() uses _main.get("map_overlay") null guard and bails before super._process() when electric_beam is null (prevents AI running in the level editor); calls _eject_from_solid() each frame; boss_spawned flag auto-adds to "boss_spawned_enemies" group (deleted on room exit/reset instead of reset); overrides _die() to play water_death SFX; reset() restores hp
  BounceEnemy.gd           — Extends WaterEnemy.gd; BOUNCE_MAX_HP=50; tile A* pathfinding (Manhattan heuristic; walk + jump over 1-tile walls or push blocks via `is_blocked()`); pathfinding constrained to home room (computed from _start_pos in _ready: _room_x0/_room_y0); hop/jump movement on flat position with arc on sprite only; MOVE_SPEED=0.286; random wait 0.5–0.8s between bounces with landing squash (sin curve); idle rhythmic squish/squash (_idle_time accumulator, ~1.1 Hz, ±5%, bottom-center pivot); stretch squash/stretch on hop/jump peaks; SPRITE_LAG_SPEED=24 (matches player); no _eject_from_solid; no wall AABB collision; inherits WaterEnemy ground-offset Y-sort (no forced z_index) — grid conversions use `_self_cell()` / offset-aware `_grid_to_world`, sprite pivot and HitboxArea compensated by `_ground_offset()`; player contact disabled during JUMP arc (wall jump); group "bounce_enemies"; overrides _handle_beam() — immune to electric beam, instead takes −1 HP/frame (+ 2px shake) while center is inside any active fan's airflow; _process() uses map_overlay null guard and bails when electric_beam is null (safe in level editor); room-reset handling (in Main._reset_room): once killed a bounce enemy does NOT respawn, but a still-living one is `reset()` back to its original start position on any room reset (R or death-by-enemy)
  SpiderEnemy.gd           — Extends WaterEnemy.gd; SPIDER_MAX_HP=10; stands still, rotates toward player via spring-damper (ANGLE_STIFFNESS=120, ANGLE_DAMPING=22); overrides _die() to enter 8s stun (STUNNED state) instead of dying — sprite changes to switch_open2.png, no contact kill; wakes and reverts to normal; states: IDLE→ROTATING→PRE_LUNGE→LUNGING→RETRACTING→COOLDOWN→STUNNED; ROTATE_RADIUS=96px (3 tiles); LUNGE_RADIUS=64px (2 tiles); AIM_TOLERANCE=0.3 rad; 0.2s pre-lunge shake (PRE_LUNGE_TIME), exponential-decay lunge over 0.5s (LUNGE_DECAY=2.5), 2s smoothstep retraction back to _start_pos; wall collision during lunge triggers 2px screen shake; COOLDOWN_TIME=0.4s between lunges; _angle initialized to PI/2 (facing down) and synced from _sprite.rotation on each IDLE→ROTATING transition; hitbox read from $HitboxArea/HitboxShape (supports CircleShape2D and RectangleShape2D; anchor = HitboxArea.position + shape.position, compensated by `_ground_offset()`); inherits WaterEnemy ground-offset Y-sort (no forced z_index — sprite/hitbox/particles compensated); sprite: spider_small.png, centered=true, position=(16, 16 − `_ground_offset()`) set in _ready(); _process() uses map_overlay null guard and bails when electric_beam is null (safe in level editor — keeps spider frozen facing down)
  WaterBoss.gd             — Extends WaterEnemy.gd; overrides `_ground_offset()`→0 (keeps tile-top origin, sorts by own rules); BOSS_MAX_HP=1000, 2× scale; overrides get_max_hp(); uses top-screen boss bar (not sprite bar); @export var debug_low_hp: bool sets HP to 10 at start if true; boss health bar via Utils (visible in boss home room when alive); takes 1 dmg/frame from beam (shake 1.0 + health bar shake+particles) + freeze-frame on first contact each exposure; teleports to random free tile (≥5 tiles from player, ≥2 tiles from room border) after 1.5s in beam; sprite slides to new position on teleport; speed scales with HP loss (BASE=40→MAX=100); spawns two WaterEnemy minions 3 tiles out below 80% HP with 0.7s scale-pulse telegraph (interval scales 4s→2s as HP drops, skips spawn if within 96px of player); charge attack: cooldown 3s, triggers when player within 5 tiles — 1s squash/stretch wind-up, then lunges at 240 px/s decelerating to normal speed; teleport mid-windup resets cooldown; phase 2 at 50% HP: screen shake + brief pause; death: series of 3 extreme shakes (0.5s apart), minion water_enemies in room deleted immediately (boss skips self in that loop), boss freezes 1s then arcs off screen in a parabola at z_index=100 with a slight rotation (dir * p * 0.8 rad) — particles fire once boss exits room bounds (boss doors open themselves once the room has no living boss — see BossDoor); sprite lag at half enemy speed (BOSS_SPRITE_SPEED=10); no modulation effects
  BounceBoss.gd            — Extends WaterEnemy.gd; overrides `_ground_offset()`→0 (keeps tile-top origin, sorts by own rules); BOSS_MAX_HP=1800, 2× scale (64×64); tile BFS pathfinding treating the boss as a single 32×32 tile, constrained to its home room (`_room_x0/_room_y0` from `_get_home_room()` in _ready); can leap over a single solid block (JUMP_TILES=2 straight jump when the next tile is blocked but the one beyond is clear); hop movement (HOP_DURATION=0.28s) + big bounce attack (5s interval, 0.8s windup, locks target at jump start, tall arc, can't hurt player mid-air); move speed scales with HP loss to 4× its starting speed (BASE=0.15→MAX=BASE*4); the idle wait between hops also shrinks as it speeds up (`_wait_scale()` = BASE/current speed); each landing shakes the screen (LAND_SHAKE=2px normal hop, LONG_JUMP_SHAKE=4px big bounce); does NOT spawn minions; NO beam damage — instead takes −1 HP/frame from any active fan's airflow (same as BounceEnemy), with a larger wind hitbox that samples all four tiles of the 2×2 footprint (`_fan_hits_boss`); two BounceBossPanel nodes (positive + negative, id "bounceboss") are spawned when the boss registers; the panels are real floor panels, so planting a prong in each and connecting them with the beam powers the "bounceboss" id — author fans with id "bounceboss" in the room and that wind damages the boss; panels relocate every 300 HP (PANEL_SWITCH_STEP) to deterministic positions ≥3 tiles from the room borders (obstacles ignored — they may sit in walls); placement uses a seeded RNG (PANEL_RNG_SEED) re-seeded on every reset so the sequence repeats, with the 5th/6th placements nudged by +1 to avoid collisions; on death: arc parabola off screen (boss doors open themselves once the room has no living boss — see BossDoor)
  BounceBossPanel.gd       — Node2D spawned by BounceBoss; @export id="bounceboss"; positive/negative variants (positive.png / negative.png, drawn via _draw()); registers as a GameManager floor panel (`register_floor_panel(gp, id)`) and activates (_active=true) when a prong is planted within PANEL_ACTIVATION_RADIUS — same as FloorPanel, so the normal beam/puzzle path powers the id (the beam must actually connect the two prongs); draws a white arc outline when active; relocate animation: `move_to()` shrinks the panel out over 0.4s, teleports at scale 0, then grows back over 0.4s (`snap_to()` is the instant version for spawn/reset); re-registers its floor-panel tile on each move and unregisters in `_exit_tree`; drawn under everything at floor level (z_as_relative=false, z_index=-10, same convention as FloorPanel/FloorSwitch)
  FloorSwitch.gd           — Pressure floor switch; group "floor_switches"; z_index=-10; @export id matches door ids; each frame checks if player body center is inside tile rect, any push_block's grid_pos matches, or any non-destroyed NanoDroid's get_center() is inside the tile rect; on state change sets GameManager.last_activator_pos to tile center then calls GameManager.set_floor_switch(id, active); reset() deactivates; `_update_frame()` sets the Sprite2D frame (0 unpressed / 1 pressed) on every state change
  Capacitor.gd             — Beam-charged powered object; group "capacitors"; @export id; `_progress` (0..1) maps to frame `round(_progress*7)` of the 8-frame Capaciter-Sheet; _process advances _progress by delta/CHARGE_TIME (0.7s) while the beam passes through its bottom-tile hitbox (`_hitbox_rect()` = Rect2(position, 32×32), tested via electric_beam.is_rect_on_beam) and decays it by delta/DISCHARGE_TIME (8.0s) otherwise (clamped 0..1); powered = frame > 0 → GameManager.set_capacitor(id, powered) (sets last_activator_pos to get_center() first); reads beam via get_tree().current_scene.electric_beam (null-safe, so inert in editor BUILD); reset() returns to frame 0 and clears power; get_grid_pos()/get_center() treat position as tile top-left
  EnemyDoor.gd             — Door that opens when all enemies sharing its id are dead; @export id: String; _process() polls enemy group each frame; _all_matching_enemies_dead() requires ≥1 enemy with matching enemy_id and all dead; fires DoorBall then _do_open() shrink animation; reset() closes door and cancels in-flight open; solid via Main._is_static_solid(); group "enemy_doors"
  BossDoor.gd              — Solid tile object in "boss_doors" group only (NOT push_blocks — has no push() method); provides grid_pos/start_grid_pos/get_grid_pos() computed from position; included in Main._is_static_solid() so it blocks player while visible; self-managing: `_process()` opens the door once its own room has no living boss — `_room_has_living_boss()` scans the "water_boss"/"bounce_boss" groups (BOSS_GROUPS) for a valid, non-`_dead` boss whose `_get_home_room()` matches the door's room; a door in a room with no boss opens immediately; open() calls SaveManager.notify_boss_door_opened() then queue_free(); reset() also frees if already opened (permanent removal). Bosses no longer open doors directly on death.
  SaveManager.notify_boss_defeated() — also called by BounceBoss._boss_die()
  RoomSolvedTile.gd        — Invisible floor tile (z_index=-10, group "room_solved_tiles"); positioned at tile top-left; _triggered marks this tile stepped on; _trigger() checks all room_solved_tiles in the same room — only fires SaveManager.notify_room_solved(), snap SFX, and shake_requested(2.0) once every tile in the room has been stepped on; auto-triggers on _ready() if room already solved (loaded from save)
  DoorBall.gd              — Short-lived Node2D (z_index=20) spawned by Main.shoot_door_ball(); draws a white filled circle (radius 5px) at its own origin; launch(from, to, on_arrive) tweens position from→to over 0.28s (EASE_IN SINE) then calls on_arrive and queue_free()s itself
  NanoDroid.gd             — Reversed-control actor; group "nanodroids"; computes `_home_room` from its start tile; `_is_in_current_room()` compares `_main.current_room` (null in the editor → always true); on the not-current→current edge it calls reset() (re-arm + snap to start); freezes (returns) while not in its room; `_clamp_to_room()` keeps it inside a 16px inset of the room rect every frame; _process reads the player's WASD axes and negates them, then moves continuously with the player's `_move_axis_x/_move_axis_y` AABB sweep against `_main.get_player_blocking_rects`; applies the same per-frame fan wind drift as the player; freezes when `_main.player.movement_locked`; bails entirely while `_main.electric_beam` is null (level-editor BUILD); `_explode()` on beam contact (BEAM_RADIUS=12) hides the sprite, plays a circular explosion animation (`_spawn_shockwave()`: expanding Line2D ring + Polygon2D flash, both tweened scale-up + alpha-fade) plus a white debris particle burst, shakes the camera, triggers BreakableWalls within BREAK_RADIUS=64, and calls `_main._reset_room()` if the player is within RESET_RADIUS=48; also calls `_main._reset_room()` when its hitbox touches the player (`_touches()`); `get_center()`=position+(16,16); reset() restores start_grid_pos and visibility; `_eject_from_solid()` BFS like the player
  Hole.gd                  — Floor pit; group "holes"; states EMPTY/FILLING/FILLED/NANO. `is_solid()` true unless FILLED (so empty/filling/droid-filled holes block via Main._is_static_solid); `can_accept_block()` true for EMPTY/NANO (so Main.can_push_block_to lets a pushable be pushed in). _process (gated on `_main.electric_beam` so it's inert in editor BUILD) detects a push_block whose grid_pos matches (begins a 0.4s sink, pulling it from "push_blocks"/"nuts" so it can't be pushed back out) or a NanoDroid whose center enters the tile (destroys/hides it, draws its sprite in the Overlay, state→NANO, hole stays solid). On fill: Nut→hole_nut.png, PushBlock (script path check)→hole_filled.png, else hole1.png + Overlay sprite; absorbed pushables tracked in `_consumed_blocks` and restored (re-added to groups, shown, reset()) by reset(); droids restored via the nanodroids reset loop. Holes reset on _reset_room and on room transition into their room
  TimedObject.gd           — Node2D that tracks per-room-visit time; sprite (arrow_up.png) appears after 120s if player lacks chain ability; blinks every 0.5s while visible; sets player.speed_multiplier=0.8 while showing; resets (hides, restores speed, clears timer) each time the player enters its room; always hidden after chain ability granted; requires Sprite2D child named "Sprite2D"

Sprites/
  player/
    stake.png                      — Prong sprite
    Spark_Front_Idle.webp          — Player front idle sheet (4×2=8f)
    Spark_Front_Run.webp           — Player front run sheet (3×2=6f)
    Spark_Side_Idle.webp           — Player side idle sheet (3×2=6f); flip_h for left
    Spark_Side_Run.webp            — Player side run sheet (3×2=6f); flip_h for left
    Spark_Back_Idle.webp           — Player back idle sheet (4×2=8f)
    Spark_Back_Run.webp            — Player back run sheet (3×2=6f)
    Teleport_Spritesheet.webp      — Player teleport effect (2×2=4f, non-looping); played forward on depart, reversed at half speed on arrive
    Push_side-Sheet.webp           — Player push pose, left/right (2 frames of 32×32; flip_h for left); frame 0 = pressing against block, frame 1 = block just moved
    Push_down-Sheet.webp           — Player push pose, downward (2 frames of 32×32)
    Push_up-Sheet.webp             — Player push pose, upward (2 frames of 32×36 — 4px taller; the extra height bleeds upward, sprite shifted up 4px in _play_push)
    Death-Sheet.webp               — Player death animation (128×128 = 4×4 grid of 16 frames of 32×32, 11.2fps, non-looping); played in place on room reset by Player.play_death(); reversed (frame 8→0, 1× speed) by Player.play_revive() to reassemble the player at the new location after repositioning

  enemies/
    Front_Idle1.png        — Enemy/WaterEnemy/Boss sprite
    BounceFront.png        — BounceEnemy sprite (64×64; drawn bottom-center anchored at the tile bottom-center; also the editor palette/ghost icon)
    spider_small.png       — SpiderEnemy sprite (centered=true at (16, 16 − ground offset); rotated via _sprite.rotation=_angle; texture faces right at rotation=0, so PI/2 = facing down)

  objects/
    Key_File.webp          — Key idle animation sheet (7×2=14f, 10fps, looping); also used for palette + ghost in editor
    Vanish.webp            — Key collect animation sheet (6×1=6f, 12fps, non-looping)
    Nanobot_Back_Idle.png  — NanoDroid sprite (32×32); also the editor palette icon for NanoDroid
    Holes/hole1.png        — Hole empty sprite (also the editor palette icon for Hole)
    Holes/hole_filled.png  — Hole filled by a regular PushBlock
    Holes/hole_nut.png     — Hole filled by a Nut
    Dust_Pile.png          — WindBlock sprite; also used as editor palette icon for WindBlock
    Dust_Pile_Alternate.png — DustPile sprite
    positive.png           — FloorPanel positive variant sprite; also BounceBossPanel positive
    negative.png           — FloorPanel negative variant sprite; also BounceBossPanel negative
    resistor_small.png     — LightningBlocker idle sprite
    resistor_small2.png    — LightningBlocker active (alternates with resistor_small every 0.5s)
    SD_Card_block.png      — PushBlock sprite
    washer_block.png       — Nut sprite
    door.webp              — Door animation sheet (5×1=5f, 32×32px per frame, 10fps, non-looping); frame 0 = closed, frame 4 = open; "open" plays 0→4, "close" plays 4→0
    switch_closed.png      — (unused by Door; legacy sprite)
    locked_door1.png       — BossDoor sprite
    switch_open2.png       — PassBlock sprite
    Key_File.webp          — Key idle animation sheet (7×2=14f, 10fps, looping)
    Vanish.webp            — Key collect animation sheet (6×1=6f, 12fps, non-looping)
    wall_breakable.png     — BreakableWall sprite
    TAB.png                — AbilityGate sprite
    teleport_closed.png    — TeleportPanel closed/solid sprite
    teleport_open.png      — TeleportPanel open/passable sprite
    arrow_up.png           — TimedObject sprite
    Switch-Sheet.webp      — FloorSwitch sprite sheet (64×32, two 32×32 frames; frame 0 unpressed, frame 1 pressed)
    Capaciter-Sheet.webp   — Capacitor sprite sheet (256×48 = 8 frames of 32×48, hframes=8; frame 0 = idle, frame 7 = fully charged); also the editor palette/ghost icon (first frame, 32×48 bottom-anchored)
    floor_switch.png       — (legacy; no longer used by FloorSwitch, which now uses Switch-Sheet.webp)
    KeyDoor.webp           — KeyDoor animation sheet (10×1=10f, 32×42px per frame, 10fps, non-looping); frame 0 = locked state; frames 1–9 = opening animation played when all keys collected
    key_file4.png          — hidden Sprite2D child in Key.tscn (palette placeholder, immediately hidden in _ready())
    undo button.png        — UI sprite used in Main.tscn
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
    Electric_Noise1.ogg    — electric_noise SFX (loops while beam active, −29.1dB)
    Electric_Spawn.ogg     — electric_spawn SFX (plays on teleport)
    Plant_Stake1.ogg       — plant_stake SFX (plays on prong placement)
    Water_Death.ogg        — water_death SFX (WaterEnemy/boss death)
    Snap.ogg               — snap SFX (−14dB, plays on room solved tile trigger)

  music/
    Motherboard_Level_Loop.ogg   — "Orange" music key; main level loop
    Motherboard_Title_Loop.ogg   — (unused by AudioManager; reserved OGG file)
    Motherboard_Level_Intro.ogg  — (unused by AudioManager; reserved)
    PlaceholderMusic/
      Yellow.mp3      — "Yellow" music key
      Blue.mp3        — "Blue" music key
      Red.mp3         — "Red" music key (target volume −7dB)
      LevelEditor.mp3 — "LevelEditor" music key
      Boss.mp3        — "Boss" music key (target volume −6dB)
```

---

## Scripts

### GameManager.gd (autoload singleton)
**Purpose:** Central puzzle state manager. `evaluate_puzzle()` is driven solely by `Main._update_beam()`.

**Key variables:**
- `prongs: Array` — up to 2 entries, each `{node: Node, grid_pos: Vector2i}`
- `beam_blocked: bool` — set by Main before `evaluate_puzzle()`
- `floor_panels: Dictionary` — `Vector2i → Array[String]` (one or two IDs per panel)
- `doors: Dictionary` — `String id → Array[Node]`; a Door with two ids registers under both keys (so it receives doors_update for each and opens on either — see Door.gd)
- `_abilities: Dictionary` — `String → bool`; tracks granted abilities
- `signal doors_update(id: String, open: bool)`
- `signal shake_requested(strength: float)`
- `wind_powered_ids: Array` — ids currently powered by WindTurbine nodes; merged with beam-solved ids in evaluate_puzzle(); cleared by clear_scene_state()
- `floor_switch_ids: Array` — ids currently powered by FloorSwitch nodes; merged in evaluate_puzzle(); cleared by clear_scene_state()
- `capacitor_ids: Array` — ids currently powered by Capacitor nodes (off frame 0); merged in evaluate_puzzle(); cleared by clear_scene_state()
- `last_activator_pos: Vector2` — world position of the object that most recently triggered evaluate_puzzle(); set by FloorSwitch (tile center), WindTurbine (get_center()), and Main._update_beam() (player body center) just before calling evaluate_puzzle()/set_floor_switch()/set_wind_power(); used by starts_open Door to aim the DoorBall from the activating object
- `const PANEL_ACTIVATION_RADIUS := 24.0` — radius (px) for prong-to-panel proximity check

**Key functions:**
- `place_prong(node, grid_pos)` — appends entry
- `remove_prong(node)` — removes by node reference
- `clear_prongs()` → `Array` — clears all, returns removed for animation
- `clear_scene_state()` — clears prongs, doors, floor_panels, resets beam_blocked; called by SaveManager before scene reload to prevent stale node refs
- `evaluate_puzzle()` — opens doors if: not beam_blocked, 2 prongs on **different** panels sharing at least one id; guards prong node refs with `is_instance_valid()`
- `set_wind_power(id, powered)` — adds/removes id from wind_powered_ids then calls evaluate_puzzle(); used by WindTurbine
- `set_capacitor(id, powered)` — adds/removes id from capacitor_ids then calls evaluate_puzzle(); used by Capacitor
- `register_floor_panel(grid_pos, id, id2="")` — stores 1–2 IDs for a panel
- `unregister_floor_panel(grid_pos)` — erases a panel entry (used by the moving BounceBossPanel when it relocates / is freed)
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
- `ability_message: Node` — `AbilityMessage` CanvasLayer instance; created in `_ready()` but currently has no active callers (AbilityPickup.gd was deleted)
- `_last_push` — Dictionary `{block, from, dir}` recording the most recent player-initiated push, or `null`; cleared on room reset and room transition; also cleared when a new push is made (invalidates redo)
- `_undo_push` — Dictionary `{block, from, dir}` recording the most recently undone push for redo, or `null`; cleared on room reset, room transition, and any new push
- **Settings panel vars:** `_settings_btn`, `_settings_canvas` (CanvasLayer layer=60, PROCESS_MODE_ALWAYS), `_settings_panel` (Control), `_settings_panel_bg` (inner border StyleBoxFlat), `_settings_outer_bg` (outer border StyleBoxFlat), `_dim_btn` (transparent full-rect Button for click-outside), `_settings_open: bool`, `_settings_tween`, `_music_slider`, `_sfx_slider`, `_confirm_panel` (delete confirmation overlay); style tracking arrays: `_settings_btn_styles: Array[StyleBoxFlat]`, `_settings_hover_styles: Array[StyleBoxFlat]`, `_settings_btns: Array[Button]` (all buttons including panel buttons), `_settings_labels: Array[Label]`, `_settings_seps: Array[HSeparator]`, `_settings_slider_fills: Array[StyleBoxFlat]`, `_settings_slider_tracks: Array[StyleBoxFlat]`, `_settings_sliders: Array[HSlider]`; `_last_btn_color: Color` — detects modulate change each frame; constants: `_PANEL_W=260`, `_PANEL_H=238`, `_PANEL_OPEN_X=(800-_PANEL_W)/2`, `_PANEL_Y=(384-_PANEL_H)/2`, `_PANEL_CLOSED_X=820`
- **Inner class `_EscapeHandler extends Node`** (PROCESS_MODE_ALWAYS, added to `_settings_canvas`): handles Escape key while tree is paused — toggles settings open/closed; only opens settings when `not player.movement_locked`

**Key functions:**
- `_setup_y_sort_children()` — enables Y-sort on `Walls`, reparents `Y_SORT_GROUPS` nodes under `wall_tilemap`. Screws are in `Y_SORT_GROUPS` and are reparented like other solids; they are also checked via `_is_static_solid()` using the `"screws"` group
- `_process(delta)` — shake decay (`lerpf(_shake_amount, 0, 9*delta)`) → `camera.offset` = random ±1.6px × `_shake_amount`
- `_trigger_shake(strength)` — sets `_shake_amount`; connected to `GameManager.shake_requested`
- `_update_beam()` — sets `GameManager.last_activator_pos = player.get_body_center()`, then checks blockers (via `BeamUtils.beam_blockers()` / `BeamUtils.expand_connected()`), sets `GameManager.beam_blocked`, calls `evaluate_puzzle()`, activates/deactivates beam
- `_compute_beam_path(pos_a, pos_b)` — gathers in-room chain Nuts, then delegates to `BeamUtils.nearest_first_beam()` (the nearest-first DFS path search, shared with LevelEditor; replaced the old shortest-path `_search_beam`)
- `spawn_prong(pixel_pos)` — `pixel_pos` is hitbox center; if 2 prongs already exist, oldest is removed with shrink animation before placing new one (no "clear both" behaviour)
- `_reset_room()` — locks player → plays character_death SFX → `player.play_death()` (death animation in place) → awaits `player.death_static_cue` (after the death animation's 3rd frame) → `reset_effect.play()` (static fades in) → awaits `peaked` → resets room state (prongs, push blocks, fans, breakable walls, key doors, keys, enemies, dust piles, wind turbines, floor switches, enemy doors, nanodroids, holes, capacitors) — enemy reset rules: boss_spawned_enemies are queue_freed; **bounce enemies don't respawn once killed** but a LIVING bounce enemy is `reset()` back to its start position (gated on `is_dead()`); other enemies are `reset()` **only if the room is not SaveManager.is_room_solved()** (no respawning in completed rooms) → `player.reset_to()` (respawn, cutting the death animation short) → awaits `player.play_revive()` (death animation reversed at the new location; the static fades out during it) → unlocks player
- `_transition_to_room(new_room, auto_unlock: bool = true)` — clears prongs instantly, resets enemies in new room (skipped entirely when the entered room is SaveManager.is_room_solved() — enemies don't respawn in completed rooms), tweens camera 0.25s; when `auto_unlock=false` the camera-tween callback does not unlock the player (used by `_complete_teleport` so the arrive animation controls unlock instead)
- `check_room_transition(player_grid, player_pixel)` — uses `floori` division; downward and rightward transitions require player pixel position to be 24px past the boundary before firing
- `tile_rect(grid_pos)` → `Rect2` — 32×32 world rect for a grid tile
- `_is_static_solid(grid_pos, include_holes := true)` — walls, closed doors, lightning blockers, key doors, closed teleport panels, screws, visible dust piles, wind turbines, breakable walls, boss doors, closed enemy doors, capacitors, unfilled holes (`hole.is_solid()`) (NOT push blocks, NOT pass blocks, NOT fans — fans block via push_blocks collision). Pass `include_holes=false` to ignore holes — NanoDroid does this so it can walk into/fall down holes. `get_player_blocking_rects(area, include_holes := true)` forwards the flag. `can_push_block_to()` special-cases holes via `_hole_at()`: an EMPTY or NANO hole returns true so a pushable can be pushed in to fill it
- `is_blocked(grid_pos)` — static solids + push blocks (used for grid queries elsewhere)
- `can_teleport_from_panel()` → `bool` — true if player is on an open panel, at least 2 total open panels exist (including one-ways), and at least one non-one-way destination exists; used for TAB prompt and teleport mode activation
- `get_open_teleport_panel_rooms()` — returns rooms with open non-one-way TeleportPanels (destinations only)
- `get_player_blocking_rects(area)` → `Array[Rect2]` — static tile rects + push-block rects overlapping `area`; used by player and enemy AABB movement
- `can_push_block_to(grid_pos)` — false if the target tile is outside the room's push bounds (`_within_room_push_bounds()` requires the block's 32×32 tile to be fully enclosed by its room rect inset PUSH_ROOM_MARGIN=16px on every side — i.e. the block can't reach the outer 1-tile ring of any room, keeping pushables from being shoved out through doorways; applies to player AND fan pushes), or if a static solid, push block, pass block, or pass_tilemap tile occupies the tile; an EMPTY/NANO hole at the tile returns true (the block sinks in)
- `get_push_block_at_face(player_rect, dir, from_point)` → `Node` — among push blocks flush against `player_rect` on the given face, returns the one whose center is closest to `from_point`; skips the `"fans"` group so fans are never pushed (they remain solid via push_blocks collision)
- `has_pass_block_at(grid_pos)` — checks pass_blocks group
- `get_push_block_at(grid_pos)` → Node or null
- `_find_nearest_open_tile(start)` — BFS for nearest unblocked tile; uses `is_blocked` (includes push blocks)
- `is_player_on_active_teleport_panel()` → `bool` — true if player hitbox overlaps any open TeleportPanel
- `get_open_teleport_panel_rooms()` → `Array` — list of room coords that contain an open TeleportPanel
- `_get_open_panel_for_room(room)` → `Node` — finds the open TeleportPanel in a given room (used by `_on_teleport_requested`)
- `_on_teleport_requested(room)` — starts `reset_effect.play_teleport_buildup()` then defers `_complete_teleport(room)`
- `_complete_teleport(room)` — locks player → `await player.play_teleport()` (depart anim) → moves player to destination panel/anchor → cancels reset effect → `_transition_to_room(room, false)` → `await player.play_teleport(true)` (arrive anim: reverse, half speed) → unlocks player
- `_update_tab_label()` — shows "TAB" Label above player sprite when on open panel with ≥2 open panels; color matches `modulate`; position tracks `player.visual_pos`
- `record_push(block, from_pos, dir)` — stores the push as `_last_push`, clears `_undo_push` (new push invalidates redo)
- `undo_last_push()` — called on Z key (while not `movement_locked`) when `_last_push != null`; any actor (player, nanodroid, enemy — collected by `_push_actors()`, matched to a tile by `PushUtils.actor_tile()`) standing at `from_pos` is shoved one tile in `-dir`; blocked (plays electric_fail) if such an actor exists and `is_blocked(from_pos - dir)` (nowhere to push it out); on success: saves entry to `_undo_push`, calls `PushUtils.displace_actor()` on each shoved actor (moves its body via `actor.push_out()` but leaves the sprite's visual position so it lags into place), `block.push_undo(from_pos)`, triggers shake (0.8) and `_update_beam()`
- `redo_last_push()` — called on Z key when `_last_push == null` and `_undo_push != null`; blocked (plays electric_fail) if any actor (`_push_actors()`) is standing at the redo destination (`from_pos + dir`); also blocked silently if `can_push_block_to(dest)` is false; on success: restores `_last_push`, calls `block.push(dir)`, triggers shake (0.8) and `_update_beam()`
- `_push_actors()` — scene-specific list of shovable actors (player + live nanodroids + live enemies). The stateless geometry it feeds lives in `PushUtils` (see below)
- `get_push_block_at_face()` / `get_push_block_at()` — thin forwarders to `PushUtils.block_at_face()` / `PushUtils.block_at()` over the `push_blocks` group (LevelEditor has matching forwarders, so editor playtests share the exact same logic)
- `teleport_between_prongs(target_center: Vector2)` — locks player → `await player.play_teleport()` → plays `electric_spawn` SFX → `player.move_to_center(target_center)` (places player exactly at other prong, ejects from walls in 4px steps) → `await player.play_teleport(true)` → unlocks player
- `_setup_settings_button()` — creates CanvasLayer (layer=60, PROCESS_MODE_ALWAYS), adds top-right Settings button, transparent `_dim_btn` (click-outside to close), `_EscapeHandler`, then calls `_build_settings_panel()` and `_refresh_settings_colors(modulate)`
- `_make_ui_button(label) -> Button` — creates a styled Button with 1px StyleBoxFlat borders; appends normal/pressed/focus styles to `_settings_btn_styles`, hover style to `_settings_hover_styles`, and the button itself to `_settings_btns` (so all buttons update color together in `_refresh_settings_colors`)
- `_build_settings_panel()` — triple-border PanelContainer hierarchy (outer 2px+margin, mid 1px+margin, inner 2px+10px padding); VBox contains: title row (Label + ✕ close button — ✕ uses `resized` signal to force square minimum size), HSeparator, music volume slider row, SFX volume slider row, HSeparator, Export/Import Save row (side by side), `SIZE_EXPAND_FILL` spacer (pushes delete to bottom), HSeparator, Delete Save File button; SFX slider `drag_ended` fires `AudioManager.play_sfx("plant_stake")`; panel starts at `_PANEL_CLOSED_X` offscreen and is hidden
- `_make_slider_row(label, initial, on_change, is_music) -> HBoxContainer` — label (88px min width) + HSlider (0–1, step 0.05); track and fill StyleBoxFlats tracked in arrays; slider added to `_settings_sliders`
- `_refresh_settings_colors(c)` — updates all tracked style arrays (border colors, hover bg, font colors on all `_settings_btns`, label colors, separator modulates, slider fill/track colors, grabber icon); runs every `_process` frame when modulate changes
- `_make_grabber_icon(c) -> ImageTexture` — draws a filled 11×11 circle in color `c` as an `ImageTexture` used for slider grabber icons
- `_open_settings()` — pauses tree, locks player, shows dim button and panel, syncs slider values from AudioManager, tweens panel from x=820 to `_PANEL_OPEN_X` over 0.25s
- `_close_settings()` — frees any `_confirm_panel`, tweens panel back to x=820 over 0.2s; on complete: hides panel and dim button, sets `_settings_open=false`, unpauses tree, unlocks player
- `_on_export_save_pressed()` — calls `SaveManager.export_save_string()`, shows `AcceptDialog` with a read-only `TextEdit` displaying the encoded string
- `_on_import_save_pressed()` — shows `AcceptDialog` with editable `TextEdit`; on confirm: unpauses tree, calls `SaveManager.import_save_string(encoded)` (which reloads scene); re-pauses if import fails
- `_on_delete_save_pressed()` — spawns `_confirm_panel` (220×90 centered dialog) with "Yes, Delete" and "Cancel" buttons; calls `_confirm_delete_save()` on confirm
- `_confirm_delete_save()` — unpauses tree then calls `SaveManager.delete_active_save()`
- **Splash + modulate:** in `_ready()`, if not `SaveManager.skip_splash`, captures `post_splash_color = modulate`, sets `modulate = Color.WHITE`, connects `splash.tree_exited` to restore `post_splash_color`; `_process` detects `modulate != _last_btn_color` and calls `_refresh_settings_colors(modulate)` so panel text updates to the new room tint after splash

---

### Player.gd (Node2D)
**Purpose:** Free pixel-based movement, push input, and prong placement.

**Constants:** `SPEED=217.6 px/s` (20% reduced from original 272), `SPRITE_SPEED=24.0`, `CONTACT_EPS=0.1`, `PUSH_FREEZE=0.15`, `PUSH_HOLD_TIME=0.15`, `WIND_FORCE=60.0`

**Scene structure:** Root `Node2D` (script) → `Body` → `AnimatedSprite2D` + `Hitbox`. Root `position` = **hitbox bottom** (Y-sort + movement anchor). `Body` holds visuals/collision at tile-centered layout.

**Hitbox:** `Body/Hitbox` `CollisionShape2D`, `RectangleShape2D` 10×10 at `(0, 8)`. Read in `_ready()` via `YSortHitboxBottom.read_hitbox()`; `_body_offset` computed so hitbox bottom sits on root origin.

**Animation:** `_setup_animations()` builds a `SpriteFrames` resource at runtime from sprite sheets (no editor setup). `_add_sheet(frames, anim, path, cols, rows, count, fps, loop)` creates `AtlasTexture` regions for each frame. Animations: `front_idle` (4×2=8f, 8fps), `front_run` (3×2=6f, 12fps), `side_idle` (3×2=6f, 8fps), `side_run` (3×2=6f, 12fps), `back_idle` (4×2=8f, 8fps), `back_run` (3×2=6f, 12fps), `teleport` (2×2=4f, 12fps, non-looping). `_update_animation(raw, moved_x, moved_y)` picks direction from input, switches between `_idle`/`_run` variants, sets `flip_h = true` for left-facing. `_facing: String` and `_facing_right: bool` track last facing. While `movement_locked`, if the current animation ends with `_run` it is switched to `_facing + "_idle"` (covers ability pickup freeze).

**Squash/stretch:** Applied to `AnimatedSprite2D.scale` on dominant movement axis. Sprite position compensates so the bottom-center of the 32×32 frame stays fixed: `_sprite.position = lag + Vector2(-16 * scale.x, 16 - 32 * scale.y)` where `lag = visual_pos − body_center`.

**Movement (AABB collision):** Root `position` is hitbox bottom. `_hitbox_rect(pos)` = `pos + _body_offset + _hitbox_offset`. Axis-separated movement against `Main.get_player_blocking_rects()`. Pass blocks are not solids. After player input movement, active fan airflow (`is_position_in_airflow(get_body_center())`) applies an additional axis-separated wind displacement at `WIND_FORCE` px/s.

**Push detection:** After movement; single cardinal input; flush against push-block face. Closest block by `_sprite_center()`. On success: `block.push(dir)`, shake (0.8), `PUSH_FREEZE` axis lock, then `Main.record_push(block, from_pos, dir)` to log the move for undo. Push is **gated** by `GameManager.has_ability("push")` — no pushing until that ability is acquired. While in active fan airflow, pushing non-fan blocks directly **against** the wind direction is blocked; pushing with or across the wind (and pushing fans) is always allowed. `_get_fan_airflow_direction()` returns the wind `Vector2i` (or `Vector2i.ZERO` if not in airflow).

**Startup ability grants:** `@export var start_with_push: bool` and `@export var start_with_chain: bool` — if true, the corresponding ability is granted via `GameManager.grant_ability()` in `_ready()` without requiring a pickup.

**Save system:** `@export var save_system_enabled: bool = false`. If `false`, SaveManager auto-activates slot 1 and loads it on start. If `true`, the player manually picks a slot with 1–9. `SaveManager.on_player_ready(save_system_enabled)` is called at the end of `_ready()`.

**Key variables:** `speed_multiplier: float = 1.0` — scales movement velocity; set to `0.8` by TimedObject while it is visible, restored to `1.0` when it hides. `_push_charge_time`, `_push_charge_dir`, `_push_charge_block` — track how long the player has held against a specific block; charge resets if direction/block changes or player moves freely; push fires only after `PUSH_HOLD_TIME=0.15s`. `_facing: String` — current facing direction (`"front"`, `"back"`, `"side"`). `_facing_right: bool` — whether side-facing is right (false = flip_h).

**Key functions:** `get_body_center()` → hitbox center world pos; `_hitbox_rect(pos)`, `_sprite_center()` (hardcoded +Vector2(16,16) for 32×32 frame), `_grid_to_world()` / `_world_to_grid()`, `reset_to(gp)`, `_try_push()`, `_is_in_fan_airflow()`, `_get_fan_airflow_direction()` → `Vector2i`, `_start_push_lock(dir)`, `eject_from_solid()` — BFS from current grid pos to nearest free tile; called every frame in `_process` and at end of `reset_to`; `get_push_hitbox() -> Rect2` — returns `_hitbox_rect(position)`, the shared push-back interface read by `Main`; `push_out(displacement: Vector2)` — translates `position` by `displacement` but leaves `visual_pos` so the sprite lags into place (used by `Main.undo_last_push()` to shove the player off the returning block's tile); `play_teleport(reverse: bool = false)` — plays `"teleport"` animation (or `play_backwards` at `speed_scale=0.5` when `reverse=true`), awaits `animation_finished`, restores idle; used by `Main._complete_teleport()`; `move_to_center(world_center: Vector2)` — places player so hitbox center lands exactly at `world_center` then calls `_eject_from_solid_fine()`; used by `Main.teleport_between_prongs()`; `_eject_from_solid_fine()` — BFS on a 4px grid from the nearest 4px-aligned position outward until the player's hitbox rect doesn't intersect any solid (finer resolution than `eject_from_solid()` which jumps in full 32px tiles); `_try_prong_teleport()` → bool — checks all prongs in group; if exactly 2 exist and player's body center is within 24px of one, calls `Main.teleport_between_prongs()` with the other prong's hitbox center and returns true

**References `Main` via `get_tree().current_scene`** (not `get_parent()`), because the player is reparented under `Walls` at runtime.

---

### Prong.gd (Node2D)
- Group `"prongs"`; same `Body` / hitbox-bottom layout as Player (8×8 hitbox on `Body`)
- `grid_pos: Vector2i` — `floori(position.x / 32), floori(position.y / 32)` (root = hitbox bottom)
- `setup(pixel_pos)` — `pixel_pos` is hitbox center; root placed via `YSortHitboxBottom.root_pos_from_hitbox_center()`; sprite `(-16,-16)`; tweens scale `0 → 1.3 → 1`
- `apply_clear_shrink(s)` — shrink-to-center clear animation (called from `Main.spawn_prong()`)
- **Max 2.** When a third prong is placed, the oldest is removed with a shrink animation (via `apply_clear_shrink`) and the new one takes its place — never clears both at once

---

### Nut.gd (Node2D)
**Purpose:** Pushable conductor. Identical push/reset behaviour to PushBlock (tile top-left node, `SPRITE_OFFSET = (0, 0)`) but also in `"nuts"` group. After slide tween, calls `Main._update_beam()` via `get_tree().current_scene`. `get_beam_point()` returns sprite center. `get_collision_rect()` → 32×32 world `Rect2`. Beam routes through Nuts only when `GameManager.has_ability("chain")`.

**Enemy interaction:** `push(direction)` checks for enemies whose center tile matches the new `grid_pos` and calls `enemy.push(direction)` on them, same as PushBlock.

`push_undo(old_pos)` — same reverse-slide as PushBlock but also fires `_update_beam()` via tween callback (same as normal `push()`).

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
- `push_undo(old_pos: Vector2i)` — reverses a push: teleports node back to `old_pos`, slides sprite from current world position back with the same EASE_OUT/SINE tween
- `reset()` — restores `start_grid_pos`, snaps sprite, clears highlight
- `set_highlight(val)` — enables/disables the pulsing white border drawn via `_draw()`
- `_draw()` — when highlighted, draws an unfilled white rectangle around the block with a ±1px oscillating offset (`sin(time * PI)`, one cycle/s)
- `_clear_all_highlights()` — iterates `"push_blocks"` group; guards with `has_method("set_highlight")` to safely skip Nut nodes

---

### Fan.gd (Node2D)
**Purpose:** Directional fan switch (solid, but NOT pushable). Turns on/off via `GameManager.doors_update` like a door. Blows wind, shows dust particles, and pushes other wind_pushable blocks in its airflow.

**Groups:** `"fans"`, `"push_blocks"`, `"nuts"` (beam chains through fans when chain ability is active, same as Nut/Screw). The `"push_blocks"` membership is for collision/solidity ONLY — fans are NOT pushable because `get_push_block_at_face()` skips the `"fans"` group.

**Constants:** `PUSH_INTERVAL=0.4`, `SLIDE_DURATION=0.15`, `PARTICLE_Z_INDEX=10`, `AIRFLOW_HALF_BAND=16` (32px tile band), `PARTICLE_SPEED_MIN=40`, `PARTICLE_SPEED_MAX=65`

**Grid/push:** `grid_pos` / `start_grid_pos` at tile top-left (same pattern as PushBlock). `get_collision_rect()` → 32×32 world `Rect2`. NOT pushable — `push(dir)`/`push_undo()` remain on the class (teleport node + slide sprite) but are now dead code since `get_push_block_at_face()` never selects a fan.

**Airflow:** `is_position_in_airflow(world_pos)` — same row/column LOS from fan tile; passes through solids; ends at room boundary. `is_active()` reflects door id state.

**Particles:** Persistent `CPUParticles2D` child of `Sprite2D` at runtime. `local_coords=true` so particles ride the sprite during push slide. `z_as_relative=false`, `z_index=10` (above walls). `color=Color.WHITE` (inherits `Main.modulate`). Opaque, no alpha fade. Rectangle emission along airflow corridor. When fan turns off, `_clear_particles()` is called (destroys and recreates the node) so all in-flight particles vanish instantly. Particle config skipped while `_sliding`.

**Airflow push:** `_push_blocks_in_airflow()` — tracks blocks continuously in stream via `_blocks_in_airflow`; first push allowed after `PUSH_INTERVAL` dwell; subsequent pushes gated by static `_block_last_pushed` per instance id.

**Key functions:** `reset()` — restores `grid_pos`, kills slide tween, clears particles; `get_grid_pos()`, `is_active()`, `is_position_in_airflow()`, `push(dir)`, `push_undo(old_pos)` — reverse-slide back to `old_pos` with the same tween pattern as `push()`; `get_beam_point()` → sprite center (used by beam path builder)

---

### DustPile.gd (Node2D)
**Purpose:** Destructible dust pile blown away by fan airflow.

**Group:** `"dust_piles"`

**Behaviour:** When an active fan's airflow covers `get_center()`, shakes for `SHAKE_DURATION=0.8s` then `_dissolve()` spawns one-shot CPUParticles2D on Main and hides sprite. `reset()` restores unless `SaveManager.is_room_solved()` for the pile's room. Solid while visible via `Main._is_static_solid()`.

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
- `@export var id: String` + `@export var id2: String = ""` — matches FloorPanel/door-source IDs; the door registers under each of its ids (`_door_ids()`) and opens when ANY one is active (OR logic, like a floor panel's two ids). `_on_doors_update()` stores each id's state in `_id_active` and calls `set_open(_any_id_active())`
- `@export var starts_open: bool = false` — when true, door starts open (invisible, passable); puzzle activation CLOSES it immediately (sprite grows in, `is_open=false`); puzzle deactivation re-opens it via DoorBall from `GameManager.last_activator_pos`; closing is ignored when room is solved
- **Normal door:** `set_open(true)` fires a DoorBall from the player to the door center; door stays solid until ball arrives; `_do_open()` sets `is_open=true`, emits `shake_requested(5.0)`, shrinks sprite to hidden. `set_open(false)` cancels in-flight open, grows sprite back; ignored when room is solved
- `force_open()` — instantly sets `is_open=true`, hides sprite, kills any in-flight tween; called by SaveManager on room-solve and on load for doors in solved rooms
- `_opening` flag prevents duplicate open transitions
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
- Uses `AnimatedSprite2D` (`$AnimatedSprite2D`); `_setup_animations()` builds `SpriteFrames` at runtime: `idle` (Key_File.webp 7×2=14f, 10fps, looping), `vanish` (Vanish.webp 6×1=6f, 12fps, non-looping)
- `_collect(player)` — notifies KeyDoors, plays `"vanish"` animation, awaits `animation_finished`, then hides sprite
- `reset()` — only resets if a KeyDoor still exists in the same room (door not permanently opened); restores position, scale, sprite.position, replays `"idle"`

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

### PowerOrb.gd (Node2D)
- Group `"power_orbs"`; positioned at tile top-left like other collectibles
- `@export var ability: String` — ability name to grant (e.g. `"push"`)
- Draws a white filled circle (radius 10px) at `(16, 16)` via `_draw()`; hidden after collect
- On collect: grants ability immediately via `GameManager.grant_ability()`, clears all prongs, sets `room_entry_positions[current_room]` to player's grid pos, locks player, starts animation
- On collect: also calls `player.look_up()` (player faces up for duration) and `AudioManager.fade_out_music(0.4)` (music fades to silence over 0.4s)
- **Animation (4.0s total):**
  - Phase 1 (0–3.0s): orb floats 34px upward; 8 tapered spike lines rotate at `TAU * 0.2` rad/s — each is a filled triangle, point at inner radius 14px, base width 7px at outer radius 38px
  - Phase 2 (3.0–4.0s): spike lines hidden; orb radius shrinks to 0 while position lerps to player body center
  - On finish: calls `PowerOrbCounter.add_orb()`, `AudioManager.fade_in_music(0.4)`, unlocks player
- `reset()` — re-shows pickup (does not revoke ability)

---

### PowerOrbCounter.gd (autoload singleton, Node)
- `var count: int` — number of PowerOrbs collected this session
- `signal count_changed(new_count: int)` — emitted by `add_orb()`
- `add_orb()` — increments `count` and emits `count_changed`

---

### OrbDisplay.gd (Node2D)
- Group `"orb_displays"`; positioned at tile top-left; `z_index = -10`; NOT in `Y_SORT_GROUPS` (floor decoration, no depth sort needed)
- No sprite child; all drawing via `_draw()`
- **Inner circle:** radius 8px at tile center `(16, 16)`; drawn filled white when this slot is filled, outline-only otherwise
- **Outer pulsing ring:** radius `11 + sin(time * TAU)` px (±1px, one cycle/s); drawn only when slot is filled
- **Filled determination:** slot is filled when `_get_rank() < PowerOrbCounter.count`; rank = index of this node in all `"orb_displays"` group nodes sorted by `position.y` ascending then `position.x` ascending (topmost object = rank 0, fills first)
- Connects to `PowerOrbCounter.count_changed` signal at `_ready()` for immediate redraw on orb collection

---

### AbilityMessage.gd (CanvasLayer, layer=25)
- Instantiated by Main on `_ready()`; exposed as `main.ability_message`
- Starts hidden (`visible = false`)
- `show_message(text)` — shows overlay immediately; after 2 seconds shows "Press any key to continue..." prompt at the bottom
- Input is only accepted once the prompt is visible; any key/button press dismisses and emits `dismissed`
- `dismissed` signal — previously used to unlock player movement after ability pickup; currently has no active subscribers

---

### AbilityTutorial.gd (autoload singleton, Node)
**Purpose:** Legacy intro animation system. Registered as an autoload singleton but not called from any active game script — PowerOrb.gd now handles its own animation directly.

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

**Save data (JSON at `user://save_slot_N.json`):** player world position, current room, abilities dict, push block/nut grid positions (keyed by `start_grid_pos`), collected keys (by `start_grid_pos`), collected power orbs (by pixel position `[x, y]`; on load: marks orbs `_collected=true`, hides them, sets `PowerOrbCounter.count` and emits `count_changed`), opened KeyDoors, open TeleportPanels, removed BossDoors, boss defeated flag, enemy positions + dead flags, map visited rooms, `music_volume` and `sfx_volume` (floats, restored via `AudioManager.set_music_volume()`/`set_sfx_volume()` on load). `save_quicksave()` writes the same data structure to `user://quicksave.json`. The shared data-building logic lives in `_build_save_data() -> Dictionary`; both `save()` and `save_quicksave()` call it. `_apply_load` guards `_tween` and `sprite` accesses on push_blocks group members with `get()` to safely skip Fan nodes (which are in `"push_blocks"` but lack these properties).

**Load flow:** `load_slot()` → `GameManager.clear_scene_state()` + `reload_current_scene()` → `_process()` detects new scene is ready → `call_deferred("_apply_load", data)` → restores all state silently (no animations/shakes) → calls `Main._update_beam()`. After restoring `player.position`, `_apply_load` immediately syncs `player.visual_pos` so the sprite appears at the correct position rather than lerping from the scene default. `load_quicksave()` uses the same deferred-apply flow but calls `change_scene_to_file("res://scenes/Main.tscn")` instead of reloading, so it works correctly when called from the LevelEditor.

**Auto-slot mode** (`Player.save_system_enabled = false`): `on_player_ready(false)` activates slot 1 for autosaving but does not load any save file — game starts from the scene's default state. Number-key input is disabled. Manual mode (`Player.save_system_enabled = true`): slot 1 is pre-selected by default; user can switch/load/delete slots with number keys.

**Notification hooks** (called by game objects before self-destruction):
- `notify_key_door_opened(gp)` — called from `KeyDoor._open()`
- `notify_boss_door_opened(gp)` — called from `BossDoor.open()`
- `notify_boss_defeated()` — called from `WaterBoss._boss_die()`

**Save import/export/delete:**
- `export_save_string() -> String` — calls `_build_save_data()`, JSON-stringifies, UTF-8 encodes, DEFLATE compresses, base64 encodes (same pattern as LevelEditor export); returns `""` if no active save
- `import_save_string(encoded: String) -> bool` — base64 decodes, DEFLATE decompresses, JSON parses, applies as a load (reloads scene); returns `false` on any decode/parse failure
- `delete_active_save() -> void` — removes save file, resets state, reloads scene

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

### PushUtils.gd (class_name)
**Purpose:** Stateless block-push & actor-shove geometry shared by Main and LevelEditor (so editor playtests match the real game). Callers pass node lists — no scene coupling.

- `rects_overlap_x(a, b)` / `rects_overlap_y(a, b)` → bool — AABB overlap on one axis
- `block_at(blocks, grid_pos)` → Node — push block whose `grid_pos` matches, or null
- `block_at_face(blocks, actor_rect, dir, from_point)` → Node — nearest push block flush against `actor_rect`'s face in `dir` (excludes fans; requires face-aligned overlap)
- `actor_tile(actor)` → `Vector2i` — tile of `actor.get_push_hitbox()` center
- `displace_actor(actor, block_rect, dir)` — slides the actor flush against a block at `block_rect` (shoved in `-dir`) via `actor.push_out()`. Actors implement `get_push_hitbox() -> Rect2` and `push_out(displacement)` (Player, Enemy base class, NanoDroid); `push_out` moves the body but not the sprite's visual var so it lags into place (NanoDroid uses `_sprite_lag`, eased in `_process`) instead of teleporting

---

### GridUtils.gd (class_name)
**Purpose:** Single definition of the 32px world↔tile-grid conversion, used by every object's `get_grid_pos()` and the editor's `world_to_grid`/`grid_to_world`/`tile_rect`. Always **floors** (so it's correct for negative coordinates) — this replaced a mix of `floori(pos/32.0)` and the buggy `int(pos)/32` (which truncates toward zero) that had drifted across ~20 scripts.

- `to_grid(pos: Vector2) -> Vector2i` — world position → containing tile (`floori(pos / TILE_SIZE)`)
- `to_world(gp: Vector2i) -> Vector2` — tile → its top-left world position
- `tile_rect(gp: Vector2i) -> Rect2` — the 32×32 world rect of a tile
- `tile_center(pos: Vector2) -> Vector2` — center of the tile whose top-left is `pos` (used by objects' `get_center()` and beam-objects' `get_beam_point()`)

Not for callers that need an offset: Player's hitbox-center `_world_to_grid` (uses `_body_offset`/`WORLD_OFFSET`), `Enemy`'s ground-offset grid calc, and `Main._world_to_grid` keep their own math. Objects with a cached `grid_pos`/`start_grid_pos` field (Fan, Hole, Screw, Nut, PushBlock, WindBlock) compute it once via `GridUtils.to_grid()` in `_ready()`.

---

### MoveUtils.gd (class_name)
**Purpose:** Stateless collision/movement primitives shared by the actors (Player, NanoDroid, Enemy and its boss subclasses). Callers pass their own hitbox rects and solid lists, so per-actor hitbox shape and include-holes choices stay local.

- `sweep_x(rect, dx, solids, eps=0.1) -> float` / `sweep_y(...)` — largest portion of the axis delta `rect` may move without entering any solid (only perpendicular-overlapping solids count), clamped to stop flush within `eps` and never reverse. Used by `Player._move_axis_x/y`, `NanoDroid._move_axis_x/y`, `Enemy._move_x/y`, `WaterBoss._move_x/y`
- `rect_hits_any(rect, solids) -> bool` — true if rect overlaps any solid; used by the `_is_inside_solid` / eject blocked-checks
- `find_free_cell(origin, is_free) -> Variant` — BFS outward over the 4-connected grid; returns the first cell where `is_free.call(cell)` is true (a `Callable(Vector2i) -> bool` the caller uses to map the cell to a world position and test its own hitbox), or null. Used by the actors' `eject_from_solid` / `_eject_from_solid_fine`

---

### EffectUtils.gd (class_name)
**Purpose:** One-shot particle burst factory.

- `spawn_burst(parent, pos, params)` — creates a fire-and-forget `CPUParticles2D` at `pos` under `parent` that emits once and frees itself after `lifetime + 0.1`. `params` keys (all optional): `z_index, explosiveness, amount, lifetime, velocity_min, velocity_max, gravity, scale_min, scale_max, color, direction, spread`. Used by `BreakableWall._explode`, `DustPile._dissolve`, `NanoDroid._spawn_particles`. (Fan's persistent emitter and Utils' retained UI burst are deliberately *not* routed through this — different lifecycles.)

---

### SerializeUtils.gd (class_name)
**Purpose:** DEFLATE + base64 (de)serialization of a JSON dictionary, shared by save export/import and level export/import.

- `encode_dict(data: Dictionary) -> String` — `JSON.stringify → UTF-8 → compress(DEFLATE) → raw_to_base64`. Used by `SaveManager.export_save_string()` and `LevelEditor._encode_level_data()`
- `decode_to_dict(encoded: String) -> Dictionary` — inverse; returns `{}` on any failure (bad base64 / undecompressable / non-dictionary JSON) so callers treat `is_empty()` as invalid. Used by `SaveManager.import_save_string()` and `LevelEditor._decode_level_string()`

---

### PlayerUtils.gd (class_name)
**Purpose:** Stateless player-vs-world queries. The player implements `get_push_hitbox() -> Rect2`.

- `standing_on(rect: Rect2, player: Node) -> bool` — true if the player's hitbox overlaps `rect`; used by `ExitPoint`/`TeleportPanel` `is_player_standing_on()`
- `is_pressing_into(rect: Rect2, player: Node, margin: float) -> bool` — true if the player is giving movement input and its hitbox overlaps `rect` grown by `margin`; used by `ExitPoint`/`TeleportPanel` `_process()` to accumulate the "press to open" hold timer

---

### BeamUtils.gd (class_name)
**Purpose:** Stateless electric-beam routing & blocker geometry shared by Main, LevelEditor, and ElectricBeam (so editor playtests match the game). Callers pass node lists — no scene coupling. Blocker nodes implement `get_grid_pos() -> Vector2i`; nut nodes implement `get_beam_point() -> Vector2`.

- `nearest_first_beam(blockers, current, target, remaining, path)` → Array — nearest-first DFS over nuts+target, backtracking through dead ends; returns a path of `Vector2` endpoints / `Node2D` nuts, or `[]`. Used by `Main._compute_beam_path()` and `LevelEditor._compute_beam_path()`
- `beam_blockers(blockers, pos_a, pos_b)` → Array — blockers whose tile the segment passes through
- `expand_connected(blockers, seed)` → Array — 4-connected flood-fill from seed blockers (the flash group when the beam is blocked)
- `segment_intersects_rect(a, b, rect)` → bool — segment/AABB test; also used by `ElectricBeam.is_rect_on_beam()`

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

**Constants:** `BOUNCE_MAX_HP=50`, `MOVE_SPEED=0.286`, `SPRITE_LAG_SPEED=24.0`, `WAIT_MIN=0.5`, `WAIT_MAX=0.8`, `SCALE_LERP=15.0`, hop/jump durations and heights, `PATH_RECALC=0.35`

**States:** `IDLE`, `HOP`, `JUMP_WINDUP`, `JUMP`

**Movement:** BFS pathfinding with 4-directional walks and jumps over 1-tile `_is_static_solid` walls; `position` follows flat tile lerp, bounce arc applied as sprite Y offset; no wall AABB collision or `_eject_from_solid()`

**Sprite:** uses the 64×64 `BounceFront.png` (not the inherited Front_Idle1.png). `_sync_sprite()` draws it with its bottom-center anchored at the tile bottom-center (16, 32) and scaling pivoting around that point: `pivot = (16 − 32·scale.x, 32 − 64·scale.y)`, then offset by `−arc − _ground_offset()`. `_rest_sprite_position()` returns that pivot at rest (scale 1, no arc/lag) and is applied in `_ready()` and `reset()` so the sprite sits correctly in the editor — where `_process`/`_sync_sprite` never run (it bails at `electric_beam == null`) — matching the first playtest frame and the placement ghost.

**Juice:** stretch on hop/jump peaks (`HOP_STRETCH`, `JUMP_STRETCH`); landing wait with `sin`-curve squash; `_apply_scale_target()` lerps scale continuously between phases; player-style sprite lag

**Combat:** overrides `_check_beam_and_contact()` — uses inherited `_handle_beam()`; player contact blocked during `JUMP` state (wall-jump arc)

**Group:** `"bounce_enemies"` (also `"enemies"`, `"water_enemies"`)

---

### SpiderEnemy.gd (Node2D)
**Purpose:** Stationary spider that rotates to face the player, lunges, retracts, and enters a stun phase instead of dying.

**Constants:** `SPIDER_MAX_HP=10`, `ROTATE_RADIUS=96.0` (3 tiles), `LUNGE_RADIUS=64.0` (2 tiles), `LUNGE_TRAVEL=96.0`, `LUNGE_DECAY=2.5`, `LUNGE_DURATION=0.5`, `RETRACT_DURATION=2.0`, `ANGLE_STIFFNESS=120.0`, `ANGLE_DAMPING=22.0`, `AIM_TOLERANCE=0.3`, `PRE_LUNGE_TIME=0.2`, `STUN_TIME=8.0`, `COOLDOWN_TIME=0.4`, `PRE_WAKE_TIME=0.8`

**States:** `IDLE → ROTATING → PRE_LUNGE → LUNGING → RETRACTING → COOLDOWN → IDLE`; `STUNNED` replaces death.

**Rotation:** Spring-damper system (`_angle_velocity`) drives `_sprite.rotation = _angle`. On each IDLE→ROTATING transition, `_angle` is synced from `_sprite.rotation` so the spring always starts from the sprite's actual facing direction. Texture faces right at rotation=0, so `_angle = PI/2` = facing down (initial resting pose).

**Lunge:** `_lunge_initial_speed` is computed so the exponential-decay integral over `LUNGE_DURATION` covers exactly `LUNGE_TRAVEL` pixels. Wall collision detected when actual movement < 90% of intended movement; triggers 2px screen shake and transitions to RETRACTING early.

**Retraction:** Smoothstep (`t²(3−2t)`) from `_retract_start_pos` to `_start_pos` over `RETRACT_DURATION`.

**Stun:** `_die()` is overridden to call `_enter_stun()` — no actual death. Spider changes sprite to `switch_open2.png`, stops killing on contact, and wakes after `STUN_TIME`. Pre-wake shake fires once at `PRE_WAKE_TIME` seconds before revival. On wake: HP restored, sprite reverted, retracts to start if displaced.

**Hitbox:** `@onready var _hitbox_col: CollisionShape2D = $HitboxArea/HitboxShape`. `_hitbox()` reads `CircleShape2D.radius` or `RectangleShape2D.size/2` dynamically, so the designer can reshape it in the editor without touching code.

**Key functions:**
- `_handle_beam()` — no-ops in STUNNED state; otherwise delegates to `super._handle_beam()` for normal HP damage
- `_die()` → `_enter_stun()` — overrides WaterEnemy death
- `_wake_from_stun()` — restores HP/sprite/angle, transitions to RETRACTING or COOLDOWN
- `reset()` — calls `super.reset()`, re-applies spider state defaults, restores sprite

**Group:** `"enemies"` (inherited from Enemy.gd via WaterEnemy)

---

### NanoDroid.gd (Node2D)
**Purpose:** Autonomous actor that mirrors the player's movement with **reversed** input. It drifts in fan airflow, can push blocks like the player, and **detonates** when it crosses the electric beam — the blast breaks nearby breakable walls and resets the room if the player is caught in it. Touching the player also resets the room.

**Constants:** `SPEED=217.6` (matches Player), `WIND_FORCE=60.0`, `CONTACT_EPS=0.1`, `BEAM_RADIUS=12.0`, `BREAK_RADIUS=64.0`, `RESET_RADIUS=48.0`, `ROOM_BORDER=16.0` (inset border it can't cross), `PUSH_HOLD_TIME=0.15`, `PUSH_FREEZE=0.15`, `SPRITE_SPEED=20.0`.

**Position/hitbox:** `position` is the 32×32 sprite top-left (tile top-left, like blocks/enemies); the collision hitbox is a small 10×10 box centered on the tile (`_half=5`, `_hitbox_offset=(16,16)`), mirroring the player. `grid_pos` / `get_grid_pos()` via `GridUtils.to_grid`.

**Lifecycle:** Active only while the player is in the droid's home room (`_home_room`, derived from `start_grid_pos`). Re-arms (`reset()`) each time the player (re)enters the room (`_was_current` edge-detect). In the level editor it stays inert until a playtest (the `electric_beam` node only exists then). `_eject_from_solid()` on spawn.

**Movement (`_process`):** Reads the player's input axes, negates them (`input = -raw`), and sweeps via `_move_axis_x/y` (built on `MoveUtils.sweep_x/y`, `include_holes=false`). Then fan-airflow drift (the same continuous push the player receives, `WIND_FORCE`), `_clamp_to_room()`, and sprite-lag easing.

**Pushing:** `_try_push()` mirrors `Player._try_push` — presses into a pushable block (resolved via `_main.get_push_block_at_face`/`PushUtils`) in its movement direction, charges `PUSH_HOLD_TIME`, then `block.push(dir)` with a `PUSH_FREEZE` cooldown, `_trigger_shake`, and `record_push` (so droid pushes are undoable like the player's).

**Push-back interface:** `get_push_hitbox()` / `push_out()` let Main's push-undo shove the droid off a returning block (see Main `undo_last_push` / PushUtils). `push_out` moves the body but offsets `_sprite_lag` so the sprite lags into place and eases back at `SPRITE_SPEED` instead of teleporting (`_sprite_lag` is normally zero, so ordinary movement is unaffected).

**Detonation (`_explode`):** On crossing the active beam (`is_point_on_beam`, `BEAM_RADIUS`): sets `_destroyed`, hides the sprite, `_trigger_shake(1.5)`, spawns an expanding `Line2D` ring (`_spawn_shockwave`) + a particle burst (`_spawn_particles` → `EffectUtils.spawn_burst`), `_triggered`s nearby breakable walls within `BREAK_RADIUS`, and resets the room if the player is within `RESET_RADIUS`.

**Group:** `"nanodroids"` (also listed in `Y_SORT_GROUPS`); resettable via `reset()`.

---

## Level Editor

### Overview

Opened from Main.tscn by pressing **K+C simultaneously** (no other keys held) via `_unhandled_input` in `Main.gd`. Before switching scenes, `SaveManager.save_quicksave()` writes current game state to `user://quicksave.json`. The editor is a fully standalone scene — it does not use Main.gd at all. The **Exit button** in the TopBar calls `SaveManager.load_quicksave()`, which reads the quicksave file, sets `_pending_data`, and calls `change_scene_to_file("res://scenes/Main.tscn")` — `SaveManager._process()` then applies the state once Main is ready (same deferred-apply flow as a normal slot load).

### Scene: `scenes/LevelEditor.tscn`

```
LevelEditor [Node2D, LevelEditor.gd]
├── Camera2D [position=(400,192)]
├── EditorRoom [Node2D]
│   ├── FloorLayer [TileMapLayer, z_index=-2, TileSet_floor — Circuit_Sprite_Sheet.webp auto-tile terrain]
│   ├── BorderWalls [TileMapLayer, TileSet_editor — wall1.png; border tiles only; never faded]
│   ├── Walls [TileMapLayer, TileSet_editor — wall1.png; user-placed interior walls]
│   ├── YSortRoot [Node2D, y_sort_enabled=true — instantiated objects placed here]
│   │   ├── GhostSprite [Sprite2D, visible=false, z_index=20, centered=false — placement preview]
│   │   └── PlayerMarker [Sprite2D, visible=false, z_index=15, centered=false — spawn position marker]
└── EditorUI [CanvasLayer, layer=10]
    ├── TopBar [HBoxContainer — ExitButton, SaveButton, LoadButton, ExportButton, ImportButton; visible only in BUILD mode and hidden in wire mode and play mode]
    ├── Palette [PanelContainer, anchored bottom-center, 22 columns, 2 rows tall]
    │   └── List [GridContainer, columns=22]
    ├── PropertiesPanel [PanelContainer, right side, visible=false]
    │   └── List [VBoxContainer]
    ├── PlacingHint [Label, bottom-center, "Space: Select Object", black outline (outline_size=4)]
    └── Toast [Label, center — fading feedback messages]
```

**TileSets:**
- `TileSet_floor` — `Circuit_Sprite_Sheet.webp`, terrain_set_0 mode=0 ("match_sides"), 14 tiles with peering bits for auto-tiling wire patterns. Used by `FloorLayer`.
- `TileSet_editor` — `wall1.png`, source ID 1. Used by both `BorderWalls` and `Walls`.

### Script: `scripts/LevelEditor.gd`

**Constants:**
- `TILE_SIZE=32`, `ROOM_COLS=25`, `ROOM_ROWS=12`, `ROOM_W=800`, `ROOM_H=384`
- `WALL_SOURCE_ID=1` — source ID for wall tiles in `TileSet_editor`
- `PLAY_COLS=24`, `PLAY_ROWS=11` — safe interior area (excludes border row/col)

**Modes:** `Mode.BUILD` (palette visible, "select" mode — click to select/inspect/drag objects; clicking an EMPTY cell or right-clicking ANY cell seamlessly switches to PLACING via `_enter_placing_from_build()`), `Mode.PLACING` (hint visible, click/drag to place or delete the selected type; Space/Escape returns to BUILD), and `Mode.PLAY` (play-test mode; see Play Mode below). **Wire mode** (`_wire_mode: bool`) is a Boolean overlay on top of BUILD mode that hides the palette and lets the user assign color-coded IDs to ID-capable objects; toggled with E (Escape also exits); Space cycles the active color.

**Eyedropper:** middle-mouse (`_unhandled_input`) or **C** key (`_input`) calls `_eyedropper_at(gp)`, which `_select_type()`s the object (or `"Wall"`, or `"Wires"` when over a floor-wire tile with nothing on top) under the cursor and switches into PLACING with that type ready. Priority: object > wall > floor wire.

**Palette types (22-column grid):**
`Wires` (floor), `Wall`, `Player`, `ExitPoint`, then the remaining SCENE_MAP keys in order: `PushBlock`, `Nut`, `Screw`, `PassBlock`, `LightningBlocker`, `Door`, `FloorPanel`, `FloorPanelNeg`, `KeyDoor`, `Key`, `FanRight`, `FanLeft`, `FanUp`, `FanDown`, `WindTurbine`, `WindBlock`, `DustPile`, `KeyDustPile` (immediately after DustPile), `BreakableWall`, `KeyBreakableWall` (immediately after BreakableWall), `NanoDroid`, `Hole`, `Capacitor` (placed right before the enemies), `WaterEnemy`, `BounceEnemy`, `SpiderEnemy`. `ExitPoint` is `erase()`d from `scene_keys` and inserted manually right after `Player`.
`SpiderEnemy` palette icon rotates `spider_small.png` 90° clockwise (`Image.rotate_90(CLOCKWISE)`). `Door` palette icon uses the first 32×32 frame of `door.webp`.
`BounceEnemy` palette icon is a Button+TextureRect (`clip_contents=true`, `STRETCH_KEEP_ASPECT_CENTERED`) showing the full 64×64 `BounceFront.png` scaled to fit the cell (PALETTE_SPRITES uses `BounceFront.png`, not Front_Idle1.png).
`KeyBreakableWall` and `KeyDustPile` each have a composite palette button (Button containing two overlapping TextureRects: the destructible base — wall_breakable.png / Dust_Pile_Alternate.png — plus Key_File.webp at 50% alpha; only the base layer, child 0, is tinted on highlight).
`KeyDoor` has a special Button+TextureRect button (`clip_contents=true`) showing the full 32×42 first frame bottom-anchored so the door's bottom pixel sits at the button's bottom.
`Capacitor` has the same special Button+TextureRect treatment (`clip_contents=true`) showing the first 32×48 frame bottom-anchored (offset_top=−48) so its bottom pixel sits at the button's bottom; the ghost likewise uses region (0,0,32,48) with `_ghost_position_for` raising it 16px (32−48) so the bottom aligns to the tile bottom.

**Special object types:**
- **Floor** — paints `FloorLayer` using `set_cells_terrain_connect`. When Floor is selected, `walls_tilemap`, `y_sort_root`, and `player_marker` all fade to 20% alpha (`_apply_floor_fade(true)`); `border_walls_tilemap` stays opaque. Painting passes ALL existing floor cells + new cell each update so neighbors are always re-evaluated. Isolated cells with no matching terrain tile get a fallback `set_cell(gp, 0, Vector2i(2,0))`.
- **Wall** — sets tiles directly on `walls_tilemap` (source_id=1, atlas=(0,0)). Border walls are on `border_walls_tilemap` and are generated at startup by `_place_border_walls()`.
- **Player** — places/moves a `PlayerMarker` Sprite2D (not an actual Player scene); records `player_spawn_pos: Vector2i`.
- **KeyBreakableWall** — palette-only convenience type; `_place_object("KeyBreakableWall", gp)` calls `_place_object("BreakableWall", gp)` then `_place_object("Key", gp)` in sequence, reusing the Key-on-destructible stacking logic.
- **KeyDustPile** — palette-only convenience type; `_place_object("KeyDustPile", gp)` calls `_place_object("DustPile", gp)` then `_place_object("Key", gp)`, the dust analogue of KeyBreakableWall.
- **FloorPanelNeg** — instantiates FloorPanel.tscn and sets `positive = false`.
- **KeyDoor** — after `add_child`, `_keys_total` is set to 1 so `_count_keys()` (deferred) never auto-opens the door when there are no keys in the editor. In play mode, `_keys_total` is reset to 0 and `_count_keys()` is re-triggered so the door behaves correctly (opens immediately if no keys, waits for collection otherwise).
- **Key on a destructible** — only legal stacking: `_place_object` (and the BUILD-mode drag-move in `_move_object_to`) allows Key placement when the existing object is a `BreakableWall` or `DustPile`. Key gets `modulate.a=0.5` and `z_index=5` **after** `add_child` (Key._ready() resets z_index to -5, so pre-add assignment is overridden). The editor's stacked-Key transparency restore (`_restore_objects`, `_apply_level_data`) is generic — it dims any Key that shares a cell with another object — so dust+key round-trips through save/load with no special casing.
- **PassBlock** — its sprite (normally hidden in-game) is forced visible at 60% alpha in the editor (`_make_passblock_visible()`, called after add_child, in `_restore_objects()`, in `_apply_level_data()`, and on undo-restore) so designers can see placements.
- **ExitPoint** — EDITOR-ONLY object (see ExitPoint.gd); same sprites/open-on-push behaviour as TeleportPanel, group `"exit_points"`, closed=solid via `_is_static_solid`. While standing on an OPEN ExitPoint in play mode, pressing Space ends the playtest (`_player_on_exit_point()` → `_exit_play_mode()`), and a "SPACE" prompt is shown above the player.

**Placement rules:** `_place_object` rejects out-of-bounds tiles, occupied tiles (`_object_at`, except Key-on-BreakableWall), and **wall tiles** (`walls_tilemap`/`border_walls_tilemap`) — so objects and the player spawn can never be placed on walls. During a left-drag, regular objects place once per empty tile (`_drag_visited` dedupes), so dragging never leaves overlaps and never starts dragging a just-placed block.

**Data model:**
- `placed_objects: Array` — entries `{node: Node, type: String, col: int, row: int}`
- `_object_at(gp)` — returns the **last** entry at `gp` (top-most object; Key is returned before BreakableWall for right-click deletion order)
- `_type_of(node)` — looks up type string by node reference

**Place/delete drag system:**
- `_drag_placing / _drag_deleting: bool` — set on mouse press, cleared on release; pressing one button clears the other so a stuck flag never blocks the opposite action (eraser fix)
- `_drag_visited: Array` — prevents placing the same tile twice in one drag
- `_floor_paint_batch / _floor_erase_batch: Array[Vector2i]` — accumulated floor cells for the current drag; cleared on mode switch
- Right-click (delete) in `_handle_drag_at`, or **holding X** (`_process_x_delete()`, polled each frame like a held right-click), removes whatever is at the cell via `_delete_at()` — object, then wall, then floor wire, then player spawn — regardless of the selected tool. So floor wires can be erased at any time (right-click or X), not only while the Wires tool is selected.

**Object/wall move-drag:** Left-pressing an EXISTING object or wall (in BUILD or PLACING, any selected tool) starts a move-drag instead of placing:
- `_try_start_drag(gp)` begins it (object preferred via `_object_at`, else a `walls_tilemap` cell); `_is_dragging()` = `_obj_drag_node != null or _obj_drag_is_wall`.
- State: `_obj_drag_node`, `_obj_drag_is_wall`, `_obj_drag_start_gp`, `_obj_drag_active` (true once the cursor leaves the start tile).
- `_process_obj_drag()` hides the real thing while dragging (object → `visible=false`; wall → erase its start cell) and shows ONLY the grid-snapped `GhostSprite` under the mouse (object bounds 0..PLAY; wall bounds −1..ROOM).
- `_finalize_obj_drag()`: objects move via `_move_object_to()` (rejects out-of-bounds, occupied, and wall cells) or just select if unmoved; walls re-place at the destination (or restore the original on an invalid drop), recorded as a 2-entry undo batch. `_set_mode` restores an interrupted drag.

**Ghost sprite:** `GhostSprite` (Sprite2D, 45% alpha) follows the mouse in PLACING mode (and during a move-drag) showing the object to be placed. `_apply_ghost_texture_to(spr, type)` sets texture/region (KeyDoor → 32×42; BounceEnemy → full 64×64, region disabled); `_ghost_position_for(type, gp)` bottom-anchors KeyDoor (y−10) and BounceEnemy (x−16, y−32 — centers the 64-wide sprite on the tile and raises it so its bottom-center sits at the tile bottom-center, matching the placed enemy and the first playtest frame). Uses `region_rect` for sprite sheets (first 32×32 frame). Hidden when Wires (floor) is selected.

**Properties panel:** Opens in BUILD mode when clicking a placed object. Shows editable fields for `id`, `id2`, `positive` (via LineEdit / CheckBox widgets) — no "Type:" label.

**Undo:** `Z` (non-play) calls `_undo_last_action()`. `_undo_stack` (Array, max 50) holds `place_obj` / `delete_obj` / `wall` / `floor` / `player_spawn` / `move_obj` / `batch` entries. Floor-wire painting and erasing each push a `floor` entry (only when the cell actually changed) via `_place_floor_at()` / `_erase_floor_at()`, so wire tiles are undoable like every other tile. A drag wraps its actions in one `batch` entry via `_begin_drag_undo_batch()` / `_commit_drag_undo_batch()`. `_apply_level_data` clears the stack.

**Player compatibility stubs / interface** (allow placed object scripts to call main-scene methods without crashing, and support full play mode):
- `shoot_door_ball(_from, _to, callback)` — immediately calls `callback.call()` (no ball animation)
- `player: Node2D` — returns `_play_player` when in play mode, otherwise `_stub_player` (inner class `_PlayerStub extends Node2D` with `get_body_center()→Vector2.ZERO`, `unlock_movement()`, `lock_movement()`)
- `electric_beam: Node` — returns `_play_beam` (used by BreakableWall.gd to check beam contact)
- `check_room_transition(...)`, `_trigger_shake(...)` — no-ops
- `get_player_blocking_rects(area, include_holes := true)`, `can_push_block_to(gp)`, `get_push_block_at(gp)`, `get_push_block_at_face(...)` — functional stubs querying push_blocks group; mirror Main: `get_push_block_at_face` skips the `"fans"` group (fans not pushable), `can_push_block_to` lets a pushable sink into an EMPTY/NANO hole via `_hole_at()`
- `has_pass_block_at(gp)`, `is_blocked(gp)` — functional stubs (pass_blocks group; static solids + push blocks)
- `_is_static_solid(gp, include_holes := true)` — checks `walls_tilemap`, `border_walls_tilemap`, and all game-object groups (doors, key_doors, lightning_blockers, screws, breakable_walls, dust_piles, wind_turbines, enemy_doors, capacitors, closed exit_points, and unfilled holes) so player collision is correct in play mode
- `record_push(block, from, dir)` — no-op stub (Player.gd calls it after each push; prevents a crash during playtest)
- `current_room: Vector2i = Vector2i(0, 0)`

**Bottom-right label** (added programmatically to EditorUI CanvasLayer, right-anchored):
- Edit mode (BUILD/PLACING): `"E: Wire    Q: Play"`
- Wire mode active: `"E: Edit    Q: Play"`
- Play mode: `"Q: Edit"`

**Play Mode:**
- **Entering play mode (Q in BUILD, PLACING, or Wire mode):**
  1. Level data captured in memory (`_play_auto_save_data`) and silently written to `user://levels/auto_save.json` (desktop only).
  2. All placed objects reset via `_restore_objects()`.
  3. Wire IDs applied: for each node in `_wire_assignments`, `node.id = "id" + str(color_index + 1)`.
  4. `GameManager.floor_panels` rebuilt by re-calling `register_floor_panel` for every floor panel (since their `_ready()` registered with empty IDs at placement time).
  5. `GameManager.doors` rebuilt by clearing and re-registering all doors and fans with their new IDs (same reason — `_ready()` registered with empty IDs).
  6. `ElectricBeam.tscn` instantiated and added as child of LevelEditor.
  7. `Player.tscn` instantiated (`start_with_push=true`, `start_with_chain=true`, `save_system_enabled=false`), added to `YSortRoot`, teleported to `player_spawn_pos` (fallback tile 2,2). `GameManager.grant_ability("break")` called.
  8. `PlayerMarker` hidden. All `key_doors` have `_keys_total` reset to 0 and `_count_keys()` called deferred.
  9. Editor UI (palette, props panel, placing hint, ghost, wire overlay) hidden. Mouse input blocked in PLAY (`_unhandled_input` returns early). Wire mode flag cleared.
- **In play mode:** Electric beam uses full nut-chaining and blocker logic (same functions as Main.gd). R resets the room (no CRT effect). Pressing **Space** while standing on an open **ExitPoint** ends the playtest and returns to BUILD/palette; `_update_space_label()` shows a black-outlined "SPACE" Label (`_space_label`, font 11) above `_play_player.visual_pos` each frame while on an open ExitPoint (world→screen via `camera.position`/`offset` + viewport half `(400,192)`).
- **Exiting play mode (Q):**
  1. Prongs cleared from GameManager and freed. Player and beam freed.
  2. `GameManager.clear_scene_state()` called.
  3. Level restored from `_play_auto_save_data` via `_apply_level_data()` — wire assignments rebuilt from position data, no "Loaded!" toast.
  4. `PlayerMarker` visibility restored. Editor returns to BUILD mode.

**Wire mode** (`_wire_mode: bool`):
- **Toggle:** E key (BUILD or PLACING mode); Escape also exits wire mode.
- **On enter:** calls `_set_mode(BUILD)` first (restores objects), then hides `top_bar` and palette, shows placing hint `"Space: Cycle Color"`, sets label to `"E: Edit    Q: Play"`.
- **On exit:** `_set_mode(BUILD)` restores the palette and label.
- **Space:** cycles `_wire_color_index` through `_get_available_color_indices()` — sorted list of all currently-used color indices plus the next unused one.
- **Left-click** on an object with an `id` field: assigns current color index to `_wire_assignments[node]`. **Right-click** removes assignment.
- **Colors:** `WIRE_BASE_COLORS = [BLUE, RED, GREEN, YELLOW]` for indices 0–3 → `id1`–`id4`. Further indices use a seeded RNG (`seed = (idx+1)*7919`) for deterministic colors.
- **Visuals (drawn on `grid_overlay` via `_draw_wire_overlay()`):**
  - Dotted lines (`draw_dashed_line`, width=1.5, dash=6) connect all objects of the same color in their wire color. Path order is determined by `_wire_nearest_neighbor()` which sorts points by x then y — this guarantees no crossing lines within a color group.
  - A colored dot (6px black outline, 6px fill) is drawn at each wired object's tile center, on top of lines.
  - A smaller cursor dot (6px black, 4.5px fill) follows the mouse grid tile. Hidden in play mode.
- **On play enter:** `node.id = "id" + str(color_index + 1)` applied to all assigned nodes, then `GameManager.floor_panels` and `GameManager.doors` are rebuilt (see Play Mode step 4–5 above).
- **Save/load:** `_wire_assignments` serialized as `wire_assignments: {"col,row": color_index}` in the level JSON. Restored in `_apply_level_data()` by matching position to placed objects with `id` fields. Deleted objects have their assignment removed via `_delete_object()`.

**Save/Load/Export/Import:**
- **Save (desktop)**: prompts filename via `AcceptDialog` (label has black outline), writes JSON to `user://levels/<name>.json`. **Load (desktop)**: opens `FileDialog` (ACCESS_USERDATA) pointing at `user://levels/`.
- **Web** (`OS.get_name() == "Web"`): Save triggers a browser file download via JS `Blob` + anchor-click (`_web_download`). Load opens a JS `<input type="file">` picker; the selected file is read by `FileReader` and stored in `window._godotUploadContent`; `_process` polls this variable each frame and calls `_apply_level_data` when content arrives.
- **Export**: on desktop, saves to `user://levels/export.json`; on all platforms, encodes the level as a compact string (`JSON → UTF-8 bytes → DEFLATE compress → base64` via `Marshalls.raw_to_base64`) and displays it in a selectable `TextEdit` dialog (pre-selected, black-outlined label). The encoded string is platform-agnostic and can be shared and pasted into Import on any build.
- **Import**: shows a `TextEdit` paste dialog (black-outlined label); on confirm, decodes the string (`base64 → DEFLATE decompress via decompress_dynamic(-1, …) → JSON`) and calls `_apply_level_data`. Shows "Invalid export code!" toast on decode failure. Works on web and desktop (pure Godot UI, no filesystem).
- All dialog labels are created via `_make_dialog_label(text)` which applies `outline_size=4` and `font_outline_color=BLACK`.
- JSON format: `{player_spawn:{col,row}, walls:[{col,row,source_id,atlas_x,atlas_y}], floor:[{col,row}], objects:[{type,col,row,id?,id2?,positive?}], wire_assignments:{"col,row":color_index}}`
- On load, Key-on-BreakableWall visuals (`modulate.a=0.5`, `z_index=5`) are restored after all objects are added to the scene tree.

**Room reset / restore:** `_restore_objects()` called when returning to BUILD mode — calls `reset()` on placed objects that have it, or snaps position back to grid. Re-applies Key transparency for stacked keys.

### K+C hotkey in Main.gd

`Main._unhandled_input()` detects K+C held simultaneously with no other movement/action keys. It calls `SaveManager.save_quicksave()` first, then `get_tree().change_scene_to_file("res://scenes/LevelEditor.tscn")`.

### SaveManager guard

`SaveManager._process()` has an early-return guard `if not _save_system_enabled: return` that prevents autosave from running in the LevelEditor (which has no real `player` node with position/state to save).

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
      ├── AnimatedSprite2D [centered=false, offset computed per-frame for bottom-center squash anchor]
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
  Node2D [Key.gd, z_index=5 in tscn → overridden to -5 in _ready()]
  ├── AnimatedSprite2D [centered=false; SpriteFrames built at runtime: idle=Key_File.webp, vanish=Vanish.webp]
  └── Sprite2D [key_file4.png, position=(16,16) — hidden in _ready(); palette placeholder only]

PassBlock.tscn:
  Node2D [PassBlock.gd]
  └── Sprite2D [switch_open2.png, centered=false]

PowerOrb.tscn:
  Node2D [PowerOrb.gd]  ← no sprite child; circle + spike lines drawn via _draw()

OrbDisplay.tscn:
  Node2D [OrbDisplay.gd, z_index=-10]  ← no sprite child; circles drawn via _draw()

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
  ├── Sprite2D [WaterEnemy → Front_Idle1.png; BounceEnemy → BounceFront.png (64×64), centered=false]
  └── Particles [CPUParticles2D — one_shot, water_death burst]

SpiderEnemy.tscn:
  Node2D [SpiderEnemy.gd, z_index=5]  ← position at tile top-left
  ├── Sprite2D [spider_small.png, centered=true, position=(16,16) set in _ready(); rotation=_angle]
  ├── Particles [CPUParticles2D — one_shot, death burst]
  └── HitboxArea [Area2D, collision_layer=0, collision_mask=0 — editor-only; not used for physics]
      └── HitboxShape [CollisionShape2D, position=(16,16), CircleShape2D radius≈14 — resize in editor]

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

LevelEditor.tscn:
  LevelEditor [Node2D, LevelEditor.gd]
  ├── Camera2D [position=(400,192)]
  ├── EditorRoom [Node2D]
  │   ├── FloorLayer [TileMapLayer, z_index=-2, TileSet_floor]
  │   ├── BorderWalls [TileMapLayer, TileSet_editor — border walls, never faded]
  │   ├── Walls [TileMapLayer, TileSet_editor — user interior walls, faded when Floor selected]
  │   ├── YSortRoot [Node2D, y_sort_enabled=true]
  │   │   ├── GhostSprite [Sprite2D, visible=false, z_index=20, centered=false]
  │   │   └── PlayerMarker [Sprite2D, visible=false, z_index=15, centered=false]
  ├── GridOverlay [Node2D, z_index=9 — draws grid lines via draw.connect]
  └── EditorUI [CanvasLayer, layer=10]
      ├── TopBar [HBoxContainer, full-width anchor — visible only in BUILD mode]
      │   ├── ExitButton [Button — returns to Main.tscn via SaveManager.load_quicksave()]
      │   ├── SaveButton [Button]
      │   ├── LoadButton [Button]
      │   ├── ExportButton [Button]
      │   └── ImportButton [Button]
      ├── Palette [PanelContainer, bottom-center anchor, ±360px, height 80px]
      │   └── List [GridContainer, columns=22]
      ├── PropertiesPanel [PanelContainer, right anchor, visible=false]
      │   └── List [VBoxContainer]
      ├── PlacingHint [Label, bottom-center anchor, outline_size=4, black outline]
      └── Toast [Label, center anchor — fading save/load feedback]
```

---

## Sprites

All objects use `centered = false`.

| Object | Sprite | Node position |
|---|---|---|
| Player | AnimatedSprite2D (Spark_Front/Back/Side_Idle/Run.webp, Teleport_Spritesheet.webp) | hitbox bottom (body/visual at tile center) |
| Prong | stake.png | hitbox bottom (placed at hitbox center from player) |
| PushBlock | SD_Card_block.png | tile top-left |
| Nut | washer_block.png | tile top-left |
| Door | switch_closed.png | tile top-left |
| FloorPanel | positive.png / negative.png | tile top-left |
| LightningBlocker | resistor_small.png / resistor_small2.png | tile top-left |
| KeyDoor | (door sprite) | tile top-left |
| Key | AnimatedSprite2D (Key_File.webp idle, Vanish.webp on collect) | tile top-left |
| PassBlock | switch_open2.png | tile top-left |
| BreakableWall | wall_breakable.png | tile top-left |
| PowerOrb | (drawn via _draw) | tile top-left |
| OrbDisplay | (drawn via _draw) | tile top-left |
| AbilityGate | TAB.png | tile top-left |
| Enemy | Front_Idle1.png | tile top-left (moves continuously) |
| WaterEnemy / WaterBoss | Front_Idle1.png | tile top-left (moves continuously) |
| BounceEnemy | BounceFront.png (64×64, bottom-center anchored to tile bottom-center) | tile top-left (moves via hops) |
| SpiderEnemy | spider_small.png (centered=true, position=(16,16), rotates via _sprite.rotation) | tile top-left (stationary; lunges then retracts) |
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
- `Camera2D` initialized to the room the player starts in (`_room_center(current_room)`) in `_ready()`; `current_room` is derived from the player's scene position, not hardcoded to `(0,0)`
- **Shake:** decays via `lerpf(..., 0, 20*delta)`; triggered on prong events (5–6 strength), door open (5), block push (0.8)
- **Room transition:** 0.25s tween on `Camera2D.position` (EASE_IN_OUT SINE)
- `CAMERA_MARGIN` of `(16, 16)` added to all room center calculations
- No lean or zoom effects

---

## Feel / Juice Features

| Feature | Where |
|---|---|
| Camera shake on prong/door/push events | Main.gd `_trigger_shake()` |
| Player sprite squash/stretch (bottom-center anchored) | Player.gd `_process` |
| Prong pop animation (scale 0→1.3→1) | Prong.gd `setup()` |
| Prong clear animation (shrink to top-center) | Prong.gd `apply_clear_shrink()`, Main.gd `spawn_prong()` |
| Y-sort depth (hitbox bottom vs tile top) | Main.gd `_setup_y_sort_children()`, YSortHitboxBottom.gd |
| Sprite lag on player move | Player.gd `visual_pos` lerp on `Body/Sprite2D` |
| Sprite lag on enemy move | Enemy.gd `_visual_pos` lerp on `Sprite2D` |
| Push block sprite slide | PushBlock.gd `push()` |
| Fan sprite slide + dust particles ride sprite | Fan.gd `push()`, `local_coords` particles on `Sprite2D` |
| Fan airflow dust particles (32px band, above walls) | Fan.gd `_update_particles()` |
| Fan airflow pushes blocks (0.4s dwell + 0.4s interval, PUSH_INTERVAL) | Fan.gd `_push_blocks_in_airflow()` |
| Player wind displacement (+60px/s in fan LOS) | Player.gd `_process()` |
| Wind blocks player push (fans exempt) | Player.gd `_try_push()`, `_is_in_fan_airflow()` |
| Push directional freeze (0.15s, push axis only) | Player.gd `_start_push_lock()` |
| Closest-block push selection | Main.gd `get_push_block_at_face()` |
| Push pose strains (cycles 1 frame/0.4s) against immovable block | Player.gd `_try_push()` `_push_blocked`, `_update_animation()` `PUSH_STRAIN_FRAME_TIME` |
| Pushables confined to room (16px inset, no edge-tile destinations) | Main.gd `can_push_block_to()` → `_within_room_push_bounds()` `PUSH_ROOM_MARGIN=16` |
| Beam thickness pulse | ElectricBeam.gd `_rebuild_points()` |
| Beam endpoint glow dots | ElectricBeam.gd `_draw()` |
| Pixelated beam (no anti-alias) | ElectricBeam.gd `_ready()` |
| Door flash + shrink-to-center on open | Door.gd `set_open()` |
| Door grow-from-center on close | Door.gd `set_open()` |
| Door opens on either of two ids (OR) | Door.gd `id`/`id2`, `_on_doors_update()`, `_any_id_active()` |
| Floor panel circle outline when active | FloorPanel.gd `_draw()` |
| Blocker texture alternation when blocking | LightningBlocker.gd `_draw()` |
| Blocker spark animation | LightningBlocker.gd `_draw()` |
| Connected blocker propagation | BeamUtils.gd `expand_connected()` (via Main/LevelEditor `_update_beam()`) |
| Beam multi-hop through Nuts (nearest-first) | Main/LevelEditor `_compute_beam_path()` → BeamUtils.gd `nearest_first_beam()` |
| Key collect animation (vanish sprite sheet, non-looping) | Key.gd `_collect()` |
| Player direction-aware animation (front/back/side idle+run, flip for left) | Player.gd `_update_animation()` |
| Player teleport animation (depart forward; arrive reversed at half speed) | Player.gd `play_teleport()`; Main.gd `_complete_teleport()` |
| KeyDoor shrink-to-center on open (same as Door) | KeyDoor.gd `_open()` |
| CRT static on room reset (fade-in 0.56s → hold 0.3s → fade-out 0.22s) | ResetEffect.gd |
| Splash screen on launch | SplashScreen.gd |
| Map overlay slides in/out from top (0.15s SINE) | MapOverlay.gd `_open_map()` / `_close_map()` |
| Floor panel pulsing border highlight (chain tutorial) | FloorPanel.gd `set_highlight()` |
| PowerOrb pickup: float + rotating spike lines → shrink + fly to player | PowerOrb.gd `_update_animation()` |
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
| Settings button (top-right, opens slide-in panel with volume sliders, save export/import/delete, Escape toggles, click-outside closes, triple border, all colors match room tint) | Main.gd `_setup_settings_button()`, `_build_settings_panel()`, `_refresh_settings_colors()`; AudioManager.gd volume API |
| Bounce boss hop squash/stretch + big bounce windup pulse | BounceBoss.gd `_process_hop()`, `_process_big_bounce_windup()` |
| Bounce boss landing screen shake (2px hop, 4px big bounce) | BounceBoss.gd `_process_hop()` / `_process_big_bounce()` → `_main._trigger_shake()` |
| Bounce boss panels relocate every 300 HP (shrink out 0.4s, grow back 0.4s at new tile) | BounceBoss.gd `_check_panel_threshold()` → `_place_panels_randomly(true)`; BounceBossPanel.gd `move_to()` |
| Bounce boss panel prong activation indicator (white arc outline) | BounceBossPanel.gd `_draw()` |
| Spider enemy spring-damper rotation toward player | SpiderEnemy.gd `_angle_velocity` spring (STIFFNESS=120, DAMPING=22) |
| Spider enemy pre-lunge shake (0.2s, 1px) | SpiderEnemy.gd `_start_shake()` on PRE_LUNGE entry |
| Spider enemy exponential-decay lunge (0.5s, 3 tiles) | SpiderEnemy.gd `LUNGING` state, `_lunge_initial_speed` integral formula |
| Spider enemy wall-impact shake (2px screen + 2px sprite) | SpiderEnemy.gd LUNGING wall detection |
| Spider enemy smoothstep retraction to start (2s) | SpiderEnemy.gd `RETRACTING` state `t²(3−2t)` |
| Spider enemy stun: sprite change + no contact kill (8s) | SpiderEnemy.gd `_enter_stun()` / `_wake_from_stun()` |
| Spider enemy pre-wake shake (0.8s before revival) | SpiderEnemy.gd STUNNED state `_shake_timer` guard |
