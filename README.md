# Cavebound

A Terraria-like 2D sandbox. **Milestone 2: world generation, walking,
and dig/build with tools, plus procedural caves and dungeons.**

Requires **Godot 4.3+** (uses `TileMapLayer`).

## Install & run

```bash
sudo pacman -S godot          # Arch
godot --editor ~/Projects/cavebound
```

Hit **F5**. The editor will import and register the `class_name` scripts
on first open.

No binary assets ship with the project — the tile art is painted
procedurally at runtime by `TilesetFactory` (per-tile textures with
speckle, cracks, bark, masonry and ore glints, not flat fills), so the
repo is pure text.

## Controls

| Key | Action |
|---|---|
| **A / D** or **Left / Right** | Move |
| **W**, **Up**, or **Space** | Jump (hold for height) |
| **Hold LMB** | Dig the tile under the cursor (within reach) |
| **RMB** | Place the selected block on a supported spot |
| **Q** | Cycle the held tool (pickaxe ↔ axe) |
| **1-4** | Pick a hotbar slot |
| **T** | Teleport to the dungeon gate |
| **C** | Drop into the nearest cave |
| **F** | Toggle background walls |
| **G** | Regenerate with a new seed |

Input is defined as named actions (`move_left`, `move_right`, `jump`) in
`project.godot` rather than using Godot's built-in `ui_*` actions,
because those default to **arrow keys only** — `ui_left` is Left, not A.
Named actions also appear in the editor's Input Map so the keys can be
rebound without touching code. Letters use `physical_keycode`, so WASD
stays under the same fingers on AZERTY/QWERTZ.

## Layout

```
scripts/world_gen.gd       generation passes (only engine dep is FastNoiseLite)
scripts/tileset_factory.gd paints the TileSet art in code (textured, not flat)
scripts/tools.gd           tool + mining table (what digs what, how fast)
scripts/target_cursor.gd   aim outline + mining progress fill
scripts/player.gd          CharacterBody2D controller, dig/build, inventory
scripts/player_art.gd      procedural character frames + held tools
scripts/world.gd           scene wiring, world painting, HUD
scenes/main.tscn           root scene
scenes/player.tscn         player + camera

tools/parse_check.gd   loads every script + scene, fails on parse errors
tools/sprite_test.gd   procedural sprite frames and their wiring
tools/gen_test.gd      worldgen stats + invariant assertions (incl. dungeon)
tools/play_test.gd     boots the scene, asserts tile collision and movement
tools/dig_test.gd      mining, drops, placement rules, tool speeds, HUD
tools/dungeon_probe.gd per-tile ASCII of a dungeon + shaft climbability
tools/world_ascii.gd   ASCII preview of a world, any seed
tools/world_png.gd     renders a world to PNG (overview/crop/dungeon)
tools/noise_probe.gd   measured min/max/mean of each noise field
tools/demo_shots.gd    windowed live capture: injects input, saves screenshots
tools/mouse_probe.gd   how injected mouse events behave on this platform
```

## Tests

```bash
./run_tests.sh                 # uses `godot` from PATH
./run_tests.sh /path/to/godot  # or an explicit binary
```

Six suites: parse/load check, player sprite art (procedural character
frames, tools and their wiring), worldgen invariants (terrain, trees,
caves, and the dungeon gate/shaft), a headless physics test (movement,
jumping, landing, and that trees are walk-through), a digging/building
test (mining drops, placement support/overlap rules, tool-speed table,
HUD text), and a boot smoke test that fails on any engine error.

`run_tests.sh` runs `--import` first on purpose. The `class_name` globals
(`WorldGen`, `TilesetFactory`) only resolve once
`.godot/global_script_class_cache.cfg` exists, and `.godot` is gitignored
— so a fresh clone fails to parse every cross-script reference until that
step runs. Opening the project in the editor does the same thing.

Useful while tuning generation or input:

```bash
godot --headless --path . --script res://tools/world_ascii.gd -- myseed 6
godot --headless --path . --script res://tools/noise_probe.gd
godot --headless --path . --script res://tools/input_dump.gd
godot --headless --path . --script res://tools/dungeon_probe.gd
godot --headless --path . --script res://tools/world_png.gd
godot --path . --script res://tools/demo_shots.gd   # windowed, needs a display
godot --path . -- --goto=dungeon                    # start at the dungeon gate
godot --path . -- --goto=cave                       # start inside a cave
```

## How generation works

`WorldGen.generate(seed, w, h)` fills three flat `PackedByteArray`s
(`tiles`, `walls`, `biomes`) indexed `y * width + x`, in eight passes:

1. **Heightmap** — FBM noise for relief, scaled by a second
   low-frequency field that decides how mountainous a region is. This is
   what produces flat plains next to peaks rather than uniform hills.
2. **Fill** — biome-appropriate surface block, a few tiles of dirt, then
   stone, with bedrock at the bottom.
3. **Caves** — carve where `abs(noise_a) + abs(noise_b)` drops below a
   depth-widening threshold. Requiring *both* fields near zero is what
   makes long connected tunnels instead of disconnected blobs.
4. **Ores** — depth-gated random-walk deposits (copper shallow, gold deep).
5. **Trees** — density per biome. Terraria-style: a straight 1-tile
   trunk that reaches the ground (trees never cut into hillsides - a
   blocked column is skipped rather than truncated), a ragged round
   canopy grown around the trunk top (leaves only fill air, so the
   trunk stays visible up through the crown), and 0-2 side branches
   ending in leaf puffs. 9-15 tiles tall.
6. **Foliage** — grass tufts, wild grass and flowers scattered in the
   air cell directly above grassy/muddy ground. Decorative only
   (`NON_SOLID`), so it can never float, bury itself, or block walking.
7. **Walls** — every air tile below the surface gets a background wall.
8. **Dungeon** — a brick compound is carved 45-65 tiles below the
   surface, 240-420 tiles left or right of the world centre. Rooms are
   grown by a clamped grid walk, joined by straight corridors and a
   climbable zig-zag staircase, and the whole excavation is lined with
   two dilation layers of `DUNGEON_BRICK` against `DUNGEON_WALL`
   backfill. A gated doorway sits on the surface above an entrance shaft
   whose alternating brick treads form a chimney you can jump back up
   one row at a time (the open centre column drops straight down). Runs
   last so the rooms own their background instead of the generic stone
   wall rule.

Same seed in, same world out. ~1s for 1600x400.

## Three Godot 4.3 traps this code hit

**FBM noise does not span [-1, 1].** Measured over a 1600-wide world,
`FastNoiseLite` FBM output spans roughly 0.4-0.7 and its mean is often
off-centre. Tuning constants written against an assumed `[-1,1]` range
produced terrain with an 8-tile height range — visually flat. Each field
is now normalised against its own observed min/max by `_sample_1d()`, so
downstream constants are real fractions of the actual range.

**TileData physics needs two things before it works.** In 4.3 there is no
`set_physics_layers_count()`; you call `add_physics_layer()` (returns
void) and read `get_physics_layers_count() - 1`. But critically, the
source must already be registered with the TileSet via `add_source()`
*before* you touch its `TileData` — otherwise `add_collision_polygon(0)`
fails with `layer_id out of bounds (physics.size() = 0)` and the player
silently falls through the world.

**Injected mouse motion does not move the viewport mouse.** Feeding an
`InputEventMouseMotion` through `Input.parse_input_event()` (or
`Viewport.push_input()`) updates the Input singleton's button state but
leaves `Viewport.get_mouse_position()` — and therefore
`Node2D.get_global_mouse_position()` — untouched; only
`Input.warp_mouse()` updates it. Under XWayland/Sway even a warp can be
undone a frame or two later by a real compositor motion event, so
`tools/demo_shots.gd` re-pins the pointer every frame and falls back to
the same `dig_at()`/`place_tile()` path if a held-button loop still
stalls. See `tools/mouse_probe.gd` for the measurements.

## Next milestones

- [x] **Mining / placing** — hold-LMB digging with per-material tool
      speeds, tile drops into a hotbar, and support/overlap-checked
      placement. Edits go straight through `TileMapLayer.set_cell()`, so
      the built-in tile collision still works.
- [ ] **Lighting** — BFS flood fill from sky + light sources, per-tile
      falloff. Deferred on purpose: it's the highest-rework-risk piece
      because every later system reads the light buffer.
- [ ] **Chunked generation** — the whole world is currently generated and
      painted in one frame-sliced pass (~1s gen + ~1s paint). Split into
      64x64 chunks generated near the camera.
- [ ] Entities, items, crafting, health.

