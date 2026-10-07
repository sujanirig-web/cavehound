extends SceneTree

## Noise probe: prints the real min/max/mean of each noise field across
## the world width, so the tuning constants in world_gen.gd are based on
## measured output rather than the assumption that it spans [-1, 1].
##
##   godot --headless --path . --script res://tools/noise_probe.gd

const W := 1600
const H := 400
const S := 4048236412


func _initialize() -> void:
    print("\n=== noise probe (x=0..%d) ===" % W)

    _row("relief  f=0.0016 oct=5", _n(S, 0.0016, 5))
    _row("relief  f=0.0016 oct=3", _n(S, 0.0016, 3))
    _row("relief  f=0.0012 oct=3", _n(S, 0.0012, 3))
    _row("relief  f=0.0006 oct=3", _n(S, 0.0006, 3))
    _row("mount   f=0.00028 oct=2", _n(S + 1337, 0.00028, 2))
    _row("mount   f=0.0009 oct=2", _n(S + 1337, 0.0009, 2))
    _row("climate f=0.00045 oct=2", _n(S + 7717, 0.00045, 2))
    _row("climate f=0.0018 oct=2", _n(S + 7717, 0.0018, 2))
    _row("jungle  f=0.0009 oct=2", _n(S + 991, 0.0009, 2))
    _row("jungle  f=0.0025 oct=2", _n(S + 991, 0.0025, 2))

    quit(0)


func _n(s: int, freq: float, oct: int) -> FastNoiseLite:
    var n := FastNoiseLite.new()
    n.seed = s
    n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    n.frequency = freq
    n.fractal_type = FastNoiseLite.FRACTAL_FBM
    n.fractal_octaves = oct
    return n


func _row(label: String, n: FastNoiseLite) -> void:
    var lo := INF
    var hi := -INF
    var sum := 0.0
    for x in W:
        var v := n.get_noise_1d(x)
        lo = minf(lo, v)
        hi = maxf(hi, v)
        sum += v
    print("  %-26s min %+.3f  max %+.3f  mean %+.3f  span %.3f"
            % [label, lo, hi, sum / W, hi - lo])
