#!/usr/bin/env bash
# Runs every claim in docs/why-your-translation-shows-boxes-or-nothing.md
# against a real Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_font_coverage.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds a throwaway project in a temp directory, so nothing here touches
# your own files. The CSV carries a Chinese, Thai, Russian and Hebrew column so
# the translation is real and imported by the engine's own importer: the
# question the script answers is not "is the string translated" but "can what
# came back be drawn".
#
# The engine's exit code is NOT the gate. Godot exits 0 on a GDScript parse
# error and the editor import pass exits 0 whether or not it imported anything.
# The gate is the summary line: if the script did not reach the end and print
# it, nothing was measured, and that is reported as an error, never a pass.
set -uo pipefail

GODOT="${1:-}"
if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
  echo "usage: $0 /path/to/godot-binary" >&2
  exit 2
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(mktemp -d)"
trap 'rm -rf "$PROJ"' EXIT

cat > "$PROJ/project.godot" <<'EOF'
config_version=5

[application]

config/name="LocGuardFontCoverageCheck"

[internationalization]

locale/translations=PackedStringArray("res://strings.en.translation", "res://strings.zh.translation", "res://strings.th.translation", "res://strings.ru.translation", "res://strings.he.translation")
EOF

cat > "$PROJ/strings.csv" <<'EOF'
keys,en,zh,th,ru,he
PLAY,Play,开始游戏,เริ่มเกม,Играть,שחק
EOF

cp "$HERE/verify_font_coverage.gd" "$PROJ/verify_font_coverage.gd"

IMPORT_LOG="$("$GODOT" --headless --path "$PROJ" --editor --quit-after 120 2>&1)"
IMPORTED="$(ls "$PROJ"/*.translation 2>/dev/null | wc -l)"
if [ "$IMPORTED" -ne 5 ]; then
  echo "ERROR: this build produced $IMPORTED .translation files from strings.csv instead of 5, so nothing below would mean anything." >&2
  printf '%s\n' "$IMPORT_LOG" | tail -3 >&2
  exit 4
fi

OUT="$("$GODOT" --headless --path "$PROJ" --script verify_font_coverage.gd 2>&1)"
echo "$OUT" | grep -E '^(Godot Engine v|---|BUILD |PASS |FAIL |NOTE |SKIP |passes=|FONT COVERAGE)'

SUMMARY="$(printf '%s\n' "$OUT" | grep -c '^FONT COVERAGE: ')"
if [ "$SUMMARY" -eq 0 ]; then
  echo "ERROR: the script did not finish — no claim was measured. Full output:" >&2
  printf '%s\n' "$OUT" >&2
  exit 3
fi

# One claim of the page is that a glyph the font cannot draw produces no
# diagnostic at all. That one cannot be asserted from inside the script, so it
# is asserted here, over the engine's own stderr for the whole run.
NOISE="$(printf '%s\n' "$OUT" | grep -E '^(ERROR|WARNING|SCRIPT ERROR|USER ERROR):' || true)"
if [ -n "$NOISE" ]; then
  echo "ERROR: the engine reported something during the run, so the page's 'no diagnostic' claim does not hold on this build:" >&2
  printf '%s\n' "$NOISE" >&2
  exit 5
fi

printf '%s\n' "$OUT" | grep -q '^FONT COVERAGE: ALL PASS' || exit 1
exit 0
