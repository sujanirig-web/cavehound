class_name PlayerArt
extends RefCounted

## Procedural pixel-art player: head, torso, swinging arms and legs with
## a 4-frame run cycle, drawn into Images at startup.
##
## Same rationale as TilesetFactory: no PNGs to diff, the repo stays pure
## text, and colours are one edit away. Frames face RIGHT; the game flips
## with AnimatedSprite2D.flip_h.
##
## Layout inside a 16x24 frame (y grows downward):
##   y 0..8   head (hair rows 0..3, face 4..8)
##   y 9      neck
##   y 10..16 torso
##   y 17     belt
##   y 18..21 legs (sheared sideways to swing)
##   y 22..23 shoes - the bottom row, which is where the feet must land

const W := 16
const H := 24

const SKIN := Color("e8b98e")
const SKIN_DARK := Color("c08f68")
const HAIR := Color("4a3220")
const HAIR_DARK := Color("352417")
const SHIRT := Color("5cb8fa")
const SHIRT_DARK := Color("3f8fd0")
const PANTS := Color("3b4468")
const PANTS_DARK := Color("2b3150")
const SHOE := Color("6b4f2c")
const SHOE_DARK := Color("4f3a1f")
const BELT := Color("4a3520")
const EYE := Color("14141e")
const EYE_WHITE := Color("f4f4f8")

## Animation name -> expected frame count. Kept here so the sprite test
## asserts against the same table that builds them.
const ANIMS := {
    "idle": 2,
    "run": 4,
    "jump": 1,
    "fall": 1,
}


## Builds the whole SpriteFrames resource. Called once from player.gd's
## _ready(); takes about a millisecond.
static func build_frames() -> SpriteFrames:
    var sf := SpriteFrames.new()

    _add_anim(sf, "idle", [
        _pose({}),
        _pose({"bob": 1}),  # breathing
    ], 1.0)

    # Four-phase run: legs shear sideways in opposite directions, arms
    # counter-swing, and the body bobs on the passing frames.
    _add_anim(sf, "run", [
        _pose({"leg_back": -2, "leg_front": 2, "arm_back": 1, "arm_front": -1}),
        _pose({"bob": 1, "leg_back": 0, "leg_front": 0,
               "arm_back": -1, "arm_front": 1}),
        _pose({"leg_back": 2, "leg_front": -2, "arm_back": -1, "arm_front": 1}),
        _pose({"bob": 1, "leg_back": 0, "leg_front": 0,
               "arm_back": 1, "arm_front": -1}),
    ], 9.0)

    _add_anim(sf, "jump", [
        _pose({"leg_back": -1, "leg_front": 1, "arm_back": -1, "arm_front": -1}),
    ], 2.0)

    _add_anim(sf, "fall", [
        _pose({"leg_back": -2, "leg_front": 2, "arm_back": -1, "arm_front": -1}),
    ], 2.0)

    # SpriteFrames always ships a "default" animation; only remove it
    # once the real ones exist (removing the last animation is unsafe).
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


# ----------------------------------------------------------------- drawing

## pose keys (all optional): bob, leg_back, leg_front, arm_back, arm_front.
## leg/arm values are horizontal swing in px; bob shifts head+torso only,
## so breathing never lifts the feet off the ground.
static func _pose(p: Dictionary) -> Image:
    var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0))

    var bob: int = p.get("bob", 0)
    var leg_back: int = p.get("leg_back", 0)
    var leg_front: int = p.get("leg_front", 0)
    var arm_back: int = p.get("arm_back", 0)
    var arm_front: int = p.get("arm_front", 0)

    # Draw order: back arm -> legs -> torso -> head -> front arm.
    _arm(img, 3, 11 + bob + arm_back, true)
    _leg(img, 5, leg_back, true)
    _leg(img, 8, leg_front, false)

    _rect(img, 5, 10 + bob, 6, 7, SHIRT)
    _col(img, 5, 10 + bob, 7, SHIRT_DARK)  # shaded back edge
    _rect(img, 5, 17 + bob, 6, 1, BELT)

    _head(img, bob)
    _arm(img, 11, 11 + bob + arm_front, false)
    return img


## Head faces right: hair caps the top and wraps the back (left side),
## the eye sits near the front edge.
static func _head(img: Image, bob: int) -> void:
    _rect(img, 4, 1 + bob, 8, 8, SKIN)          # skull
    _rect(img, 4, 0 + bob, 8, 4, HAIR)           # hair cap
    _rect(img, 4, 4 + bob, 2, 4, HAIR)           # hair down the back
    _col(img, 4, 0 + bob, 6, HAIR_DARK)          # shaded back edge
    _rect(img, 9, 5 + bob, 2, 2, EYE)            # eye
    _px(img, 9, 5 + bob, EYE_WHITE)              # glint
    _rect(img, 7, 9 + bob, 2, 1, SKIN_DARK)      # neck


## Arms hang beside the torso: 2px sleeve then 4px of skin.
static func _arm(img: Image, x0: int, y0: int, dark: bool) -> void:
    _rect(img, x0, y0, 2, 2, SHIRT_DARK if dark else SHIRT)
    _rect(img, x0, y0 + 2, 2, 4, SKIN_DARK if dark else SKIN)


## Legs shear sideways instead of detaching: each row shifts by
## dx * (row - hip) / 3, so the leg stays attached at the hip while the
## foot swings the full dx. Shoes point right (the facing direction).
static func _leg(img: Image, x0: int, dx: int, dark: bool) -> void:
    var pants := PANTS_DARK if dark else PANTS
    for row in range(18, 22):
        var off := int(round(dx * float(row - 18) / 3.0))
        _rect(img, x0 + off, row, 3, 1, pants)
    _rect(img, x0 + dx, 22, 4, 1, SHOE)
    _rect(img, x0 + dx, 23, 4, 1, SHOE_DARK)


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


# ------------------------------------------------------------------- tools

## Held tool: a 14x14 pickaxe, axe or hammer, facing right. Same
## procedural rationale as everything else here - no PNGs, colours one
## edit away.
static func build_tool(kind: String) -> Texture2D:
    var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
    img.fill(Color(0, 0, 0, 0))
    if kind == "hammer":
        _tool_hammer(img)
    elif kind == "axe":
        _tool_axe(img)
    else:
        _tool_pick(img)
    return ImageTexture.create_from_image(img)


## Diagonal wooden haft from bottom-left to the head at the top-right.
static func _tool_handle(img: Image) -> void:
    for i in 9:
        var x := 1 + i
        var y := 12 - i
        _px(img, x, y, Color("6b4f2c"))
        _px(img, x, y + 1, Color("4f3a1f"))


static func _tool_pick(img: Image) -> void:
    _tool_handle(img)
    var steel := Color("9a9aa8")
    var steel_hi := Color("c8c8d4")
    var steel_dark := Color("585862")
    # shallow arc across the top, tips curving down at both ends
    var arc := [
        Vector2i(4, 6), Vector2i(5, 5), Vector2i(6, 4), Vector2i(7, 3),
        Vector2i(8, 2), Vector2i(9, 2), Vector2i(10, 3), Vector2i(11, 4),
        Vector2i(12, 5), Vector2i(13, 6),
    ]
    for p in arc:
        _px(img, p.x, p.y, steel_hi if p.y <= 3 else steel)
        _px(img, p.x, p.y + 1, steel_dark)


static func _tool_axe(img: Image) -> void:
    _tool_handle(img)
    var steel := Color("9a9aa8")
    var steel_hi := Color("d8d8e0")
    var steel_dark := Color("585862")
    var rows := {
        0: [7, 8, 9, 10],
        1: [6, 7, 8, 9, 10, 11],
        2: [6, 7, 8, 9, 10, 11],
        3: [7, 8, 9, 10],
    }
    for y in rows:
        var xs: Array = rows[y]
        for x in xs:
            # lit cutting edge on the left, plain steel behind it
            _px(img, x, y, steel_hi if x <= xs[0] + 1 else steel)
    for x in range(7, 11):
        _px(img, x, 4, steel_dark)


## A solid steel head on the same diagonal haft - the wall tool.
static func _tool_hammer(img: Image) -> void:
    _tool_handle(img)
    var steel := Color("9a9aa8")
    var steel_hi := Color("d8d8e0")
    var steel_dark := Color("585862")
    var rows := {
        0: [8, 9, 10, 11, 12],
        1: [7, 8, 9, 10, 11, 12],
        2: [7, 8, 9, 10, 11, 12],
        3: [8, 9, 10, 11, 12],
    }
    for y in rows:
        var xs: Array = rows[y]
        for x in xs:
            # lit face on the left, plain steel behind it
            _px(img, x, y, steel_hi if x <= xs[0] + 1 else steel)
    for x in range(8, 12):
        _px(img, x, 4, steel_dark)
