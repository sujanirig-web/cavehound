extends SceneTree

## Functional test for the building milestone: background-wall placement
## and removal rules, torch placement (including hanging on a wall), and
## platform physics - the one-way top strip means you can jump up through
## a platform and land on top of it, never pass down through it.
## Plus the crafting table and the hammer tool.
##
##   godot --headless --path . --script res://tools/build_test.gd
##
## Generation is frame-sliced, so phase 0 waits for the loading overlay.

const T := TilesetFactory.TILE_SIZE

var main: Node
var frames := 0
var phase := 0
var failures: Array[String] = []
var feet := Vector2i.ZERO


func _initialize() -> void:
    main = load("res://scenes/main.tscn").instantiate()
    root.add_child(main)


func _process(_delta: float) -> bool:
    frames += 1
    var player := main.get_node_or_null("Entities/Player") as CharacterBody2D
    var loading := main.get_node_or_null("UI/Loading") as Control

    match phase:
        0: return _wait_for_world(player, loading)
        1: return _settle(player)
        2: return _rule_table(player)
        3: return _walls(player)
        4: return _torches(player)
        5: return _platform_place(player)
        6: return _platform_jump(player)
        7: return _platform_rest(player)

    return false


# -- phase 0: wait for generation -------------------------------------

func _wait_for_world(player: CharacterBody2D, loading: Control) -> bool:
    if frames > 900:
        failures.append("world never finished generating (loading still up)")
        return _finish()
    if loading != null and not loading.visible and player != null:
        phase = 1
        frames = 0
    return false


# -- phase 1: stand still on spawn ground -----------------------------

func _settle(player: CharacterBody2D) -> bool:
    if frames < 90:
        return false
    if not player.is_on_floor():
        failures.append("player not resting on the floor after 90 frames")
        return _finish()
    var tx := int(player.global_position.x / T)
    var ty := ceili((player.global_position.y + 11.0) / T)
    feet = Vector2i(tx, ty)
    print("settled at %s, feet tile %s" % [player.global_position, feet])
    phase = 2
    frames = 0
    return false


# -- phase 2: tool table + crafting (pure functions, no world) --------

func _rule_table(player: CharacterBody2D) -> bool:
    if Tools.NAMES.find("hammer") == -1:
        failures.append("hammer missing from Tools.NAMES")
    var t := Tools.next_tool("axe")
    if t != "hammer":
        failures.append("Q cycle does not reach the hammer from the axe")
    if Tools.wall_time("hammer", WorldGen.Tile.PLANK_WALL) \
            >= Tools.wall_time("pickaxe", WorldGen.Tile.PLANK_WALL):
        failures.append("hammer is not the fastest wall tool")
    if not is_inf(Tools.wall_time("hammer", WorldGen.Tile.AIR)):
        failures.append("wall_time on an empty cell must be INF")
    if not Tools.is_wall(WorldGen.Tile.PLANK_WALL) \
            or not Tools.is_wall(WorldGen.Tile.STONE_WALL):
        failures.append("plank/stone walls not flagged as wall items")
    if Tools.is_wall(WorldGen.Tile.DIRT):
        failures.append("dirt is not a wall item")
    if Tools.category(WorldGen.Tile.PLATFORM) != "wood" \
            or Tools.category(WorldGen.Tile.TORCH) != "wood":
        failures.append("platform/torch not in the wood category")
    if Tools.item_for(WorldGen.Tile.PLATFORM) != WorldGen.Tile.PLATFORM \
            or Tools.item_for(WorldGen.Tile.TORCH) != WorldGen.Tile.TORCH:
        failures.append("platform/torch must drop as themselves")

    # Crafting: first affordable recipe in fixed order, inputs consumed.
    var inv := {WorldGen.Tile.WOOD: 5, WorldGen.Tile.STONE: 1}
    if Tools.craftable(inv) != WorldGen.Tile.PLANK_WALL:
        failures.append("5 wood must first craft a plank wall (3 wood)")
    if Tools.craft(inv) != WorldGen.Tile.PLANK_WALL:
        failures.append("craft did not produce a plank wall")
    if inv.get(WorldGen.Tile.WOOD, 0) != 2:
        failures.append("plank wall craft did not consume 3 wood: %s" % inv)
    if Tools.craftable(inv) != WorldGen.Tile.PLATFORM:
        failures.append("2 wood left must next craft a platform")
    if Tools.craft(inv) != WorldGen.Tile.PLATFORM:
        failures.append("craft did not produce a platform")
    if Tools.craftable(inv) != -1:
        failures.append("no materials left but a recipe is affordable: %s" % inv)
    if Tools.craft(inv) != -1:
        failures.append("craft succeeded with no materials: %s" % inv)

    var inv2 := {WorldGen.Tile.WOOD: 1, WorldGen.Tile.STONE: 1}
    if Tools.craftable(inv2) != WorldGen.Tile.TORCH:
        failures.append("wood+stone must craft a torch")
    if Tools.craft(inv2) != WorldGen.Tile.TORCH:
        failures.append("torch craft failed")
    var recipe: String = Tools.recipe_text(WorldGen.Tile.TORCH)
    if not recipe.contains("wood") or not recipe.contains("stone"):
        failures.append("torch recipe text wrong: %s" % recipe)

    # The B-key wiring: player._craft() uses the same table and banks the
    # product into the hotbar.
    player.set_tool("hammer")
    if player.hud_tool_text() != "hammer (Q)":
        failures.append("hud tool text did not reflect the hammer")
    player.set_tool(Tools.DEFAULT)
    player.inventory = {WorldGen.Tile.WOOD: 4}
    player.selected_item = -1
    player._craft()
    if player.inventory.get(WorldGen.Tile.PLANK_WALL, 0) != 1 \
            or player.inventory.get(WorldGen.Tile.WOOD, 0) != 1:
        failures.append("player._craft() did not bank a plank wall: %s"
                % player.inventory)
    if player.selected_item != WorldGen.Tile.PLANK_WALL:
        failures.append("crafted item not auto-selected")
    var craft_hud: String = player.hud_craft_text()
    if craft_hud.length() == 0:
        failures.append("craft HUD line is empty")

    print("tools + crafting ok; craft HUD: %s" % craft_hud)
    phase = 3
    frames = 0
    return false


# -- phase 3: background wall rules ------------------------------------

func _walls(player: CharacterBody2D) -> bool:
    var tiles := main.get_node("World/Tiles") as TileMapLayer
    var walls := main.get_node("World/Walls") as TileMapLayer

    # a. a wall floating in open sky must be refused
    if main.place_wall(3, 2, WorldGen.Tile.PLANK_WALL):
        failures.append("placed a floating wall at (3,2)")

    # b. find a clean column next to the spawn and wall up from the
    #    surface, then chain a second wall above the first
    var wx := _clear_column(feet.x + 2)
    if wx < 0:
        failures.append("no clean column found for wall tests")
        return _finish()
    var gy := feet.y
    if not main.place_wall(wx, gy - 1, WorldGen.Tile.PLANK_WALL):
        failures.append("wall refused at the surface (%d, %d)" % [wx, gy - 1])
        return _finish()
    if main.gen.walls[(gy - 1) * main.gen.width + wx] != WorldGen.Tile.PLANK_WALL:
        failures.append("wall data not updated at (%d, %d)" % [wx, gy - 1])
    if walls.get_cell_source_id(Vector2i(wx, gy - 1)) == -1:
        failures.append("wall not drawn in the walls layer at (%d, %d)" % [wx, gy - 1])
    if not main.place_wall(wx, gy - 2, WorldGen.Tile.PLANK_WALL):
        failures.append("wall-to-wall chaining refused at (%d, %d)" % [wx, gy - 2])

    # c. a solid block cell can't take a wall
    if main.place_wall(wx, gy, WorldGen.Tile.PLANK_WALL):
        failures.append("placed a wall into a solid block at (%d, %d)" % [wx, gy])

    # d. mining the wall gives it back as an item
    var got: int = main.mine_wall(wx, gy - 1)
    if got != WorldGen.Tile.PLANK_WALL:
        failures.append("mine_wall returned %d, expected %d"
                % [got, WorldGen.Tile.PLANK_WALL])
    if main.gen.walls[(gy - 1) * main.gen.width + wx] != WorldGen.Tile.AIR:
        failures.append("mined wall still set in gen data at (%d, %d)" % [wx, gy - 1])
    if walls.get_cell_source_id(Vector2i(wx, gy - 1)) != -1:
        failures.append("mined wall still drawn at (%d, %d)" % [wx, gy - 1])

    print("walls ok: surface attach, chaining, block refusal, mine-back")
    phase = 4
    frames = 0
    return false


# -- phase 4: torch placement ------------------------------------------

func _torches(_player: CharacterBody2D) -> bool:
    var tiles := main.get_node("World/Tiles") as TileMapLayer
    var gy := feet.y

    # a. floating torch in open sky must be refused
    if main.place_tile(3, 2, WorldGen.Tile.TORCH):
        failures.append("placed a floating torch at (3,2)")

    # b. next to the ground: solid support below
    var tx := _clear_column(feet.x + 2)
    if tx < 0:
        failures.append("no clean column found for torch tests")
        return _finish()
    if not main.place_tile(tx, gy - 1, WorldGen.Tile.TORCH):
        failures.append("torch refused beside the ground at (%d, %d)" % [tx, gy - 1])
        return _finish()
    if main.gen.tiles[(gy - 1) * main.gen.width + tx] != WorldGen.Tile.TORCH:
        failures.append("torch data not updated at (%d, %d)" % [tx, gy - 1])
    if tiles.get_cell_source_id(Vector2i(tx, gy - 1)) == -1:
        failures.append("torch not drawn at (%d, %d)" % [tx, gy - 1])

    # c. a torch can hang on a background wall with no block behind it
    var wx := _clear_column(tx + 2)
    if wx < 0:
        failures.append("no clean column found for wall-hung torch")
        return _finish()
    if not main.place_wall(wx, gy - 1, WorldGen.Tile.STONE_WALL):
        failures.append("wall for torch test refused at (%d, %d)" % [wx, gy - 1])
        return _finish()
    if not main.place_tile(wx, gy - 1, WorldGen.Tile.TORCH):
        failures.append("torch could not hang on the wall at (%d, %d)" % [wx, gy - 1])

    print("torches ok: float refused, ground support, wall-hang")
    phase = 5
    frames = 0
    return false


# -- phase 5: platform placement + teleport under it -------------------

func _platform_place(player: CharacterBody2D) -> bool:
    var tiles := main.get_node("World/Tiles") as TileMapLayer
    var gy := feet.y

    if main.place_tile(3, 2, WorldGen.Tile.PLATFORM):
        failures.append("placed a floating platform at (3,2)")

    var fx := _clear_column(feet.x + 2)
    if fx < 0:
        failures.append("no clean column found for platform tests")
        return _finish()
    if not main.place_tile(fx, gy - 1, WorldGen.Tile.PLATFORM):
        failures.append("platform refused beside the ground at (%d, %d)" % [fx, gy - 1])
        return _finish()
    if main.gen.tiles[(gy - 1) * main.gen.width + fx] != WorldGen.Tile.PLATFORM:
        failures.append("platform data not updated at (%d, %d)" % [fx, gy - 1])
    if tiles.get_cell_source_id(Vector2i(fx, gy - 1)) == -1:
        failures.append("platform not drawn at (%d, %d)" % [fx, gy - 1])
    # a second platform directly below proves platforms support platforms
    if not main.place_tile(fx, gy - 2, WorldGen.Tile.PLATFORM):
        failures.append("platforms cannot chain as support at (%d, %d)" % [fx, gy - 2])

    # park the player directly under the chain, on the ground
    player.velocity = Vector2.ZERO
    player.global_position = Vector2((fx + 0.5) * T, feet.y * T - 11.0)
    _ledge_top = Vector2i(fx, gy - 2)
    print("platforms placed, chain top at %s; player parked under it"
            % _ledge_top)
    phase = 6
    frames = 0
    return false


var _ledge_top := Vector2i.ZERO


# -- phase 6: jump through the platform --------------------------------

func _platform_jump(player: CharacterBody2D) -> bool:
    if frames == 1:
        player.velocity = Vector2(0, player.JUMP_VELOCITY)
    if frames < 180:
        return false
    print("after jump: y=%.1f floor=%s under=%s"
            % [player.global_position.y, player.is_on_floor(),
            main.gen.tiles[_ledge_top.y * main.gen.width + _ledge_top.x]])
    phase = 7
    return false


# -- phase 7: resting on top of the platform ---------------------------

func _platform_rest(player: CharacterBody2D) -> bool:
    var rest_top := _ledge_top.y * T - 11.0
    if not player.is_on_floor():
        failures.append("player is not resting after the jump-through")
    elif absf(player.global_position.y - rest_top) > 2.0:
        failures.append(("player rests at y=%.1f, expected platform top %.1f "
                + "(one-way collision missing?)")
                % [player.global_position.y, rest_top])
    if main.gen.tiles[_ledge_top.y * main.gen.width + _ledge_top.x] \
            != WorldGen.Tile.PLATFORM:
        failures.append("platform was lost during the jump")
    print("platform physics ok: jumped through, landed on top at y=%.1f"
            % player.global_position.y)
    return _finish()


# -- shared helpers ------------------------------------------------------

## First column at or after from_x where the cell just above the surface
## row is open air (no block, no wall) and the surface row itself is
## solid, so placement rules start from a clean slate.
func _clear_column(from_x: int) -> int:
    var gy := feet.y
    for x in range(from_x, from_x + 16):
        var above: int = (gy - 1) * main.gen.width + x
        var ground: int = gy * main.gen.width + x
        if main.gen.tiles[above] == WorldGen.Tile.AIR \
                and main.gen.walls[above] == WorldGen.Tile.AIR \
                and TilesetFactory.SOLID.has(main.gen.tiles[ground]):
            return x
    return -1


func _finish() -> bool:
    print("\n-- result --")
    if failures.is_empty():
        print("  all checks passed")
        quit(0)
    else:
        for f in failures:
            print("  FAIL: %s" % f)
        quit(1)
    return true