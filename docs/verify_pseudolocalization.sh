#!/usr/bin/env bash
# Runs every claim in docs/why-pseudolocalization-hides-your-missing-translations.md
# against a real Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_pseudolocalization.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds a throwaway project in a temp directory with pseudolocalization
# switched on in project.godot, the way the Project Settings checkbox saves it.
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

config/name="LocGuardPseudolocalizationCheck"

[internationalization]

pseudolocalization/use_pseudolocalization=true
EOF

cp "$HERE/verify_pseudolocalization.gd" "$PROJ/verify_pseudolocalization.gd"

OUT="$("$GODOT" --headless --path "$PROJ" --script verify_pseudolocalization.gd 2>&1)"
echo "$OUT" | grep -E '^(Godot Engine v|PASS |FAIL |PSEUDOLOCALIZATION)'

if ! printf '%s\n' "$OUT" | grep -q '^PSEUDOLOCALIZATION: '; then
  echo "ERROR: the script did not finish — no claim was measured. Full output:" >&2
  printf '%s\n' "$OUT" >&2
  exit 3
fi

printf '%s\n' "$OUT" | grep -q '^PSEUDOLOCALIZATION: ALL PASS' || exit 1
exit 0
