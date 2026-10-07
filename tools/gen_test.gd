extends SceneTree

## Headless sanity check for the generator. Not part of the game.
##
##   godot --headless --path . --script res://tools/gen_test.gd
##
## Prints timing, a tile histogram, biome distribution, and asserts the
## invariants that are easy to break while tuning: bedrock floor intact,
## spawn in open air with sky above, no wall on a tile that holds a block.

const W := 1600
const H := 400
const NAMES := ["AIR", "DIRT", "GRASS", "STONE", "SAND", "SNOW", "MUD",
        "WOOD", "LEAVES", "COPPER", "IRON", "GOLD", "BEDROCK",
        "PLANK_WALL", "STONE_WALL", "GRASS_TUFT", "WILD_GRASS", "FLOWER",
        "DUNGEON_BRICK", "DUNGEON_WALL"]


func _initialize() -> void:
    var failures: Array[String] = []
    var gen := WorldGen.new()

    var t0 := Time.get_ticks_msec()
    gen.generate(abs(hash("cavebound")), W, H)
    var ms := Time.get_ticks_msec() - t0

    var counts := PackedInt32Array()
    counts.resize(WorldGen.TILE_COUNT)
    for t in gen.tiles:
        counts[t] += 1

    print("\n=== Cavebound worldgen ===")
    print("seed=%d  %dx%d  generated in %d ms (%.1f cells/ms)"
            % [abs(hash("cavebound")), W, H, ms, float(W * H) / maxf(ms, 1)])

    print("\n-- tiles --")
    for id in WorldGen.TILE_COUNT:
        var pct := 100.0 * counts[id] / (W * H)
        print("  %-11s %8d  %5.2f%%"
                % [NAMES[id], counts[id], pct])

    print("\n-- biomes --")
    var biome_hits := PackedInt32Array()
    biome_hits.resize(5)
    for x in W:
        biome_hits[gen.biomes[gen.surface[x] * W + x]] += 1
    var names := ["Plains", "Forest", "Desert", "Jungle", "Tundra"]
    for b in 5:
        if biome_hits[b] > 0:
            print("  %-8s %5d cols  %5.1f%%"
                    % [names[b], biome_hits[b], 100.0 * biome_hits[b] / W])

    var wall_count := 0
    for wv in gen.walls:
        if wv != WorldGen.Tile.AIR:
            wall_count += 1
    print("\n-- background --")
    print("  walls     %d  (%.1f%% of all cells)" % [wall_count, 100.0 * wall_count / (W * H)])

    # --- terrain shape ---
    var s_min := gen.surface[0]
    var s_max := gen.surface[0]
    var s_sum := 0
    for x in W:
        s_min = mini(s_min, gen.surface[x])
        s_max = maxi(s_max, gen.surface[x])
        s_sum += gen.surface[x]
    print("\n-- terrain --")
    print("  surface y   min %d   avg %d   max %d" % [s_min, s_sum / W, s_max])

    var carved := 0
    var rock := 0
    for x in W:
        var sy := gen.surface[x]
        for y in range(sy + 4, H - WorldGen.BEDROCK_DEPTH):
            if gen.tiles[y * W + x] == WorldGen.Tile.AIR:
                carved += 1
            else:
                rock += 1
    print("  underground  %d air / %d rock  -> %.1f%% carved"
            % [carved, rock, 100.0 * carved / float(carved + rock)])

    # --- invariants ---

    for x in W:
        if gen.tiles[(H - 1) * W + x] != WorldGen.Tile.BEDROCK:
            failures.append("no bedrock at bottom, x=%d" % x)
            break

    var s := gen.spawn
    if gen.tiles[s.y * W + s.x] != WorldGen.Tile.AIR:
        failures.append("spawn is inside a solid tile at %s" % s)
    var sky := true
    for y in range(0, s.y):
        if gen.tiles[y * W + s.x] != WorldGen.Tile.AIR:
            sky = false
            break
    if not sky:
        failures.append("spawn is buried, no open sky above at %s" % s)

    for i in W * H:
        if gen.tiles[i] != WorldGen.Tile.AIR and gen.walls[i] != WorldGen.Tile.AIR:
            failures.append("wall behind solid tile at index %d" % i)
            break

    if counts[WorldGen.Tile.AIR] == 0:
        failures.append("no air at all - caves never carved")

    # --- dungeon ---
    var dwall_count := 0
    for wv in gen.walls:
        if wv == WorldGen.Tile.DUNGEON_WALL:
            dwall_count += 1
    print("\n-- dungeon --")
    print("  %d dungeon bricks   %d dungeon-walled cells"
            % [counts[WorldGen.Tile.DUNGEON_BRICK], dwall_count])
    if counts[WorldGen.Tile.DUNGEON_BRICK] < 100:
        failures.append("dungeon missing: only %d dungeon bricks"
                % counts[WorldGen.Tile.DUNGEON_BRICK])
    if dwall_count < 100:
        failures.append("dungeon missing: only %d dungeon-walled cells"
                % dwall_count)

    if not TilesetFactory.SOLID.has(WorldGen.Tile.DUNGEON_BRICK):
        failures.append("DUNGEON_BRICK missing from SOLID")
    if TilesetFactory.SOLID.has(WorldGen.Tile.DUNGEON_WALL):
        failures.append("DUNGEON_WALL is solid - it is background")
    if not TilesetFactory.NON_SOLID.has(WorldGen.Tile.DUNGEON_WALL):
        failures.append("DUNGEON_WALL missing from NON_SOLID")

    # The gate must rise above ground somewhere (a structure, not a
    # hidden basement entrance).
    var gate := 0
    for x in W:
        for y in range(gen.surface[x]):
            if gen.tiles[y * W + x] == WorldGen.Tile.DUNGEON_BRICK:
                gate += 1
    if gate == 0:
        failures.append("no dungeon gate above the surface")

    # Reachability: flood the walk-through map (non-SOLID cells) from
    # spawn and require it to touch dungeon-walled air. Catches a
    # dungeon sealed behind its own brickwork.
    var seen := PackedByteArray()
    seen.resize(W * H)
    var queue: Array[int] = [gen.spawn.y * W + gen.spawn.x]
    var head := 0
    var touched := 0
    while head < queue.size():
        var idx: int = queue[head]
        head += 1
        if seen[idx] == 1:
            continue
        seen[idx] = 1
        if gen.walls[idx] == WorldGen.Tile.DUNGEON_WALL:
            touched += 1
        var qx := idx % W
        var qy := idx / W
        var nb: Array[int] = []
        if qx > 0:
            nb.append(idx - 1)
        if qx < W - 1:
            nb.append(idx + 1)
        if qy > 0:
            nb.append(idx - W)
        if qy < H - 1:
            nb.append(idx + W)
        for n in nb:
            if seen[n] == 0 and not TilesetFactory.SOLID.has(gen.tiles[n]):
                queue.append(n)
    if touched == 0:
        failures.append("dungeon not reachable from spawn")
    else:
        print("  reachable from spawn: %d dungeon cells touched" % touched)

    # The entrance shaft must be climbable back out: locate its centre
    # (air column below ground) and require alternating brick treads on
    # both walls - a dungeon you can only fall into is a trap, not a
    # destination.
    var shaft := _find_shaft(gen)
    if shaft == -1:
        failures.append("no entrance shaft with chimney treads found")
    else:
        print("  shaft at x=%d climbable: treads both walls" % shaft)

    # Trees must be walk-through. If WOOD/LEAVES ever get a collision
    # polygon, a forest becomes impassable: trunks sit every 3-8 tiles and
    # are 9-15 tall, but a jump only clears ~3.5 tiles. Same for the
    # surface decoration - a solid tuft is an invisible wall at ankle
    # height.
    for id in [WorldGen.Tile.WOOD, WorldGen.Tile.LEAVES,
               WorldGen.Tile.GRASS_TUFT, WorldGen.Tile.WILD_GRASS,
               WorldGen.Tile.FLOWER]:
        if TilesetFactory.SOLID.has(id):
            failures.append("%s is solid - player will be trapped by trees"
                    % NAMES[id])
        if not TilesetFactory.NON_SOLID.has(id):
            failures.append("%s missing from NON_SOLID" % NAMES[id])

    # Trees must reach the ground: a trunk row directly above the surface,
    # and never a trunk body with air underneath it (the original
    # generator started the trunk one row too high, so every tree
    # floated). Requiring two stacked wood rows above the gap matters:
    # a branch cell is a single isolated wood tile that can legally sit
    # two rows above a neighbouring column's surface.
    var grounded := 0
    for x in W:
        var sy := gen.surface[x]
        if gen.tiles[(sy - 1) * W + x] == WorldGen.Tile.WOOD:
            grounded += 1
        elif gen.tiles[(sy - 1) * W + x] == WorldGen.Tile.AIR \
                and gen.tiles[(sy - 2) * W + x] == WorldGen.Tile.WOOD \
                and gen.tiles[(sy - 3) * W + x] == WorldGen.Tile.WOOD:
            failures.append("floating trunk bottom at x=%d" % x)
            break
    if grounded == 0:
        failures.append("no tree trunk touches the ground - trees float")

    # Surface foliage lives exactly in the air cell above grassy or muddy
    # ground: never floating in the sky, never buried below the surface,
    # never sitting on sand/snow/stone.
    var foliage := 0
    for i in W * H:
        var id: int = gen.tiles[i]
        if id != WorldGen.Tile.GRASS_TUFT and id != WorldGen.Tile.WILD_GRASS \
                and id != WorldGen.Tile.FLOWER:
            continue
        foliage += 1
        var fx := i % W
        var fy := i / W
        var fsy := gen.surface[fx]
        if fy != fsy - 1:
            failures.append("%s at (%d,%d) is not directly above the surface (y=%d)"
                    % [NAMES[id], fx, fy, fsy])
            break
        var below: int = gen.tiles[(fy + 1) * W + fx]
        if below != WorldGen.Tile.GRASS and below != WorldGen.Tile.MUD:
            failures.append("%s at (%d,%d) sits on %s, not grass/mud"
                    % [NAMES[id], fx, fy, NAMES[below]])
            break
    if foliage == 0:
        failures.append("no surface grass/flowers generated")

    # Nothing solid may float above the local surface. Cave ceilings are
    # fine (below it); this catches generation mistakes that drop blocks
    # into the sky and would look like invisible walls. The dungeon gate
    # is the one legal exception - it deliberately rises above ground.
    var floating := 0
    for x in W:
        var sy := gen.surface[x]
        for y in range(0, sy):
            var fid: int = gen.tiles[y * W + x]
            if fid == WorldGen.Tile.DUNGEON_BRICK:
                continue
            if TilesetFactory.SOLID.has(fid):
                floating += 1
    if floating > 0:
        failures.append("%d solid tiles floating above the surface" % floating)

    print("\n-- result --")
    if failures.is_empty():
        print("  all checks passed")
        quit(0)
    else:
        for f in failures:
            print("  FAIL: %s" % f)
        quit(1)


## The shaft centre: a mostly-air column below ground whose two
## neighbours carry enough dungeon-brick treads to climb back out.
## Returns x, or -1 when no climbable shaft exists.
func _find_shaft(gen: WorldGen) -> int:
    for x in range(1, W - 1):
        var sy := gen.surface[x]
        if sy + 40 >= H:
            continue
        var air := 0
        var tl := 0
        var tr := 0
        for y in range(sy + 2, sy + 40):
            var i := y * W + x
            if gen.tiles[i] == WorldGen.Tile.AIR:
                air += 1
            if gen.tiles[i - 1] == WorldGen.Tile.DUNGEON_BRICK:
                tl += 1
            if gen.tiles[i + 1] == WorldGen.Tile.DUNGEON_BRICK:
                tr += 1
        if air >= 30 and tl >= 8 and tr >= 8:
            return x
    return -1
