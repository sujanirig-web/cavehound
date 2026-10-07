extends SceneTree

## Functional test: boots the real main scene headlessly and verifies
## player movement, jumping, tile collision, and that trees are
## walk-through.
##
##   godot --headless --path . --script res://tools/play_test.gd
##
## Generation + painting is frame-sliced, so this waits for the loading
## overlay to clear before touching anything.

const T := TilesetFactory.TILE_SIZE
const JUMP_MIN_RISE := 20.0

var main: Node
var frames := 0
var phase := 0
var start_x := 0.0
var ground_y := 0.0
var peak_y := 0.0
var trunk_x := -1
var failures: Array[String] = []


func _initialize() -> void:
    main = load("res://scenes/main.tscn").instantiate()
    root.add_child(main)


func _process(_delta: float) -> bool:
    frames += 1

    var player := main.get_node_or_null("Entities/Player") as CharacterBody2D
    var loading := main.get_node_or_null("UI/Loading") as Control

    match phase:
        0: return _wait_for_world(player, loading)
        1: return _check_settle(player)
        2: return _check_walk(player)
        3: return _reset_to_ground(player)
        4: return _track_jump(player)
        5: return _check_jump(player)
        6: return _setup_tree_test(player)
        7:
            # let the player drop onto the ground next to the trunk
            if frames < 45:
                return false
            phase = 8
            frames = 0
            start_x = player.global_position.x
            Input.action_press("move_right")
            return false
        8:
            if frames < 90:
                return false
            Input.action_release("move_right")
            return _check_tree_passed(player)

    return false


# -- phase 0: wait for generation and painting ------------------------

func _wait_for_world(player: CharacterBody2D, loading: Control) -> bool:
    if frames > 900:
        failures.append("world never finished generating (loading still up)")
        return _finish()
    if loading != null and not loading.visible and player != null:
        phase = 1
        frames = 0
    return false


# -- phase 1: gravity + tile collision --------------------------------

func _check_settle(player: CharacterBody2D) -> bool:
    if frames < 90:
        return false

    if player.global_position.y > 400 * T:
        failures.append("player fell out of the world (y=%.0f)"
                % player.global_position.y)
        return _finish()

    if not player.is_on_floor():
        failures.append("player is not resting on a floor after 90 frames "
                + "(y=%.1f, vy=%.1f) - tile collision is missing"
                % [player.global_position.y, player.velocity.y])
        return _finish()

    var feet := Vector2i(
            int(player.global_position.x / T), int(player.global_position.y / T) + 1)
    var ts := main.get_node("World/Tiles") as TileMapLayer
    if ts.get_cell_source_id(feet) == -1:
        failures.append("no tile under the player's feet at %s" % feet)

    _check_sprite(player)

    print("settled at %s  on_floor=%s  vy=%.2f"
            % [player.global_position, player.is_on_floor(), player.velocity.y])
    ground_y = player.global_position.y
    start_x = player.global_position.x
    phase = 2
    frames = 0
    Input.action_press("move_right")
    return false


# -- phase 1b: the character is actually drawn ------------------------

func _check_sprite(player: CharacterBody2D) -> void:
    var sprite := player.get_node_or_null("Sprite") as AnimatedSprite2D
    if sprite == null:
        failures.append("player has no Sprite node - the character is invisible")
        return
    if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation("idle"):
        failures.append("player sprite has no frames assigned in _ready()")
        return
    if not sprite.is_playing():
        failures.append("player sprite is not playing any animation")
    # Feet must sit on the collision box bottom: player origin + half the
    # box height. Anything else and the character floats or sinks.
    var feet := sprite.global_position.y + 11.0
    var soles := sprite.global_position.y + sprite.offset.y + PlayerArt.H * 0.5
    if absf(feet - soles) > 0.51:
        failures.append("sprite feet at y=%.1f but collision bottom at y=%.1f - the character floats"
                % [soles, feet])
    print("sprite playing \"%s\" at %d fps, feet y=%.1f (box bottom %.1f)"
            % [sprite.animation,
               int(sprite.sprite_frames.get_animation_speed(sprite.animation)),
               soles, feet])


# -- phase 2: horizontal movement -------------------------------------

func _check_walk(player: CharacterBody2D) -> bool:
    if frames < 90:
        return false
    Input.action_release("move_right")

    var moved := player.global_position.x - start_x
    print("walked right %.1f px in 90 frames" % moved)
    if moved < 40.0:
        failures.append("move_right produced almost no movement (%.1f px)" % moved)

    phase = 3
    frames = 0
    return false


# -- phase 3: return to known solid ground ----------------------------

## The walk test can leave the player on a ledge or mid-fall, which makes
## the jump measurement meaningless. Put them back on the spawn column
## and wait for a clean standstill before testing the jump.
func _reset_to_ground(player: CharacterBody2D) -> bool:
    var gen: WorldGen = main.gen
    if frames == 1:
        player.velocity = Vector2.ZERO
        player.global_position = Vector2(gen.spawn.x * T + T / 2,
                gen.surface[gen.spawn.x] * T - 2 * T)
    if frames < 180 and not player.is_on_floor():
        return false
    ground_y = player.global_position.y
    peak_y = ground_y
    print("reset to ground, y=%.1f on_floor=%s" % [ground_y, player.is_on_floor()])
    phase = 4
    frames = 0
    Input.action_press("jump")
    return false


# -- phase 4/5: jump --------------------------------------------------

func _track_jump(player: CharacterBody2D) -> bool:
    peak_y = minf(peak_y, player.global_position.y)
    # Release after ~20 frames so the variable-jump-cut path is exercised
    # rather than only the full-height case.
    if frames == 20:
        Input.action_release("jump")
    if frames < 90:
        return false

    Input.action_release("jump")
    return _check_jump(player)


func _check_jump(player: CharacterBody2D) -> bool:
    var rise := ground_y - peak_y
    print("jump rose %.1f px (ground y=%.1f, peak y=%.1f)" % [rise, ground_y, peak_y])
    if rise < JUMP_MIN_RISE:
        failures.append("jump barely moved the player (%.1f px) - is the "
                % rise + "jump action bound?")
    if not player.is_on_floor():
        failures.append("player did not land back on the floor after jumping")

    phase = 6
    frames = 0
    return false


# -- phase 5/6/7: walk through a tree ---------------------------------

## Nearest tree trunk to spawn. Solid trunks used to make forests
## impassable, so this is the regression guard for that bug.
func _find_trunk() -> int:
    var gen: WorldGen = main.gen
    var sx: int = gen.spawn.x
    for d in range(2, 220):
        for x in [sx + d, sx - d]:
            if x < 1 or x >= gen.width - 1:
                continue
            var sy: int = gen.surface[x]
            for y in range(sy - 1, sy - 12, -1):
                if gen.tiles[y * gen.width + x] == WorldGen.Tile.WOOD:
                    return x
    return -1


func _setup_tree_test(player: CharacterBody2D) -> bool:
    trunk_x = _find_trunk()
    if trunk_x == -1:
        failures.append("no tree trunk found anywhere near spawn")
        return _finish()

    var gen: WorldGen = main.gen
    # Drop the player a few tiles to the left of the trunk, on the surface.
    var x: int = maxi(trunk_x - 4, 1)
    player.global_position = Vector2(x * T + T / 2, gen.surface[x] * T)
    player.velocity = Vector2.ZERO
    print("tree trunk at x=%d, dropped player at x=%d" % [trunk_x, x])
    phase = 7
    frames = 0
    return false


func _check_tree_passed(player: CharacterBody2D) -> bool:
    var trunk_px := trunk_x * T
    var travelled := player.global_position.x - start_x
    print("travelled %.1f px, trunk at %.1f px, now at %.1f px"
            % [travelled, trunk_px, player.global_position.x])

    if player.global_position.x <= trunk_px:
        failures.append("player did NOT get past the tree trunk: stopped at "
                + "%.1f px, trunk at %.1f px - trees are solid again"
                % [player.global_position.x, trunk_px])

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
