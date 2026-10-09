class_name Lighting
extends RefCounted

## Bakes a static 2D lightmap from a generated world: sky light floods down
## from the top of the map and creeps sideways into cave mouths, dying out a
## tile or two into rock. It is a pure function of the world data, so the
## same seed always produces the same light (checked by tools/light_test.gd).
##
## The result is a world-sized image whose RGB is the cave tint and whose
## alpha is darkness: 0 = fully lit (open sky), ~0.85 = deep cave. The
## atmosphere node draws it as an overlay above the terrain and below the
## entities, so caves go dark and the surface stays lit.

const LIT := 255
const AIR_COST := 5        # light lost per air tile in a cave (fades ~50 tiles)
const SOLID_COST := 65     # light lost per rock tile (gradient ~4 tiles deep)
const SURFACE_BONUS := 30  # exposed rock inherits most of the nearby air light
const MAX_DARK := 0.72     # alpha of the darkest cave (never pitch black)
const CAVE := Color(0.03, 0.045, 0.08)


static func bake(gen: WorldGen) -> Image:
    var w: int = gen.width
    var h: int = gen.height
    var n := w * h
    var light := PackedByteArray()
    light.resize(n)

    # Per-cell light cost, precomputed once so the sweeps are a single
    # table read per neighbour. The solidity lookup is a 256-entry table
    # built once (SOLID.has() is a linear scan and would be O(n*11) here).
    var solid := PackedByteArray()
    solid.resize(256)
    for t in 256:
        solid[t] = 1 if TilesetFactory.SOLID.has(t) else 0
    var cost := PackedByteArray()
    cost.resize(n)
    for i in n:
        cost[i] = SOLID_COST if solid[gen.tiles[i]] != 0 else AIR_COST

    # Seed the sky: every open cell from the top of the map down to the
    # ground row (open sky, tree canopies, cave-mouth lips) starts fully
    # lit, so sunlight does not attenuate in the ~170-tile air column.
    # Only the flood into underground caves pays the air cost.
    for x in w:
        var sy: int = gen.surface[x]
        for y in sy:
            var i := y * w + x
            if cost[i] != SOLID_COST:
                light[i] = LIT

    # Relaxation sweeps: alternating forward/backward passes push light to
    # the right/down then left/up neighbours, subtracting the per-cell
    # cost. Flat arrays, no queues - cheaper than a bucket queue and just
    # as deterministic. Four sweeps: each forward pass cascades a full row
    # and column of caves, so two per direction clears the geometry.
    for sweep in 4:
        if sweep % 2 == 0:
            for y in h:
                var row := y * w
                for x in w:
                    var i := row + x
                    var lv: int = light[i]
                    if lv == 0:
                        continue
                    if x < w - 1:
                        var nr: int = lv - cost[i + 1]
                        if nr > light[i + 1]:
                            light[i + 1] = nr
                    if y < h - 1:
                        var dn: int = lv - cost[i + w]
                        if dn > light[i + w]:
                            light[i + w] = dn
        else:
            for y in range(h - 1, -1, -1):
                var row := y * w
                for x in range(w - 1, -1, -1):
                    var i := row + x
                    var lv: int = light[i]
                    if lv == 0:
                        continue
                    if x > 0:
                        var lf: int = lv - cost[i - 1]
                        if lf > light[i - 1]:
                            light[i - 1] = lf
                    if y > 0:
                        var up: int = lv - cost[i - w]
                        if up > light[i - w]:
                            light[i - w] = up

    # Exposed rock should read as lit, not as the deep-shadow the flood gave
    # it: any solid touching lit air inherits that light minus a small
    # penalty. This is what puts a readable rim on cave walls and surfaces.
    var lit := PackedByteArray()
    lit.resize(n)
    for y in h:
        for x in w:
            var i := y * w + x
            if solid[gen.tiles[i]] == 0:
                lit[i] = light[i]
                continue
            var best := 0
            if x > 0 and solid[gen.tiles[i - 1]] == 0:
                best = maxi(best, light[i - 1])
            if x < w - 1 and solid[gen.tiles[i + 1]] == 0:
                best = maxi(best, light[i + 1])
            if y > 0 and solid[gen.tiles[i - w]] == 0:
                best = maxi(best, light[i - w])
            if y < h - 1 and solid[gen.tiles[i + w]] == 0:
                best = maxi(best, light[i + w])
            lit[i] = maxi(light[i], best - SURFACE_BONUS) if best > 0 else light[i]

    return _to_image(lit, w, h)


static func _to_image(light: PackedByteArray, w: int, h: int) -> Image:
    var data := PackedByteArray()
    data.resize(w * h * 4)
    var r := int(CAVE.r * 255.0)
    var g := int(CAVE.g * 255.0)
    var b := int(CAVE.b * 255.0)
    for i in w * h:
        var dark := 1.0 - float(light[i]) / float(LIT)
        var o := i * 4
        data[o] = r
        data[o + 1] = g
        data[o + 2] = b
        data[o + 3] = int(clampf(dark * MAX_DARK, 0.0, 1.0) * 255.0)
    return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
