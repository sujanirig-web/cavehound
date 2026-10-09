extends SceneTree

## Captures a fixed trio of screenshots (surface, cave, dungeon) for
## before/after comparison while tuning the atmosphere. Windowed, so it
## is NOT part of run_tests.sh:
##
##   godot --path . --script res://tools/atmosphere_shots.gd -- --tag=before --no-creatures
##
## Writes ~/.cache/cavebound_atmo/atmo_<tag>_<name>.png. Same seed every run, so the
## only thing that changes between a before and an after run is the code.

var main: Node
var frames := 0
var phase := 0
var tag := "shot"


func _initialize() -> void:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--tag="):
            tag = a.substr(6)
    main = load("res://scenes/main.tscn").instantiate()
    root.add_child(main)


func _process(_delta: float) -> bool:
    frames += 1
    var player := main.get_node_or_null("Entities/Player") as CharacterBody2D
    var loading := main.get_node_or_null("UI/Loading") as Control

    match phase:
        0:
            if frames > 900:
                push_error("world never finished generating")
                return _finish()
            if loading != null and not loading.visible and player != null \
                    and main.gen != null:
                _shot("surface")
                phase = 1
                frames = 0
        1:
            if frames < 45:
                return false
            main._teleport_to_cave()
            phase = 2
            frames = 0
        2:
            if frames < 70:
                return false
            _shot("cave")
            main._teleport_to_dungeon()
            phase = 3
            frames = 0
        3:
            if frames < 90:
                return false
            _shot("dungeon")
            return _finish()
    return false


func _shot(name: String) -> void:
    var img := root.get_texture().get_image()
    var path := "/home/sagiri/.cache/cavebound_atmo/atmo_%s_%s.png" % [tag, name]
    img.save_png(path)
    print("shot %-8s %dx%d -> %s"
            % [name, img.get_width(), img.get_height(), path])


func _finish() -> bool:
    quit(0)
    return true
