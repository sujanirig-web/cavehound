extends SceneTree

## ASCII preview of a generated world. Lets terrain shape, biome bands
## and the cave network be sanity-checked straight in the terminal.
##
##   godot --headless --path . --script res://tools/world_ascii.gd
##
## Optional seed + sample step:
##   godot --headless --path . --script res://tools/world_ascii.gd -- myseed 6

const W := 1600
const H := 400

const GLYPH := {
    0: " ",   # air
    1: "d",   # dirt
    2: "\"",  # grass
    3: "#",   # stone
    4: ".",   # sand
    5: "*",   # snow
    6: "m",   # mud
    7: "|",   # wood
    8: "o",   # leaves
    9: "c",   # copper
    10: "i",  # iron
    11: "g",  # gold
    12: "B",  # bedrock
    15: ",",  # grass tuft
    16: "w",  # wild grass
    17: "f",  # flower
    18: "D",  # dungeon brick
    19: "n",  # dungeon wall (background)
}


func _initialize() -> void:
    var seed_name := "cavebound"
    var step := 8
    if OS.get_cmdline_user_args().size() >= 1:
        seed_name = OS.get_cmdline_user_args()[0]
    if OS.get_cmdline_user_args().size() >= 2:
        step = maxi(int(OS.get_cmdline_user_args()[1]), 1)

    var gen := WorldGen.new()
    gen.generate(abs(hash(seed_name)), W, H)

    var cols := W / step
    var rows := H / step
    print("\n=== %s  %dx%d  sampled every %d tiles ===" % [seed_name, W, H, step])

    var band := ""
    for x in cols:
        var b: int = gen.biomes[gen.surface[x * step] * W + x * step]
        band += ["P", "F", "D", "J", "T"][b]
    print("biomes: " + band + "\n")

    for ry in rows:
        var line := ""
        for rx in cols:
            var x := rx * step
            var y := ry * step
            var t: int = gen.tiles[y * W + x]
            if t == WorldGen.Tile.AIR:
                if y > gen.surface[x] and gen.walls[y * W + x] != WorldGen.Tile.AIR:
                    line += ":"      # walled cave
                elif y > gen.surface[x]:
                    line += " "      # unlit open cave, rare
                else:
                    line += " "      # sky
            else:
                line += GLYPH.get(t, "?")
        print(line)

    print("\nlegend: \" grass  d dirt  # stone  . sand  * snow  m mud")
    print("        | wood  o leaves  c copper  i iron  g gold  B bedrock")
    print("        , tuft  w wild grass  f flower  D dungeon brick")
    print("        : walled cave   (blank) sky or open cave")
    print("        spawn %s   surface y %d" % [gen.spawn, gen.surface[gen.spawn.x]])
    quit(0)
