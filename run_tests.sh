#!/usr/bin/env bash
# Headless checks for Cavebound. Usage: ./run_tests.sh [path-to-godot]
set -euo pipefail

GODOT="${1:-godot}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run() {
    echo
    echo "############ $1 ############"
    "$GODOT" --headless --path "$DIR" --script "$2" "${@:3}"
}

# The class_name globals (WorldGen, TilesetFactory) only resolve once
# .godot/global_script_class_cache.cfg exists. On a fresh copy - or any
# clone that excluded .godot - that file is missing and every script that
# references another fails to parse with "Identifier not declared".
# Importing first makes this work from a clean checkout.
echo
echo "############ import ############"
"$GODOT" --headless --path "$DIR" --import

run "parse check" "res://tools/parse_check.gd"
run "player sprite art" "res://tools/sprite_test.gd"
run "worldgen invariants" "res://tools/gen_test.gd"
run "player physics / collision" "res://tools/play_test.gd" -- --no-creatures
run "digging / building" "res://tools/dig_test.gd" -- --no-creatures
run "building / crafting" "res://tools/build_test.gd" -- --no-creatures
run "mobs + npcs" "res://tools/mob_test.gd"
run "lightmap" "res://tools/light_test.gd"

echo
echo "############ boot smoke test ############"
# 900 frames is enough for generation + the frame-sliced world paint.
"$GODOT" --headless --path "$DIR" --quit-after 900
echo "boot clean, no engine errors"

echo
echo "all suites passed"
