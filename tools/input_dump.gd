extends SceneTree

## Dumps the resolved input map so bindings can be checked rather than
## assumed from defaults.
##
##   godot --headless --path . --script res://tools/input_dump.gd

func _initialize() -> void:
    print("\n=== resolved input map (non ui_*) ===")
    var any := false
    for action in InputMap.get_actions():
        if action.begins_with("ui_"):
            continue
        var keys := _keys(action)
        if keys.is_empty():
            continue
        any = true
        print("  %-12s %s" % [action, ", ".join(keys)])
    if not any:
        print("  (none defined in project.godot)")

    print("\n=== built-in ui_* actions (Godot defaults) ===")
    for action in ["ui_left", "ui_right", "ui_up", "ui_down", "ui_accept"]:
        if not InputMap.has_action(action):
            print("  %-12s MISSING" % action)
            continue
        print("  %-12s %s" % [action, ", ".join(_keys(action))])

    quit(0)


## Reports both keycode and physical_keycode. Godot's built-in ui_*
## defaults are stored as logical keycodes, while anything authored in
## the editor's Input Map usually sets physical_keycode - reading only
## one of the two makes bindings look empty.
func _keys(action: StringName) -> Array[String]:
    var out: Array[String] = []
    for e in InputMap.action_get_events(action):
        if e is InputEventKey:
            var logical := OS.get_keycode_string((e as InputEventKey).keycode)
            var physical := OS.get_keycode_string((e as InputEventKey).physical_keycode)
            if physical.is_empty():
                out.append(logical)
            elif physical == logical:
                out.append(physical)
            else:
                out.append("%s/%s" % [physical, logical])
        elif e is InputEventMouseButton:
            out.append("mouse%d" % (e as InputEventMouseButton).button_index)
        elif e is InputEventJoypadButton:
            out.append("pad%d" % (e as InputEventJoypadButton).button_index)
    return out
