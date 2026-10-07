extends CharacterBody2D

## Milestone-1 player: run, jump, variable jump height - plus digging
## and building with tools, and (milestone 3) health + a melee swing
## that works exactly like digging: LMB on a mob hits it, LMB on a tile
## digs it.
##
## Gravity is applied manually so the constant stays next to the other
## movement numbers and tuning is one place. The scene sets
## gravity_scale = 0 so the engine doesn't add its own on top.

const SPEED := 190.0
const ACCEL := 1400.0
const FRICTION := 1800.0
const JUMP_VELOCITY := -330.0
const GRAVITY := 950.0
const MAX_FALL := 700.0

## Releasing jump early cuts upward velocity, which is what makes
## short hops and full jumps share one key.
const JUMP_CUT := 0.45

## Animation speed floor: below this the run cycle looks like a twitch.
const RUN_ANIM_MIN := 20.0

## Health / melee tuning.
const MAX_HP := 10
const MELEE_DAMAGE := 2
const MELEE_CD := 0.35
const IFRAME_TIME := 1.0

const TILE := TilesetFactory.TILE_SIZE
const SLOT_COUNT := 4

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var tool_sprite: Sprite2D = $Tool
@onready var aim: Node2D = $Cursor

## Set by World once the world exists; every tool action no-ops until
## then so the player scene still loads standalone.
var world: Node2D

## "pickaxe" | "axe" - see Tools.NAMES.
var active_tool := Tools.DEFAULT

## item id -> count. Keys in sorted order are hotbar slots 1..4.
var inventory := {}
var selected_item := -1

var hp := MAX_HP

var _anim := "idle"
var _mine_target := Vector2i(-9999, -9999)
var _mine_progress := 0.0
var _swinging := false
var _swing_t := 0.0
var _iframes := 0.0
var _melee_cd := 0.0
var _run_fps := -1.0


func _ready() -> void:
    add_to_group("player")
    sprite.sprite_frames = PlayerArt.build_frames()
    sprite.play(_anim)
    # The cursor draws in raw world coordinates, not player-relative.
    aim.top_level = true
    set_tool(Tools.DEFAULT)


func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

    var dir := Input.get_axis("move_left", "move_right")
    if not is_zero_approx(dir):
        velocity.x = move_toward(velocity.x, dir * SPEED, ACCEL * delta)
        # AnimatedSprite2D has flip_h of its own, so facing is independent
        # of the squash animation that writes scale.y.
        sprite.flip_h = dir < 0.0
    else:
        velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

    if Input.is_action_just_pressed("jump") and is_on_floor():
        velocity.y = JUMP_VELOCITY
        sprite.scale.y = 0.82
    elif Input.is_action_just_released("jump") and velocity.y < 0.0:
        velocity.y *= JUMP_CUT

    move_and_slide()
    _animate(delta)
    _tool_tick(delta)
    _melee_tick(delta)
    _update_tool_pose(delta)

    # Hurt flash: red for the first beat of the i-frame window, then back
    # to the normal palette.
    _iframes = maxf(_iframes - delta, 0.0)
    _melee_cd = maxf(_melee_cd - delta, 0.0)
    if _iframes > IFRAME_TIME - 0.15:
        sprite.modulate = Color(1, 0.45, 0.45)
    elif sprite.modulate != Color.WHITE:
        sprite.modulate = Color.WHITE


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed \
            and event.button_index == MOUSE_BUTTON_RIGHT:
        _place_at(get_global_mouse_position())


func set_tool(kind: String) -> void:
    active_tool = kind
    tool_sprite.texture = PlayerArt.build_tool(kind)


func _animate(delta: float) -> void:
    sprite.scale.y = move_toward(sprite.scale.y, 1.0, delta * 3.0)

    var next := "idle"
    if not is_on_floor():
        next = "jump" if velocity.y < 0.0 else "fall"
        _run_fps = -1.0
    elif absf(velocity.x) > RUN_ANIM_MIN:
        next = "run"
        # Scale the cycle with speed so walking and sprinting differ.
        # Only touch the resource when the value actually changes -
        # rewriting set_animation_speed every frame dirties SpriteFrames
        # for no reason.
        var fps := clampf(absf(velocity.x) / 6.0, 6.0, 16.0)
        if fps != _run_fps:
            _run_fps = fps
            sprite.sprite_frames.set_animation_speed("run", fps)
    else:
        _run_fps = -1.0

    if next != _anim:
        _anim = next
        sprite.play(next)


# ------------------------------------------------------------------ tools

## Called every physics frame: cycles tools/slots, mines while the left
## button is held, and keeps the aim cursor in sync. A mob under the
## cursor suppresses digging - LMB means "hit the critter" there.
func _tool_tick(delta: float) -> void:
    if world == null or world.gen == null:
        return

    if Input.is_action_just_pressed("cycle_tool"):
        set_tool(Tools.next_tool(active_tool))
    for s in SLOT_COUNT:
        if Input.is_action_just_pressed("slot_%d" % (s + 1)):
            select_slot(s + 1)

    var mouse := get_global_mouse_position()
    var mob: Node = world.mob_at(mouse)
    var target := Vector2i(
            floori(mouse.x / float(TILE)), floori(mouse.y / float(TILE)))
    var id := _tile_at(target)
    var in_reach := _within_reach(target)

    if not in_reach:
        target = Vector2i(-9999, -9999)
        _mine_progress = 0.0
        _mine_target = target
        _swinging = false
    elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
            and mob == null \
            and Tools.is_diggable(id):
        if target != _mine_target:
            _mine_target = target
            _mine_progress = 0.0
        _mine_progress += delta / maxf(Tools.mining_time(active_tool, id), 0.001)
        _swinging = true
        if _mine_progress >= 1.0:
            dig_at(target)
            _mine_progress = 0.0
            _mine_target = Vector2i(-9999, -9999)
    else:
        _mine_progress = 0.0
        _mine_target = Vector2i(-9999, -9999)
        _swinging = false

    aim.set_aim(target, _mine_progress, in_reach)


## Breaks the tile at a cell if it is in reach, and banks the drop.
## Shared by the mining loop and the test suite.
func dig_at(cell: Vector2i) -> bool:
    if world == null or world.gen == null or not _within_reach(cell):
        return false
    if not Tools.is_diggable(_tile_at(cell)):
        return false
    var item: int = world.mine_tile(cell.x, cell.y)
    # Foliage clears but drops nothing (-1); that is still a successful dig.
    if item >= 0:
        inventory[item] = inventory.get(item, 0) + 1
        if selected_item < 0:
            selected_item = item
    return true


## Right-click: drop the selected block on a supported spot.
func _place_at(pos: Vector2) -> void:
    if world == null or world.gen == null:
        return
    if selected_item < 0 or inventory.get(selected_item, 0) <= 0:
        return
    var target := Vector2i(
            floori(pos.x / float(TILE)), floori(pos.y / float(TILE)))
    if not _within_reach(target):
        return
    if world.place_tile(target.x, target.y, selected_item):
        inventory[selected_item] -= 1
        if inventory[selected_item] <= 0:
            inventory.erase(selected_item)
            selected_item = -1
            var keys := inventory.keys()
            keys.sort()
            if not keys.is_empty():
                selected_item = keys[0]


## Tile id at a world cell, or -1 outside the map.
func _tile_at(cell: Vector2i) -> int:
    if world == null or world.gen == null:
        return -1
    if cell.x < 0 or cell.y < 0 \
            or cell.x >= world.gen.width or cell.y >= world.gen.height:
        return -1
    return world.gen.tiles[cell.y * world.gen.width + cell.x]


func _within_reach(cell: Vector2i) -> bool:
    var center := Vector2(cell) * TILE + Vector2(TILE, TILE) * 0.5
    return global_position.distance_to(center) <= Tools.REACH_TILES * TILE


# --------------------------------------------------------- health/melee

## Melee: while LMB is held, hit whatever mob is under the cursor, on a
## cooldown so a held click doesn't machine-gun.
func _melee_tick(delta: float) -> void:
    if world == null or world.gen == null:
        return
    _melee_cd = maxf(_melee_cd - delta, 0.0)
    if _melee_cd > 0.0 or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        return
    if attack_mob_at(get_global_mouse_position()):
        _melee_cd = MELEE_CD


## Shared melee path: a reachable mob under pos takes MELEE_DAMAGE and is
## knocked away. Returns true when something was hit. The test suite
## calls this directly the way it calls dig_at().
func attack_mob_at(pos: Vector2) -> bool:
    if world == null or world.gen == null:
        return false
    if global_position.distance_to(pos) > Tools.REACH_TILES * TILE:
        return false
    var mob = world.mob_at(pos)
    if mob == null:
        return false
    sprite.flip_h = pos.x < global_position.x
    mob.take_damage(MELEE_DAMAGE, global_position)
    return true


## Mob contact / fall damage land here. I-frames stop the hits stacking.
func take_damage(amount: int) -> void:
    if _iframes > 0.0:
        return
    hp = maxi(hp - amount, 0)
    _iframes = IFRAME_TIME
    if hp <= 0:
        die()


func die() -> void:
    if world != null and world.has_method("respawn_player"):
        world.respawn_player()


func heal_full() -> void:
    hp = MAX_HP
    _iframes = 0.0


func select_slot(n: int) -> void:
    var keys := inventory.keys()
    keys.sort()
    if n >= 1 and n <= keys.size():
        selected_item = keys[n - 1]


func hud_tool_text() -> String:
    return "%s (Q)" % active_tool


func hud_hotbar_text() -> String:
    var keys := inventory.keys()
    keys.sort()
    var parts := PackedStringArray()
    for i in mini(keys.size(), SLOT_COUNT):
        var item: int = keys[i]
        var mark := "*" if item == selected_item else " "
        parts.append("%s%d:%s x%d" % [
                mark, i + 1, Tools.item_name(item), inventory[item]])
    var line := "  ".join(parts) if not parts.is_empty() else "hotbar empty"
    if keys.size() > SLOT_COUNT:
        line += "  +%d" % (keys.size() - SLOT_COUNT)
    return line


## Tool pose: hangs off the right hand, mirrored when facing left, and
## sweeps a smooth chop arc while digging.
func _update_tool_pose(delta: float) -> void:
    var facing := -1.0 if sprite.flip_h else 1.0
    tool_sprite.position.x = 6.0 * facing
    tool_sprite.scale.x = facing
    if _swinging:
        _swing_t += delta * 8.0
        tool_sprite.rotation = deg_to_rad(
                -55.0 + 95.0 * (0.5 - 0.5 * cos(_swing_t * TAU)))
    else:
        _swing_t = 0.0
        tool_sprite.rotation = move_toward(
                tool_sprite.rotation, deg_to_rad(-35.0), delta * 8.0)
