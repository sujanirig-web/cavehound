extends SceneTree

## Functional test for tools: boots the real main scene headlessly and
## verifies digging (data + layer + inventory), gravity reacting to a
## mined floor, placement rules (support, player overlap), and that a
## placed block has collision.
##
##   godot --headless --path . --script res://tools/dig_test.gd
##
## Generation is frame-sliced, so phase 0 waits for the loading overlay.

const T := TilesetFactory.TILE_SIZE

var main: Node
var frames := 0
var phase := 0
var failures: Array[String] = []
var feet := Vector2i.ZERO
var ground_y := 0.0


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
        2: return _dig_under_feet(player)
        3: return _check_fall(player)
        4: return _place_rules(player)
        5: return _check_landing(player)

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
    ground_y = player.global_position.y
    var tx := int(player.global_position.x / T)
    # ceili: the box bottom rests a hair below the floor line, so floor()
    # would report the (possibly decorative) row the feet hang into rather
    # than the solid row the player actually stands on.
    var ty := ceili((player.global_position.y + 11.0) / T)
    feet = Vector2i(tx, ty)
    print("settled at %s, feet tile %s" % [player.global_position, feet])
    phase = 2
    frames = 0
    return false


# -- phase 2: dig the tile out from under the player ------------------

func _dig_under_feet(player: CharacterBody2D) -> bool:
    var world: Node = main
    var ts := main.get_node("World/Tiles") as TileMapLayer
    if ts.get_cell_source_id(feet) == -1:
        failures.append("no tile under the player's feet at %s" % feet)
        return _finish()
    if not player.dig_at(feet):
        failures.append("dig_at refused a reachable solid tile at %s" % feet)
        return _finish()

    if ts.get_cell_source_id(feet) != -1:
        failures.append("mined tile still drawn in the layer at %s" % feet)
    if world.gen.tiles[feet.y * world.gen.width + feet.x] != WorldGen.Tile.AIR:
        failures.append("mined tile still solid in gen data at %s" % feet)
    var total := 0
    for k in player.inventory:
        total += player.inventory[k]
    if total == 0:
        failures.append("mining the surface gave nothing to the inventory")

    print("dug %s, inventory=%s" % [feet, player.inventory])
    phase = 3
    frames = 0
    return false


# -- phase 3: the floor is gone, the player must fall -----------------

func _check_fall(player: CharacterBody2D) -> bool:
    if frames < 60:
        return false
    var fell := player.global_position.y - ground_y
    if fell < 8.0:
        failures.append("player did not fall into the mined hole (%.1f px)"
                % fell)
        return _finish()
    print("fell %.1f px after digging the floor" % fell)
    phase = 4
    frames = 0
    return false


# -- phase 4: placement rules -----------------------------------------

func _place_rules(player: CharacterBody2D) -> bool:
    var world: Node = main
    var ts := main.get_node("World/Tiles") as TileMapLayer
    var dirt := WorldGen.Tile.DIRT

    # a. no support: sky cell with no solid neighbour must refuse
    if world.place_tile(2, 2, dirt):
        failures.append("placed a floating block at (2,2) with no support")

    # b. inside the player's body must refuse
    if world.place_tile(feet.x, feet.y, dirt):
        failures.append("placed a block inside the player's body at %s" % feet)

    # c. lift the player, then the same cell is legal (supported by the
    #    block below the hole, and clear of the body)
    player.velocity = Vector2.ZERO
    player.global_position.y -= 40.0
    if not world.place_tile(feet.x, feet.y, dirt):
        failures.append("placement refused at supported, clear cell %s" % feet)
        return _finish()
    if world.gen.tiles[feet.y * world.gen.width + feet.x] != dirt:
        failures.append("gen data not updated by place_tile at %s" % feet)
    if ts.get_cell_source_id(feet) != 0:
        failures.append("placed block not drawn in the layer at %s" % feet)

    print("placement: float refused, body refused, cell %s filled" % feet)
    phase = 5
    frames = 0
    return false


# -- phase 5: the placed block has collision --------------------------

func _check_landing(player: CharacterBody2D) -> bool:
    if frames < 120:
        return false
    if not player.is_on_floor():
        failures.append("player did not land back after placement "
                + "(the placed block has no collision?)")
        return _finish()
    # Resting on the replaced tile means y is back to the spawn height.
    if absf(player.global_position.y - ground_y) > 1.0:
        failures.append("landed at y=%.1f but started at %.1f - block collision missing"
                % [player.global_position.y, ground_y])

    _check_tools(player)
    print("landed back at y=%.1f (started %.1f)"
            % [player.global_position.y, ground_y])
    return _finish()


# -- tool table sanity (runs inside phase 5) --------------------------

func _check_tools(player: CharacterBody2D) -> void:
    if not is_inf(Tools.mining_time("pickaxe", WorldGen.Tile.BEDROCK)):
        failures.append("bedrock must be undiggable")
    if not is_inf(Tools.mining_time("axe", WorldGen.Tile.AIR)):
        failures.append("air must have no mining time")
    if Tools.mining_time("axe", WorldGen.Tile.STONE) \
            <= Tools.mining_time("pickaxe", WorldGen.Tile.STONE):
        failures.append("axe is not slower than pickaxe on stone")
    if Tools.mining_time("axe", WorldGen.Tile.WOOD) \
            >= Tools.mining_time("pickaxe", WorldGen.Tile.WOOD):
        failures.append("axe is not faster than pickaxe on wood")
    if Tools.item_for(WorldGen.Tile.GRASS) != WorldGen.Tile.DIRT:
        failures.append("mining grass must yield dirt")

    var next := Tools.next_tool("pickaxe")
    if next == "pickaxe" or Tools.NAMES.find(next) == -1:
        failures.append("cycle_tool does not leave the pickaxe")

    # the HUD lines the world label renders must not crash
    var hud: String = player.hud_tool_text() + player.hud_hotbar_text()
    if hud.length() == 0:
        failures.append("HUD text is empty")

    # aim cursor accepts state
    var aim := player.get_node_or_null("Cursor")
    if aim == null:
        failures.append("aim cursor node missing from player.tscn")
    else:
        aim.set_aim(Vector2i(3, 4), 0.5, true)
        if aim.target != Vector2i(3, 4) or not aim.shown:
            failures.append("aim cursor did not take the target")
    print("tools ok: %s | %s" % [player.hud_tool_text(), player.hud_hotbar_text()])


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
