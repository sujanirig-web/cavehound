extends SceneTree

## Prints a per-tile view around the dungeon entrance so the gate frame,
## shaft, chimney treads and room walls can be inspected exactly (the
## PNG downsampling hides single-tile detail).
##
##   godot --headless --path . --script res://tools/dungeon_probe.gd

const W := 1600
const H := 400
const T := TilesetFactory.TILE_SIZE


func _initialize() -> void:
    var gen := WorldGen.new()
    gen.generate(abs(hash("cavebound")), W, H)

    # first dungeon brick above the surface = the gate
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
        print("FAIL: no dungeon brick above the surface")
        quit(1)
        return

    var x0 := gx - 22
    var y0 := maxi(gy - 10, 0)
    var x1 := mini(gx + 23, W - 1)
    var y1 := mini(y0 + 70, H - 1)
    print("gate top at (%d,%d)  window x[%d..%d] y[%d..%d]"
            % [gx, gy, x0, x1, y0, y1])

    # column ruler
    var ruler := "   "
    for x in range(x0, x1 + 1):
        ruler += str(x % 10)
    print(ruler)

    for y in range(y0, y1 + 1):
        var line := "%3d" % y
        for x in range(x0, x1 + 1):
            var i := y * W + x
            var t: int = gen.tiles[i]
            var wv: int = gen.walls[i]
            var ch := "."
            match t:
                WorldGen.Tile.DUNGEON_BRICK:
                    ch = "D"
                WorldGen.Tile.AIR:
                    if wv == WorldGen.Tile.DUNGEON_WALL:
                        ch = "w"
                    elif wv == WorldGen.Tile.STONE_WALL:
                        ch = ":"
                    else:
                        ch = " "
                WorldGen.Tile.WOOD:
                    ch = "|"
                WorldGen.Tile.LEAVES:
                    ch = "o"
                WorldGen.Tile.GRASS, WorldGen.Tile.MUD:
                    ch = "\""
                WorldGen.Tile.BEDROCK:
                    ch = "B"
                WorldGen.Tile.GRASS_TUFT, WorldGen.Tile.WILD_GRASS, \
                WorldGen.Tile.FLOWER:
                    ch = ","
                _:
                    ch = "#"
            if x == gx and y == gy:
                ch = "+"
            line += ch
        print(line)

    _check_treads(gen, gx)


## Locate the shaft centre (the column that stays air below ground while
## both neighbours carry alternating brick treads) and verify the ladder.
## The gate's first brick is the lintel end, not entrance_x, so we cannot
## just use gx+-1.
func _check_treads(gen: WorldGen, gate_x: int) -> void:
    var center := -1
    for x in range(maxi(gate_x - 4, 1), mini(gate_x + 6, W - 1)):
        var sy := gen.surface[x]
        if sy + 40 >= H:
            continue
        var air := 0
        var tl := 0
        var tr := 0
        for y in range(sy + 2, sy + 40):
            if gen.tiles[y * W + x] == WorldGen.Tile.AIR:
                air += 1
            if gen.tiles[y * W + x - 1] == WorldGen.Tile.DUNGEON_BRICK:
                tl += 1
            if gen.tiles[y * W + x + 1] == WorldGen.Tile.DUNGEON_BRICK:
                tr += 1
        if air >= 30 and tl >= 8 and tr >= 8:
            center = x
            print("\nshaft centre x=%d (air %d/38, treads L%d R%d)"
                    % [x, air, tl, tr])
            break
    if center == -1:
        print("FAIL: no shaft with chimney treads found near gate x=%d" % gate_x)
        quit(1)
    else:
        quit(0)
