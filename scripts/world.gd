extends Node2D

## Wires the generator into the scene: builds the tileset, paints it,
## drops the player at spawn, and runs the HUD.
##
## Controls: arrows / A-D to move, Space to jump,
##           hold LMB to dig, RMB to place the selected block,
##           Q switch tool, 1-4 pick a hotbar slot,
##           F toggle background walls, G new seed.

const WORLD_W := 1600
const WORLD_H := 400
const TILE := 16
const SEED_NAME := "cavebound"

const BIOME_NAMES := ["Plains", "Forest", "Desert", "Jungle", "Tundra"]

@onready var tiles_layer: TileMapLayer = $World/Tiles
@onready var walls_layer: TileMapLayer = $World/Walls
@onready var player: CharacterBody2D = $Entities/Player
@onready var loading: Control = $UI/Loading
@onready var status: Label = $UI/Loading/Status
@onready var info: Label = $UI/Info

var gen: WorldGen
var world_seed := 0


func _ready() -> void:
    _generate(SEED_NAME)


func _generate(seed_name: String) -> void:
    loading.visible = true
    status.text = "Generating world..."
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
    info.text = "x %5d   y %4d   depth %4d   %s   %s\n%s" % [
        tx, ty, depth, BIOME_NAMES[biome], tool_text, hotbar]


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
            KEY_F:
                walls_layer.visible = not walls_layer.visible
            KEY_G:
                tiles_layer.clear()
                walls_layer.clear()
                _generate("cavebound-%d" % randi())
