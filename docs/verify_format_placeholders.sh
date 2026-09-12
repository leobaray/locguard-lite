#!/usr/bin/env bash
# Runs every claim in docs/why-your-translated-line-comes-out-empty.md against a
# real Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_format_placeholders.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds a throwaway project in a temp directory, so nothing here touches
# your own files. The CSV carries a German and a French column damaged the way
# translators damage them — a swapped placeholder order, a dropped doubled
# per-cent, a %d turned into %s, a literal per-cent in prose — so the strings
# under test are the ones the engine's own importer produced, not literals.
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

config/name="LocGuardFormatPlaceholderCheck"

[internationalization]

locale/translations=PackedStringArray("res://strings.en.translation", "res://strings.de.translation", "res://strings.fr.translation")
EOF

cat > "$PROJ/strings.csv" <<'EOF'
keys,en,de,fr
SCORE_MSG,%s scored %d points,%s hat %d Punkte erzielt,%d points marques par %s
PCT_MSG,%d%% complete,%d%% abgeschlossen,%d% termine
COUNT_MSG,%d items,%s Gegenstaende,%d objets
PLAIN_MSG,All good,100% sicher,tout va bien
NAMED_MSG,{who} scored {pts},{who} erzielte {pts},{pts} points pour {who}
EOF

cp "$HERE/verify_format_placeholders.gd" "$PROJ/verify_format_placeholders.gd"

IMPORT_LOG="$("$GODOT" --headless --path "$PROJ" --editor --quit-after 200 2>&1)"
IMPORTED="$(ls "$PROJ"/*.translation 2>/dev/null | wc -l)"
if [ "$IMPORTED" -ne 3 ]; then
  echo "ERROR: this build produced $IMPORTED .translation files from strings.csv instead of 3, so nothing below would mean anything." >&2
  printf '%s\n' "$IMPORT_LOG" | tail -3 >&2
  exit 4
fi

# Claim F0 of the page: the import of a table whose translations disagree with
# the source about placeholders is completely quiet. Asserted over the editor
# pass's own output, because it cannot be asserted from inside the game.
IMPORT_NOISE="$(printf '%s\n' "$IMPORT_LOG" | grep -iE 'placeholder|format string|per.?cent' || true)"
if [ -n "$IMPORT_NOISE" ]; then
  echo "ERROR: the importer said something about placeholders on this build, so the page's 'nothing is checked at import time' claim does not hold:" >&2
  printf '%s\n' "$IMPORT_NOISE" >&2
  exit 5
fi
echo "PASS  F0  the editor imported all 5 rows into 3 locales without one word about the placeholder mismatch"

OUT="$("$GODOT" --headless --path "$PROJ" --script verify_format_placeholders.gd 2>&1)"
echo "$OUT" | grep -E '^(Godot Engine v|---|BUILD |PASS |FAIL |NOTE |SKIP |FORMAT PLACEHOLDERS)'

SUMMARY="$(printf '%s\n' "$OUT" | grep -c '^FORMAT PLACEHOLDERS: ')"
if [ "$SUMMARY" -eq 0 ]; then
  echo "ERROR: the script did not finish — no claim was measured. Full output:" >&2
  printf '%s\n' "$OUT" >&2
  exit 3
fi

# Claim F18: the engine does report every failure in the Output — but it words
# the SAME defect two different ways depending on the call site, and one of the
# two wordings changed between 4.3 and 4.4. A log filter written for one of the
# three strings is blind to the others. Measured over the run above.
MINOR="$(printf '%s\n' "$OUT" | sed -n 's/^BUILD 4\.\([0-9]*\).*/\1/p' | head -1)"
if [ -z "$MINOR" ]; then
  echo "ERROR: could not read the engine version back from the run." >&2
  exit 6
fi
DYN="$(printf '%s\n' "$OUT" | grep -c "SCRIPT ERROR: unsupported format character in operator")"
VAL_OLD="$(printf '%s\n' "$OUT" | grep -c "^ERROR: unsupported format character")"
VAL_NEW="$(printf '%s\n' "$OUT" | grep -c "^ERROR: String formatting error: unsupported format character")"
if [ "$DYN" -eq 0 ]; then
  echo "ERROR: no untyped-call-site failure was reported on this build; the page claims one line per failure." >&2
  exit 6
fi
echo "PASS  F18  an untyped call site is reported as \"SCRIPT ERROR: unsupported format character in operator '%'\" ($DYN times on this run)"
if [ "$MINOR" -le 3 ]; then
  if [ "$VAL_OLD" -eq 0 ] || [ "$VAL_NEW" -ne 0 ]; then
    echo "FAIL  F20  on this 4.$MINOR build the typed call site was expected to say 'ERROR: unsupported format character' (got $VAL_OLD) and not the 4.4 wording (got $VAL_NEW)" >&2
    exit 6
  fi
  echo "PASS  F20  the same defect on a typed call site is worded differently — \"ERROR: unsupported format character\" ($VAL_OLD times), with no 'String formatting error' prefix anywhere; a filter written against 4.4 output sees nothing here"
else
  if [ "$VAL_NEW" -eq 0 ] || [ "$VAL_OLD" -ne 0 ]; then
    echo "FAIL  F20  on this 4.$MINOR build the typed call site was expected to say 'ERROR: String formatting error: ...' (got $VAL_NEW) and not the 4.3 wording (got $VAL_OLD)" >&2
    exit 6
  fi
  echo "PASS  F20  the same defect on a typed call site is worded differently — \"ERROR: String formatting error: unsupported format character.\" ($VAL_NEW times); that prefix does not exist before 4.4, so a filter written against 4.3 output sees nothing here"
fi

# Claim F6 of the page says the untyped failure stops the function that assigns
# it. That cannot be asserted from inside a script that has to keep running, so
# it gets its own throwaway run: the marker after the assignment must NOT print.
cat > "$PROJ/abort_demo.gd" <<'EOF'
extends SceneTree
func dyn(s, v):
	return s % v
func _initialize() -> void:
	var lbl := Label.new()
	lbl.text = "TITLE BEFORE"
	print("MARKER_BEFORE")
	lbl.text = dyn("100% sure", [])
	print("MARKER_AFTER")
	lbl.free()
	quit()
EOF
ABORT="$(timeout 60 "$GODOT" --headless --path "$PROJ" --script abort_demo.gd 2>&1)"
BEFORE="$(printf '%s\n' "$ABORT" | grep -c '^MARKER_BEFORE')"
AFTER="$(printf '%s\n' "$ABORT" | grep -c '^MARKER_AFTER')"
if [ "$BEFORE" -eq 0 ]; then
  echo "ERROR: the abort demo never started, so its claim was not measured." >&2
  exit 7
fi
if [ "$AFTER" -ne 0 ]; then
  echo "FAIL  F19  assigning a failed format to label.text did NOT stop the function on this build — the line after it ran" >&2
  exit 1
fi
echo "PASS  F19  assigning the failed format to label.text stopped the function: the statement after it never ran, so every node configured later in that _ready() is left untouched"

printf '%s\n' "$OUT" | grep -q '^FORMAT PLACEHOLDERS: ALL PASS' || exit 1
exit 0
