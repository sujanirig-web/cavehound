extends Node2D

## Wires the generator into the scene: builds the tileset, paints it,
## drops the player at spawn, and runs the HUD.
##
## Controls: arrows / A-D to move, Space to jump,
##           hold LMB to dig (or hit a mob under the cursor),
##           RMB to place the selected block,
##           Q switch tool, 1-4 pick a hotbar slot,
##           E talk to a nearby npc,
##           F toggle background walls, G new seed,
##           T jump to the dungeon gate, C drop into a cave.
## Launch with `-- --goto=dungeon` (or `--goto=cave`) to start there, or
## `-- --no-creatures` for a world without slimes/npcs (used by tests).

const WORLD_W := 1600
const WORLD_H := 400
const TILE := 16
const SEED_NAME := "cavebound"

const BIOME_NAMES := ["Plains", "Forest", "Desert", "Jungle", "Tundra"]

const MOB_SCENE := preload("res://scenes/mob.tscn")
const NPC_SCENE := preload("res://scenes/npc.tscn")

## Walk-through decorative tiles that may sit right above the ground row.
const DECOR := [
    WorldGen.Tile.GRASS_TUFT,
    WorldGen.Tile.WILD_GRASS,
    WorldGen.Tile.FLOWER,
]

## Creatures populating a generated world. Layout is derived from the
## world seed, so the same seed always spawns the same slimes/npcs.
const SLIME_COUNT := 8
const NPC_COUNT := 2
const MOB_HALF_H := 5.0   # half the slime's collision box height
const NPC_HALF_H := 11.0  # half the villager's collision box height

@onready var tiles_layer: TileMapLayer = $World/Tiles
@onready var walls_layer: TileMapLayer = $World/Walls
@onready var player: CharacterBody2D = $Entities/Player
@onready var loading: Control = $UI/Loading
@onready var status: Label = $UI/Loading/Status
@onready var info: Label = $UI/Info

var gen: WorldGen
var world_seed := 0
var slime_kills := 0

## One-shot HUD line set by the teleporters; cleared on regenerate.
var hud_flash := ""


func _ready() -> void:
    _generate(SEED_NAME)


func _generate(seed_name: String) -> void:
    loading.visible = true
    status.text = "Generating world..."
    hud_flash = ""
    # Let the loading screen actually paint before we block the thread.
    await get_tree().process_frame

    world_seed = abs(hash(seed_name))
    gen = WorldGen.new()
    gen.generate(world_seed, WORLD_W, WORLD_H)

    var ts := TilesetFactory.build()
    tiles_layer.tile_set = ts
    walls_layer.tile_set = ts

    await _paint()

    player.global_position = Vector2(gen.spawn) * TILE + Vector2(TILE, TILE) * 0.5
    player.world = self
    var cam := player.get_node("Camera2D") as Camera2D
    cam.limit_left = 0
    cam.limit_top = 0
    cam.limit_right = WORLD_W * TILE
    cam.limit_bottom = WORLD_H * TILE
    cam.reset_smoothing()

    loading.visible = false

    if not OS.get_cmdline_user_args().has("--no-creatures"):
        spawn_creatures()

    var args := OS.get_cmdline_user_args()
    if args.has("--goto=dungeon"):
        _teleport_to_dungeon()
    elif args.has("--goto=cave"):
        _teleport_to_cave()


## Column-major so consecutive writes land near each other in memory,
## yielding to the frame between batches to keep the window responsive.
func _paint() -> void:
    for x in WORLD_W:
        for y in WORLD_H:
            var i := y * WORLD_W + x
            var w: int = gen.walls[i]
            if w != WorldGen.Tile.AIR:
                walls_layer.set_cell(Vector2i(x, y), 0,
                        TilesetFactory.atlas_coords(w))
            var t: int = gen.tiles[i]
            if t != WorldGen.Tile.AIR:
                tiles_layer.set_cell(Vector2i(x, y), 0,
                        TilesetFactory.atlas_coords(t))

        if x % 64 == 0:
            status.text = "Painting world...  %d%%" % (x * 100 / WORLD_W)
            await get_tree().process_frame


func _process(_delta: float) -> void:
    if gen == null or loading.visible:
        return

    var tx := int(player.global_position.x / TILE)
    var ty := int(player.global_position.y / TILE)
    var cx := clampi(tx, 0, WORLD_W - 1)
    var cy := clampi(ty, 0, WORLD_H - 1)
    var biome: int = gen.biomes[cy * WORLD_W + cx]
    var depth := ty - gen.surface[cx]

    var tool_text: String = player.hud_tool_text()
    var hotbar: String = player.hud_hotbar_text()
    info.text = "x %5d   y %4d   depth %4d   %s   HP %d/%d   %s\n%s\nslimes slain: %d" % [
            tx, ty, depth, BIOME_NAMES[biome], player.hp, player.MAX_HP,
            tool_text, hotbar, slime_kills]
    if hud_flash != "":
        info.text += "\n" + hud_flash


## Breaks a tile and returns the item picked up (-1 = nothing).
## Refuses bedrock and anything already empty; underground holes keep a
## stone wall behind them so you never see raw sky underground.
func mine_tile(tx: int, ty: int) -> int:
    if tx < 0 or ty < 0 or tx >= WORLD_W or ty >= WORLD_H:
        return -1
    var i := ty * WORLD_W + tx
    var id: int = gen.tiles[i]
    if not Tools.is_diggable(id):
        return -1
    gen.tiles[i] = WorldGen.Tile.AIR
    tiles_layer.set_cell(Vector2i(tx, ty))
    if ty >= gen.surface[tx] + 2:
        gen.walls[i] = WorldGen.Tile.STONE_WALL
        walls_layer.set_cell(Vector2i(tx, ty), 0,
                TilesetFactory.atlas_coords(WorldGen.Tile.STONE_WALL))
    else:
        gen.walls[i] = WorldGen.Tile.AIR
        walls_layer.set_cell(Vector2i(tx, ty))
    return Tools.item_for(id)


## Puts a tile back. Needs one solid four-neighbour for support (no
## floating blocks) and must not overlap the player's body.
func place_tile(tx: int, ty: int, item: int) -> bool:
    if tx < 1 or ty < 1 or tx >= WORLD_W - 1 or ty >= WORLD_H - 1:
        return false
    var i := ty * WORLD_W + tx
    if gen.tiles[i] != WorldGen.Tile.AIR:
        return false
    var supported := false
    for n in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
        var j: int = (ty + n.y) * WORLD_W + (tx + n.x)
        if TilesetFactory.SOLID.has(gen.tiles[j]):
            supported = true
            break
    if not supported or _overlaps_player(tx, ty):
        return false
    gen.tiles[i] = item
    tiles_layer.set_cell(Vector2i(tx, ty), 0, TilesetFactory.atlas_coords(item))
    return true


func _overlaps_player(tx: int, ty: int) -> bool:
    var half := Vector2(5, 11)  # matches the player's collision shape
    var body := Rect2(player.global_position - half, half * 2.0)
    return body.intersects(Rect2(tx * TILE, ty * TILE, TILE, TILE))


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        match event.keycode:
            KEY_T:
                _teleport_to_dungeon()
            KEY_C:
                _teleport_to_cave()
            KEY_E:
                talk_nearby()
            KEY_F:
                walls_layer.visible = not walls_layer.visible
            KEY_G:
                tiles_layer.clear()
                walls_layer.clear()
                _generate("cavebound-%d" % randi())


# ------------------------------------------------------------- creatures

## Populate the world: a spread of slimes across the surface either side
## of spawn plus a couple of friendly villagers near spawn. Derives
## every spot from the world seed so the same seed gives the same world,
## and refuses tree trunks, hillsides and the spawn column itself.
func spawn_creatures() -> void:
    clear_creatures()
    if gen == null:
        return
    var rng := RandomNumberGenerator.new()
    rng.seed = world_seed
    var spawn_x: int = gen.spawn.x
    var used := {}

    var placed := 0
    var guard := 0
    while placed < SLIME_COUNT and guard < 400:
        guard += 1
        var x := spawn_x + rng.randi_range(-350, 350)
        if x < 2 or x >= gen.width - 2 or absi(x - spawn_x) < 8 \
                or used.has(x):
            continue
        var sy: int = gen.surface[x]
        if not _surface_spot(x, sy):
            continue
        _spawn_slime(x, sy)
        used[x] = true
        placed += 1

    var village := [spawn_x - 20, spawn_x + 32]
    var npc_done := 0
    guard = 0
    var side := 0
    while npc_done < NPC_COUNT and guard < 80:
        guard += 1
        var x: int = village[side % village.size()]
        side += 1
        if x < 2 or x >= gen.width - 2:
            continue
        var sy: int = gen.surface[x]
        if _surface_spot(x, sy) and npc_done < NPC_COUNT:
            _spawn_npc(x, sy)
            npc_done += 1


func clear_creatures() -> void:
    for m in get_tree().get_nodes_in_group("mobs"):
        m.queue_free()
    for n in get_tree().get_nodes_in_group("npcs"):
        n.queue_free()


## A valid creature spot: solid ground with two clear rows above (grass
## tufts / flowers count as clear - they're walk-through decor), so
## nothing spawns inside a trunk, under a ledge, or in the sky.
func _surface_spot(x: int, sy: int) -> bool:
    if sy < 8 or sy >= gen.height - 4:
        return false
    var ground: int = gen.tiles[sy * gen.width + x]
    if not TilesetFactory.SOLID.has(ground):
        return false
    var above: int = gen.tiles[(sy - 1) * gen.width + x]
    if above != WorldGen.Tile.AIR and not DECOR.has(above):
        return false
    if gen.tiles[(sy - 2) * gen.width + x] != WorldGen.Tile.AIR:
        return false
    return true


func _spawn_slime(x: int, sy: int) -> void:
    var mob := MOB_SCENE.instantiate() as CharacterBody2D
    mob.world = self
    $Entities.add_child(mob)
    # Park the collision box bottom exactly on the floor line.
    mob.global_position = Vector2((x + 0.5) * TILE, sy * TILE - MOB_HALF_H)


func _spawn_npc(x: int, sy: int) -> void:
    var npc := NPC_SCENE.instantiate() as CharacterBody2D
    npc.world = self
    $Entities.add_child(npc)
    npc.global_position = Vector2((x + 0.5) * TILE, sy * TILE - NPC_HALF_H)
    # _ready() already ran (add_child) before the position was set, so the
    # villager's wander anchor must be handed to it from the spawn point.
    npc.anchor = npc.global_position


## Nearest mob within ~3/4 tile of a world point, or null.
func mob_at(pos: Vector2) -> Node:
    for m in get_tree().get_nodes_in_group("mobs"):
        if (m as Node2D).global_position.distance_to(pos) <= 12.0:
            return m
    return null


## A mob died: count the kill and flash the HUD. (Slime gel drops can
## hang off this hook later.)
func on_mob_killed(_mob: Node) -> void:
    slime_kills += 1
    hud_flash = "Slime slain!  (%d slain)" % slime_kills


## E next to a villager: cycle one of its lines into the HUD.
func talk_nearby() -> bool:
    if player == null or player.world == null:
        return false
    var best: Node = null
    var best_d := INF
    for n in get_tree().get_nodes_in_group("npcs"):
        var d: float = (n as Node2D).global_position.distance_to(player.global_position)
        if d < best_d:
            best_d = d
            best = n
    if best == null or best_d > TILE * 4.0:
        return false
    hud_flash = best.talk()
    return true


## Player died: back to spawn at full health.
func respawn_player() -> void:
    player.heal_full()
    _stand_on(gen.spawn.x, gen.surface[gen.spawn.x])
    _snap_camera()
    hud_flash = "You died... and woke up at spawn"


# ------------------------------------------------------------- teleporting

func _snap_camera() -> void:
    var cam := player.get_node("Camera2D") as Camera2D
    cam.reset_smoothing()


## Park the player on top of a solid ground row: the body centre sits
## 11px above the cell top so the feet rest exactly on it.
func _stand_on(cx: int, gy: int) -> void:
    player.velocity = Vector2.ZERO
    player.global_position = Vector2((cx + 0.5) * TILE, gy * TILE - 11.0)


## Drop the player into the middle of an air cell inside a cave.
func _drop_into(cx: int, cy: int) -> void:
    player.velocity = Vector2.ZERO
    player.global_position = Vector2((cx + 0.5) * TILE, (cy + 0.5) * TILE)


## Teleport to the surface just outside the dungeon door, so the gate is
## on screen. The door faces the approach side (dir==1: door on the west
## side of the gate, dungeon to the east).
func _teleport_to_dungeon() -> void:
    if gen == null or gen.dungeon_entrance_x < 0:
        hud_flash = "no dungeon this seed - press G to reseed"
        return
    var gx := gen.dungeon_entrance_x
    var land_x: int = clampi(gx - 3 if gen.dungeon_dir == 1 else gx + 3, 1, WORLD_W - 2)
    _stand_on(land_x, gen.surface[land_x])
    _snap_camera()
    hud_flash = "Dungeon gate at x=%d - it is to your %s" % [
            gx, "RIGHT" if gen.dungeon_dir == 1 else "LEFT"]


## Scan outward from the world centre for the first underground pocket
## the player actually fits in (air above and below the body's middle
## cell, solid floor), then drop them into it.
func _teleport_to_cave() -> void:
    if gen == null:
        return
    var found := Vector2i(-1, -1)
    for dx: int in range(gen.width / 2):
        for sx: int in [gen.width / 2 - dx, gen.width / 2 + dx]:
            if sx < 1 or sx >= gen.width - 1:
                continue
            for y: int in range(mini(gen.surface[sx] + 12, gen.height - 3), gen.height - 3):
                var i: int = y * gen.width + sx
                if gen.tiles[i] != WorldGen.Tile.AIR:
                    continue
                if gen.tiles[i - gen.width] != WorldGen.Tile.AIR:
                    continue  # no headroom
                if gen.tiles[i + gen.width] == WorldGen.Tile.AIR:
                    continue  # no floor to stand on
                found = Vector2i(sx, y)
                break
            if found.x >= 0:
                break
        if found.x >= 0:
            break
    if found.x < 0:
        hud_flash = "no cave found nearby - press G to reseed"
        return
    _drop_into(found.x, found.y)
    _snap_camera()
    hud_flash = "Inside a cave at (%d, %d) - dig your way out" % [found.x, found.y]
