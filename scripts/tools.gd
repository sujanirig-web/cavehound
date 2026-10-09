class_name Tools
extends RefCounted

## Tool + mining data: which tool digs which material, how long it takes,
## and what you get back. Pure data and pure functions so the player,
## the HUD and the tests all read from one table.
##
## Two tools, Terraria-style: the pickaxe is right for earth and rock,
## the axe is right for trees, the hammer is right for background walls.
## Anything can be broken with any tool - the wrong one is just slower.

## How close you can dig, measured from the player's centre in tiles.
const REACH_TILES := 4.5

## Held tools, in cycle order (Q).
const NAMES := ["pickaxe", "axe", "hammer"]
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
    # The hammer's real job is walls (see WALL_SPEED); it is poor at
    # breaking foreground blocks, so players reach for the right tool.
    "hammer": {
        "soil": 3.0, "leaf": 1.5, "wood": 2.5,
        "stone": 3.5, "ore": 4.0, "brick": 3.0,
    },
}

## Seconds to clear one background wall with each tool. The hammer is
## the wall tool: fastest by far. Pickaxe/axe still work, just slower.
const WALL_BASE := 0.30

const WALL_SPEED := {
    "hammer": 1.0,
    "pickaxe": 3.0,
    "axe": 3.5,
}


## Material group a tile belongs to - what the mining table keys on.
static func category(tile: int) -> String:
    match tile:
        WorldGen.Tile.DIRT, WorldGen.Tile.GRASS, WorldGen.Tile.SAND, \
        WorldGen.Tile.SNOW, WorldGen.Tile.MUD:
            return "soil"
        WorldGen.Tile.WOOD, WorldGen.Tile.PLATFORM, WorldGen.Tile.TORCH:
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
        WorldGen.Tile.DUNGEON_BRICK, WorldGen.Tile.PLATFORM, \
        WorldGen.Tile.TORCH:
            return tile
        _:
            return -1


static func item_name(item: int) -> String:
    var key: Variant = WorldGen.Tile.find_key(item)
    return str(key).to_lower() if key != null else "?"


static func next_tool(tool: String) -> String:
    var i := NAMES.find(tool)
    return NAMES[(i + 1) % NAMES.size()] if i >= 0 else DEFAULT


## Seconds of holding to remove the wall at a cell; INF when no wall.
static func wall_time(tool: String, wall_tile: int) -> float:
    if wall_tile == WorldGen.Tile.AIR:
        return INF
    var speed: float = WALL_SPEED.get(tool, 3.0)
    return WALL_BASE * speed


## A background wall item (placeable into the walls layer, not the
## foreground one).
static func is_wall(tile: int) -> bool:
    return tile == WorldGen.Tile.PLANK_WALL or tile == WorldGen.Tile.STONE_WALL


## Crafting: what each crafted item needs, keyed by product id with
## {input item id: count} values. Pure data so the player, HUD and the
## tests all read one table. Chopped trees drop WOOD; STONE comes from
## mining it.
const RECIPES := {
    WorldGen.Tile.PLANK_WALL: {WorldGen.Tile.WOOD: 3},
    WorldGen.Tile.PLATFORM: {WorldGen.Tile.WOOD: 2},
    WorldGen.Tile.TORCH: {WorldGen.Tile.WOOD: 1, WorldGen.Tile.STONE: 1},
}

## Craft order for the B key: always the first affordable recipe.
const RECIPE_ORDER := [
    WorldGen.Tile.PLANK_WALL, WorldGen.Tile.PLATFORM, WorldGen.Tile.TORCH,
]


## First recipe in RECIPE_ORDER the inventory can afford, or -1. This is
## also the "what would I craft" hint the HUD shows.
static func craftable(inventory: Dictionary) -> int:
    for item: int in RECIPE_ORDER:
        if _affordable(inventory, item):
            return item
    return -1


## Crafts the first affordable recipe: consumes the inputs from
## `inventory` (mutated in place) and returns the product to add, or -1
## when nothing can be crafted.
static func craft(inventory: Dictionary) -> int:
    var item := craftable(inventory)
    if item < 0:
        return -1
    var need: Dictionary = RECIPES[item]
    for input_id in need:
        var cost: int = need[input_id]
        var have: int = inventory.get(input_id, 0) - cost
        if have <= 0:
            inventory.erase(input_id)
        else:
            inventory[input_id] = have
    return item


static func _affordable(inventory: Dictionary, item: int) -> bool:
    var need: Dictionary = RECIPES[item]
    for input_id in need:
        var cost: int = need[input_id]
        if inventory.get(input_id, 0) < cost:
            return false
    return true


## "3 wood, 1 stone" - the material list of a recipe, for the HUD.
static func recipe_text(item: int) -> String:
    var need: Dictionary = RECIPES[item]
    var parts := PackedStringArray()
    for input_id in need:
        var cost: int = need[input_id]
        parts.append("%d %s" % [cost, item_name(int(input_id))])
    return ", ".join(parts)
