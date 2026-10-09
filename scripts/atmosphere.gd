extends Node2D

## The "look" layer: a baked static lightmap (dark caves, lit surface), a
## warm light that follows the player, a dusk sky behind everything, and a
## full-screen colour grade + vignette. Purely visual - it never touches the
## generator or gameplay data. The lightmap bakes on a worker thread as soon
## as the world exists (overlapping the frame-sliced paint, so boot never
## freezes) and the rest builds itself after the loading screen hides, so
## world.gd needs no wiring.
##
## Draw order (z): sky -1000 < walls -10 < tiles 0 < lightmap 40 <
## player glow 50 < entities 60. The grade lives on a CanvasLayer under the
## HUD so the UI stays crisp.

const TILE := 16
const SKY_Z := -1000
const LIGHTMAP_Z := 40
const GLOW_Z := 50

var _built := false
var _bake_started := false
var _bake_thread: Thread
var _bake_img: Image


func _ready() -> void:
    # Gen can take ~1s and the paint is frame-sliced, so wait for it.
    set_process(true)


## The bake runs on a worker thread so the boot never freezes: `gen` is
## read-only until the loading screen hides (player actions no-op while
## loading), so the thread only ever reads the world arrays. If the paint
## wins the race the lightmap simply pops in a frame later.
func _process(_delta: float) -> void:
    if _built:
        return
    var main := get_parent()
    if main == null:
        return
    var gen: WorldGen = main.get("gen")
    if gen == null:
        return
    if not _bake_started:
        _bake_started = true
        _bake_thread = Thread.new()
        _bake_thread.start(_thread_bake.bind(gen))
    var loading: Control = main.get("loading")
    if loading != null and loading.visible:
        return
    if _bake_thread != null and _bake_thread.is_alive():
        return  # paint won the race; the lightmap lands in a moment
    if _bake_thread != null and _bake_thread.is_started():
        _bake_thread.wait_to_finish()
        _bake_thread = null
    _build(main)
    _built = true
    set_process(false)


func _thread_bake(gen: WorldGen) -> void:
    _bake_img = Lighting.bake(gen)


func _exit_tree() -> void:
    if _bake_thread != null and _bake_thread.is_started():
        _bake_thread.wait_to_finish()
        _bake_thread = null


func _build(main: Node) -> void:
    var gen: WorldGen = main.get("gen")
    var world_px := Vector2(gen.width * TILE, gen.height * TILE)
    var t0 := Time.get_ticks_msec()

    _add_sky(world_px)
    if _bake_img != null:
        _add_lightmap(_bake_img)
    _add_player_glow()
    _add_grade()

    print("atmosphere built in %d ms (lightmap %dx%d baked on a thread)"
            % [Time.get_ticks_msec() - t0, gen.width, gen.height])


func _add_sky(world_px: Vector2) -> void:
    var grad := Image.create(1, 256, false, Image.FORMAT_RGBA8)
    # Dusk sky: indigo above, a warm lilac glow hugging the horizon (which
    # sits at ~42% of the world height, roughly where the ground line is).
    var stops := [
        [0.0, Color("0d1226")],
        [0.28, Color("24304f")],
        [0.45, Color("3f4460")],
        [0.55, Color("55545c")],
        [1.0, Color("0a0c12")],
    ]
    for y in 256:
        var t := float(y) / 255.0
        var c: Color = stops[0][1]
        for i in range(stops.size() - 1):
            var a: float = stops[i][0]
            var b: float = stops[i + 1][0]
            if t >= a and t <= b:
                c = (stops[i][1] as Color).lerp(stops[i + 1][1],
                        (t - a) / maxf(b - a, 0.0001))
                break
        grad.set_pixel(0, y, c)
    var sky := Sprite2D.new()
    sky.name = "Sky"
    sky.texture = ImageTexture.create_from_image(grad)
    sky.centered = false
    sky.position = Vector2.ZERO
    sky.scale = Vector2(world_px.x, world_px.y / 256.0)
    sky.z_index = SKY_Z
    sky.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    add_child(sky)


func _add_lightmap(img: Image) -> void:
    var overlay := Sprite2D.new()
    overlay.name = "Lightmap"
    overlay.texture = ImageTexture.create_from_image(img)
    overlay.centered = false
    overlay.position = Vector2.ZERO
    overlay.scale = Vector2(TILE, TILE)
    overlay.z_index = LIGHTMAP_Z
    overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    add_child(overlay)


func _add_player_glow() -> void:
    var players := get_tree().get_nodes_in_group("player")
    if players.is_empty():
        return
    var glow := Sprite2D.new()
    glow.name = "PlayerGlow"
    glow.texture = _radial(256, 2.0)
    glow.scale = Vector2(1.15, 1.15)
    glow.z_index = GLOW_Z
    var mat := CanvasItemMaterial.new()
    mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    glow.material = mat
    glow.modulate = Color(1.0, 0.72, 0.42, 0.42)
    (players[0] as Node2D).add_child(glow)

    # a wider, fainter halo keeps the transition from light into the dark
    var halo := Sprite2D.new()
    halo.name = "PlayerHalo"
    halo.texture = _radial(256, 1.4)
    halo.scale = Vector2(2.3, 2.3)
    halo.z_index = GLOW_Z - 1
    var hm := CanvasItemMaterial.new()
    hm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
    halo.material = hm
    halo.modulate = Color(0.55, 0.5, 0.6, 0.24)
    (players[0] as Node2D).add_child(halo)


## The grade sits on its own CanvasLayer below the HUD (which main.tscn
## moves to layer 2): readable UI, graded world.
func _add_grade() -> void:
    var layer := CanvasLayer.new()
    layer.name = "Grade"
    layer.layer = 1
    add_child(layer)

    var rect := ColorRect.new()
    rect.name = "GradeRect"
    rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var mat := ShaderMaterial.new()
    mat.shader = load("res://shaders/grade.gdshader")
    rect.material = mat
    layer.add_child(rect)


func _radial(size: int, power: float) -> ImageTexture:
    var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
    var c := (size - 1) * 0.5
    for y in size:
        for x in size:
            var d := Vector2(x - c, y - c).length() / c
            var a := pow(clampf(1.0 - d, 0.0, 1.0), power)
            img.set_pixel(x, y, Color(1, 1, 1, a))
    return ImageTexture.create_from_image(img)
