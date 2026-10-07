# Cavebound — Agent Instructions

Terraria-like 2D sandbox for **Godot 4.3** (uses `TileMapLayer`). Standard GDScript
build — the project is **GDScript only**, no C#/.NET (so no mono-specific addons).

## Before writing code

- Run `./run_tests.sh` after any script/scene change. Seven suites: parse check,
  sprite art, worldgen invariants + dungeon, physics, dig/build, mobs & npcs, boot smoke.
  (`play_test`/`dig_test` run with `--no-creatures` so legacy movement/digging
  expectations see a clean world; the mob suite and real boots keep creatures.)
- The repo is pure text: all tile art is painted procedurally at runtime by
  `scripts/tileset_factory.gd`. Never add binary assets.
- World generation must stay deterministic: same seed → same world
  (`WorldGen.generate(seed, w, h)`).
- `scripts/world_gen.gd` and `scripts/world.gd` may have local uncommitted work —
  inspect before rewriting.
- Update `README.md`'s next-milestones when a milestone lands.

## GodotPrompter skills (installed via this project's opencode.json)

56 Godot 4.x skills live in `~/.local/share/opencode/godot-prompter/skills` and are
registered as agent skills for this project. Load them on demand with the `skill`
tool. Start with **`using-godot-prompter`** for the routing card, then pick
task-specific ones:

| Task | Skill(s) |
|---|---|
| Player / movement / input | `player-controller`, `input-handling`, `state-machine` |
| World gen / caves / tiles | `procedural-generation`, `resource-pattern` |
| Digging / inventory / tools | `inventory-system`, `event-bus` |
| Lighting (planned) | `2d-essentials`, `shader-basics`, `godot-optimization` |
| Code review | `godot-code-review` |
| Project layout / architecture | `godot-project-setup`, `scene-organization`, `godot-brainstorming` |

## Godot MCP (installed in this project's opencode.json)

A `godot` MCP server (`@coding-solo/godot-mcp`) can launch the editor / run the
project / capture debug output and manage scenes. Use it to verify behavior in
Godot itself rather than guessing. It targets `godot` at
`/home/sagiri/.local/bin/godot` via `GODOT_PATH`.

## Conventions

- Named input actions (`move_left`, `move_right`, `jump`) exist in `project.godot`
  — don't switch to built-in `ui_*` actions.
- Geometry: tile index is `y * width + x` on flat `PackedByteArray`s inside
  `world_gen.gd`.
- Keep code small and necessary; the project's style is minimal, deterministic,
  well-tested systems.