#!/usr/bin/env bash
# Runs every claim in docs/why-the-locale-change-does-not-update-the-ui.md
# against a real Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_locale_change.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds a throwaway project in a temp directory, so nothing here touches
# your own files, and it needs no .csv/.po import pass: the translations are
# built in memory with Translation.add_message().
#
# The engine's own exit code is NOT the gate. Godot exits 0 on a GDScript parse
# error: point this at a 4.2 build, where Node.AUTO_TRANSLATE_MODE_* does not
# exist, and the script fails to compile, runs not one claim and still exits 0.
# So the gate is the summary line — if the script did not reach the end and
# print it, nothing was measured, and that is reported as a skip or an error,
# never as a pass.
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

config/name="LocGuardLocaleChangeCheck"
EOF

cp "$HERE/verify_locale_change.gd" "$PROJ/verify_locale_change.gd"

OUT="$("$GODOT" --headless --path "$PROJ" --script verify_locale_change.gd 2>&1)"
echo "$OUT" | grep -E '^(Godot Engine v|---|PASS |FAIL |NOTE |LOCALE CHANGE)'

SUMMARY="$(printf '%s\n' "$OUT" | grep -c '^LOCALE CHANGE: ')"
if [ "$SUMMARY" -eq 0 ]; then
  if printf '%s\n' "$OUT" | grep -q 'AUTO_TRANSLATE_MODE_'; then
    echo "SKIP: this build has no Node.auto_translate_mode — L8 cannot be expressed, so nothing was measured."
    echo "      auto_translate_mode arrived in Godot 4.3; 4.2 and earlier used a plain auto_translate bool."
    exit 0
  fi
  echo "ERROR: the script did not finish — no claim was measured. Full output:" >&2
  printf '%s\n' "$OUT" >&2
  exit 3
fi

printf '%s\n' "$OUT" | grep -q '^LOCALE CHANGE: ALL PASS' || exit 1
exit 0
