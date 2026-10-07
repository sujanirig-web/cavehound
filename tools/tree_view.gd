extends SceneTree

## Renders one full generated tree (crown, trunk, flare) at 1:1 so the
## tree art can be inspected without launching the game.
##
##   godot --headless --path . --script res://tools/tree_view.gd
##
## Writes /tmp/cavebound_tree.png.

const W := 1600
const H := 400
const T := TilesetFactory.TILE_SIZE
const OUT := "/tmp/cavebound_tree.png"


func _initialize() -> void:
    var gen := WorldGen.new()
    gen.generate(abs(hash("cavebound")), W, H)
    var atlas := TilesetFactory.build_atlas()

    # Frame the whole tree: crown above the trunk top, flare + ground below.
    var cw := 40
    var ch := 56

    # Snag the first tree we scan: a leaf cell just above ground, then
    # follow its column down to the trunk. Skip x near the world edges so
    # the crop is never cut off.
    var tx := -1
    var ty := 0
    for x in range(cw / 2 + 2, W - cw / 2 - 2):
        var found := false
        for y in range(gen.surface[x] - 40, gen.surface[x]):
            if gen.tiles[y * W + x] == WorldGen.Tile.LEAVES:
                tx = x
                ty = y
                found = true
                break
        if found:
            break
    if tx == -1:
        print("no tree found")
        quit(1)

    var trunk_y := ty
    while trunk_y < H and gen.tiles[trunk_y * W + tx] != WorldGen.Tile.WOOD:
        trunk_y += 1
    if trunk_y >= H:
        trunk_y = ty

    var x0 := clampi(tx - cw / 2, 0, W - cw)
    var y0 := clampi(trunk_y - 22, 0, H - ch)

    var out := Image.create(cw * T, ch * T, false, Image.FORMAT_RGB8)
    out.fill(Color("101018"))
    for i in 2:
        for tyy in ch:
            for txx in cw:
                var idx := (y0 + tyy) * W + (x0 + txx)
                var id: int = gen.walls[idx] if i == 0 else gen.tiles[idx]
                if id == WorldGen.Tile.AIR:
                    continue
                _blit(out, atlas, id, txx * T, tyy * T)

    out.save_png(OUT)
    print("tree at x=%d crown top y=%d trunk top y=%d -> %s"
            % [tx, ty, trunk_y, OUT])
    quit(0)


func _blit(dst: Image, atlas: Image, id: int, ox: int, oy: int) -> void:
    var c := TilesetFactory.atlas_coords(id) * T
    for y in T:
        for x in T:
            var p := atlas.get_pixel(c.x + x, c.y + y)
            if p.a > 0.05:
                dst.set_pixel(ox + x, oy + y, Color(p.r, p.g, p.b))