class_name NpcArt
extends RefCounted

## Procedural pixel-art villager: a hooded traveller in an earth-tone
## robe with a grey beard and a staff tipped with a glowing crystal.
##
## Same no-PNG rationale as PlayerArt; frames face RIGHT and the game
## flips with AnimatedSprite2D.flip_h.
##
## 16x24 layout mirrors the player:
##   y 0..3   hood crown
##   y 4..8   face (skin) with eyes; beard hangs rows 8..11
##   y 10..21 robe with belt
##   y 22..23 shoes - the bottom rows, where the feet must land

const W := 16
const H := 24

const ROBE := Color("7a5c3e")
const ROBE_DARK := Color("5d4529")
const ROBE_LIGHT := Color("967347")
const BELT := Color("43301f")
const SKIN := Color("d8a878")
const SKIN_DARK := Color("bf9263")
const BEARD := Color("c9c9cf")
const BEARD_DARK := Color("9aa0a8")
const EYE := Color("1a1a24")
const EYE_WHITE := Color("f4f4f8")
const STAFF := Color("6b4f2c")
const STAFF_DARK := Color("4f3a1f")
const STAFF_TIP := Color("8fe3e3")
const STAFF_GLINT := Color("d6f6f6")

## Animation name -> expected frame count. Shared with the sprite test.
const ANIMS := {
    "idle": 2,
    "walk": 2,
}


static func build_frames() -> SpriteFrames:
    var sf := SpriteFrames.new()

    _add_anim(sf, "idle", [
        _pose({}),
        _pose({"bob": 1}),
    ], 1.2)

    # Walking: the shoes step forward/back under a bobbing hem.
    _add_anim(sf, "walk", [
        _pose({"step": -1}),
        _pose({"step": 1, "bob": 1}),
    ], 6.0)

    if sf.has_animation("default"):
        sf.remove_animation("default")
    return sf


static func _add_anim(sf: SpriteFrames, anim: String, poses: Array,
        fps: float) -> void:
    sf.add_animation(anim)
    sf.set_animation_speed(anim, fps)
    sf.set_animation_loop(anim, true)
    for pose in poses:
        sf.add_frame(anim, ImageTexture.create_from_image(pose))


## pose keys (optional): bob (head+torso rises one px), step (shoe swing).
static func _pose(p: Dictionary) -> Image:
    var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0))

    var bob: int = p.get("bob", 0)
    var step: int = p.get("step", 0)

    # Hooded head, facing right.
    _rect(img, 4, 0 + bob, 8, 4, ROBE_DARK)      # hood crown
    _rect(img, 4, 4 + bob, 8, 5, SKIN)           # face
    _col(img, 4, 0 + bob, 9, ROBE)               # hood hanging down the back
    _rect(img, 8, 7 + bob, 2, 4, BEARD)          # beard
    _rect(img, 8, 7 + bob, 2, 1, BEARD_DARK)     # beard shading
    _rect(img, 10, 5 + bob, 2, 2, EYE)           # eye
    _px(img, 10, 5 + bob, EYE_WHITE)             # glint
    _px(img, 6, 8 + bob, SKIN_DARK)              # nose shadow

    # Robe torso with a shaded front edge and a belt at the waist.
    _rect(img, 5, 10 + bob, 7, 11, ROBE)
    _col(img, 5, 10 + bob, 11, ROBE_DARK)
    _rect(img, 5, 18 + bob, 7, 1, BELT)

    # Hem: shifts against the stepping shoe so the walk reads a stride.
    _rect(img, 5, 21, 7, 1, ROBE_LIGHT)
    var shoe_x := 5 + step
    _rect(img, shoe_x, 22, 3, 1, ROBE_DARK)
    _rect(img, shoe_x, 23, 3, 1, STAFF_DARK)

    # Staff: drawn last, in front of the body.
    _px(img, 13, 2, STAFF_TIP)                   # crystal
    _px(img, 14, 2, STAFF_GLINT)
    _px(img, 13, 3, STAFF_TIP)
    _px(img, 13, 4, STAFF_DARK)
    for y in range(5, 21):
        _px(img, 13, y, STAFF)
        _px(img, 14, y, STAFF_DARK)

    return img


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
    for dy in h:
        for dx in w:
            _px(img, x + dx, y + dy, c)


static func _col(img: Image, x: int, y: int, h: int, c: Color) -> void:
    for dy in h:
        _px(img, x, y + dy, c)


static func _px(img: Image, x: int, y: int, c: Color) -> void:
    if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
        return
    img.set_pixel(x, y, c)