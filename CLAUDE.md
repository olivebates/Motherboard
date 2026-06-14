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

**Grid system:** All objects snap to a 32px tile grid. Room size is 25×12 tiles (800×384px). Objects position at tile top-left (`col*32, row*32`). Player/Prong are exceptions — their root is at hitbox-bottom for Y-sort; see `YSortHitboxBottom.gd`.

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
