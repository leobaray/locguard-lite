#!/usr/bin/env bash
# Runs every claim in docs/why-your-arabic-build-comes-out-mirrored.md against a
# real Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_rtl_layout.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds throwaway projects in a temp directory and runs them headless. The
# numbers it checks are positions read back from real Control nodes after the
# engine's own layout pass, not geometry computed by the harness.
#
# Every binary gets its OWN project directory, freshly imported. That is not
# tidiness: a .translation written by 4.4 is refused by 4.2 ("format version (6)
# ... not supported"), so a directory shared between binaries would silently
# measure "no translation loaded" on the older one — which is one of the cases
# this document is about, and would then be measured in the wrong place.
#
# The engine's exit code is NOT the gate. The gate is the LG_END line printed by
# verify_rtl_layout.gd: a run that did not reach it measured nothing, and that is
# reported as an error rather than as a passing claim.
#
# LG_SELFTEST=1 flips one expectation on purpose: the run must then FAIL. That is
# the negative control for the harness itself.
set -uo pipefail

GODOT="${1:-}"
if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
  echo "usage: $0 /path/to/godot-binary" >&2
  exit 2
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
VER="$("$GODOT" --headless --version 2>/dev/null | head -1)"
VER_MM="$(printf '%s' "$VER" | cut -d. -f1,2)"
PASSED=0; FAILED=0; SKIPPED=0
say() { printf '%s\n' "$*"; }
claim() {  # claim <id> <desc> <ok:0|1> [detail]
  if [ "$3" = "1" ]; then say "PASS  $1  $2"; PASSED=$((PASSED+1));
  else say "FAIL  $1  $2"; FAILED=$((FAILED+1)); fi
  [ -n "${4:-}" ] && say "        $4"
  return 0
}
skip() { say "SKIP  $1  $2"; SKIPPED=$((SKIPPED+1)); }

# --------------------------------------------------------------- the projects
# <dir> <locales in the CSV> <force setting true|false>
build() {
  local d="$1" locales="$2" force="$3"
  mkdir -p "$d"
  {
    printf 'config_version=5\n\n[application]\n\n'
    printf 'config/name="LocGuardRtlCheck"\nrun/main_scene="res://main.tscn"\n\n'
    printf '[internationalization]\n\n'
    printf 'locale/translations=PackedStringArray('
    local first=1 loc
    for loc in $locales; do
      [ "$first" = "0" ] && printf ', '
      printf '"res://strings.%s.translation"' "$loc"
      first=0
    done
    printf ')\n'
    [ "$force" = "true" ] && printf 'rendering/force_right_to_left_layout_direction=true\n'
  } > "$d/project.godot"

  # The CSV carries only the locales this case is supposed to have. A locale the
  # player can select but that was never translated is the whole point of one of
  # the cases below, so it is produced by leaving a column out, not by faking it.
  {
    printf 'keys'
    local loc
    for loc in $locales; do printf ',%s' "$loc"; done
    printf '\n'
    printf 'GREET'
    for loc in $locales; do
      case "$loc" in
        ar) printf ',%s' "مرحبا" ;;
        he) printf ',%s' "שלום" ;;
        *)  printf ',Hello' ;;
      esac
    done
    printf '\n'
  } > "$d/strings.csv"

  cat > "$d/main.tscn" <<'EOF'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://verify_rtl_layout.gd" id="1"]

[node name="Main" type="Node"]
script = ExtResource("1")
EOF
  cp "$HERE/verify_rtl_layout.gd" "$d/verify_rtl_layout.gd"
}

import_pass() { "$GODOT" --headless --path "$1" --editor --quit-after 300 > "$1/import.log" 2>&1; }

# run_case <case> <dir> <locale the player picked>
run_case() {
  local case_name="$1" d="$2" locale="$3" out
  out="$(LGCASE="$case_name" LGLOCALE="$locale" "$GODOT" --headless --path "$d" 2>&1)"
  printf '%s\n' "$out" > "$WORK/$case_name.out"
  if ! printf '%s\n' "$out" | grep -q '^LG_END'; then
    echo "ERROR: case $case_name did not reach LG_END — nothing was measured there. Full output:" >&2
    printf '%s\n' "$out" >&2
    exit 3
  fi
}
field() { grep -m1 "^LG_$2 " "$WORK/$1.out" | cut -d' ' -f2- ; }

# loaded: the Arabic translation is really there, the player picked Arabic.
build "$WORK/loaded" "en ar" false
import_pass "$WORK/loaded"
if [ ! -f "$WORK/loaded/strings.ar.translation" ]; then
  echo "ERROR: the import pass produced no strings.ar.translation — nothing below is measurable." >&2
  tail -5 "$WORK/loaded/import.log" >&2; exit 3
fi
run_case loaded "$WORK/loaded" ar

# missing: the player can pick Hebrew (a right-to-left language) and no Hebrew
# translation was ever loaded. This is what an export that dropped one locale,
# or a language menu written ahead of the translators, actually looks like.
run_case missing "$WORK/loaded" he

# forced: no right-to-left language anywhere, the project setting on. This is
# how you look at a mirrored build before a single Arabic string exists.
build "$WORK/forced" "en" true
import_pass "$WORK/forced"
run_case forced "$WORK/forced" en

# --------------------------------------------------------------------- claims
say "== $VER"
W="$(field loaded ROW_W)"

EXPECT_RTL=true
[ "${LG_SELFTEST:-0}" = "1" ] && EXPECT_RTL=false   # negative control

# The answer for a right-to-left locale that no loaded translation covers is
# where the engines part company, so it is pinned per version rather than
# accepted as whatever came out. See M9.
case "$VER_MM" in
  4.2|4.3|4.4) EXPECT_MISSING_RTL=false ;;
  *)           EXPECT_MISSING_RTL=true ;;
esac

# So is the answer for the project setting that exists to force the mirror. It
# works on 4.2 and is inert from 4.3 on, so the expectation is pinned rather
# than written as "true" and quietly failed on three engines out of four.
case "$VER_MM" in
  4.2) EXPECT_FORCED=true ;;
  *)   EXPECT_FORCED=false ;;
esac

# M1 ------------------------------------------------------------------------
# 12 glyphs for 12 code points, the last glyph starting at code point 0, and an
# inferred direction of 2 (RTL) is the engine reporting a reversed run.
[ "$(field loaded SHAPE_DIR)" = "2" ] && [ "$(field loaded SHAPE_LAST_START)" = "0" ] && ok=1 || ok=0
claim M1 "the Arabic text itself is shaped and reversed correctly: the string is not what is broken" "$ok" \
  "glyphs=$(field loaded SHAPE_GLYPHS), first glyph starts at code point $(field loaded SHAPE_FIRST_START), last at $(field loaded SHAPE_LAST_START), inferred direction=$(field loaded SHAPE_DIR) (2=RTL)"

# M2 ------------------------------------------------------------------------
MODE0="$(field loaded MODE0_X)"
[ "$(field loaded MODE0_RTL)" = "$EXPECT_RTL" ] && awk -v a="$MODE0" -v w="$W" 'BEGIN{exit !(a > w/2)}' && ok=1 || ok=0
claim M2 "selecting a right-to-left language mirrors the whole interface with no code and no setting: the first child of a ${W}px row moves from the left edge to the right" "$ok" \
  "first child x=$MODE0 in a ${W}px row, is_layout_rtl=$(field loaded MODE0_RTL), locale=$(field loaded LOCALE), tr(GREET)=$(field loaded TR)"

# M3 ------------------------------------------------------------------------
[ "$(field loaded BEFORE_X)" != "$(field loaded SAMEFRAME_X)" ] && \
  [ "$(field loaded SAMEFRAME_RTL)" = "true" ] && ok=1 || ok=0
claim M3 "the mirror is synchronous: the positions have already changed in the same frame as set_locale(), before any await" "$ok" \
  "x before=$(field loaded BEFORE_X), x in the same frame after=$(field loaded SAMEFRAME_X), is_layout_rtl=$(field loaded SAMEFRAME_RTL)"

# M4 ------------------------------------------------------------------------
NOISE="$(grep -icE '(ERROR|WARNING).*(layout|direction|mirror|rtl)' "$WORK/loaded.out" || true)"
[ "${NOISE:-0}" = "0" ] && ok=1 || ok=0
claim M4 "nothing is printed when it happens: no error and no warning naming layout, direction or mirroring" "$ok" \
  "matching error/warning lines in the run that mirrored the interface: ${NOISE:-0}"

# M5 ------------------------------------------------------------------------
# 2010 is Node.NOTIFICATION_TRANSLATION_CHANGED, delivered to everything.
# NOTIFICATION_LAYOUT_DIRECTION_CHANGED is the Control notification you would
# subscribe to in order to react to the mirror; the row measured below is a
# Control subclass, so it is the object that would receive it.
NOTIF="$(field loaded NOTIF_CONST)"
[ "$(field loaded SPY_SAW_LAYOUT_NOTIF)" = "false" ] && \
  [ "$(field loaded SPY_SAW_TRANSLATION_NOTIF)" = "true" ] && \
  [ "$(field loaded BEFORE_X)" != "$(field loaded SAMEFRAME_X)" ] && ok=1 || ok=0
claim M5 "Control.NOTIFICATION_LAYOUT_DIRECTION_CHANGED ($NOTIF) exists on every version and is NOT delivered when the layout actually flips: the row moved and the notification never arrived" "$ok" \
  "the row that mirrored ($(field loaded BEFORE_X) -> $(field loaded SAMEFRAME_X)) received: [$(field loaded SPY_NOTES)]; layout-direction notification among them=$(field loaded SPY_SAW_LAYOUT_NOTIF), TRANSLATION_CHANGED (2010)=$(field loaded SPY_SAW_TRANSLATION_NOTIF)"

# M6 ------------------------------------------------------------------------
[ "$(field loaded MODE2_RTL)" = "false" ] && [ "$(field loaded MODE2_X)" = "0" -o "$(field loaded MODE2_X)" = "0.0" ] && ok=1 || ok=0
claim M6 "LAYOUT_DIRECTION_LTR (2) pins a subtree unmirrored while the rest of the interface flips: the escape hatch for a code view or a phone field" "$ok" \
  "pinned row: x=$(field loaded MODE2_X), is_layout_rtl=$(field loaded MODE2_RTL); mirrored row alongside it: x=$MODE0"

# M7 ------------------------------------------------------------------------
if [ "$(field loaded HAS_SYSTEM_LOCALE)" = "true" ]; then
  [ "$(field loaded MODE4_RTL)" = "false" ] && ok=1 || ok=0
  claim M7 "LAYOUT_DIRECTION_SYSTEM_LOCALE follows the player's OPERATING SYSTEM, not the language they picked in your menu: it stays left-to-right for an Arabic player on an English machine" "$ok" \
    "mode 4 with locale $(field loaded LOCALE): x=$(field loaded MODE4_X), is_layout_rtl=$(field loaded MODE4_RTL); OS locale on this machine is what it reads"
else
  skip M7 "this engine has no LAYOUT_DIRECTION_SYSTEM_LOCALE (added in 4.4): [$(field loaded ENUMS)]"
fi

# M8 ------------------------------------------------------------------------
# The rename is the finding: the integer stayed 1, so a .tscn saved by either
# engine keeps working, and only code that spells the name out breaks.
ENUMS="$(field loaded ENUMS)"
if [ "$(field loaded HAS_APPLICATION_LOCALE)" = "true" ]; then
  printf '%s' "$ENUMS" | grep -q 'LAYOUT_DIRECTION_APPLICATION_LOCALE=1' && \
    printf '%s' "$ENUMS" | grep -q 'LAYOUT_DIRECTION_LOCALE=1' && ok=1 || ok=0
  claim M8 "4.4 renamed LAYOUT_DIRECTION_LOCALE to LAYOUT_DIRECTION_APPLICATION_LOCALE and kept both at the value 1: your scene files survive the upgrade, code that writes the name does not travel backwards" "$ok" \
    "[$ENUMS]"
else
  printf '%s' "$ENUMS" | grep -q 'LAYOUT_DIRECTION_LOCALE=1' && \
    ! printf '%s' "$ENUMS" | grep -q 'APPLICATION_LOCALE' && ok=1 || ok=0
  claim M8 "on this engine the mode is still spelled LAYOUT_DIRECTION_LOCALE; the 4.4 name does not exist here, so a script written against 4.4 fails to PARSE, not to run" "$ok" \
    "[$ENUMS]"
fi

# M9 ------------------------------------------------------------------------
# Same build, same player, a right-to-left locale that no translation covers.
MISS_RTL="$(field missing MODE0_RTL)"
[ "$(field missing IS_RTL_LOCALE)" = "true" ] && [ "$MISS_RTL" = "$EXPECT_MISSING_RTL" ] && ok=1 || ok=0
claim M9 "with a right-to-left locale selected that NO loaded translation covers, 4.2/4.3/4.4 answer is_layout_rtl=false and leave the interface unmirrored, while 4.7 answers true and mirrors it: same build, same player, opposite layouts (expected here: $EXPECT_MISSING_RTL)" "$ok" \
  "locale=$(field missing LOCALE), loaded=[$(field missing LOADED)], is_locale_right_to_left=$(field missing IS_RTL_LOCALE), first child x=$(field missing MODE0_X), is_layout_rtl=$MISS_RTL"

# M10 -----------------------------------------------------------------------
# The consequence, in the artifact: on the engines that mirror it, the player
# reads the untranslated source language inside a mirrored interface.
[ "$(field missing TR)" = "GREET" -o "$(field missing TR)" = "Hello" ] && ok=1 || ok=0
claim M10 "the untranslated locale still gets a layout decision: the text falls back to the source language (or the key) while the interface is laid out for the language that was never translated" "$ok" \
  "tr(GREET)=$(field missing TR) with loaded=[$(field missing LOADED)], label is_layout_rtl=$(field missing LABEL_RTL)"

# M11 -----------------------------------------------------------------------
# A hand-reversed child order plus the engine's own mirror is two mirrors.
HS_A="$(field loaded HANDSWAP_A_X)"; HS_B="$(field loaded HANDSWAP_B_X)"
awk -v a="$HS_A" -v b="$HS_B" 'BEGIN{exit !(a < b)}' && [ "$(field loaded HANDSWAP_RTL)" = "true" ] && ok=1 || ok=0
claim M11 "mirroring you did by hand is applied ON TOP of the engine's: a row whose children were reversed in code comes out in the original visual order again, pinned to the wrong edge" "$ok" \
  "hand-swapped row (B added first): A.x=$HS_A, B.x=$HS_B — A is back to the left of B; is_layout_rtl=$(field loaded HANDSWAP_RTL)"

# M12 -----------------------------------------------------------------------
ICON_X="$(field loaded ICON_X)"
[ "$(field loaded ICON_FLIP_H)" = "false" ] && awk -v a="$ICON_X" 'BEGIN{exit !(a > 0)}' && ok=1 || ok=0
claim M12 "textures are MOVED by the mirror and never flipped: a back arrow or a progress chevron keeps pointing the way it was drawn" "$ok" \
  "icon inside the mirrored row: x=$ICON_X, flip_h=$(field loaded ICON_FLIP_H)"

# M13 -----------------------------------------------------------------------
# The setting is read back as true on every version. Whether it does anything
# is the measurement.
[ "$(field forced FORCE_SETTING)" = "true" ] && [ "$(field forced LOCALE)" = "en" ] && \
  [ "$(field forced WIN_RTL_BEFORE)" = "$EXPECT_FORCED" ] && \
  [ "$(field forced MODE0_RTL)" = "$EXPECT_FORCED" ] && ok=1 || ok=0
claim M13 "force_right_to_left_layout_direction mirrors the build on 4.2 and does NOTHING from 4.3 on, while still reading back as true: the switch that exists to preview a mirrored interface before the translators deliver stopped working and says nothing (expected here: $EXPECT_FORCED)" "$ok" \
  "forced project: setting=$(field forced FORCE_SETTING), locale=$(field forced LOCALE), loaded=[$(field forced LOADED)], root window is_layout_rtl=$(field forced WIN_RTL_BEFORE), first child x=$(field forced MODE0_X), row is_layout_rtl=$(field forced MODE0_RTL)"

# M14 -----------------------------------------------------------------------
# The payoff: the two calls that answer the question, and the fact that reading
# the text property answers a different one.
[ "$(field loaded IS_RTL_LOCALE)" = "true" ] && [ "$(field loaded LABEL_RTL)" = "true" ] && ok=1 || ok=0
claim M14 "the two calls that tell you: is_locale_right_to_left(locale) for what the language wants, is_layout_rtl() for what this node got — reading .text or .position alone answers neither" "$ok" \
  "is_locale_right_to_left=$(field loaded IS_RTL_LOCALE), is_layout_rtl=$(field loaded MODE0_RTL), label text=$(field loaded LABEL_TEXT)"

# ------------------------------------------------------------------- roll-call
say ""
say "SUMMARY $VER: $PASSED passed, $FAILED failed, $SKIPPED skipped"
[ "$FAILED" -gt 0 ] && exit 1
exit 0
