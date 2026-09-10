#!/usr/bin/env bash
# Runs every claim in docs/why-a-key-in-your-csv-still-shows-untranslated.md
# against a real Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_auto_translate.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds a throwaway project in a temp directory, so nothing here touches
# your own files, and it needs no .csv/.po import pass: the translations are
# built in memory with Translation.add_message(), which is the same object the
# importer produces.
#
# The engine's own exit code is NOT the gate. Godot exits 0 on a GDScript parse
# error, so a build that runs not one claim would still look green. The gate is
# the summary line: if the script did not reach the end and print it, nothing
# was measured, and that is reported as an error, never as a pass.
#
# 4.2 is measured too, with its own smaller claim set (6 checks): that build has
# neither auto_translate_mode nor atr(), and the claims say exactly that.
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

config/name="LocGuardAutoTranslateCheck"
EOF

cp "$HERE/verify_auto_translate.gd" "$PROJ/verify_auto_translate.gd"

OUT="$("$GODOT" --headless --path "$PROJ" --script verify_auto_translate.gd 2>&1)"
echo "$OUT" | grep -E '^(Godot Engine v|---|PASS |FAIL |NOTE |AUTO TRANSLATE)'

SUMMARY="$(printf '%s\n' "$OUT" | grep -c '^AUTO TRANSLATE: ')"
if [ "$SUMMARY" -eq 0 ]; then
  echo "ERROR: the script did not finish -- no claim was measured. Full output:" >&2
  printf '%s\n' "$OUT" >&2
  exit 3
fi

printf '%s\n' "$OUT" | grep -q '^AUTO TRANSLATE: ALL PASS' || exit 1
exit 0
