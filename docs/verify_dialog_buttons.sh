#!/usr/bin/env bash
# Runs every claim in docs/why-the-ok-button-stays-in-english.md against a real
# Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_dialog_buttons.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds a throwaway project in a temp directory, so nothing here touches
# your own files. The CSV carries the english literals the engine puts on its
# own dialog buttons, so the question the script answers is not "is there a
# translation" but "does the button use the one that is already there".
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

config/name="LocGuardDialogButtonCheck"

[internationalization]

locale/translations=PackedStringArray("res://strings.pt_BR.translation")
EOF

# The keys are the engine's own english literals. "Save" and "OK" are both
# here on purpose: the FileDialog accept button uses a different one depending
# on the build, and the script measures which.
cat > "$PROJ/strings.csv" <<'EOF'
keys,en,pt_BR
OK,OK,Certo
Cancel,Cancel,Cancelar
Save,Save,Salvar
Alert!,Alert!,Alerta!
EOF

cp "$HERE/verify_dialog_buttons.gd" "$PROJ/verify_dialog_buttons.gd"

IMPORT_LOG="$("$GODOT" --headless --path "$PROJ" --editor --quit-after 120 2>&1)"
IMPORTED="$(ls "$PROJ"/*.translation 2>/dev/null | wc -l)"
if [ "$IMPORTED" -eq 0 ]; then
  echo "ERROR: this build produced no .translation from strings.csv, so nothing below would mean anything." >&2
  printf '%s\n' "$IMPORT_LOG" | tail -3 >&2
  exit 4
fi

OUT="$("$GODOT" --headless --path "$PROJ" --script verify_dialog_buttons.gd 2>&1)"
echo "$OUT" | grep -E '^(Godot Engine v|---|BUILD |PASS |FAIL |NOTE |passes=|DIALOG BUTTONS)'

SUMMARY="$(printf '%s\n' "$OUT" | grep -c '^DIALOG BUTTONS: ')"
if [ "$SUMMARY" -eq 0 ]; then
  echo "ERROR: the script did not finish — no claim was measured. Full output:" >&2
  printf '%s\n' "$OUT" >&2
  exit 3
fi

printf '%s\n' "$OUT" | grep -q '^DIALOG BUTTONS: ALL PASS' || exit 1
exit 0
