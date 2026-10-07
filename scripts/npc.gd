extends CharacterBody2D

## A friendly villager: wanders a small area around its anchor point and
## talks when you press E next to it. Never damages the player.
##
## Gravity is applied like the player's so the wander stays on terrain.

const WALK_SPEED := 42.0
const WANDER_RADIUS := 56.0
const GRAVITY := 950.0
const MAX_FALL := 600.0
const TALK_DIST := 4.0  # tiles

const LINES := [
    "They call me the Guide... long way from home.",
    "The slimes here are friendly. Not THAT friendly.",
    "Keep your tools sharp; the caves go deep.",
    "A roof over your head beats a bed of stone.",
    "They say there is a dungeon gate to the west. Or was it east?",
]

## Set by World before the npc is added to the tree.
var world: Node2D

var anchor := Vector2.ZERO

var _decide_t := 0.0
var _walk_t := 0.0
var _dir := 0
var _line := 0

@onready var sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
    add_to_group("npcs")
    anchor = global_position
    sprite.sprite_frames = NpcArt.build_frames()
    sprite.play("idle")


func _physics_process(delta: float) -> void:
    # Lazy anchor: _ready() runs during add_child, before a spawner that
    # positions the node afterwards gets to set global_position - so the
    # wander home is captured here, or handed over by World._spawn_npc().
    if anchor == Vector2.ZERO:
        anchor = global_position

    if not is_on_floor():
        velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

    _decide_t -= delta
    if is_on_floor() and _decide_t <= 0.0:
        if randf() < 0.45:
            _dir = randi_range(-1, 1)
            _walk_t = randf_range(0.4, 1.2)
        else:
            _dir = 0
        _decide_t = randf_range(1.5, 3.5)

    if _dir != 0 and _walk_t > 0.0:
        _walk_t -= delta
        velocity.x = move_toward(velocity.x, _dir * WALK_SPEED, 400.0 * delta)
        sprite.flip_h = _dir < 0.0
        # Turn back at the edge of the wander radius so the villager
        # never drifts away from its spawn.
        if global_position.x > anchor.x + WANDER_RADIUS:
            _dir = -1
        elif global_position.x < anchor.x - WANDER_RADIUS:
            _dir = 1
    else:
        velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
        _dir = 0

    move_and_slide()

    var anim := "walk" if absf(velocity.x) > 10.0 else "idle"
    if sprite.animation != anim:
        sprite.play(anim)


## Next line of flavour dialogue, cycling through the scripted set.
func talk() -> String:
    var line: String = LINES[_line]
    _line = (_line + 1) % LINES.size()
    return line


func in_range_of(origin: Vector2) -> bool:
    return global_position.distance_to(origin) <= TALK_DIST * TilesetFactory.TILE_SIZE