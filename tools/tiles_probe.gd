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
        0x8a6a3e: "+",  # lit chip / knot core
        0x7d5c35: ":",  # light ridge
        0x6b4f2c: ".",  # mid bark
        0x5a4126: "-",  # shaded tone
        0x543d21: "-",  # cylinder shadow
        0x453318: "#",  # groove
        0x3b2c14: "#",  # crack
        0x40301a: "#",  # knot ring
    })
    _dump_tile(atlas, WorldGen.Tile.LEAVES, {
        0x8ad455: "+",  # sunlit top
        0x4e8c38: ".",  # mid leaf
        0x39742e: "*",  # darker pocket
        0x2a5c24: "#",  # deep leaf
        0x1d4218: "=",  # shaded underside
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