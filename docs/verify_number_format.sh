#!/usr/bin/env bash
# Runs every claim in docs/why-your-numbers-ignore-the-players-language.md
# against a real Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_number_format.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds an empty throwaway project in a temp directory. Nothing is rendered:
# the claims are about the strings the engine hands to a Label, not the glyphs.
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
PROJ="$(mktemp -d)"
trap 'rm -rf "$PROJ"' EXIT

cat > "$PROJ/project.godot" <<'EOF'
config_version=5

[application]

config/name="LocGuardNumberFormatCheck"
EOF

cp "$HERE/verify_number_format.gd" "$PROJ/verify_number_format.gd"

OUT="$("$GODOT" --headless --path "$PROJ" --script verify_number_format.gd 2>&1)"
echo "$OUT" | grep -E '^(Godot Engine v|PASS |FAIL |NUMBER FORMAT)'

if ! printf '%s\n' "$OUT" | grep -q '^NUMBER FORMAT: '; then
  echo "ERROR: the script did not finish — no claim was measured. Full output:" >&2
  printf '%s\n' "$OUT" >&2
  exit 3
fi

printf '%s\n' "$OUT" | grep -q '^NUMBER FORMAT: ALL PASS' || exit 1
exit 0
