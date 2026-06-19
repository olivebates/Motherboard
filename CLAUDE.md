# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the Game

There is no build step or test suite. Run the game by launching the Godot 4.5 editor (`Godot_v4.5.1-stable_win64.exe` is in the repo root) and pressing F5, or via the CLI:

```
Godot_v4.5.1-stable_win64.exe --path . res://scenes/Main.tscn
```

## Architecture

See `context.md` for comprehensive documentation of every script, scene, sprite, and mechanic. It is the authoritative reference — read it before making changes.

### Key architectural patterns

**Grid system:** All objects snap to a 32px tile grid. Room size is 25×12 tiles (800×384px). Objects position at tile top-left (`col*32, row*32`). Convert between world and tile coordinates with `GridUtils` (`to_grid`/`to_world`/`tile_rect`) — it floors (correct for negative coordinates), so use it for any object's `get_grid_pos()` rather than re-deriving `floori(pos/32)` (and never `int(pos)/32`, which truncates). Player/Prong are exceptions — their root is at hitbox-bottom for Y-sort; see `YSortHitboxBottom.gd`.

**Y-sorting:** At startup, `Main._setup_y_sort_children()` reparents all gameplay nodes (listed in `Y_SORT_GROUPS`) under the `Walls` TileMapLayer so they depth-sort against wall tiles. Every new interactive object must be added to `Y_SORT_GROUPS` in `Main.gd` and call `add_to_group("its_group")` in `_ready()`.

**Singleton autoloads:** Four singletons handle cross-cutting concerns:
- `GameManager` — puzzle state, abilities, door signals, beam evaluation
- `SaveManager` — save/load slots, persistent room state, scene reload
- `AudioManager` — SFX and music with crossfade
- `Utils` — boss/enemy health bar HUDs
- `AbilityTutorial` — ability intro animations

**Push block pattern:** Pushable objects live in `"push_blocks"` group. `grid_pos` tracks their tile; `push(dir)` teleports the node then sprite-slides to catch up. `get_collision_rect()` returns the 32×32 tile rect at `grid_pos`. Objects that should also be pushed by fans go in `"wind_pushable"` group (Fan.gd queries this — not `"push_blocks"`).

**Solids:** `Main._is_static_solid(grid_pos)` is the authoritative check for walls, doors, and static objects. Push blocks are checked separately via `is_blocked()`. New solid objects must be added to `_is_static_solid()`.

**Beam/puzzle flow:** `Main._update_beam()` → `GameManager.evaluate_puzzle()`. Beam routes from prong A through Nuts/Screws to prong B using nearest-first DFS. Doors open when two prongs land on floor panels sharing an id. `GameManager.doors_update` signal drives Doors, Fans, and WindTurbines.

**Room reset:** `Main._reset_room()` calls `reset()` on all push blocks, fans, enemies, keys, key doors, breakable walls, dust piles, and wind turbines in the scene. Any new resettable object needs a `reset()` method and must be iterated in `_reset_room()`.

**Variable declaration style:** Use `=` not `:=` for variable and constant declarations in GDScript.

### Code reuse & consolidation

Duplicate or near-identical logic — copies that can drift apart — is worth consolidating. This applies especially to logic shared between `Main.gd` and `LevelEditor.gd` (the editor reimplements much of the main scene's interface for playtests), and to the actor scripts (`Player.gd`, `NanoDroid.gd`, `Enemy.gd`).

**Always flag it; never consolidate unprompted — the user makes the call.** Whenever you notice duplicate or similar code that *might* be worth consolidating — whether you're working on it directly or just stumbled across it during an unrelated task — surface it to the user and let them decide. Do **not** extract, merge, or refactor it on your own initiative. Report, at a natural point in your reply (don't derail the current task):
- what the duplicated/similar logic is, and where the copies live (`file:line` for each);
- whether they look **identical** or only **similar**, and any divergence or latent bug you noticed (e.g. one copy floors while another truncates);
- a brief recommendation (consolidate / leave as intentionally-divergent / looks like a bug).

Then wait for the user's judgement. Only when they approve do you change anything. (One exception: code you are *already editing* for the current task may be consolidated as part of that task if it's clearly identical and low-risk — but still mention that you did so.)

When the user approves a consolidation, do it this way:
- Extract the shared logic into a **stateless `class_name` static-helper script**, not a copy-paste and not an autoload. Existing examples: `PushUtils` (block-push / actor-shove geometry), `BeamUtils` (beam routing & blocker geometry), `GridUtils` (world↔tile-grid conversion), `SerializeUtils` (DEFLATE+base64 dict (de)serialization), `PlayerUtils` (player-vs-world queries), `MoveUtils` (axis-sweep / overlap / eject-BFS), `EffectUtils` (one-shot particle bursts), `YSortHitboxBottom` (hitbox-bottom layout math). Helpers take node lists / values as parameters so they have no scene coupling.
- Autoloads are reserved for cross-cutting **state** (`GameManager`, `SaveManager`, `AudioManager`, …). Shared **math/geometry/pure functions** belong in a static helper.
- Keep scene-specific divergence in the scene: only the identical core moves to the helper; `Main` and `LevelEditor` keep thin entry-point methods that forward to it (so existing call sites like `_main.get_push_block_at_face(...)` stay stable).
- After adding a new `class_name` helper from outside the editor, the global class cache won't know it yet. Register it with a reimport: `Godot_v4.5.1-stable_win64.exe --headless --editor --quit` (otherwise it fails with "Identifier ... not declared").
- Update `context.md` to match (file index + a helper section), and remove the now-dead private copies.

**Do not force-merge logic that only *looks* duplicated but is intentionally divergent.** Example: `_is_static_solid()` checks different object sets in `Main` (`teleport_panels`, `boss_doors`) vs the editor (`exit_points`), and `can_push_block_to()` adds room-bounds / pass-tilemap checks only in `Main`. When you spot such divergence, treat it as a possible bug to flag and review — not something to silently unify.
