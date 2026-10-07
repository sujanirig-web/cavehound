class_name Tools
extends RefCounted

## Tool + mining data: which tool digs which material, how long it takes,
## and what you get back. Pure data and pure functions so the player,
## the HUD and the tests all read from one table.
##
## Two tools, Terraria-style: the pickaxe is right for earth and rock,
## the axe is right for trees. Anything can be broken with any tool -
## the wrong one is just slower.

## How close you can dig, measured from the player's centre in tiles.
const REACH_TILES := 4.5

## Held tools, in cycle order (Q).
const NAMES := ["pickaxe", "axe"]
const DEFAULT := "pickaxe"

## Seconds to clear one tile with the neutral tool, by material.
const BASE := {
    "soil": 0.35,
    "leaf": 0.12,
    "wood": 0.50,
    "stone": 0.90,
    "ore": 1.20,
    "brick": 1.60,
}

## Multiplier per tool: below 1 means the right tool for the job.
const SPEED := {
    "pickaxe": {
        "soil": 1.0, "leaf": 1.0, "wood": 1.6,
        "stone": 1.0, "ore": 1.0, "brick": 1.0,
    },
    "axe": {
        "soil": 2.6, "leaf": 0.3, "wood": 0.35,
        "stone": 4.5, "ore": 6.0, "brick": 4.0,
    },
}


## Material group a tile belongs to - what the mining table keys on.
static func category(tile: int) -> String:
    match tile:
        WorldGen.Tile.DIRT, WorldGen.Tile.GRASS, WorldGen.Tile.SAND, \
        WorldGen.Tile.SNOW, WorldGen.Tile.MUD:
            return "soil"
        WorldGen.Tile.WOOD:
            return "wood"
        WorldGen.Tile.LEAVES, WorldGen.Tile.GRASS_TUFT, \
        WorldGen.Tile.WILD_GRASS, WorldGen.Tile.FLOWER:
            return "leaf"
        WorldGen.Tile.COPPER, WorldGen.Tile.IRON, WorldGen.Tile.GOLD:
            return "ore"
        WorldGen.Tile.DUNGEON_BRICK:
            return "brick"
        _:
            return "stone"


## Seconds of holding to clear the tile. INF for what cannot be dug.
static func mining_time(tool: String, tile: int) -> float:
    if tile == WorldGen.Tile.AIR or tile == WorldGen.Tile.BEDROCK:
        return INF
    var cat := category(tile)
    var table: Dictionary = SPEED.get(tool, SPEED[DEFAULT])
    return BASE[cat] * table.get(cat, 1.0)


static func is_diggable(tile: int) -> bool:
    return tile != WorldGen.Tile.AIR and tile != WorldGen.Tile.BEDROCK


## What mining the tile puts in your inventory (-1 = nothing).
## Grass yields dirt, because you cannot place grass back.
static func item_for(tile: int) -> int:
    match tile:
        WorldGen.Tile.GRASS:
            return WorldGen.Tile.DIRT
        WorldGen.Tile.DIRT, WorldGen.Tile.STONE, WorldGen.Tile.SAND, \
        WorldGen.Tile.SNOW, WorldGen.Tile.MUD, WorldGen.Tile.WOOD, \
        WorldGen.Tile.COPPER, WorldGen.Tile.IRON, WorldGen.Tile.GOLD, \
        WorldGen.Tile.DUNGEON_BRICK:
            return tile
        _:
            return -1


static func item_name(item: int) -> String:
    var key: Variant = WorldGen.Tile.find_key(item)
    return str(key).to_lower() if key != null else "?"


static func next_tool(tool: String) -> String:
    var i := NAMES.find(tool)
    return NAMES[(i + 1) % NAMES.size()] if i >= 0 else DEFAULT
