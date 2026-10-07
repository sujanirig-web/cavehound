extends SceneTree

## Prints the WOOD and LEAVES atlas tiles as a colour-keyed ASCII grid,
## so texture structure (bark grooves/notches, leaf dapples) can be
## sanity-checked without opening an image editor.
##
##   godot --headless --path . --script res://tools/tiles_probe.gd

const T := 16


func _initialize() -> void:
    var atlas := TilesetFactory.build_atlas()
    _dump_tile(atlas, WorldGen.Tile.WOOD, {
        0x8a6a3e: "+",  # lit bark chip
        0x7d5c35: ":",  # light ridge
        0x6b4f2c: ".",  # mid bark
        0x5a4126: "-",  # shaded edge
        0x543d21: "-",
        0x4f3a1f: "#",  # groove / knot / notch
        0x4a341c: "#",
    })
    _dump_tile(atlas, WorldGen.Tile.LEAVES, {
        0x67b24a: "+",  # sunlit fleck / cluster highlight
        0x478c39: ".",  # light leaf
        0x3f7a34: "*",  # deep dapple
        0x2f6b2a: "=",  # mid leaf
        0x2e5c26: "*",
        0x255a22: "=",
        0x1e4a1c: "#",  # shade leaf
    })
    quit(0)


func _dump_tile(atlas: Image, id: int, key: Dictionary) -> void:
    var ox := (id % TilesetFactory.ATLAS_COLS) * T
    var oy := (id / TilesetFactory.ATLAS_COLS) * T
    print("\n-- tile %d ---------------------------" % id)
    for y in T:
        var line := ""
        for x in T:
            var c := atlas.get_pixel(ox + x, oy + y)
            if c.a == 0.0:
                line += " "
                continue
            var rgb := (int(c.r * 255) << 16) | (int(c.g * 255) << 8) | int(c.b * 255)
            line += key.get(rgb, "?")
        print(line)