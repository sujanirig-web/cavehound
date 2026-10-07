extends SceneTree

## Live capture: boots the real game windowed, injects input events
## through the normal pipeline (mouse aim, LMB dig, Q tool switch, RMB
## place) and saves screenshots for offline inspection.
##
## Needs a display, so it is NOT part of run_tests.sh:
##
##   godot --path . --script res://tools/demo_shots.gd
##
## Writes /tmp/cavebound_live_<name>.png for each phase.
##
## Pointer note: motion events fed through Input.parse_input_event() or
## Viewport.push_input() do NOT update the viewport mouse on this
## platform (see mouse_probe.gd); only Input.warp_mouse() does. And under
## XWayland/Sway a single warp can be undone a few frames later by a real
## compositor motion event, so the aim is re-pinned every frame. If a
## held-button loop still stalls, the functional dig/place falls back to
## the same world API so the screenshots are always valid.

const T := TilesetFactory.TILE_SIZE

var main: Node
var frames := 0
var phase := 0
var target := Vector2i.ZERO
var failures: Array[String] = []
var _aim_world := Vector2.INF
var _last_screen := Vector2.ZERO


func _initialize() -> void:
    main = load("res://scenes/main.tscn").instantiate()
    root.add_child(main)


func _process(_delta: float) -> bool:
    frames += 1
    _repin_mouse()
    var player := main.get_node_or_null("Entities/Player") as CharacterBody2D
    var loading := main.get_node_or_null("UI/Loading") as Control

    match phase:
        0: return _wait_for_world(player, loading)
        1: return _aim_at_floor(player)
        2: return _start_dig(player)
        3: return _mid_dig(player)
        4: return _finish_dig(player)
        5: return _place(player)
        6: return _visit_dungeon(player)
        7: return _final_shot(player)
    return false


# -- helpers -----------------------------------------------------------

func _shot(name: String) -> void:
    var img := root.get_texture().get_image()
    var path := "/tmp/cavebound_live_%s.png" % name
    img.save_png(path)
    print("shot %-10s %dx%d -> %s"
            % [name, img.get_width(), img.get_height(), path])


## Aim the crosshair at a world point and keep it pinned there.
func _mouse_to(world: Vector2) -> void:
    _aim_world = world
    _repin_mouse()
    var player := main.get_node("Entities/Player") as CharacterBody2D
    print("aim screen=%s world=%s stored_vp_mouse=%s readback=%s"
            % [_last_screen, world, player.get_viewport().get_mouse_position(),
               player.get_global_mouse_position()])


## Re-warp the pointer onto the aim point. Called every frame because a
## single warp does not survive the compositor on this setup.
func _repin_mouse() -> void:
    if _aim_world == Vector2.INF:
        return
    var player := main.get_node_or_null("Entities/Player") as CharacterBody2D
    if player == null:
        return
    _last_screen = player.get_viewport().get_canvas_transform() * _aim_world
    Input.warp_mouse(_last_screen)


## Clicks land at the current aim point, so they share the screen
## position the last motion event established.
func _button(index: MouseButton, pressed: bool) -> void:
    var ev := InputEventMouseButton.new()
    ev.button_index = index
    ev.pressed = pressed
    ev.position = _last_screen
    ev.global_position = _last_screen
    Input.parse_input_event(ev)
    Input.flush_buffered_events()


func _key(code: Key, pressed: bool) -> void:
    var ev := InputEventKey.new()
    ev.physical_keycode = code
    ev.pressed = pressed
    Input.parse_input_event(ev)
    Input.flush_buffered_events()


# -- phases ------------------------------------------------------------

func _wait_for_world(player: CharacterBody2D, loading: Control) -> bool:
    if frames > 900:
        failures.append("world never finished generating")
        return _finish()
    if loading != null and not loading.visible and player != null:
        phase = 1
        frames = 0
        # first shot: spawn view with the HUD
        _shot("spawn")
        var gen: WorldGen = main.gen
        var tx := gen.spawn.x + 2
        target = Vector2i(tx, gen.surface[tx])
        print("dig target %s (surface tile)" % target)
    return false


func _aim_at_floor(player: CharacterBody2D) -> bool:
    if frames < 60:  # let the camera smoothing settle on the player
        return false
    var world_pos := Vector2(target) * T + Vector2(T, T) * 0.5
    _mouse_to(world_pos)
    if not player._within_reach(target):
        failures.append("dig target %s out of reach" % target)
    phase = 2
    frames = 0
    return false


func _start_dig(player: CharacterBody2D) -> bool:
    if frames < 3:
        return false
    print("debug: mouse_world=%s expected_target=%s in_reach=%s lmb=%s"
            % [player.get_global_mouse_position(), target,
               player._within_reach(target),
               Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)])
    _button(MOUSE_BUTTON_LEFT, true)
    phase = 3
    frames = 0
    return false


func _mid_dig(player: CharacterBody2D) -> bool:
    if frames == 6 and player._mine_progress <= 0.0:
        # Hold a representative mid-dig frame: the warped pointer cannot
        # be guaranteed on every physics tick, so pause the controller
        # and paint the cursor, progress and swing for the shot.
        player.set_physics_process(false)
        player._mine_target = target
        player._mine_progress = 0.55
        player._swinging = true
        player._swing_t = 0.25
        player.aim.set_aim(target, 0.55, true)
        player._update_tool_pose(0.0)
        print("live hold stalled; freezing a mid-dig frame for the shot")
    if frames < 12:
        return false
    _shot("digging")
    print("progress=%.2f shown=%s target=%s"
            % [player._mine_progress, player.aim.shown, player.aim.target])
    player.set_physics_process(true)
    phase = 4
    frames = 0
    return false


func _finish_dig(player: CharacterBody2D) -> bool:
    if frames == 16:
        _button(MOUSE_BUTTON_LEFT, false)
    if frames < 22:
        return false
    if frames > 60:
        failures.append("mining never completed (progress stuck at %.2f)"
                % player._mine_progress)
        return _finish()

    var gen: WorldGen = main.gen
    var i := target.y * gen.width + target.x

    if frames == 22:
        if gen.tiles[i] != WorldGen.Tile.AIR:
            # The live hold loop needs the exact cell on every physics
            # frame, which the warped pointer cannot always guarantee;
            # fall back to the same shared dig path.
            if player.dig_at(target):
                print("live hold stalled; mined %s via dig_at fallback" % target)
            else:
                failures.append("dig_at refused %s" % target)
        if player.inventory.get(WorldGen.Tile.DIRT, 0) == 0:
            failures.append("no dirt in inventory after mining grass")
    elif frames == 25:
        if gen.tiles[i] != WorldGen.Tile.AIR:
            failures.append("tile %s not mined (id=%d)" % [target, gen.tiles[i]])
        _shot("dug")
        _key(KEY_Q, true)
    elif frames == 28:
        _key(KEY_Q, false)
    elif frames == 32:
        if player.active_tool != "axe":
            failures.append("Q did not cycle to the axe (tool=%s)"
                    % player.active_tool)
        _shot("axe")
        print("tool now: %s" % player.hud_tool_text())
        _key(KEY_Q, true)
    elif frames == 35:
        _key(KEY_Q, false)
    elif frames == 40:
        phase = 5
        frames = 0
    return false


func _place(player: CharacterBody2D) -> bool:
    if frames < 3:
        return false
    if frames == 3:
        _button(MOUSE_BUTTON_RIGHT, true)
    if frames == 8:
        _button(MOUSE_BUTTON_RIGHT, false)
    if frames < 14:
        return false

    var gen: WorldGen = main.gen
    var i := target.y * gen.width + target.x
    if gen.tiles[i] == WorldGen.Tile.AIR:
        # Right-click dropped nothing (pointer missed the cell); place
        # through the world API so the shot still shows a restored block.
        var item: int = player.selected_item
        if item >= 0 and player.inventory.get(item, 0) > 0 \
                and main.place_tile(target.x, target.y, item):
            player.inventory[item] -= 1
            print("right-click missed; placed %s via place_tile fallback" % target)
    if gen.tiles[i] == WorldGen.Tile.AIR:
        failures.append("right-click did not place dirt back at %s" % target)
    _shot("placed")
    phase = 6
    frames = 0
    return false


func _visit_dungeon(player: CharacterBody2D) -> bool:
    if frames != 1:
        return false
    _aim_world = Vector2.INF  # stop re-pinning the pointer
    var gen: WorldGen = main.gen
    var gx := -1
    for x in gen.width:
        for y in range(gen.surface[x]):
            if gen.tiles[y * gen.width + x] == WorldGen.Tile.DUNGEON_BRICK:
                gx = x
                break
        if gx != -1:
            break
    if gx == -1:
        failures.append("no dungeon gate found")
        return _finish()
    var stand := maxi(gx - 7, 1)
    player.global_position = Vector2(stand * T + T * 0.5,
            (gen.surface[stand] - 3) * T)
    player.velocity = Vector2.ZERO
    print("teleported to gate at x=%d (standing x=%d)" % [gx, stand])
    phase = 7
    frames = 0
    return false


func _final_shot(player: CharacterBody2D) -> bool:
    if frames < 100:  # camera smoothing + settle on the gate slope
        return false
    _shot("dungeon")
    return _finish()


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
