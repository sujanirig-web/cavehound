extends SceneTree

## Live capture for the mob/npc milestone: boots the real game windowed,
## snaps the spawn view, parks the player next to the village (so a
## villager is on screen), then corners the nearest slime, and saves
## screenshots for offline inspection.
##
## Not part of run_tests.sh (needs a display):
##
##   godot --path . --script res://tools/mob_shots.gd
##
## Writes /tmp/cavebound_mobs_<name>.png for each phase.

const T := TilesetFactory.TILE_SIZE

var main: Node
var frames := 0
var phase := 0
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
        1: return _visit_village(player)
        2: return _chase_slime(player)
    return false


func _shot(name: String) -> void:
    var img := root.get_texture().get_image()
    var path := "/tmp/cavebound_mobs_%s.png" % name
    img.save_png(path)
    print("shot %-10s %dx%d -> %s" % [name, img.get_width(), img.get_height(), path])


func _wait_for_world(player: CharacterBody2D, loading: Control) -> bool:
    if frames > 900:
        failures.append("world never finished generating")
        return _finish()
    if loading != null and not loading.visible and player != null:
        _shot("spawn")
        print("hud: %s" % main.info.text.replace("\n", " | "))
        phase = 1
        frames = 0
    return false


## Park beside the village: the villagers spawn at spawn +/- 20/32 tiles,
## so standing a few tiles right of spawn puts one on screen.
func _visit_village(player: CharacterBody2D) -> bool:
    if frames == 4:
        var gen: WorldGen = main.gen
        var x: int = gen.spawn.x + 18
        player.velocity = Vector2.ZERO
        player.global_position = Vector2((x + 0.5) * T,
                gen.surface[x] * T - 11.0)
        print("teleported player to x=%d to face the village" % x)
    if frames < 100:
        return false  # let the camera glide over
    for n in get_nodes_in_group("npcs"):
        print("npc %s at (%d, %d), anchor (%d, %d)" % [n.name,
                int((n as Node2D).global_position.x),
                int((n as Node2D).global_position.y),
                int(n.anchor.x), int(n.anchor.y)])
    _shot("village")
    phase = 2
    frames = 0
    return false


## Hop beside the closest slime so it is mid-frame.
func _chase_slime(player: CharacterBody2D) -> bool:
    if frames == 4:
        var best: Node = null
        var best_d := INF
        for m in get_nodes_in_group("mobs"):
            var d: float = (m as Node2D).global_position.distance_to(
                    player.global_position)
            if d < best_d:
                best_d = d
                best = m
        if best == null:
            failures.append("no slimes on the surface")
            return _finish()
        player.velocity = Vector2.ZERO
        player.global_position = (best as Node2D).global_position + Vector2(-11 * T, 0)
        print("nearest slime at %s (%d px away); hopped beside it"
                % [(best as Node2D).global_position, int(best_d)])
    if frames < 100:
        return false
    _shot("slime")
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