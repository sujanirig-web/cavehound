class_name MobArt
extends RefCounted

## Procedural pixel-art slime: a rounded green blob with a dark outline,
## top shine, two eyes and a couple of body specks. Frames squash and
## stretch for the hop cycle, exactly like Terraria's slimes.
##
## Same rationale as PlayerArt: no PNGs, the repo stays pure text, and
## the colours are one edit away. Frames face RIGHT; the game flips with
## AnimatedSprite2D.flip_h.
##
## Canvas is 16x16. The body's bottom row is 15 and never moves, so the
## feet stay on the ground line through every squash/stretch frame.

const W := 16
const H := 16

const BODY := Color("6fbf44")
const BODY_LIGHT := Color("a8e068")
const BODY_DARK := Color("4a8f33")
const OUTLINE := Color("356b26")
const EYE := Color("1d2f1a")

## Animation name -> expected frame count. Shared with the sprite test.
const ANIMS := {
    "idle": 2,
    "hop": 3,
}


static func build_frames() -> SpriteFrames:
    var sf := SpriteFrames.new()

    # Idle: two gentle "breathing" stretches.
    _add_anim(sf, "idle", [_slime(0), _slime(2)], 1.4)

    # Hop: stretch on takeoff -> neutral mid-air -> deep squash on landing.
    _add_anim(sf, "hop", [_slime(3), _slime(0), _slime(-4)], 9.0)

    if sf.has_animation("default"):
        sf.remove_animation("default")
    return sf


static func _add_anim(sf: SpriteFrames, anim: String, frames: Array,
        fps: float) -> void:
    sf.add_animation(anim)
    sf.set_animation_speed(anim, fps)
    sf.set_animation_loop(anim, true)
    for f in frames:
        sf.add_frame(anim, ImageTexture.create_from_image(f))


## squish > 0 makes the blob taller and narrower (rising hop / in-breath),
## squish < 0 makes it lower and wider (landing / out-breath). Width and
## height trade against each other so the body volume reads constant.
static func _slime(squish: int) -> Image:
    var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0))

    var h := 12 + squish
    var w := 12 - squish
    var x0 := int((W - w) / 2.0)
    var top := H - h

    # Blob cells, minus the 4 rounded corners.
    var cell := {}
    for dy in h:
        for dx in w:
            var corner := (dx == 0 or dx == w - 1) \
                    and (dy == 0 or dy == h - 1)
            if not corner:
                cell[Vector2i(x0 + dx, top + dy)] = true

    for p: Vector2i in cell.keys():
        _px(img, p.x, p.y, BODY)

    # Shaded underside: the three rows above the bottom edge go dark.
    for p: Vector2i in cell.keys():
        if p.y >= top + h - 4:
            _px(img, p.x, p.y, BODY_DARK)

    # Dark outline where a body pixel has an empty 4-neighbour.
    var outline := {}
    for p: Vector2i in cell.keys():
        for n in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0),
                Vector2i(1, 0)]:
            if not cell.has(p + n):
                outline[p] = true
                break
    for p: Vector2i in outline.keys():
        _px(img, p.x, p.y, OUTLINE)

    # Top-left shine and two eyes near the top of the blob.
    _rect(img, x0 + 2, top + 1, 2, 1, BODY_LIGHT)
    var eye_y := top + 3
    var eye_l := x0 + 2
    var eye_r := x0 + w - 5
    if cell.has(Vector2i(eye_l, eye_y)) and cell.has(Vector2i(eye_l + 1, eye_y + 1)):
        _rect(img, eye_l, eye_y, 2, 2, EYE)
    if cell.has(Vector2i(eye_r, eye_y)) and cell.has(Vector2i(eye_r + 1, eye_y + 1)):
        _rect(img, eye_r, eye_y, 2, 2, EYE)

    # A couple of interior specks for texture.
    for s in [Vector2i(x0 + 5, top + 7), Vector2i(x0 + 7, top + 10)]:
        if cell.has(s):
            _px(img, s.x, s.y, BODY_DARK)

    return img


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
    for dy in h:
        for dx in w:
            _px(img, x + dx, y + dy, c)


static func _px(img: Image, x: int, y: int, c: Color) -> void:
    if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
        return
    img.set_pixel(x, y, c)