extends SceneTree

## Measures the boot-time costs that dominate the loading screen: world
## generation, atlas painting, tileset build, and the full scene boot
## (generate -> paint -> spawn). Prints numbers so optimisation work has
## a before/after. Not part of run_tests.sh.
##
##   godot --headless --path . --script res://tools/bench_probe.gd

const W := 1600
const H := 400

var main: Node
var boot_t0 := 0
var boot_done := false


func _initialize() -> void:
    var seed: int = abs(hash("cavebound"))

    var t0 := Time.get_ticks_usec()
    var gen := WorldGen.new()
    gen.generate(seed, W, H)
    var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0

    t0 = Time.get_ticks_usec()
    TilesetFactory.build_atlas()
    var atlas_ms := (Time.get_ticks_usec() - t0) / 1000.0

    t0 = Time.get_ticks_usec()
    TilesetFactory.build()
    var tileset_ms := (Time.get_ticks_usec() - t0) / 1000.0

    var non_air := 0
    for t in gen.tiles:
        if t != WorldGen.Tile.AIR:
            non_air += 1
    var wall_count := 0
    for wv in gen.walls:
        if wv != WorldGen.Tile.AIR:
            wall_count += 1

    print("worldgen %.1f ms (%.0f cells/ms)  %d solid tiles  %d walls"
            % [gen_ms, float(W * H) / maxf(gen_ms, 0.001), non_air, wall_count])
    print("atlas %.1f ms   tileset %.1f ms" % [atlas_ms, tileset_ms])

    boot_t0 = Time.get_ticks_usec()
    main = load("res://scenes/main.tscn").instantiate()
    root.add_child(main)


func _process(_delta: float) -> bool:
    if boot_done:
        return false
    var loading := main.get_node_or_null("UI/Loading") as Control
    if loading == null or loading.visible:
        return false
    var boot_ms := (Time.get_ticks_usec() - boot_t0) / 1000.0
    print("scene boot (gen + paint + spawn) %.1f ms" % boot_ms)
    boot_done = true
    quit(0)
    return true