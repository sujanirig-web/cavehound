extends SceneTree

## Renders a generated world to a PNG so terrain can be inspected
## without launching the game.
##
##   godot --headless --path . --script res://tools/world_png.gd
##
## Writes /tmp/cavebound_overview.png (whole world, downscaled) and
## /tmp/cavebound_crop.png   (1:1 pixels around spawn).

const W := 1600
const H := 400
const T := TilesetFactory.TILE_SIZE
const OUT := "/tmp/cavebound"


func _initialize() -> void:
    var gen := WorldGen.new()
    gen.generate(abs(hash("cavebound")), W, H)
    var atlas := TilesetFactory.build_atlas()

    _overview(gen, atlas)
    _crop(gen, atlas)
    _dungeon_crop(gen, atlas)
    print("\nwrote %s_overview.png, %s_crop.png, %s_dungeon.png"
            % [OUT, OUT, OUT])
    quit(0)


## Whole world scaled down, so terrain shape and biome bands are obvious.
func _overview(gen: WorldGen, atlas: Image) -> void:
    var step := 2
    var w := W / step
    var h := H / step
    var out := Image.create(w, h, false, Image.FORMAT_RGB8)
    out.fill(Color("101018"))

    for x in w:
        var gx := x * step
        for y in h:
            var gy := y * step
            var t: int = gen.tiles[gy * W + gx]
            if t == WorldGen.Tile.AIR:
                # below the surface and unwalled = open cave, tint it so
                # the cave network reads as distinct from the sky
                if gy > gen.surface[gx]:
                    out.set_pixel(x, y, Color("241f2b"))
                else:
                    out.set_pixel(x, y, Color("101018"))
                continue
            out.set_pixel(x, y, _tile_pixel(atlas, t))

    out.save_png(OUT + "_overview.png")


## 1:1 crop centred on spawn, drawn walls-then-tiles like the real scene.
func _crop(gen: WorldGen, atlas: Image) -> void:
    var cw := 96
    var ch := 56
    var x0 := clampi(gen.spawn.x - cw / 2, 0, W - cw)
    var y0 := clampi(gen.spawn.y - ch / 2, 0, H - ch)

    var out := Image.create(cw * T, ch * T, false, Image.FORMAT_RGB8)
    out.fill(Color("101018"))

    for i in 2:
        for ty in ch:
            for tx in cw:
                var gx := x0 + tx
                var gy := y0 + ty
                var idx := gy * W + gx
                var id: int = gen.walls[idx] if i == 0 else gen.tiles[idx]
                if id == WorldGen.Tile.AIR:
                    continue
                _blit(out, atlas, id, tx * T, ty * T)

    # mark the spawn point
    var sx := (gen.spawn.x - x0) * T + T / 2
    var sy := (gen.spawn.y - y0) * T + T / 2
    for r in range(3, 7):
        for a in range(0, 360, 6):
            var ang := deg_to_rad(a)
            out.set_pixel(sx + int(cos(ang) * r), sy + int(sin(ang) * r), Color(1, 0.2, 0.6))

    out.save_png(OUT + "_crop.png")


## The dungeon entrance: gate, shaft and the top of room 0, so the
## masonry, treads and chimney ladder can be inspected at 1:1.
func _dungeon_crop(gen: WorldGen, atlas: Image) -> void:
    # Find the gate: first dungeon brick above the surface line.
    var gx := -1
    var gy := 0
    for x in W:
        for y in range(gen.surface[x]):
            if gen.tiles[y * W + x] == WorldGen.Tile.DUNGEON_BRICK:
                gx = x
                gy = y
                break
        if gx != -1:
            break
    if gx == -1:
        print("no dungeon found - skipping dungeon crop")
        return

    var cw := 40
    var ch := 64
    var x0 := clampi(gx - cw / 2, 0, W - cw)
    var y0 := clampi(gy - 8, 0, H - ch)

    var out := Image.create(cw * T, ch * T, false, Image.FORMAT_RGB8)
    out.fill(Color("101018"))
    for i in 2:
        for ty in ch:
            for tx in cw:
                var idx := (y0 + ty) * W + (x0 + tx)
                var id: int = gen.walls[idx] if i == 0 else gen.tiles[idx]
                if id == WorldGen.Tile.AIR:
                    continue
                _blit(out, atlas, id, tx * T, ty * T)

    # red cross marks the gate top
    var sx := (gx - x0) * T + T / 2
    var sy := (gy - y0) * T + T / 2
    for d in range(-6, 7):
        out.set_pixel(sx + d, sy, Color(1, 0.2, 0.6))
        out.set_pixel(sx, sy + d, Color(1, 0.2, 0.6))

    out.save_png(OUT + "_dungeon.png")
    print("dungeon gate at x=%d y=%d -> %s_dungeon.png" % [gx, gy, OUT])


func _tile_pixel(atlas: Image, id: int) -> Color:
    var c := TilesetFactory.atlas_coords(id) * T
    return atlas.get_pixel(c.x + T / 2, c.y + T / 2)


func _blit(dst: Image, atlas: Image, id: int, ox: int, oy: int) -> void:
    var c := TilesetFactory.atlas_coords(id) * T
    for y in T:
        for x in T:
            var p := atlas.get_pixel(c.x + x, c.y + y)
            if p.a > 0.05:
                dst.set_pixel(ox + x, oy + y, Color(p.r, p.g, p.b))
