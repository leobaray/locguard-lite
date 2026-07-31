#!/bin/bash
# Produces shot-dock.png (1280x720) for the LITE listing from a real Godot
# editor session — the Lite dock (2 rules + promo LinkButton), never the Pro
# one. Same recipe as locguard/pro/shot-tools/capture.sh, with the Lite addon
# from THIS worktree swapped in over the shared test fixture.
#
# Usage: shot-tools/capture.sh [output.png]
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
GODOT=/sistemas/blobsmith/tools/godot/Godot_v4.7-stable_linux.x86_64
OUT=${1:-$REPO/shot-dock.png}
PROJ=/tmp/lg-lite-shot
RAW=/tmp/lg-lite-shot-raw.png

rm -rf "$PROJ"
cp -r /sistemas/locguard/test/fixtures/godot-proj "$PROJ"
# The fixture ships the Pro addon and scripts that preload it; the shot must
# show ONLY Lite, so both go.
rm -rf "$PROJ/addons/locguard" "$PROJ/verify_addon_parity.gd" "$PROJ/verify_addon_parity.gd.uid"
cp -r "$REPO/addons/locguard_lite" "$PROJ/addons/locguard_lite"
mkdir -p "$PROJ/addons/shotkick"
cp "$HERE/shotkick_plugin.gd" "$PROJ/addons/shotkick/plugin.gd"
cp "$HERE/shotkick_plugin.cfg" "$PROJ/addons/shotkick/plugin.cfg"
sed -i 's|enabled=PackedStringArray("res://addons/locguard/plugin.cfg")|enabled=PackedStringArray("res://addons/locguard_lite/plugin.cfg", "res://addons/shotkick/plugin.cfg")|' \
  "$PROJ/project.godot"
grep -q shotkick "$PROJ/project.godot" || { echo "FAIL: shotkick not enabled in project.godot"; exit 1; }
grep -q locguard_lite "$PROJ/project.godot" || { echo "FAIL: locguard_lite not enabled"; exit 1; }

xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" --editor --path "$PROJ" --import >/tmp/godot-lite-import.log 2>&1
echo "import done"

pkill -f 'Xvfb :99' 2>/dev/null
Xvfb :99 -screen 0 1600x900x24 >/tmp/xvfb99.log 2>&1 &
XPID=$!
sleep 3
DISPLAY=:99 "$GODOT" --editor --resolution 1600x900 --position 0,0 --path "$PROJ" >/tmp/godot-lite-shot.log 2>&1 &
GPID=$!
sleep 45
DISPLAY=:99 import -window root "$RAW"
echo "grab-exit=$?"
grep -a SHOTKICK /tmp/godot-lite-shot.log
kill $GPID 2>/dev/null
sleep 2
kill $XPID 2>/dev/null

ffmpeg -y -loglevel error -i "$RAW" -vf "scale=1280:720:flags=lanczos" "$OUT"
identify "$OUT"
