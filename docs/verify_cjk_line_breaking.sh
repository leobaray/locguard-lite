#!/usr/bin/env bash
# Runs every claim in docs/why-your-chinese-japanese-or-thai-text-does-not-wrap.md
# against a real Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_cjk_line_breaking.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds throwaway projects in a temp directory: one for the in-engine claims
# (verify_cjk_line_breaking.gd), and two exported with --export-pack for E1/E2.
# --export-pack writes the data pack only, so no export template is needed.
#
# The gate is the summary line, not Godot's exit code: a GDScript parse error
# still exits 0 and measures nothing.
set -uo pipefail

GODOT="${1:-}"
if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
  echo "usage: $0 /path/to/godot-binary" >&2
  exit 2
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0

mkdir -p "$WORK/engine"
cat > "$WORK/engine/project.godot" <<'EOF'
config_version=5

[application]

config/name="LocGuardCjkLineBreakingCheck"
EOF
cp "$HERE/verify_cjk_line_breaking.gd" "$WORK/engine/verify_cjk_line_breaking.gd"

OUT="$("$GODOT" --headless --path "$WORK/engine" --script verify_cjk_line_breaking.gd 2>&1)"
echo "$OUT" | grep -E '^(Godot Engine v|PASS |FAIL )'
if ! printf '%s\n' "$OUT" | grep -q '^CJK LINE BREAKING: '; then
  echo "ERROR: the script did not finish — no claim was measured. Full output:" >&2
  printf '%s\n' "$OUT" >&2
  exit 3
fi
printf '%s\n' "$OUT" | grep -q '^CJK LINE BREAKING: ALL PASS' || fails=$((fails + 1))

# The preset's platform string: 4.2 calls it "Linux/X11", 4.3+ "Linux". A preset
# whose platform the binary does not know is silently no preset at all.
case "$("$GODOT" --version 2>/dev/null)" in
  4.2*) PLATFORM="Linux/X11" ;;
  *)    PLATFORM="Linux" ;;
esac

# export_pck <include_text_server_data> -> prints the pack size; pack in $WORK/<flag>
export_pck() {
  local d="$WORK/$1"
  mkdir -p "$d"
  cat > "$d/project.godot" <<EOF
config_version=5

[application]

config/name="LocGuardCjkExport"
run/main_scene="res://main.tscn"

[internationalization]

locale/include_text_server_data=$1
EOF
  printf '[gd_scene format=3]\n\n[node name="Main" type="Node"]\n' > "$d/main.tscn"
  cat > "$d/export_presets.cfg" <<EOF
[preset.0]

name="Linux"
platform="$PLATFORM"
runnable=true
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="game.pck"
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false

[preset.0.options]

EOF
  "$GODOT" --headless --path "$d" --editor --quit-after 200 > "$d/import.log" 2>&1
  "$GODOT" --headless --path "$d" --export-pack Linux "$d/game.pck" > "$d/export.log" 2>&1
  if [ ! -f "$d/game.pck" ]; then
    echo "ERROR: no game.pck came out of $d — E1/E2 are not measurable." >&2
    tail -8 "$d/export.log" >&2
    exit 3
  fi
  stat -c%s "$d/game.pck"
}

claim() { # claim <id> <ok 0|1> <text>
  if [ "$2" = 1 ]; then echo "PASS $1 — $3"; else echo "FAIL $1 — $3"; fails=$((fails + 1)); fi
}

size_off="$(export_pck false)"
size_on="$(export_pck true)"
dat_off="$(grep -a -o 'icudt[a-z0-9_]*\.dat' "$WORK/false/game.pck" | sort -u | tr '\n' ' ')"
dat_on="$(grep -a -o 'icudt[a-z0-9_]*\.dat' "$WORK/true/game.pck" | sort -u | tr '\n' ' ')"

ok=0; [ -z "$dat_off" ] && ok=1
claim E1 "$ok" "a default export (include_text_server_data=false) packs no icudt*.dat: pack is $size_off bytes"
ok=0; [ -n "$dat_on" ] && [ $((size_on - size_off)) -gt 4000000 ] && ok=1
claim E2 "$ok" "include_text_server_data=true packs ${dat_on}and adds $((size_on - size_off)) bytes"

if [ "$fails" -eq 0 ]; then echo "CJK LINE BREAKING SUITE: ALL PASS"; exit 0; fi
echo "CJK LINE BREAKING SUITE: $fails FAIL"
exit 1
