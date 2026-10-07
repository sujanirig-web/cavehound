extends SceneTree

## Builds the player's SpriteFrames headlessly and asserts the art is
## actually there: every animation present with the right frame count,
## frames that differ (a cycle that really cycles), a figure that fills
## the frame from hair row to shoe row, and no leftover "default".
##
##   godot --headless --path . --script res://tools/sprite_test.gd

const BOTTOM := PlayerArt.H - 1


func _initialize() -> void:
    var failures: Array[String] = []
    var sf := PlayerArt.build_frames()

    if sf.has_animation("default"):
        failures.append("leftover SpriteFrames \"default\" animation")

    for anim in PlayerArt.ANIMS:
        if not sf.has_animation(anim):
            failures.append("missing animation \"%s\"" % anim)
            continue
        var want: int = PlayerArt.ANIMS[anim]
        var got := sf.get_frame_count(anim)
        if got != want:
            failures.append("\"%s\" has %d frames, expected %d"
                    % [anim, got, want])
            continue
        _check_frames(sf, anim, failures)

    _check_frame_geometry(sf, failures)

    print("")
    if failures.is_empty():
        print("  all checks passed")
        quit(0)
    else:
        for f in failures:
            print("  FAIL  %s" % f)
        quit(1)


func _check_frames(sf: SpriteFrames, anim: String,
        failures: Array[String]) -> void:
    var hashes := {}
    for i in sf.get_frame_count(anim):
        var tex := sf.get_frame_texture(anim, i)
        if tex == null:
            failures.append("\"%s\" frame %d has no texture" % [anim, i])
            return
        var img := tex.get_image()
        var opaque := 0
        for y in img.get_height():
            for x in img.get_width():
                if img.get_pixel(x, y).a > 0.5:
                    opaque += 1
        if opaque < 150:
            failures.append("\"%s\" frame %d is nearly blank (%d px) - the character did not draw"
                    % [anim, i, opaque])
        # A cycle whose frames are byte-identical is a static image.
        hashes[hash(img.get_data())] = true
    if sf.get_frame_count(anim) > 1 and hashes.size() == 1:
        failures.append("\"%s\" frames are all identical - not animating"
                % anim)


## Every pose must keep the head within the top two rows (the breathing
## frames sit 1px lower than the rest) and shoes on the bottom row,
## otherwise the sprite floats above - or sinks into - the tile it stands on.
func _check_frame_geometry(sf: SpriteFrames, failures: Array[String]) -> void:
    for anim in PlayerArt.ANIMS:
        if not sf.has_animation(anim):
            continue
        for i in sf.get_frame_count(anim):
            var img := sf.get_frame_texture(anim, i).get_image()
            var top := false
            var bottom := false
            for x in img.get_width():
                if img.get_pixel(x, 0).a > 0.5 or img.get_pixel(x, 1).a > 0.5:
                    top = true
                if img.get_pixel(x, BOTTOM).a > 0.5:
                    bottom = true
            if not top:
                failures.append("\"%s\" frame %d: no head in the top two rows"
                        % [anim, i])
            if not bottom:
                failures.append("\"%s\" frame %d: no feet on the bottom row - the sprite will float"
                        % [anim, i])
