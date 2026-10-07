extends SceneTree

## Diagnostic: which injection route updates the viewport mouse position?
##   1. Input.parse_input_event(motion)
##   2. root.push_input(motion)
##   3. Input.warp_mouse()
##
##   godot --path . --script res://tools/mouse_probe.gd

var frames := 0
var step := 0


func _process(_delta: float) -> bool:
    frames += 1
    if frames < 5:
        return false

    match step:
        0:
            print("baseline                          vp=", root.get_mouse_position())
        1:
            _motion(Vector2(100, 100))
            Input.parse_input_event(_motion(Vector2(100, 100)))
            Input.flush_buffered_events()
            print("after Input.parse_input_event     vp=", root.get_mouse_position())
        2:
            root.push_input(_motion(Vector2(300, 300)))
            print("after root.push_input             vp=", root.get_mouse_position())
        3:
            root.push_input(_motion(Vector2(500, 500)))
            print("after root.push_input (500,500)   vp=", root.get_mouse_position())
        4:
            Input.warp_mouse(Vector2(640, 360))
            print("after Input.warp_mouse            vp=", root.get_mouse_position())
        5:
            # motion with relative delta only (Wayland style)
            var ev := InputEventMouseMotion.new()
            ev.position = Vector2(640, 360)
            ev.relative = Vector2(10, 10)
            root.push_input(ev)
            print("after push_input w/ relative      vp=", root.get_mouse_position())
            quit(0)
            return true
    step += 1
    return false


func _motion(pos: Vector2) -> InputEventMouseMotion:
    var ev := InputEventMouseMotion.new()
    ev.position = pos
    ev.global_position = pos
    return ev
