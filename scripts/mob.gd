extends CharacterBody2D

## A slime mob: hops toward the player inside aggro range, deals contact
## damage on landing against them, flinches and knocks back when hit,
## and dies to the player's melee swing.
##
## Gravity mirrors the player (gravity_scale = 0, applied here) so the
## hop reads as a proper arc. The scene sets the sprite and collision
## box; this script only tunes the fight.

const HOP_VX := 110.0
const HOP_VY := -250.0
const HOP_INTERVAL := 0.9
const HOP_JITTER := 0.5
const AGGRO_DIST := 320.0
const GRAVITY := 950.0
const MAX_FALL := 600.0
const MAX_HP := 4
const CONTACT_DAMAGE := 1
const HURT_CD := 1.0
const KNOCKBACK := 140.0

## Set by World before the slime is added to the tree.
var world: Node2D

var hp := MAX_HP
var dead := false

var _hop_t := 0.0
var _hurt_t := 0.0
var _flash := 0.0

@onready var sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
    add_to_group("mobs")
    sprite.sprite_frames = MobArt.build_frames()
    sprite.play("idle")


func _physics_process(delta: float) -> void:
    _hop_t = maxf(_hop_t - delta, 0.0)
    _hurt_t = maxf(_hurt_t - delta, 0.0)
    _flash = maxf(_flash - delta * 6.0, 0.0)
    sprite.modulate = Color(1.0 + _flash, 1.0 + _flash, 1.0 + _flash)

    if not is_on_floor():
        velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL)

    var player: CharacterBody2D = get_tree().get_first_node_in_group("player") \
            as CharacterBody2D
    var dist := INF
    var face := 1.0
    if player != null:
        dist = global_position.distance_to(player.global_position)
        if not is_equal_approx(player.global_position.x, global_position.x):
            face = 1.0 if player.global_position.x > global_position.x else -1.0
    sprite.flip_h = face < 0.0

    if dist <= AGGRO_DIST and is_on_floor() and _hop_t <= 0.0:
        velocity.x = face * HOP_VX
        velocity.y = HOP_VY
        _hop_t = HOP_INTERVAL + randf() * HOP_JITTER
    elif is_on_floor():
        velocity.x = move_toward(velocity.x, 0.0, 2400.0 * delta)

    move_and_slide()

    if not is_on_floor():
        _play("hop")
    else:
        _play("idle")

    _contact_damage()


## Landing on the player (or being bumped into them) hurts them, but only
## after a cooldown so a single contact can't stack multiple hits.
func _contact_damage() -> void:
    if _hurt_t > 0.0:
        return
    for i in get_slide_collision_count():
        var body := get_slide_collision(i).get_collider()
        if body is CharacterBody2D and body.is_in_group("player") \
                and body.has_method("take_damage"):
            body.take_damage(CONTACT_DAMAGE)
            _hurt_t = HURT_CD
            break


func _play(anim: String) -> void:
    if sprite.animation != anim:
        sprite.play(anim)


## Melee hit from the player. Flinches white and gets knocked away from
## the attacker; at zero HP the slime dies and the world counts the kill.
func take_damage(amount: int, from: Vector2) -> void:
    if dead:
        return
    hp -= amount
    _flash = 1.0
    var dir := 1.0 if global_position.x >= from.x else -1.0
    velocity.x = dir * KNOCKBACK
    velocity.y = -80.0
    if hp <= 0:
        die()


func die() -> void:
    dead = true
    var w := world
    queue_free()
    if w != null and w.has_method("on_mob_killed"):
        w.on_mob_killed(self)