extends Node2D

## Aim feedback for digging: a white outline around the tile under the
## cursor plus a bottom-up fill that shows mining progress.
##
## The player sets top_level = true so this node ignores the player's
## transform and draws in raw world coordinates.

var target := Vector2i(-9999, -9999)
var progress := 0.0
var shown := false


func set_aim(t: Vector2i, p: float, on: bool) -> void:
    if t == target and is_equal_approx(p, progress) and on == shown:
        return
    target = t
    progress = clampf(p, 0.0, 1.0)
    shown = on
    queue_redraw()


func _draw() -> void:
    if not shown:
        return
    var size := float(TilesetFactory.TILE_SIZE)
    var rect := Rect2(Vector2(target) * size, Vector2(size, size))
    draw_rect(rect, Color(1, 1, 1, 0.45), false, 1.0)
    if progress > 0.0:
        var inner := size - 2.0
        var fill_h := inner * progress
        draw_rect(Rect2(
                Vector2(rect.position.x + 1.0, rect.position.y + size - 1.0 - fill_h),
                Vector2(inner, fill_h)), Color(1, 1, 1, 0.30), true)
