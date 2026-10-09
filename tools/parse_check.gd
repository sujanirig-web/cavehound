extends SceneTree

## Loads every script and scene in the project so parse errors, bad
## signatures and missing class_name references surface as failures
## instead of silently breaking at runtime.
##
##   godot --headless --path . --script res://tools/parse_check.gd

const SCRIPTS := [
    "res://scripts/world_gen.gd",
    "res://scripts/tileset_factory.gd",
    "res://scripts/tools.gd",
    "res://scripts/player.gd",
    "res://scripts/player_art.gd",
    "res://scripts/mob.gd",
    "res://scripts/mob_art.gd",
    "res://scripts/npc.gd",
    "res://scripts/npc_art.gd",
    "res://scripts/target_cursor.gd",
    "res://scripts/world.gd",
    "res://scripts/lighting.gd",
    "res://scripts/atmosphere.gd",
    "res://tools/light_test.gd",
    "res://tools/gen_test.gd",
    "res://tools/dig_test.gd",
    "res://tools/mob_test.gd",
    "res://tools/dungeon_probe.gd",
    "res://tools/demo_shots.gd",
    "res://tools/mob_shots.gd",
    "res://tools/bench_probe.gd",
    "res://tools/mouse_probe.gd",
    "res://tools/noise_probe.gd",
    "res://tools/world_png.gd",
    "res://tools/tree_view.gd",
    "res://tools/world_ascii.gd",
    "res://tools/play_test.gd",
]

const SCENES := [
    "res://scenes/main.tscn",
    "res://scenes/player.tscn",
    "res://scenes/mob.tscn",
    "res://scenes/npc.tscn",
]


func _initialize() -> void:
    var bad := 0

    for path in SCRIPTS:
        # load() returns null when a GDScript fails to compile.
        if load(path) == null:
            print("  FAIL  %s" % path)
            bad += 1
        else:
            print("  ok    %s" % path)

    for path in SCENES:
        var res: Resource = load(path)
        if res == null:
            print("  FAIL  %s did not load" % path)
            bad += 1
            continue
        if not (res is PackedScene):
            print("  FAIL  %s is not a PackedScene" % path)
            bad += 1
            continue
        var inst: Node = (res as PackedScene).instantiate()
        if inst == null:
            print("  FAIL  %s could not instantiate" % path)
            bad += 1
        else:
            inst.free()
            print("  ok    %s" % path)

    print("")
    if bad == 0:
        print("  all %d resources parsed" % (SCRIPTS.size() + SCENES.size()))
        quit(0)
    else:
        print("  %d resource(s) failed" % bad)
        quit(1)
