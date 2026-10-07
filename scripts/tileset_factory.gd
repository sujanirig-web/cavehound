class_name TilesetFactory
extends RefCounted

## Builds a TileSet entirely in code.
##
## Every tile is painted procedurally at runtime (grass blades, cracked
## stone, bark-grooved wood, masonry, ore glints …) into an Image. That
## keeps the repo pure text (no PNGs to diff) and means the art can be
## tuned without an image editor. Replace `build()` with a load of a
## real atlas once you have hand-drawn art.

const TILE_SIZE := 16
const ATLAS_COLS := 8

## Solid tiles get a full-tile collision box. Walls deliberately do not,
## so you can walk behind them.
##
## WOOD and LEAVES are intentionally NOT solid. Terraria trees are
## decorative and you walk straight through them; making trunks solid
## turns a forest into a wall of impassable obstacles, because tree
## density is 0.60-0.78 (a trunk every 3-8 tiles) and each trunk is 5-10
## tiles tall while a jump only clears about 3.5.
const SOLID := [
    WorldGen.Tile.DIRT, WorldGen.Tile.GRASS, WorldGen.Tile.STONE,
    WorldGen.Tile.SAND, WorldGen.Tile.SNOW, WorldGen.Tile.MUD,
    WorldGen.Tile.COPPER, WorldGen.Tile.IRON, WorldGen.Tile.GOLD,
    WorldGen.Tile.BEDROCK, WorldGen.Tile.DUNGEON_BRICK,
]

## Non-solid decoration. Kept as data so tests can assert intent.
const NON_SOLID := [
    WorldGen.Tile.AIR, WorldGen.Tile.WOOD, WorldGen.Tile.LEAVES,
    WorldGen.Tile.PLANK_WALL, WorldGen.Tile.STONE_WALL,
    WorldGen.Tile.GRASS_TUFT, WorldGen.Tile.WILD_GRASS, WorldGen.Tile.FLOWER,
    WorldGen.Tile.DUNGEON_WALL,
]


static func build() -> TileSet:
    var img := build_atlas()

    var ts := TileSet.new()
    ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

    # Godot 4.3 has no set_physics_layers_count(), and add_physics_layer()
    # returns void rather than the new index, so derive it from the count.
    ts.add_physics_layer()
    var physics_layer := ts.get_physics_layers_count() - 1
    ts.set_physics_layer_collision_layer(physics_layer, 1)

    var src := TileSetAtlasSource.new()
    src.texture = ImageTexture.create_from_image(img)
    src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
    for id in WorldGen.TILE_COUNT:
        src.create_tile(atlas_coords(id))

    # Order matters: a TileData only knows about the TileSet's physics
    # layers once its source has been registered. Calling
    # get_tile_data() before this line makes add_collision_polygon(0)
    # fail with "layer_id out of bounds (physics.size() = 0)", and the
    # player then falls straight through the world.
    ts.add_source(src, 0)

    for id in WorldGen.TILE_COUNT:
        if SOLID.has(id):
            var data := src.get_tile_data(atlas_coords(id), 0)
            data.add_collision_polygon(physics_layer)
            data.set_collision_polygon_points(physics_layer, 0, PackedVector2Array([
                Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8),
            ]))
    return ts


static func atlas_coords(id: int) -> Vector2i:
    return Vector2i(id % ATLAS_COLS, id / ATLAS_COLS)


## The placeholder atlas, exposed so tools/world_png.gd can render the
## world to a file without going through a GPU.
static func build_atlas() -> Image:
    # Float division is required here. TILE_COUNT / ATLAS_COLS with two
    # ints is integer division, so 15 / 8 == 1 and the atlas ends up one
    # row tall - which silently pushes every tile past id 7 outside the
    # texture and makes create_tile() fail.
    var rows := ceili(float(WorldGen.TILE_COUNT) / float(ATLAS_COLS))
    var img := Image.create(
        ATLAS_COLS * TILE_SIZE, rows * TILE_SIZE, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0))
    for id in WorldGen.TILE_COUNT:
        _paint(img, id,
                (id % ATLAS_COLS) * TILE_SIZE, (id / ATLAS_COLS) * TILE_SIZE)
    return img


# ---------------------------------------------------------------- painting

static func _paint(img: Image, id: int, ox: int, oy: int) -> void:
    # Seeded per tile so the texture is identical every run.
    var rng := RandomNumberGenerator.new()
    rng.seed = id * 7919 + 13

    match id:
        WorldGen.Tile.GRASS:
            _dirt_base(img, ox, oy, rng)
            _fill(img, ox, oy, Color("5aa03c"), 0, 4)
            _fill(img, ox, oy, Color("6fbe4a"), 0, 1)  # lit top row
            for x in TILE_SIZE:
                var h := 3 + rng.randi_range(0, 2)
                _px(img, ox + x, oy + h, Color("4c8a33"))
            for x in TILE_SIZE:
                if rng.randf() < 0.35:
                    _px(img, ox + x, oy + rng.randi_range(1, 3), Color("8ad45e"))
            for x in TILE_SIZE:
                if rng.randf() < 0.35:
                    _px(img, ox + x, oy + rng.randi_range(4, 6), Color("6fbe4a"))
            _edges(img, ox, oy, Color(0, 0, 0, 0), Color("4a3320"))

        WorldGen.Tile.DIRT:
            _dirt_base(img, ox, oy, rng)
            for i in 2:
                # small stone: dark base with a lit cap
                var px := rng.randi_range(1, 13)
                var py := rng.randi_range(5, 13)
                _px(img, ox + px, oy + py, Color("54381f"))
                _px(img, ox + px + 1, oy + py, Color("54381f"))
                _px(img, ox + px, oy + py - 1, Color("7d5733"))
            _edges(img, ox, oy, Color("7a5733"), Color("4a3320"))

        WorldGen.Tile.STONE:
            _stone_base(img, ox, oy, rng)
            _speckle(img, ox, oy, 3, Color("7d7d88"), rng)
            _crack(img, ox, oy, rng, Color("4f4f58"))
            _crack(img, ox, oy, rng, Color("4f4f58"))
            _edges(img, ox, oy, Color("7d7d88"), Color("585862"))

        WorldGen.Tile.SAND:
            _fill(img, ox, oy, Color("d9c48a"))
            _speckle(img, ox, oy, 5, Color("c0a970"), rng)
            _speckle(img, ox, oy, 3, Color("e8d6a4"), rng)
            # wind ripple: a wavy darker run across the middle
            var ry := 5 + rng.randi_range(0, 3)
            var x := rng.randi_range(0, 3)
            while x < TILE_SIZE:
                _px(img, ox + x, oy + ry, Color("c0a970"))
                if rng.randf() < 0.35:
                    ry = clampi(ry + rng.randi_range(-1, 1), 3, 13)
                x += 1
            _edges(img, ox, oy, Color("e8d6a4"), Color("b09a62"))

        WorldGen.Tile.SNOW:
            _fill(img, ox, oy, Color("7d8ba0"))
            _speckle(img, ox, oy, 3, Color("6a7789"), rng)
            _fill(img, ox, oy, Color("e8f1fb"), 0, 5)
            _fill(img, ox, oy, Color("ffffff"), 0, 1)
            for x in TILE_SIZE:
                _px(img, ox + x, oy + 4 + rng.randi_range(0, 2), Color("d3e2f2"))
            for i in 2:
                var sx := rng.randi_range(2, 13)
                var sy := rng.randi_range(1, 12)
                _px(img, ox + sx, oy + sy, Color("ffffff"))
                _px(img, ox + sx - 1, oy + sy, Color("d3e2f2"))
                _px(img, ox + sx + 1, oy + sy, Color("d3e2f2"))
                _px(img, ox + sx, oy + sy - 1, Color("d3e2f2"))
                _px(img, ox + sx, oy + sy + 1, Color("d3e2f2"))
            _edges(img, ox, oy, Color(0, 0, 0, 0), Color("6a7789"))

        WorldGen.Tile.MUD:
            _fill(img, ox, oy, Color("3f5230"))
            _speckle(img, ox, oy, 6, Color("33422a"), rng)
            _speckle(img, ox, oy, 3, Color("4a6138"), rng)
            _fill(img, ox, oy, Color("6fae3f"), 0, 4)
            _fill(img, ox, oy, Color("7fc44c"), 0, 1)
            for x in TILE_SIZE:
                _px(img, ox + x, oy + 3 + rng.randi_range(0, 2), Color("578c31"))
            _edges(img, ox, oy, Color(0, 0, 0, 0), Color("2c3a22"))

        WorldGen.Tile.WOOD:
            # vertical bark: dark grooves, lit ridges, side shading so a
            # column of trunks reads as a cylinder rather than a strip
            _fill(img, ox, oy, Color("6b4f2c"))
            for gx in [1, 5, 9, 13]:
                for y in TILE_SIZE:
                    if rng.randf() < 0.75:
                        _px(img, ox + gx, oy + y, Color("4f3a1f"))
            for gx in [3, 7, 11]:
                for y in TILE_SIZE:
                    if rng.randf() < 0.5:
                        _px(img, ox + gx, oy + y, Color("7d5c35"))
            for y in TILE_SIZE:
                _px(img, ox, oy + y, Color("5a4126"))
                _px(img, ox + TILE_SIZE - 1, oy + y, Color("543d21"))
            # a knot: dark ring with a lit core
            var kx := rng.randi_range(3, 11)
            var ky := rng.randi_range(3, 11)
            for dx in range(2):
                for dy in range(2):
                    _px(img, ox + kx + dx, oy + ky + dy, Color("4f3a1f"))
            _px(img, ox + kx, oy + ky, Color("7d5c35"))
            _edges(img, ox, oy, Color("7d5c35"), Color("453218"))

        WorldGen.Tile.LEAVES:
            # Three tones plus ragged transparent borders: neighbouring
            # tiles then merge into an organic canopy instead of a
            # green brick wall.
            for y in TILE_SIZE:
                for x in TILE_SIZE:
                    var border := x == 0 or y == 0 \
                            or x == TILE_SIZE - 1 or y == TILE_SIZE - 1
                    var corner := (x == 0 or x == TILE_SIZE - 1) \
                            and (y == 0 or y == TILE_SIZE - 1)
                    if border and rng.randf() < (0.55 if corner else 0.30):
                        _px(img, ox + x, oy + y, Color(0, 0, 0, 0))
                        continue
                    var d := x + y  # light falls from the top-left
                    var roll := rng.randf()
                    if d < 10 and roll < 0.40:
                        _px(img, ox + x, oy + y, Color("478c39"))
                    elif d > 20 and roll < 0.45:
                        _px(img, ox + x, oy + y, Color("1e4a1c"))
                    elif roll < 0.75:
                        _px(img, ox + x, oy + y, Color("255a22"))
                    else:
                        _px(img, ox + x, oy + y, Color("2f6b2a"))
            # a couple of holes punched through the interior
            for i in 3:
                _px(img, ox + rng.randi_range(2, 13), oy + rng.randi_range(2, 13),
                        Color(0, 0, 0, 0))

        WorldGen.Tile.COPPER:
            _stone_base(img, ox, oy, rng)
            _crack(img, ox, oy, rng, Color("4f4f58"))
            _blobs(img, ox, oy, Color("c87137"), Color("e08a4a"), rng)
            _edges(img, ox, oy, Color("7d7d88"), Color("585862"))

        WorldGen.Tile.IRON:
            _stone_base(img, ox, oy, rng)
            _crack(img, ox, oy, rng, Color("4f4f58"))
            _blobs(img, ox, oy, Color("b8b8c0"), Color("dcdce4"), rng)
            _edges(img, ox, oy, Color("7d7d88"), Color("585862"))

        WorldGen.Tile.GOLD:
            _stone_base(img, ox, oy, rng)
            _crack(img, ox, oy, rng, Color("4f4f58"))
            _blobs(img, ox, oy, Color("e0b43c"), Color("fff0a8"), rng)
            _edges(img, ox, oy, Color("7d7d88"), Color("585862"))

        WorldGen.Tile.BEDROCK:
            _fill(img, ox, oy, Color("2e2e34"))
            for i in TILE_SIZE * TILE_SIZE:
                var v := rng.randi_range(0, 3)
                if v > 0:
                    _px(img, ox + (i % TILE_SIZE), oy + (i / TILE_SIZE),
                        Color("3d3d45") if v == 1 else Color("22222a"))
            for i in 4:
                var bx := rng.randi_range(0, 12)
                var by := rng.randi_range(2, 13)
                for dx in range(3):
                    _px(img, ox + bx + dx, oy + by, Color("45454e"))
                    _px(img, ox + bx + dx, oy + by + 1, Color("22222a"))
            _edges(img, ox, oy, Color("3d3d45"), Color("1a1a20"))

        WorldGen.Tile.PLANK_WALL:
            _fill(img, ox, oy, Color("5a4526"))
            for y in [0, 5, 10, 15]:
                for x in TILE_SIZE:
                    _px(img, ox + x, oy + y, Color("43331b"))
            # staggered vertical seams = individual planks
            for x in [7]:
                for y in range(1, 5):
                    _px(img, ox + x, oy + y, Color("43331b"))
            for x in [3, 11]:
                for y in range(6, 10):
                    _px(img, ox + x, oy + y, Color("43331b"))
            for y in [1, 6, 11]:
                for x in TILE_SIZE:
                    if rng.randf() < 0.6:
                        _px(img, ox + x, oy + y, Color("6a5330"))

        WorldGen.Tile.STONE_WALL:
            _fill(img, ox, oy, Color("3c3c45"))
            _speckle(img, ox, oy, 3, Color("33333b"), rng)
            for y in [0, 7, 15]:
                for x in TILE_SIZE:
                    _px(img, ox + x, oy + y, Color("2a2a31"))
            for y in range(0, 7):
                _px(img, ox + 8, oy + y, Color("2a2a31"))
            for y in range(8, 15):
                _px(img, ox + 3, oy + y, Color("2a2a31"))
                _px(img, ox + 12, oy + y, Color("2a2a31"))
            _fill(img, ox, oy, Color("45454f"), 0, 1)

        WorldGen.Tile.DUNGEON_BRICK:
            # dark blue-grey masonry: 8x5 staggered bricks with mortar
            # lines and a lit top edge on each course
            _fill(img, ox, oy, Color("3a4152"))
            for y in TILE_SIZE:
                for x in TILE_SIZE:
                    var band := y / 5
                    var mortar := y % 5 == 4
                    if band % 2 == 0:
                        mortar = mortar or x % 8 == 7
                    else:
                        mortar = mortar or x % 8 == 3
                    if mortar:
                        _px(img, ox + x, oy + y, Color("242a36"))
            for band in 4:
                for x in TILE_SIZE:
                    var band_y := band * 5
                    if band_y < TILE_SIZE:
                        var b := band
                        if (b % 2 == 0 and x % 8 == 7) \
                                or (b % 2 == 1 and x % 8 == 3):
                            continue
                        _px(img, ox + x, oy + band_y, Color("4a5266"))
            _speckle(img, ox, oy, 3, Color("33394a"), rng)
            _edges(img, ox, oy, Color(0, 0, 0, 0), Color("2a3040"))

        WorldGen.Tile.DUNGEON_WALL:
            # same masonry, much darker - rooms read as depth behind you
            _fill(img, ox, oy, Color("262c38"))
            for y in TILE_SIZE:
                for x in TILE_SIZE:
                    var band := y / 5
                    var mortar := y % 5 == 4
                    if band % 2 == 0:
                        mortar = mortar or x % 8 == 7
                    else:
                        mortar = mortar or x % 8 == 3
                    if mortar:
                        _px(img, ox + x, oy + y, Color("1e232e"))
            _speckle(img, ox, oy, 3, Color("2e3542"), rng)
            _fill(img, ox, oy, Color("2e3542"), 0, 1)

        WorldGen.Tile.GRASS_TUFT:
            _tuft(img, ox, oy, rng, 4, 6, 11)

        WorldGen.Tile.WILD_GRASS:
            _tuft(img, ox, oy, rng, 6, 8, 14)

        WorldGen.Tile.FLOWER:
            _tuft(img, ox, oy, rng, 2, 4, 7)
            var stem_x := 6 + rng.randi_range(0, 4)
            var stem_h := rng.randi_range(8, 11)
            for i in stem_h:
                _px(img, ox + stem_x, oy + 15 - i, Color("4c8a33"))
            var heads := [Color("d95c5c"), Color("f0d048"), Color("e28ac0")]
            var head: Color = heads[rng.randi_range(0, 2)]
            var head_y := 16 - stem_h  # top of the stem
            for dy in range(-1, 2):
                for dx in range(-1, 2):
                    _px(img, ox + stem_x + dx, oy + head_y + dy, head)
            _px(img, ox + stem_x, oy + head_y, Color("fff3cc"))


## Dirt/stone shared body: dark clumps plus lighter flecks so the ground
## is not a flat brown rectangle once you dig into it.
static func _dirt_base(img: Image, ox: int, oy: int,
        rng: RandomNumberGenerator) -> void:
    _fill(img, ox, oy, Color("6b4a2b"))
    _speckle(img, ox, oy, 6, Color("54381f"), rng)
    _speckle(img, ox, oy, 3, Color("7d5733"), rng)


## Lit top row and shaded bottom row. Every solid tile gets this so flat
## ground reads as a lit surface with depth instead of wallpaper.
static func _edges(img: Image, ox: int, oy: int, top: Color,
        bottom: Color) -> void:
    if top.a > 0.0:
        _fill(img, ox, oy, top, 0, 1)
    if bottom.a > 0.0:
        _fill(img, ox, oy, bottom, TILE_SIZE - 1, 1)


## A short meandering dark line - cracks make stone read as rock.
static func _crack(img: Image, ox: int, oy: int,
        rng: RandomNumberGenerator, c: Color) -> void:
    var x := rng.randi_range(2, 12)
    var y := rng.randi_range(2, 8)
    var len := rng.randi_range(3, 6)
    for i in len:
        _px(img, ox + x, oy + y, c)
        if rng.randf() < 0.5:
            y += 1
        else:
            x += rng.randi_range(-1, 1)
        x = clampi(x, 1, TILE_SIZE - 2)


## A clump of blades growing from the bottom edge. Blades start evenly
## spaced and bend quadratically outward, which reads as grass rather
## than a row of vertical lines. Transparent elsewhere.
static func _tuft(img: Image, ox: int, oy: int,
        rng: RandomNumberGenerator, count: int, h_min: int, h_max: int) -> void:
    var dark := Color("4c8a33")
    var light := Color("6fbe4a")
    for blade in count:
        # Float maths: int step (14 / 3) would quantise blades to every
        # 4px and clump them; the jitter below adds the rest of the spread.
        var bx := int(round(1.0 + float(blade) * 14.0 / float(maxi(count - 1, 1)))) \
                + rng.randi_range(0, 2)
        var h := rng.randi_range(h_min, h_max)
        var dir := -1.0 if bx < 8 else 1.0
        if rng.randf() < 0.25:
            dir = 0.0
        var bend := rng.randf_range(0.7, 1.7) * dir
        var x := float(bx)
        for i in h:
            var y := 15 - i
            var c := dark if i * 2 < h else light
            _px(img, ox + int(round(x)), oy + y, c)
            # drift grows with height: quadratic, not a straight slash
            x += bend * float(i) / float(h) * 0.35


static func _stone_base(img: Image, ox: int, oy: int, rng: RandomNumberGenerator) -> void:
    _fill(img, ox, oy, Color("6e6e78"))
    _speckle(img, ox, oy, 4, Color("585862"), rng)
    _speckle(img, ox, oy, 3, Color("7d7d88"), rng)


## Ore veins: five ragged blobs with a lit top-left pixel each, plus a
## four-point glint on the first one so ore reads as treasure, not paint.
static func _blobs(img: Image, ox: int, oy: int, c: Color, hi: Color,
        rng: RandomNumberGenerator) -> void:
    for i in 5:
        var bx := rng.randi_range(2, 11)
        var by := rng.randi_range(2, 11)
        for dy in range(3):
            for dx in range(3):
                if rng.randf() < 0.7:
                    _px(img, ox + bx + dx, oy + by + dy, c)
        _px(img, ox + bx, oy + by, hi)
        if i == 0:
            var sx := bx + 1
            var sy := by + 1
            _px(img, ox + sx - 1, oy + sy, hi)
            _px(img, ox + sx + 1, oy + sy, hi)
            _px(img, ox + sx, oy + sy - 1, hi)
            _px(img, ox + sx, oy + sy + 1, hi)


static func _fill(img: Image, ox: int, oy: int, c: Color,
        from_y: int = 0, rows: int = TILE_SIZE) -> void:
    for y in range(from_y, mini(from_y + rows, TILE_SIZE)):
        for x in TILE_SIZE:
            _px(img, ox + x, oy + y, c)


static func _speckle(img: Image, ox: int, oy: int, count: int, c: Color,
        rng: RandomNumberGenerator) -> void:
    for _i in count * 4:
        _px(img, ox + rng.randi_range(0, 15), oy + rng.randi_range(0, 15), c)


static func _px(img: Image, x: int, y: int, c: Color) -> void:
    if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
        return
    img.set_pixel(x, y, c)
