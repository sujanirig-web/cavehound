class_name WorldGen
extends RefCounted

## Procedural world generator.
##
## Produces three flat byte arrays indexed by `y * width + x`:
##   tiles[]  - foreground blocks (what you stand on)
##   walls[]  - background walls (what you see behind you)
##   biomes[] - Biome id per cell
##
## Generation runs in passes so each one can read the previous:
##   1. heightmap + biome per column (smoothed for rolling relief)
##   2. fill dirt/stone columns (wavy dirt/stone boundary)
##   3. carve caves
##   4. scatter ores
##   5. plant trees
##   6. scatter surface grass/flowers
##   7. wall every underground air cell
##   8. build the dungeon (brick rooms, corridors, gated entrance)
##
## Everything is driven by `world_seed`, so the same seed always
## produces the same world.

enum Tile {
    AIR = 0,
    DIRT = 1,
    GRASS = 2,
    STONE = 3,
    SAND = 4,
    SNOW = 5,
    MUD = 6,
    WOOD = 7,
    LEAVES = 8,
    COPPER = 9,
    IRON = 10,
    GOLD = 11,
    BEDROCK = 12,
    PLANK_WALL = 13,
    STONE_WALL = 14,
    GRASS_TUFT = 15,
    WILD_GRASS = 16,
    FLOWER = 17,
    DUNGEON_BRICK = 18,
    DUNGEON_WALL = 19,
}

enum Biome { PLAINS, FOREST, DESERT, JUNGLE, TUNDRA }

const TILE_COUNT := 20
const ATLAS_COLS := 8
const BEDROCK_DEPTH := 6

var tiles := PackedByteArray()
var walls := PackedByteArray()
var biomes := PackedByteArray()
var surface := PackedInt32Array()

var width := 0
var height := 0
var spawn := Vector2i.ZERO

## Where the dungeon gate sits (column of the entrance shaft) and which
## side it is on, set by the dungeon pass. -1 means this seed has none.
var dungeon_entrance_x := -1
var dungeon_dir := 1


func generate(world_seed: int, w: int, h: int) -> void:
    width = w
    height = h
    tiles.resize(w * h)
    walls.resize(w * h)
    biomes.resize(w * h)
    surface.resize(w)

    _pass_heightmap(world_seed)
    _pass_fill(rng_for(world_seed + 1), world_seed)
    _pass_caves(world_seed)
    _pass_ores(rng_for(world_seed + 2))
    _pass_trees(rng_for(world_seed + 3))
    _pass_foliage(rng_for(world_seed + 4))
    _pass_walls()
    _pass_dungeon(rng_for(world_seed + 5))
    _find_spawn()


# ---------------------------------------------------------------- helpers

func rng_for(s: int) -> RandomNumberGenerator:
    var r := RandomNumberGenerator.new()
    r.seed = s
    return r


func _noise(s: int, freq: float, octaves: int, type: int) -> FastNoiseLite:
    var n := FastNoiseLite.new()
    n.seed = s
    n.noise_type = type
    n.frequency = freq
    n.fractal_type = FastNoiseLite.FRACTAL_FBM
    n.fractal_octaves = octaves
    return n


func _in_bounds(x: int, y: int) -> bool:
    return x >= 0 and y >= 0 and x < width and y < height


func _tile_at(x: int, y: int) -> int:
    if not _in_bounds(x, y):
        return Tile.BEDROCK
    return tiles[y * width + x]


func _put(x: int, y: int, id: int) -> void:
    if _in_bounds(x, y):
        tiles[y * width + x] = id


func _surface_tile(biome: int) -> int:
    match biome:
        Biome.DESERT: return Tile.SAND
        Biome.TUNDRA: return Tile.SNOW
        Biome.JUNGLE: return Tile.MUD
        _: return Tile.GRASS


# ---------------------------------------------------------------- pass 1

## Sample a 1D noise field across the world width and normalise it to
## 0..1 against its own observed min/max.
##
## This exists because FastNoiseLite's FBM output does NOT span [-1, 1] -
## measured over a 1600-wide world it spans roughly 0.4..0.7 depending on
## frequency and octave count. Writing tuning constants against an assumed
## [-1,1] range produces terrain that is almost flat, which is exactly
## the bug this function was added to fix.
##
## Normalising also makes the downstream constants readable: a biome
## threshold of 0.74 really does mean "the top quartile of this range".
func _sample_1d(n: FastNoiseLite) -> PackedFloat32Array:
    var out := PackedFloat32Array()
    out.resize(width)
    var lo := INF
    var hi := -INF
    for x in width:
        var v := n.get_noise_1d(x)
        out[x] = v
        lo = minf(lo, v)
        hi = maxf(hi, v)
    if hi - lo > 0.00001:
        for x in width:
            out[x] = (out[x] - lo) / (hi - lo)
    return out


## One surface height + one biome per column.
##
## A second, very low-frequency field controls how mountainous a region
## is, and scales the amplitude of the main relief field. That is what
## gives you flat plains next to big peaks instead of uniform rolling
## hills everywhere.
##
## Frequencies are in tile units: 0.0011 means one noise period per ~900
## tiles. Lower it for sweeping continents, raise it for choppy hills.
func _pass_heightmap(world_seed: int) -> void:
    var relief := _sample_1d(_noise(world_seed, 0.0011, 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH))
    var mountains := _sample_1d(_noise(world_seed + 1337, 0.0007, 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH))
    var climate := _sample_1d(_noise(world_seed + 7717, 0.0019, 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH))
    var jungle := _sample_1d(_noise(world_seed + 991, 0.0026, 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH))

    for x in width:
        var amp := lerpf(10.0, 88.0, smoothstep(0.30, 0.85, mountains[x]))
        var h := relief[x] - 0.5
        var y := height * 0.34 - h * 2.0 * amp
        y = clampf(y, height * 0.10, height * 0.68)
        surface[x] = int(y)

    # Two 3-tap smoothing passes (edge-clamped) remove the per-column
    # jitter the raw noise leaves behind, so relief reads as rolling
    # landforms instead of a picket fence. Two passes blur roughly five
    # columns - enough to soften steps, not enough to flatten mountains.
    for _pass in 2:
        var prev: int = surface[0]
        for x in width:
            var cur: int = surface[x]
            var right: int = surface[mini(x + 1, width - 1)]
            surface[x] = (prev + 2 * cur + right) / 4
            prev = cur

    # Biomes depend on the final surface row, so they are assigned after
    # smoothing rather than in the heightmap loop above.
    for x in width:
        # Climate bands, on the normalised 0..1 field.
        var c := climate[x]
        var biome := Biome.PLAINS
        if c < 0.22:
            biome = Biome.DESERT
        elif c > 0.74:
            biome = Biome.TUNDRA
        elif c < 0.48:
            biome = Biome.FOREST
        if biome != Biome.DESERT and biome != Biome.TUNDRA and jungle[x] > 0.66:
            biome = Biome.JUNGLE
        biomes[surface[x] * width + x] = biome


# ---------------------------------------------------------------- pass 2

func _pass_fill(rng: RandomNumberGenerator, world_seed: int) -> void:
    # Where dirt gives way to stone. The per-column random base keeps
    # depth roughly uniform, and the low-frequency noise wobble turns the
    # straight horizontal seam into a wavering boundary - one of the
    # details that separates "realistic ground" from a layered cake.
    var seam := _noise(world_seed + 4242, 0.018, 2, FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
    for x in width:
        var sy := surface[x]
        var biome := biomes[sy * width + x]
        var top := _surface_tile(biome)
        var dirt_depth := 4 + rng.randi_range(0, 3) \
                + int(round(seam.get_noise_1d(x) * 3.0))
        dirt_depth = maxi(dirt_depth, 3)
        for y in range(height):
            var idx := y * width + x
            biomes[idx] = biome
            if y >= height - BEDROCK_DEPTH:
                tiles[idx] = Tile.BEDROCK
            elif y >= sy:
                var depth := y - sy
                if depth == 0:
                    tiles[idx] = top
                elif depth < dirt_depth:
                    tiles[idx] = Tile.DIRT
                else:
                    tiles[idx] = Tile.STONE


# ---------------------------------------------------------------- pass 3

## Worm caves + cheese caverns.
##
## The worm trick: take two independent noise fields and carve wherever
## `abs(a) + abs(b)` falls below a threshold. Because both fields have
## to be near zero at the same time, the carved-out space forms long
## connected tunnels instead of the disconnected blobs you get from
## thresholding a single noise field.
##
## The threshold widens with depth, so the surface stays intact and
## caverns open up as you descend.
func _pass_caves(world_seed: int) -> void:
    var cave_a := _noise(world_seed + 101, 0.011, 2, FastNoiseLite.TYPE_SIMPLEX)
    var cave_b := _noise(world_seed + 202, 0.011, 2, FastNoiseLite.TYPE_SIMPLEX)
    var cavern := _noise(world_seed + 303, 0.006, 3, FastNoiseLite.TYPE_SIMPLEX)

    var floor_y := height - BEDROCK_DEPTH
    for x in width:
        var sy := surface[x]
        for y in range(sy + 4, floor_y):
            var idx := y * width + x
            if tiles[idx] == Tile.BEDROCK:
                continue

            var depth := float(y - sy) / float(maxi(height - sy, 1))
            var worm_thr := lerpf(0.16, 0.60, clampf(depth, 0.0, 1.0))
            var a := cave_a.get_noise_2d(x, y)
            var b := cave_b.get_noise_2d(x, y)
            var carve := absf(a) + absf(b) < worm_thr

            if not carve and depth > 0.40:
                carve = cavern.get_noise_2d(x, y) > lerpf(0.84, 0.50, depth)

            if carve:
                tiles[idx] = Tile.AIR


# ---------------------------------------------------------------- pass 4

## Ores are depth-gated, so copper sits near the top and gold hugs the
## bedrock. Each deposit is a short random walk rather than a single
## tile, which stops them looking like salt-and-pepper noise.
func _pass_ores(rng: RandomNumberGenerator) -> void:
    var ore_ids := [Tile.COPPER, Tile.IRON, Tile.GOLD]
    var ore_min := [0.05, 0.32, 0.72]
    var ore_max := [0.78, 0.93, 0.99]
    var ore_count := [240, 170, 60]
    var ore_blob := [16, 11, 7]

    var floor_y := height - BEDROCK_DEPTH - 1
    for k in ore_ids.size():
        var id: int = ore_ids[k]
        for n in ore_count[k]:
            var x := rng.randi_range(2, width - 3)
            var sy := surface[x]
            var y0 := int(lerpf(float(sy), float(floor_y), ore_min[k]))
            var y1 := int(lerpf(float(sy), float(floor_y), ore_max[k]))
            var cx := x
            var cy := rng.randi_range(mini(y0, y1), maxi(y0, y1))

            for step in ore_blob[k]:
                _put(cx, cy, id)
                var dir := rng.randi_range(0, 3)
                match dir:
                    0: cx += 1
                    1: cx -= 1
                    2: cy += 1
                    _: cy -= 1
                cx = clampi(cx, 1, width - 2)
                cy = clampi(cy, sy + 2, floor_y)


# ---------------------------------------------------------------- pass 5

## Terraria-style trees: a straight 1-tile trunk that actually reaches
## the ground, a big ragged canopy around the trunk top, and 0-2 small
## branches ending in their own leaf puffs.
##
## Height is total (apex to ground): 9-15 tiles, which puts the canopy
## well above jump height so a forest reads as a ceiling of leaves.
func _pass_trees(rng: RandomNumberGenerator) -> void:
    var x := 4
    while x < width - 5:
        var sy := surface[x]
        var biome := biomes[sy * width + x]
        var density := 0.0
        match biome:
            Biome.FOREST: density = 0.60
            Biome.PLAINS: density = 0.09
            Biome.JUNGLE: density = 0.78
            Biome.TUNDRA: density = 0.05
            Biome.DESERT: density = 0.0

        if density > 0.0 and rng.randf() < density \
                and tiles[sy * width + x] == _surface_tile(biome):
            _place_tree(x, sy, rng)
            x += rng.randi_range(3, 8)
        else:
            x += 1


func _place_tree(x: int, ground_y: int, rng: RandomNumberGenerator) -> void:
    var hgt := rng.randi_range(9, 15)
    var top_y := ground_y - hgt
    var rx := rng.randf_range(3.4, 4.6)
    var ry := rng.randf_range(2.6, 3.4)
    var canopy_r := ceili(ry)
    var cy := top_y + canopy_r  # canopy centre: apex row lands exactly on top_y

    # Every trunk cell, ground to apex, must be air - or the tree is
    # skipped entirely. Trees never cut into a hillside, and pre-checking
    # means a blocked tree leaves nothing behind instead of a stub.
    for y in range(ground_y - 1, top_y - 1, -1):
        if _tile_at(x, y) != Tile.AIR:
            return
    for y in range(ground_y - 1, top_y - 1, -1):
        _put(x, y, Tile.WOOD)

    # Canopy: ragged ellipse centred on the trunk top. Leaves only ever
    # fill air, so the trunk column stays WOOD - the crown grows around
    # the trunk and terrain clips it naturally.
    for dy in range(-canopy_r, canopy_r + 1):
        for dx in range(-ceili(rx), ceili(rx) + 1):
            var u := float(dx) / rx
            var v := float(dy) / ry
            var f := u * u + v * v
            var edge := 1.0
            var chance := 1.0
            if f > 1.0:
                # Fringe: sparse tufts past the smooth outline, so the
                # canopy silhouette is ragged like Terraria's instead of
                # a clean oval.
                edge = 1.5
                chance = 0.20
            if f <= edge and rng.randf() < chance \
                    and _tile_at(x + dx, cy + dy) == Tile.AIR:
                _put(x + dx, cy + dy, Tile.LEAVES)

    _place_branches(x, ground_y, top_y, canopy_r, rng)


## A branch is a short horizontal-then-rising line of wood off the upper
## trunk, capped with a small puff of leaves. Only air cells are touched.
func _place_branches(x: int, ground_y: int, top_y: int, canopy_r: int,
        rng: RandomNumberGenerator) -> void:
    var lo := top_y + 2 * canopy_r + 1  # first trunk row below the canopy
    var hi := ground_y - 4              # branches stay off the ground
    if hi < lo:
        return

    var count := 0
    var roll := rng.randf()
    if roll > 0.85:
        count = 2
    elif roll > 0.50:
        count = 1

    for b in count:
        var by := rng.randi_range(lo, hi)
        var dir := rng.randi_range(0, 1) * 2 - 1
        var reach := rng.randi_range(2, 3)
        var cells := PackedVector2Array()
        for s in range(1, reach + 1):
            # s / 2 is intentional integer division: the branch runs
            # horizontal for one step, then rises (1/2 == 0, 2/2 == 1).
            var cx := x + dir * s
            var cy := by - s / 2
            if _tile_at(cx, cy) != Tile.AIR:
                cells.clear()
                break
            cells.append(Vector2i(cx, cy))
        if cells.is_empty():
            continue
        for c in cells:
            _put(c.x, c.y, Tile.WOOD)
        var tip: Vector2i = cells[cells.size() - 1]
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                var u := float(dx) / 2.2
                var v := float(dy) / 1.7
                if u * u + v * v <= 1.0 and _tile_at(tip.x + dx, tip.y + dy) == Tile.AIR:
                    _put(tip.x + dx, tip.y + dy, Tile.LEAVES)


# ---------------------------------------------------------------- pass 6

## Grass tufts, wild grass and flowers on grassy/muddy ground - purely
## decorative (NON_SOLID). Only ever placed in the air cell directly
## above the surface, so foliage can never float or bury itself, and
## never where a trunk or branch already stands.
func _pass_foliage(rng: RandomNumberGenerator) -> void:
    for x in width:
        var sy := surface[x]
        var ground := tiles[sy * width + x]
        if ground != Tile.GRASS and ground != Tile.MUD:
            continue
        if tiles[(sy - 1) * width + x] != Tile.AIR:
            continue
        var density := 0.62 if ground == Tile.MUD else 0.55
        if rng.randf() >= density:
            continue
        var pick := rng.randf()
        if pick < 0.40:
            _put(x, sy - 1, Tile.GRASS_TUFT)
        elif pick < 0.75:
            _put(x, sy - 1, Tile.WILD_GRASS)
        else:
            _put(x, sy - 1, Tile.FLOWER)


# ---------------------------------------------------------------- pass 7

## Give every underground air tile a background wall.
##
## This started out as a flood-fill from the sky, which was wrong. The
## worm-cave network is one connected component and it always reaches
## daylight *somewhere*, so a single surface opening marked the entire
## cave system as sky-exposed and no walls were ever placed.
##
## Terraria's actual rule is simpler and more robust: walls exist
## everywhere below the surface, independent of whether you can see sky
## from there. A cave mouth on a hillside therefore shows the dirt bank
## behind it, which is exactly what you want.
func _pass_walls() -> void:
    for x in width:
        var sy := surface[x]
        for y in range(sy + 2, height):
            var idx := y * width + x
            if tiles[idx] == Tile.AIR:
                walls[idx] = Tile.STONE_WALL


# ---------------------------------------------------------------- pass 8

## Procedural dungeon: a random walk of brick rooms joined by corridors,
## an entrance shaft from the surface, and a gated doorway on top.
##
## Runs last so the rooms can claim their own background (DUNGEON_WALL)
## instead of the generic stone wall the surface rule hands out.
##
## Traversability drives the shapes: corridors are straight runs plus a
## zig-zag staircase (climbable in both directions with a 3.5-tile
## jump), and the entrance shaft gets alternating brick treads - a
## chimney ladder you can jump up one row at a time, while the open
## centre column lets you drop straight back down.
func _pass_dungeon(rng: RandomNumberGenerator) -> void:
    var dir := 1 if rng.randf() < 0.5 else -1
    var entrance_x := clampi(width / 2 + dir * rng.randi_range(240, 420),
            70, width - 70)
    dungeon_dir = dir
    dungeon_entrance_x = entrance_x
    var base_y := surface[entrance_x] + rng.randi_range(45, 65)

    # --- layout: one room per accepted step of a clamped grid walk.
    var spx := 13
    var spy := 10
    var walk: Array[Vector2i] = [Vector2i.ZERO]
    var cell := Vector2i.ZERO
    var dirs: Array[Vector2i] = [
        Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
    for i in range(1, rng.randi_range(6, 9)):
        var next := cell + dirs[rng.randi_range(0, 3)]
        next.x = clampi(next.x, -4, 4)
        next.y = clampi(next.y, -1, 2)
        if walk.has(next):
            continue
        cell = next
        walk.append(cell)

    # --- carve the rooms, remembering centres for corridors and the
    # top row of room 0 for the entrance shaft. Room 0 is fixed at 5
    # tall so the climbing treads line up with its floor.
    var carved: Array[Vector2i] = []
    var treads: Array[Vector2i] = []
    var centers: Array[Vector2i] = []
    var room0_top := base_y
    for g in walk.size():
        var w := rng.randi_range(7, 10)
        var h := 5 if g == 0 else rng.randi_range(5, 6)
        var cx := entrance_x + walk[g].x * spx
        var cy := base_y + walk[g].y * spy
        centers.append(Vector2i(cx, cy))
        if g == 0:
            room0_top = cy - h / 2
        for yy in range(cy - h / 2, cy - h / 2 + h):
            for xx in range(cx - w / 2, cx - w / 2 + w):
                _dungeon_carve(xx, yy, carved)

    for g in range(1, walk.size()):
        _dungeon_corridor(centers[g - 1], centers[g], carved, treads)

    # --- cut every tree standing in the gate's footprint first: a shaft
    # through a trunk would leave a floating canopy and trip the
    # grounded-trunk check. 24 rows covers the tallest tree plus canopy.
    for c in range(entrance_x - 3, entrance_x + 4):
        if c < 0 or c >= width:
            continue
        for y in range(maxi(surface[c] - 24, 0), surface[c]):
            var i := y * width + c
            if tiles[i] == Tile.WOOD or tiles[i] == Tile.LEAVES:
                tiles[i] = Tile.AIR

    # --- gate: brick frame (pillars + lintel) around an opening that
    # connects down into the shaft, with a doorway cut through the wall
    # on the side you approach from. lintel = min surface of the five
    # gate columns, six rows up.
    var gx0 := entrance_x - 2
    var gx1 := entrance_x + 2
    var min_sy := surface[entrance_x]
    for c in range(gx0, gx1 + 1):
        min_sy = mini(min_sy, surface[c])
    var lintel := min_sy - 6
    # The approach side is fully open, roof to ground: a waist-high door
    # would be sealed off whenever the outside terrain sits higher, and
    # would leave the dungeon unreachable without digging.
    var door_col := gx0 if dir == 1 else gx1
    for c in range(gx0, gx1 + 1):
        if c == door_col:
            continue
        for y in range(lintel, surface[c] + 1):
            if c == gx0 or c == gx1 or y == lintel:
                _dungeon_brick(c, y)
    # doorway column: clear the air side of the frame (also removes any
    # foliage standing there) and keep its ground row as the floor
    for y in range(lintel, surface[door_col]):
        _dungeon_carve(door_col, y, carved)
    # interior between the lintel and the ground
    for c in range(entrance_x - 1, entrance_x + 2):
        for y in range(lintel + 1, surface[c]):
            _dungeon_carve(c, y, carved)

    # --- entrance shaft: three columns from the surface into room 0...
    for c in range(entrance_x - 1, entrance_x + 2):
        for y in range(surface[c], room0_top):
            _dungeon_carve(c, y, carved)

    # ...plus the chimney ladder: alternating brick treads every row so
    # the shaft can be climbed back out (each jump rises one row and
    # moves two across), from 2 rows above room 0 up to 3 rows below the
    # surface. The centre column stays clear so you can drop straight
    # back down. One tread inside room 0 bridges the last 3-tile gap
    # from its floor.
    var side := -1
    for y in range(room0_top - 2, surface[entrance_x] + 2, -1):
        _dungeon_tread(entrance_x + side, y, treads)
        side = -side
    _dungeon_tread(entrance_x - 1, room0_top + 1, treads)

    # --- line the excavation with two layers of brick. The frontier only
    # ever grows from carved *air*, so surface foliage and terrain a few
    # columns away are never swallowed by the dilation.
    var brick: Array[Vector2i] = []
    var frontier: Array[Vector2i] = carved
    for layer in 2:
        var next_frontier: Array[Vector2i] = []
        for p in frontier:
            for dx in range(-1, 2):
                for dy in range(-1, 2):
                    if dx == 0 and dy == 0:
                        continue
                    var nx: int = p.x + dx
                    var ny: int = p.y + dy
                    if not _in_bounds(nx, ny) or ny >= height - BEDROCK_DEPTH:
                        continue
                    var ni := ny * width + nx
                    if tiles[ni] == Tile.AIR:
                        continue
                    if tiles[ni] == Tile.DUNGEON_BRICK:
                        continue
                    _dungeon_brick(nx, ny)
                    next_frontier.append(Vector2i(nx, ny))
                    brick.append(Vector2i(nx, ny))
        frontier = next_frontier

    # --- lay the collected treads down last: later excavation (other
    # corridors, the shaft) may have passed through their cells.
    for t in treads:
        _dungeon_brick(t.x, t.y)

    # --- treasure: a few gold veins mixed into the lining.
    if not brick.is_empty():
        for n in rng.randi_range(4, 7):
            var p: Vector2i = brick[rng.randi_range(0, brick.size() - 1)]
            tiles[p.y * width + p.x] = Tile.GOLD

    # --- anything the dungeon built ground under must lose its foliage.
    for i in width * height - width:
        var id: int = tiles[i]
        if id == Tile.GRASS_TUFT or id == Tile.WILD_GRASS \
                or id == Tile.FLOWER:
            var below: int = tiles[i + width]
            if below != Tile.GRASS and below != Tile.MUD:
                tiles[i] = Tile.AIR


func _dungeon_carve(x: int, y: int, carved: Array[Vector2i]) -> void:
    if not _in_bounds(x, y) or y >= height - BEDROCK_DEPTH:
        return
    var i := y * width + x
    tiles[i] = Tile.AIR
    # Below the surface rule (sy+2) the excavation keeps a background
    # wall (upgraded to dungeon wall); sky-adjacent cells stay open so
    # the gate reads as a doorway.
    if y >= surface[x] + 2:
        walls[i] = Tile.DUNGEON_WALL
    else:
        walls[i] = Tile.AIR
    carved.append(Vector2i(x, y))


func _dungeon_brick(x: int, y: int) -> void:
    if not _in_bounds(x, y) or y >= height - BEDROCK_DEPTH:
        return
    var i := y * width + x
    tiles[i] = Tile.DUNGEON_BRICK
    walls[i] = Tile.AIR  # solid never keeps a wall behind it


func _dungeon_tread(x: int, y: int, treads: Array[Vector2i]) -> void:
    if _in_bounds(x, y):
        treads.append(Vector2i(x, y))


## L-shaped corridor with a zig-zag staircase on the vertical leg. The
## centre column is carved at every step (that is the cell you actually
## step through) and each side visit records a tread under itself, so
## the staircase works in both directions.
func _dungeon_corridor(a: Vector2i, b: Vector2i, carved: Array[Vector2i],
        treads: Array[Vector2i]) -> void:
    var x := a.x
    var y := a.y
    var step_x := 1 if b.x >= a.x else -1
    while x != b.x:
        _dungeon_corridor_row(x, y, carved)
        x += step_x
    _dungeon_corridor_row(x, y, carved)

    var step_y := 1 if b.y >= a.y else -1
    var n := 0
    while y != b.y:
        var y_prev := y
        y += step_y
        n += 1
        var side := b.x + (1 if n % 2 == 1 else -1)
        _dungeon_corridor_row(side, y, carved)
        _dungeon_corridor_row(b.x, y_prev, carved)
        _dungeon_corridor_row(b.x, y, carved)
        treads.append(Vector2i(side, y + 1))
    _dungeon_corridor_row(b.x, y, carved)


func _dungeon_corridor_row(x: int, y: int, carved: Array[Vector2i]) -> void:
    for dy in range(-3, 1):  # foot cell plus three tiles of headroom
        _dungeon_carve(x, y + dy, carved)


# ---------------------------------------------------------------- spawn

func _find_spawn() -> void:
    var walkable := [Tile.GRASS, Tile.SAND, Tile.SNOW, Tile.MUD,
                     Tile.DIRT, Tile.STONE]
    var cx := width / 2
    for d in range(0, width / 2):
        for x in [cx + d, cx - d]:
            if x < 1 or x >= width - 1:
                continue
            var xx := int(x)
            var sy := surface[xx]
            if walkable.has(tiles[sy * width + xx]):
                spawn = Vector2i(xx, sy - 3)
                return
    spawn = Vector2i(cx, maxi(surface[cx] - 3, 2))
