#!/usr/bin/env bash
# Runs every claim in docs/why-the-translation-is-not-loading-for-my-locale.md
# against a real Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_locale_matching.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds a throwaway project in a temp directory, so nothing here touches
# your own files. The project contains a strings.csv whose column headers are
# the four spellings people actually write, and the script runs the SAME binary
# once in editor mode to import it: the claims about what a column header
# becomes are measured through the real importer, not asserted.
#
# The engine's own exit code is NOT the gate. Godot exits 0 on a GDScript parse
# error, and the editor import pass exits 0 whether or not it imported anything.
# So the gate is the summary line — if the script did not reach the end and
# print it, nothing was measured, and that is reported as an error, never as a
# pass.
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

config/name="LocGuardLocaleMatchingCheck"
EOF

# The four spellings, side by side, each with a text that names the column it
# came from. Whatever the importer does to the header is then readable.
cat > "$PROJ/strings.csv" <<'EOF'
keys,en,pt-br,pt-BR,PT_BR
GREETING,from-column-en,from-column-pt-br,from-column-pt-BR,from-column-PT_BR
EOF

cp "$HERE/verify_locale_matching.gd" "$PROJ/verify_locale_matching.gd"

# Import pass. Headless editor, bounded, output kept only for diagnosis.
IMPORT_LOG="$("$GODOT" --headless --path "$PROJ" --editor --quit-after 120 2>&1)"
IMPORTED="$(ls "$PROJ"/*.translation 2>/dev/null | wc -l)"
if [ "$IMPORTED" -eq 0 ]; then
  echo "NOTE: this build produced no .translation from strings.csv, so M20-M23 will report as skipped."
  echo "      (import pass tail: $(printf '%s\n' "$IMPORT_LOG" | tail -1))"
fi

OUT="$("$GODOT" --headless --path "$PROJ" --script verify_locale_matching.gd 2>&1)"
echo "$OUT" | grep -E '^(Godot Engine v|---|BUILD |PASS |FAIL |NOTE |LOCALE MATCHING)'

SUMMARY="$(printf '%s\n' "$OUT" | grep -c '^LOCALE MATCHING: ')"
if [ "$SUMMARY" -eq 0 ]; then
  echo "ERROR: the script did not finish — no claim was measured. Full output:" >&2
  printf '%s\n' "$OUT" >&2
  exit 3
fi

printf '%s\n' "$OUT" | grep -q '^LOCALE MATCHING: ALL PASS' || exit 1
exit 0
