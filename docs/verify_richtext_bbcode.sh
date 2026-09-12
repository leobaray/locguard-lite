#!/usr/bin/env bash
# Runs every claim in
# docs/why-your-richtextlabel-shows-the-key-instead-of-the-translation.md
# against a real Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_richtext_bbcode.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds a throwaway project in a temp directory, so nothing here touches
# your own files. The German column carries markup the way a translator hands
# it back -- correct in one row, closed with the wrong tag in another, opened
# and closed backwards in a third -- so the strings under test are the ones the
# engine's own CSV importer produced, not literals typed into the script.
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

config/name="LocGuardRichTextCheck"

[internationalization]

locale/translations=PackedStringArray("res://strings.en.translation", "res://strings.de.translation")
EOF

cat > "$PROJ/strings.csv" <<'EOF'
keys,en,de
GREET,Hello,Hallo
QUEST,Find the [b]key[/b].,Finde den [b]Schluessel[/b].
BROKEN,Find the [b]key[/b].,Finde den [b]Schluessel[/i].
SWAPPED,[b]Bold[/b],[/b]Fett[b]
EOF

cp "$HERE/verify_richtext_bbcode.gd" "$PROJ/verify_richtext_bbcode.gd"

IMPORT_LOG="$("$GODOT" --headless --path "$PROJ" --editor --quit-after 200 2>&1)"
IMPORTED="$(ls "$PROJ"/*.translation 2>/dev/null | wc -l)"
if [ "$IMPORTED" -ne 2 ]; then
  echo "ERROR: this build produced $IMPORTED .translation files from strings.csv instead of 2, so nothing below would mean anything." >&2
  printf '%s\n' "$IMPORT_LOG" | tail -3 >&2
  exit 4
fi

# Claim R0 of the page: importing a table whose markup is broken in two of four
# rows is completely quiet. Asserted over the editor pass's own output, because
# it cannot be asserted from inside the game.
IMPORT_NOISE="$(printf '%s\n' "$IMPORT_LOG" | grep -iE 'bbcode|unclosed|tag' || true)"
if [ -n "$IMPORT_NOISE" ]; then
  echo "ERROR: the importer said something about the markup on this build, so the page's 'nothing is checked at import time' claim does not hold:" >&2
  printf '%s\n' "$IMPORT_NOISE" >&2
  exit 5
fi
echo "PASS  R0  the editor imported all 4 rows into 2 locales without one word about the two broken tag pairs"

OUT="$("$GODOT" --headless --path "$PROJ" --script verify_richtext_bbcode.gd 2>&1)"
echo "$OUT" | grep -E '^(Godot Engine v|---|BUILD |PASS |FAIL |NOTE |SKIP |RICHTEXT BBCODE)'

SUMMARY="$(printf '%s\n' "$OUT" | grep -c '^RICHTEXT BBCODE: ')"
if [ "$SUMMARY" -eq 0 ]; then
  echo "ERROR: the script did not finish — no claim was measured. Full output:" >&2
  printf '%s\n' "$OUT" >&2
  exit 3
fi

printf '%s\n' "$OUT" | grep -q '^RICHTEXT BBCODE: ALL PASS' || exit 1
exit 0
