extends SceneTree

## Functional test for mobs + npcs: boots the real main scene headlessly
## and verifies the creature spawner, slime AI (idle / aggro hop),
## contact damage + i-frames, the player's melee swing killing a slime,
## the villager's dialogue + harmlessness, and death respawning.
##
##   godot --headless --path . --script res://tools/mob_test.gd
##
## Runs WITHOUT --no-creatures so the seed-derived auto-spawner is
## exercised first; the precise AI/combat phases then use one exact
## slime + one exact npc placed at known cells for determinism.

const T := TilesetFactory.TILE_SIZE
const SLIME_SCENE := preload("res://scenes/mob.tscn")
const NPC_SCENE := preload("res://scenes/npc.tscn")

const SLIME_HALF_H := 5.0
const NPC_HALF_H := 11.0
const MAX_HP := 10

var main: Node
var frames := 0
var phase := 0
var failures: Array[String] = []
var slime: CharacterBody2D
var villager: CharacterBody2D
var slime_spot := Vector2i(-1, -1)
var npc_spot := Vector2i(-1, -1)
var _idle_x0 := 0.0
var _aggro_x0 := 0.0
var _npc_tail := 1


func _initialize() -> void:
    main = load("res://scenes/main.tscn").instantiate()
    root.add_child(main)


func _process(_delta: float) -> bool:
    frames += 1
    var player := main.get_node_or_null("Entities/Player") as CharacterBody2D
    var loading := main.get_node_or_null("UI/Loading") as Control

    match phase:
        0: return _wait_for_world(player, loading)
        1: return _check_art()
        2: return _check_auto_spawn()
        3: return _place_creatures(player)
        4: return _check_idle()
        5: return _check_aggro(player)
        6: return _check_contact(player)
        7: return _check_melee(player)
        8: return _check_npc(player)
        9: return _check_npc_tail(player)

    return false


# -- phase 0: wait for generation and painting ------------------------

func _wait_for_world(player: CharacterBody2D, loading: Control) -> bool:
    if frames > 900:
        failures.append("world never finished generating (loading still up)")
        return _finish()
    if loading != null and not loading.visible and player != null:
        phase = 1
        frames = 0
    return false


# -- phase 1: slime + villager art ------------------------------------

func _check_art() -> bool:
    _art_sanity("slime", MobArt.build_frames(), MobArt.ANIMS,
            [MobArt.BODY, MobArt.EYE])
    _art_sanity("villager", NpcArt.build_frames(), NpcArt.ANIMS,
            [NpcArt.ROBE, NpcArt.BEARD])
    print("  art ok")
    phase = 2
    frames = 0
    return false


func _art_sanity(kind: String, sf: SpriteFrames, expected: Dictionary,
        colors: Array) -> void:
    for anim: String in expected.keys():
        if not sf.has_animation(anim):
            failures.append("%s art has no \"%s\" animation" % [kind, anim])
            continue
        var n: int = sf.get_frame_count(anim)
        if n != expected[anim]:
            failures.append("%s \"%s\" has %d frames, expected %d"
                    % [kind, anim, n, expected[anim]])
            continue
        var prev: Image = null
        for f in n:
            var img: Image = sf.get_frame_texture(anim, f).get_image()
            var opaque := 0
            var seen: Dictionary = {}
            for y in img.get_height():
                for x in img.get_width():
                    if img.get_pixel(x, y).a > 0.0:
                        opaque += 1
                        var rgb: int = img.get_pixel(x, y).to_rgba32()
                        seen[rgb] = true
            if opaque < 20:
                failures.append("%s \"%s\" frame %d is nearly blank (%d px)"
                        % [kind, anim, f, opaque])
            if f > 0 and prev != null and prev.get_data() == img.get_data():
                failures.append("%s \"%s\" frames %d and %d are identical"
                        % [kind, anim, f - 1, f])
            prev = img
            for want in colors:
                if not _image_has(img, want):
                    failures.append("%s \"%s\" frame %d missing colour %s"
                            % [kind, anim, f, want.to_html()])


func _image_has(img: Image, c: Color) -> bool:
    for y in img.get_height():
        for x in img.get_width():
            if img.get_pixel(x, y) == c:
                return true
    return false


# -- phase 2: the auto-spawner produced its creatures ------------------

func _check_auto_spawn() -> bool:
    if frames < 10:
        return false
    _expect_counts(8, 2)
    _expect_grounded()
    print("  auto-spawn: mobs=%d npcs=%d, all on the ground"
            % [get_nodes_in_group("mobs").size(),
               get_nodes_in_group("npcs").size()])
    # Re-running the spawner must give the same world (seed-derived).
    main.clear_creatures()
    main.spawn_creatures()
    phase = 3
    frames = -15  # let the old mobs free themselves first
    return false


# -- phase 3: exact creatures for the AI/combat phases -----------------

func _place_creatures(player: CharacterBody2D) -> bool:
    if frames < 20:
        return false
    # Rebuilt from the seed, so the same counts must come back.
    _expect_counts(8, 2)
    _expect_grounded()
    main.clear_creatures()

    slime_spot = _find_spot(70)
    npc_spot = _find_spot(40)
    if slime_spot.x < 0 or npc_spot.x < 0:
        failures.append("no clean surface spots found for the test creatures")
        return _finish()

    slime = _place_slime(slime_spot)
    villager = _place_npc(npc_spot)
    player.velocity = Vector2.ZERO
    phase = 4
    frames = 0
    return false


func _place_slime(cell: Vector2i) -> CharacterBody2D:
    var mob := SLIME_SCENE.instantiate() as CharacterBody2D
    main.get_node("Entities").add_child(mob)
    mob.world = main
    mob.global_position = Vector2((cell.x + 0.5) * T, cell.y * T - SLIME_HALF_H)
    return mob


func _place_npc(cell: Vector2i) -> CharacterBody2D:
    var npc := NPC_SCENE.instantiate() as CharacterBody2D
    main.get_node("Entities").add_child(npc)
    npc.world = main
    npc.global_position = Vector2((cell.x + 0.5) * T, cell.y * T - NPC_HALF_H)
    return npc


# -- phase 4: out of aggro, a slime stands still -----------------------

func _check_idle() -> bool:
    if frames == 60:
        if not slime.is_on_floor():
            failures.append("slime never settled on the ground (y=%.1f)"
                    % slime.global_position.y)
            return _finish()
        # Player is at spawn, far outside the slime's aggro radius.
        var px := int(slime.global_position.x / T)
        var player_x := int((main.get_node("Entities/Player") as Node2D).position.x / T)
        if absi(px - player_x) < 20:
            failures.append("test slime too close to the player for an idle test")
            return _finish()
        _idle_x0 = slime.global_position.x
    elif frames == 210:  # 60 frames to settle + 150 of standing
        if absf(slime.global_position.x - _idle_x0) > 2.0:
            failures.append("slime moved while the player was out of aggro "
                    + "(dx=%.1f px)" % absf(slime.global_position.x - _idle_x0))
        print("  idle ok: dx=%.1f px over 150 frames"
                % absf(slime.global_position.x - _idle_x0))
        phase = 5
        frames = 0
    return false


# -- phase 5: inside aggro, a slime hops toward the player -------------

func _check_aggro(player: CharacterBody2D) -> bool:
    if frames == 1:
        player.velocity = Vector2.ZERO
        player.global_position = slime.global_position + Vector2(-64, 0)
    elif frames == 60:
        _aggro_x0 = slime.global_position.x  # player has settled beside it
    elif frames == 240:  # 60 to settle + 180 of hopping
        var dx := slime.global_position.x - _aggro_x0
        if dx > -6.0:
            failures.append("slime did not hop toward the player (dx=%.1f px, "
                    % dx + "player to its left)")
        else:
            print("  aggro ok: slime moved %.1f px toward the player"
                    % absf(dx))
        phase = 6
        frames = 0
    return false


# -- phase 6: contact damage + i-frames --------------------------------

func _check_contact(player: CharacterBody2D) -> bool:
    if frames == 1:
        player.velocity = Vector2.ZERO
        player.global_position = slime.global_position
        return false
    if frames < 150:
        return false
    if player.hp >= MAX_HP:
        failures.append("slime contact never damaged the player "
                + "(hp=%d after 150 frames on top of it)" % player.hp)
        return _finish()

    # Back-to-back hits: the second one must be swallowed by the i-frames
    # the first one opens, no matter when contact last landed.
    var before: int = player.hp
    player.take_damage(1)
    var after_first: int = player.hp
    player.take_damage(1)
    if player.hp != after_first:
        failures.append("i-frames did not stop a back-to-back hit "
                + "(hp %d -> %d)" % [after_first, player.hp])
    player.heal_full()
    print("  contact ok: took damage (hp -> %d), i-frames hold" % before)
    phase = 7
    frames = 0
    return false


# -- phase 7: the melee swing kills the slime --------------------------

func _check_melee(player: CharacterBody2D) -> bool:
    if frames == 1:
        player.velocity = Vector2.ZERO
        player.global_position = slime.global_position + Vector2(-40, 0)
        return false
    if frames < 30:
        return false

    # mob_at() resolution + reach refusal.
    if main.mob_at(slime.global_position) != slime:
        failures.append("mob_at() did not find the slime at its position")
    if main.mob_at(Vector2(99999, 99999)) != null:
        failures.append("mob_at() found a mob in the void")
    var far := player.global_position + Vector2(500, 0)
    player.global_position = slime.global_position + Vector2(-10, 0)
    if player.attack_mob_at(far):
        failures.append("melee hit something 500px away")

    # Two hits (2 dmg each) kill the 4-hp slime.
    if not player.attack_mob_at(slime.global_position):
        failures.append("first melee hit missed a reachable slime")
    if slime.hp != 2:
        failures.append("first hit did not deal 2 damage (hp=%d)" % slime.hp)
    if not player.attack_mob_at(slime.global_position):
        failures.append("second melee hit missed the slime")
    if is_instance_valid(slime) and not slime.is_queued_for_deletion():
        failures.append("slime survived two 2-damage hits (hp=%d)" % slime.hp)
    if slime.hp != 0:
        failures.append("slime still has hp after two hits (hp=%d)" % slime.hp)

    if main.slime_kills != 1:
        failures.append("kill was not counted (slime_kills=%d)" % main.slime_kills)
    print("  melee ok: two hits killed the slime, kill counted")
    phase = 8
    frames = 0
    return false


# -- phase 8: the villager talks and never hurts -----------------------

func _check_npc(player: CharacterBody2D) -> bool:
    if frames == 1:
        for i in 3:
            var line: String = villager.talk()
            if not villager.LINES.has(line):
                failures.append("talk() returned a line outside the script")
                return false
        player.velocity = Vector2.ZERO
        player.global_position = villager.global_position + Vector2(-24, 0)
        return false
    if frames < 45:
        return false

    # E next to the villager shows one of its lines in the HUD.
    var before_flash: String = main.hud_flash
    if not main.talk_nearby():
        failures.append("talk_nearby() failed with the player beside the npc")
    if not villager.LINES.has(main.hud_flash):
        failures.append("talk_nearby() did not put a villager line in the HUD")
    main.hud_flash = before_flash

    # Send the player back to spawn and let the villager wander alone, so
    # the wander-bound check measures only its own walking.
    var gen: WorldGen = main.gen
    player.velocity = Vector2.ZERO
    player.global_position = Vector2((gen.spawn.x + 0.5) * T,
            gen.surface[gen.spawn.x] * T - 11.0)
    _npc_tail = 1
    phase = 9
    frames = 0
    return false


# -- phase 9: wander bounds, then villager contact, then death ----------

func _check_npc_tail(player: CharacterBody2D) -> bool:
    if _npc_tail == 1:
        # Stage A: 240 frames of free wandering; player stays at spawn so
        # nothing can shove the villager - it must stay inside its radius.
        if frames == 240:
            var drift: float = absf(villager.global_position.x - villager.anchor.x)
            if drift > villager.WANDER_RADIUS + 8.0:
                failures.append("villager wandered away from its anchor "
                        + "(drift=%.1f px)" % drift)
            print("  wander ok: max drift %.1f px" % drift)
            player.velocity = Vector2.ZERO
            player.global_position = villager.global_position
            _npc_tail = 2
            frames = 0
        return false
    if _npc_tail == 2:
        # Stage B: standing on the villager must not hurt the player.
        if frames == 60:
            if player.hp != MAX_HP:
                failures.append("standing on the villager damaged the player "
                        + "(hp=%d)" % player.hp)
            print("  npc contact ok: no damage from standing on the villager")
            _npc_tail = 3
            frames = 0
        return false

    # Stage C: death respawns the player at spawn with full health.
    if frames == 1:
        player.take_damage(99)
        if player.hp != MAX_HP:
            failures.append("death did not respawn the player at full health")
        var gen: WorldGen = main.gen
        var target := Vector2((gen.spawn.x + 0.5) * T,
                gen.surface[gen.spawn.x] * T)
        if player.global_position.distance_to(target) > 3 * T:
            failures.append("respawn left the player away from spawn "
                    + "(%.0f, %.0f)" % [player.global_position.x,
                    player.global_position.y])
        print("  death ok: respawned at (%d, %d) with full health"
                % [gen.spawn.x, gen.surface[gen.spawn.x]])
        return _finish()
    return false


# ------------------------------------------------------------------ utils

## First surface cell at least `offset` tiles right of spawn with solid
## ground + clear rows above - a spot a creature can live on.
func _find_spot(offset: int) -> Vector2i:
    var gen: WorldGen = main.gen
    for x in range(gen.spawn.x + offset, gen.spawn.x + offset + 200):
        if x < 2 or x >= gen.width - 2:
            continue
        var sy: int = gen.surface[x]
        if sy < 8:
            continue
        var i := sy * gen.width + x
        if not TilesetFactory.SOLID.has(gen.tiles[i]):
            continue
        var above: int = gen.tiles[i - gen.width]
        if above != WorldGen.Tile.AIR \
                and not main.DECOR.has(above):
            continue
        if gen.tiles[i - 2 * gen.width] != WorldGen.Tile.AIR:
            continue
        return Vector2i(x, sy)
    return Vector2i(-1, -1)


func _expect_counts(mobs: int, npcs: int) -> void:
    var m: int = get_nodes_in_group("mobs").size()
    var n: int = get_nodes_in_group("npcs").size()
    if m != mobs or n != npcs:
        failures.append("spawner made %d mobs + %d npcs, expected %d + %d"
                % [m, n, mobs, npcs])


## Every creature must rest with a solid tile under its feet, and its
## sprite soles must line up with the collision box bottom.
func _expect_grounded() -> void:
    for m in get_nodes_in_group("mobs"):
        if not _on_ground(m as Node2D, SLIME_HALF_H):
            failures.append("a slime floats over no solid ground")
        _feet_aligned(m as Node2D, SLIME_HALF_H, 16.0, -3.0)
    for n in get_nodes_in_group("npcs"):
        if not _on_ground(n as Node2D, NPC_HALF_H):
            failures.append("a villager floats over no solid ground")
        _feet_aligned(n as Node2D, NPC_HALF_H, 24.0, -1.0)


func _on_ground(node: Node2D, half_h: float) -> bool:
    var gen: WorldGen = main.gen
    var cell := Vector2i(
            int(node.global_position.x / T),
            int((node.global_position.y + half_h) / T))
    if cell.x < 0 or cell.x >= gen.width or cell.y < 0 or cell.y >= gen.height:
        return false
    return TilesetFactory.SOLID.has(gen.tiles[cell.y * gen.width + cell.x])


## Feet at the box bottom: node.y + half_h must equal the sprite's sole
## row (node.y + offset.y + H/2 within the sprite atlas).
func _feet_aligned(node: Node2D, half_h: float, art_h: float, off_y: float) -> void:
    var sprite := node.get_node("Sprite") as AnimatedSprite2D
    var box := node.global_position.y + half_h
    var sole := node.global_position.y + off_y + art_h * 0.5
    if absf(box - sole) > 0.51:
        failures.append("%s soles at y=%.1f, box bottom at y=%.1f"
                % [node.name, sole, box])


func _finish() -> bool:
    print("\n-- result --")
    if failures.is_empty():
        print("  all checks passed")
        quit(0)
    else:
        for f in failures:
            print("  FAIL: %s" % f)
        quit(1)
    return true