extends SceneTree

## Headless sanity check for the baked lightmap.
##
##   godot --headless --path . --script res://tools/light_test.gd
##
## Asserts the things most likely to break while tuning the flood: the map
## is world-sized, deterministic, open sky is not darkened, and buried air
## (caves deep under the surface) is genuinely dark.

const W := 1600
const H := 400
const LIT_ALPHA := Lighting.LIT  # 255


func _initialize() -> void:
    var failures: Array[String] = []
    var gen := WorldGen.new()
    gen.generate(abs(hash("cavebound")), W, H)

    var t0 := Time.get_ticks_msec()
    var img := Lighting.bake(gen)
    var ms := Time.get_ticks_msec() - t0
    print("lightmap baked in %d ms" % ms)
    if ms > 3000:
        failures.append("bake too slow: %d ms" % ms)

    if img.get_width() != W or img.get_height() != H:
        failures.append("size %dx%d != %dx%d"
                % [img.get_width(), img.get_height(), W, H])

    var img2 := Lighting.bake(gen)
    if img.get_data() != img2.get_data():
        failures.append("lightmap is not deterministic")

    # 1. open sky (top-row air) is never darkened
    var rng := RandomNumberGenerator.new()
    rng.seed = 1337
    for s in 200:
        var x := rng.randi_range(0, W - 1)
        var a := img.get_pixel(x, 0).a
        if a != 0.0:
            failures.append("sky cell x=%d darkened (alpha %.2f)" % [x, a])
            break

    # 2. the surface is lit: the air cell right above the ground row
    var surface_dark := 0.0
    var surface_n := 0
    for x in W:
        var sy: int = gen.surface[x]
        if sy < 2 or sy >= H - 1:
            continue
        surface_dark += img.get_pixel(x, sy - 1).a
        surface_n += 1
    surface_dark /= float(maxi(surface_n, 1))
    print("mean surface-air darkness %.2f (of 1)" % surface_dark)
    if surface_dark > 0.35:
        failures.append("surface looks dark (%.2f)" % surface_dark)

    # 3. deep buried air (a cave well below the surface) is dark
    var darkest := 0.0
    var found_n := 0
    for x in W:
        var sy: int = gen.surface[x]
        var y0 := mini(sy + 24, H - 2)
        for y in range(y0, H - 1, 3):
            if gen.tiles[y * W + x] != WorldGen.Tile.AIR:
                continue
            darkest = maxf(darkest, img.get_pixel(x, y).a)
            found_n += 1
    print("darkest buried air darkness %.2f (%d samples)" % [darkest, found_n])
    if found_n > 0 and darkest < 0.55:
        failures.append("no dark cave found (darkest %.2f)" % darkest)

    print("")
    if failures.is_empty():
        print("  lightmap ok (%d ms)" % ms)
        quit(0)
    else:
        for f in failures:
            print("  FAIL: %s" % f)
        quit(1)