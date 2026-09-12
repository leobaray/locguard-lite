#!/usr/bin/env bash
# Runs every claim in docs/why-your-exported-game-is-not-translated.md against a
# real Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_export_pack.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds throwaway projects in a temp directory, exports a .pck from each one
# with the engine's own exporter, and then RUNS that .pck. Nothing here touches
# your files, and no export template is needed: `--export-pack` writes the data
# pack, which is the part that carries (or does not carry) your translations.
#
# The engine's exit code is NOT the gate: the export exits 0 whether or not your
# translations went in, which is half of what this document is about. The gate is
# the LG_END line printed by verify_export_pack.gd inside each artifact. A run
# that did not reach it measured nothing, and that is reported as an error.
#
# LG_SELFTEST=1 flips one expectation on purpose: the run must then FAIL. That is
# the negative control for the harness itself.
set -uo pipefail

GODOT="${1:-}"
if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
  echo "usage: $0 /path/to/godot-binary [more binaries...]" >&2
  exit 2
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
VER="$("$GODOT" --headless --version 2>/dev/null | head -1)"
VER_MM="$(printf '%s' "$VER" | cut -d. -f1,2)"
# The preset's platform string is part of the file format, not of this document:
# 4.2 calls the platform "Linux/X11" and 4.3 renamed it to "Linux". A preset
# whose platform the binary does not know is silently detected as no preset at
# all, so this is checked rather than assumed (see the pack guard below).
case "$VER_MM" in
  4.2) PLATFORM="Linux/X11" ;;
  *)   PLATFORM="Linux" ;;
esac
PASSED=0; FAILED=0; SKIPPED=0
say() { printf '%s\n' "$*"; }
claim() {  # claim <id> <desc> <ok:0|1> [detail]
  if [ "$3" = "1" ]; then say "PASS  $1  $2"; PASSED=$((PASSED+1));
  else say "FAIL  $1  $2"; FAILED=$((FAILED+1)); fi
  [ -n "${4:-}" ] && say "        $4"
  return 0
}
skip() { say "SKIP  $1  $2"; SKIPPED=$((SKIPPED+1)); }

# --------------------------------------------------------------- the project
# One table, two locales, one scene, and the reporter as that scene's script, so
# the same project can be run from source and from the pack with nothing else
# differing. The .translation files are named ONLY in project.godot: no scene,
# script or resource references them. That is not a trick of this harness, it is
# how every Godot project declares its translations.
build() {  # build <dir> <export_filter> <include_filter> <exclude_filter>
  local d="$1" ef="$2" inc="$3" exc="$4"
  mkdir -p "$d"
  cat > "$d/project.godot" <<'EOF'
config_version=5

[application]

config/name="LocGuardExportPackCheck"
run/main_scene="res://main.tscn"

[internationalization]

locale/translations=PackedStringArray("res://strings.en.translation", "res://strings.pt.translation")
EOF
  printf 'keys,en,pt\nGREET,Hello,Ola\n' > "$d/strings.csv"
  cat > "$d/main.tscn" <<'EOF'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://verify_export_pack.gd" id="1"]

[node name="Main" type="Node"]
script = ExtResource("1")
EOF
  cp "$HERE/verify_export_pack.gd" "$d/verify_export_pack.gd"
  cat > "$d/export_presets.cfg" <<EOF
[preset.0]

name="Linux"
platform="$PLATFORM"
runnable=true
custom_features=""
export_filter="$ef"
include_filter="$inc"
exclude_filter="$exc"
export_files=PackedStringArray("res://main.tscn")
export_path="game.pck"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false

[preset.0.options]

EOF
}

import_pass() { "$GODOT" --headless --path "$1" --editor --quit-after 300 > "$1/import.log" 2>&1; }
export_pack() {
  "$GODOT" --headless --path "$1" --export-pack Linux "$1/game.pck" > "$1/export.log" 2>&1
  local code=$?
  if [ ! -f "$1/game.pck" ]; then
    echo "ERROR: no game.pck came out of $1 (exit $code) — nothing below is measurable." >&2
    tail -8 "$1/export.log" >&2
    exit 3
  fi
  echo "$code"
}

# Runs an artifact and stores its output. run_artifact <case> <dir> <pack|source>
run_artifact() {
  local case_name="$1" d="$2" mode="$3" out
  if [ "$mode" = "pack" ]; then
    # Never hand a missing pack to the engine: without one it falls back to the
    # project manager and waits forever instead of failing.
    [ -f "$d/game.pck" ] || { echo "ERROR: case $case_name has no game.pck to run." >&2; exit 3; }
    out="$(LGCASE="$case_name" "$GODOT" --headless --main-pack "$d/game.pck" 2>&1)"
  else
    out="$(LGCASE="$case_name" "$GODOT" --headless --path "$d" 2>&1)"
  fi
  printf '%s\n' "$out" > "$WORK/$case_name.$mode.out"
  if ! printf '%s\n' "$out" | grep -q '^LG_END'; then
    echo "ERROR: case $case_name ($mode) did not reach LG_END — nothing was measured there. Full output:" >&2
    printf '%s\n' "$out" >&2
    exit 3
  fi
}
field() { grep -m1 "^$2 " "$WORK/$1.out" | cut -d' ' -f2- ; }

# ------------------------------------------------------------------ scenarios
# base: the default preset every new project gets — export all resources.
build "$WORK/base" all_resources "" ""
import_pass "$WORK/base"
if [ ! -f "$WORK/base/strings.pt.translation" ]; then
  echo "ERROR: the import pass produced no strings.pt.translation — nothing below is measurable." >&2
  tail -5 "$WORK/base/import.log" >&2; exit 3
fi
BASE_EXIT="$(export_pack "$WORK/base")"
run_artifact base "$WORK/base" pack

# scenes: "Export selected scenes (and dependencies)" — the preset a team picks
# to keep test maps and tooling out of the shipped build.
build "$WORK/scenes" scenes "" ""
import_pass "$WORK/scenes"
SCENES_EXIT="$(export_pack "$WORK/scenes")"
run_artifact scenes "$WORK/scenes" pack
run_artifact scenes "$WORK/scenes" source

# a resource filter that does not mean to name the translations
build "$WORK/exctrans" all_resources "" "*.translation"
import_pass "$WORK/exctrans"
EXCT_EXIT="$(export_pack "$WORK/exctrans")"
run_artifact exctrans "$WORK/exctrans" pack
run_artifact exctrans "$WORK/exctrans" source

# one locale left out, the rest shipped
build "$WORK/excpt" all_resources "" "*.pt.translation"
import_pass "$WORK/excpt"
export_pack "$WORK/excpt" > /dev/null
run_artifact excpt "$WORK/excpt" pack

# the CSV left out on purpose
build "$WORK/exccsv" all_resources "" "*.csv"
import_pass "$WORK/exccsv"
export_pack "$WORK/exccsv" > /dev/null
run_artifact exccsv "$WORK/exccsv" pack

# scenes again, with the include filter that brings the translations back
build "$WORK/fixed" scenes "*.translation" ""
import_pass "$WORK/fixed"
export_pack "$WORK/fixed" > /dev/null
run_artifact fixed "$WORK/fixed" pack

# a tree nobody opened in the editor: no .godot/, no .import, no .translation —
# a fresh clone on a build machine.
build "$WORK/fresh" all_resources "" ""
FRESH_EXIT="$(export_pack "$WORK/fresh")"
run_artifact fresh "$WORK/fresh" pack

# --------------------------------------------------------------------- claims
say "== $VER"

EXPECT_KEY="GREET"
[ "${LG_SELFTEST:-0}" = "1" ] && EXPECT_KEY="Ola"   # negative control

[ "$(field base.pack LG_SEES)" = "Ola" ] && ok=1 || ok=0
claim M1 "the default preset (export all resources) ships the translations: the packed game translates" "$ok" \
  "pack: LG_SEES=$(field base.pack LG_SEES), loaded=[$(field base.pack LG_LOADED)], export exit=$BASE_EXIT"

[ "$(field base.pack LG_HAS_CSV)" = "false" ] && [ "$(field base.pack LG_HAS_PT)" = "true" ] && ok=1 || ok=0
claim M2 "your strings.csv is NOT in the pack even with all resources exported — only the generated .translation is" "$ok" \
  "pack: strings.csv exists=$(field base.pack LG_HAS_CSV), strings.pt.translation exists=$(field base.pack LG_HAS_PT)"

[ "$(field scenes.pack LG_SEES)" = "$EXPECT_KEY" ] && [ "$(field scenes.pack LG_HAS_PT)" = "false" ] && ok=1 || ok=0
claim M3 "with 'export selected scenes (and dependencies)' no scene depends on a .translation, so none is packed and the player reads the KEY" "$ok" \
  "pack: LG_SEES=$(field scenes.pack LG_SEES), loaded=[$(field scenes.pack LG_LOADED)], strings.pt.translation exists=$(field scenes.pack LG_HAS_PT)"

[ "$(field exctrans.pack LG_SEES)" = "GREET" ] && [ "$(field exctrans.pack LG_LOADED)" = "" ] && ok=1 || ok=0
claim M4 "a resource exclude filter that happens to match *.translation empties the game of every language, silently" "$ok" \
  "pack: LG_SEES=$(field exctrans.pack LG_SEES), loaded=[$(field exctrans.pack LG_LOADED)]"

[ "$SCENES_EXIT" = "0" ] && [ "$EXCT_EXIT" = "0" ] && \
  ! grep -qi 'translation' "$WORK/scenes/export.log" && ok=1 || ok=0
claim M5 "the export that dropped every translation exits 0 and its log never says the word" "$ok" \
  "export exit: scenes=$SCENES_EXIT exclude=*.translation=$EXCT_EXIT; 'translation' in the scenes export log: $(grep -ci translation "$WORK/scenes/export.log")"

# The first sentence is the invariant across 4.2 -> 4.7. The advice that follows
# it ("open the project in the editor at least once") is NOT: 4.2, 4.3 and 4.4
# append it, 4.7 dropped it. Asserting the long form would report a documentation
# defect as an engine regression, so the tail is measured and printed, not gated.
if grep -q 'opening the project in the editor at least once' "$WORK/scenes.pack.out"; then
  M6TAIL="yes"; else M6TAIL="no"; fi
grep -q 'Failed loading resource: res://strings\..*\.translation' "$WORK/scenes.pack.out" && ok=1 || ok=0
claim M6 "the only runtime signal is an error on stdout, printed after the game already decided to show the key" "$ok" \
  "$(grep -m1 'Failed loading resource' "$WORK/scenes.pack.out" | sed 's/^[[:space:]]*//') [editor-import advice appended: $M6TAIL]"

[ "$(field excpt.pack LG_SEES)" = "Hello" ] && [ "$(field excpt.pack LG_LOADED)" = "en" ] && ok=1 || ok=0
claim M7 "leave ONE locale out and that player gets the source language, not the key: nothing on screen looks broken" "$ok" \
  "pack: LG_SEES=$(field excpt.pack LG_SEES) (asked for pt), loaded=[$(field excpt.pack LG_LOADED)]"

PCKGREP="$(grep -a -c 'strings\.pt\.translation' "$WORK/scenes/game.pck" 2>/dev/null || true)"
[ "${PCKGREP:-0}" -gt 0 ] && [ "$(field scenes.pack LG_HAS_PT)" = "false" ] && ok=1 || ok=0
claim M8 "grepping the .pck for the filename finds it even when the file is not in there (the path lives in the packed project settings), so a grep is not a presence test" "$ok" \
  "grep hits in the pack=$PCKGREP, file present at runtime=$(field scenes.pack LG_HAS_PT)"

[ "$(field scenes.source LG_SEES)" = "Ola" ] && [ "$(field exctrans.source LG_SEES)" = "Ola" ] && ok=1 || ok=0
claim M9 "both broken projects translate perfectly when run from the project directory: the failure exists only in the artifact the player runs" "$ok" \
  "source run: scenes=$(field scenes.source LG_SEES), exclude-translation=$(field exctrans.source LG_SEES)"

[ "$(field fixed.pack LG_SEES)" = "Ola" ] && [ "$(field fixed.pack LG_HAS_PT)" = "true" ] && ok=1 || ok=0
claim M10 "adding *.translation to the preset's include filter fixes it without touching the CSV, the code or the locales" "$ok" \
  "pack: LG_SEES=$(field fixed.pack LG_SEES), strings.pt.translation exists=$(field fixed.pack LG_HAS_PT)"

[ "$(field exccsv.pack LG_SEES)" = "Ola" ] && ok=1 || ok=0
claim M11 "excluding *.csv from the export changes nothing for the player: the game never reads the CSV" "$ok" \
  "pack: LG_SEES=$(field exccsv.pack LG_SEES), loaded=[$(field exccsv.pack LG_LOADED)]"

[ "$(field fresh.pack LG_SEES)" = "Ola" ] && ok=1 || ok=0
claim M12 "exporting a tree nobody opened in the editor (no .godot/, no .translation on disk) still ships the translations: the export runs its own import first" "$ok" \
  "export exit=$FRESH_EXIT, pack: LG_SEES=$(field fresh.pack LG_SEES), loaded=[$(field fresh.pack LG_LOADED)]"

# ------------------------------------------------------------------- roll-call
say ""
say "SUMMARY $VER: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -gt 0 ] && exit 1
exit 0
