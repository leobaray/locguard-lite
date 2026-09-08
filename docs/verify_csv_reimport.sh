#!/usr/bin/env bash
# Runs every claim in docs/why-editing-strings-csv-changes-nothing.md against a
# real Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_csv_reimport.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds throwaway projects in temp directories, so nothing here touches your
# own files. Every import is done by the SAME binary running as a headless
# editor: what a column becomes, and what survives a column being deleted, are
# measured through the real importer, never asserted.
#
# The engine's exit code is NOT the gate. Godot exits 0 on a GDScript parse
# error and the editor import pass exits 0 whether or not it imported anything.
# The gate is the per-phase summary line: a phase that did not print one
# measured nothing, and that is reported as an error, never as a pass.
set -uo pipefail

GODOT="${1:-}"
if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
  echo "usage: $0 /path/to/godot-binary" >&2
  exit 2
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
GD="$HERE/verify_csv_reimport.gd"
[ -f "$GD" ] || { echo "missing $GD" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILED=0
PHASES_SEEN=0

new_project() {  # $1 = dir, $2 = extra project.godot body
  mkdir -p "$1"
  { printf 'config_version=5\n\n[application]\n\nconfig/name="CsvReimportCheck"\n'; printf '%s' "$2"; } > "$1/project.godot"
  cp "$GD" "$1/verify_csv_reimport.gd"
}

import_pass() { "$GODOT" --headless --path "$1" --editor --quit-after 300 >/dev/null 2>&1; }

run_phase() {  # $1 = dir, $2 = phase id
  local out
  out="$("$GODOT" --headless --path "$1" --script verify_csv_reimport.gd -- "$2" 2>&1)"
  printf '%s\n' "$out" | grep -E '^(---|PASS |FAIL |NOTE |CSV REIMPORT)'
  if [ "$(printf '%s\n' "$out" | grep -c '^CSV REIMPORT ')" -eq 0 ]; then
    echo "ERROR: phase $2 did not finish — nothing was measured. Full output:" >&2
    printf '%s\n' "$out" >&2
    FAILED=1
    return
  fi
  PHASES_SEEN=$((PHASES_SEEN + 1))
  printf '%s\n' "$out" | grep -q '^FAIL ' && FAILED=1
  return 0
}

echo "### $("$GODOT" --version)"

# --- phase A: a CSV dropped into a project whose settings were never touched.
A="$WORK/a"
new_project "$A" ""
printf 'keys,en,fr\nGREETING,Hello,Bonjour\n' > "$A/strings.csv"
import_pass "$A"
run_phase "$A" a

# --- phases B*: the same CSV, with both files listed in project settings.
B="$WORK/b"
new_project "$B" '
[internationalization]

locale/translations=PackedStringArray("res://strings.en.translation", "res://strings.fr.translation")
'
printf 'keys,en,fr\nGREETING,Hello,Bonjour\n' > "$B/strings.csv"
import_pass "$B"
run_phase "$B" b1

printf 'keys,en,fr\nGREETING,Hello-v2,Bonjour\n' > "$B/strings.csv"
import_pass "$B"
run_phase "$B" b2

printf 'keys,en\nGREETING,Hello-v2\n' > "$B/strings.csv"   # the fr column is deleted
import_pass "$B"
run_phase "$B" b3

# --- phase C: the clean-clone case (.godot/ and *.translation gitignored).
C="$WORK/c"
new_project "$C" '
[internationalization]

locale/translations=PackedStringArray("res://strings.en.translation", "res://strings.fr.translation")
'
printf 'keys,en,fr\nGREETING,Hello,Bonjour\n' > "$C/strings.csv"
import_pass "$C"
rm -f "$C"/*.translation
rm -rf "$C/.godot"
import_pass "$C"
run_phase "$C" c

# --- the control that says what this script does NOT measure.
# A headless editor is left running while a brand-new CSV appears next to it.
# If a running headless editor imported new files, the same setup could measure
# godotengine/godot#115486 (a running editor ignoring an edited CSV). It does
# not import them, so that case is out of reach here and is reported as unknown
# rather than as a finding.
D="$WORK/d"
new_project "$D" ""
printf 'keys,en\nGREETING,Hello\n' > "$D/strings.csv"
import_pass "$D"
"$GODOT" --headless --path "$D" --editor --quit-after 3000 >/dev/null 2>&1 &
EPID=$!
sleep 6
printf 'keys,en\nGREETING,BrandNew\n' > "$D/later.csv"
sleep 20
kill "$EPID" 2>/dev/null; wait "$EPID" 2>/dev/null
if [ -f "$D/later.en.translation" ]; then
  echo "NOTE  a running headless editor DID import a file that appeared while it ran (unlike the run this doc was written on)."
else
  echo "NOTE  a running headless editor imports nothing that appears while it runs, so the running-editor half of godotengine/godot#115486 cannot be measured this way. Unknown, not disproved."
fi

if [ "$PHASES_SEEN" -ne 5 ]; then
  echo "ERROR: expected 5 phases, only $PHASES_SEEN reported a summary." >&2
  FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
  echo "RESULT: FAILED"
  exit 1
fi
echo "RESULT: all claims hold on this binary"
