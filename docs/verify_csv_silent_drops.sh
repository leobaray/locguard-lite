#!/usr/bin/env bash
# Runs every claim in docs/why-a-row-in-strings-csv-never-reaches-the-player.md
# against a real Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_csv_silent_drops.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds a throwaway project in a temp directory, so nothing here touches
# your own files. The CSV in it is written the way people actually write one by
# hand: a blank cell, a key typed twice, a key with stray spaces, a quoted
# comma, and a backslash-n on both sides of the comma.
#
# The claims about storage need the SAME csv imported with different importer
# options, so the script runs three import passes and one measuring pass each:
#
#   phase a  the default import (compress on) — what ships
#   phase b  compress=false     — the only spelling that reads the keys back
#   phase c  compress=0         — the same option as a person hand-edits it
#
# The engine's own exit code is NOT the gate. Godot exits 0 on a GDScript parse
# error, and the editor import pass exits 0 whether or not it imported
# anything. So the gate is the summary line — if a phase did not reach the end
# and print it, nothing was measured, and that is reported as an error, never
# as a pass.
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

config/name="LocGuardCsvSilentDropsCheck"
EOF

# Eight data rows, seven distinct keys. Every row is a shape that appears in
# real hand-maintained files; none of them is invalid CSV.
printf 'keys,en,pt\n'                              >  "$PROJ/strings.csv"
printf 'GREETING,Hello,Ola\n'                      >> "$PROJ/strings.csv"
printf 'EMPTY_CELL,,Vazio\n'                       >> "$PROJ/strings.csv"
printf 'DUP,first-en,first-pt\n'                   >> "$PROJ/strings.csv"
printf 'DUP,second-en,second-pt\n'                 >> "$PROJ/strings.csv"
printf ' SPACED ,spaced-en,spaced-pt\n'            >> "$PROJ/strings.csv"
printf 'QUOTED,"with, comma",virgula\n'            >> "$PROJ/strings.csv"
printf 'LINE\\nBREAK,two-line-en,two-line-pt\n'    >> "$PROJ/strings.csv"
printf 'ESCAPED,first\\nsecond,pri\\nseg\n'        >> "$PROJ/strings.csv"

cp "$HERE/verify_csv_silent_drops.gd" "$PROJ/verify_csv_silent_drops.gd"

FAILED=0

import_pass() {  # $1 = label; imports whatever is on disk now
  "$GODOT" --headless --path "$PROJ" --editor --quit-after 120 > "$PROJ/import_log.txt" 2>&1
  if [ ! -f "$PROJ/strings.en.translation" ]; then
    echo "ERROR: import pass '$1' produced no .translation — nothing to measure." >&2
    printf '%s\n' "$(tail -3 "$PROJ/import_log.txt")" >&2
    exit 3
  fi
}

run_phase() {  # $1 = phase letter
  local out
  out="$("$GODOT" --headless --path "$PROJ" --script verify_csv_silent_drops.gd -- "$1" 2>&1)"
  echo "$out" | grep -E '^(---|PASS |FAIL |NOTE |CSV SILENT DROPS)'
  if [ "$(printf '%s\n' "$out" | grep -c '^CSV SILENT DROPS: ')" -eq 0 ]; then
    echo "ERROR: phase $1 did not finish — no claim was measured. Full output:" >&2
    printf '%s\n' "$out" >&2
    exit 3
  fi
  printf '%s\n' "$out" | grep -q '^CSV SILENT DROPS: ALL PASS' || FAILED=1
}

write_import() {  # $1 = the compress value to put on disk
  cat > "$PROJ/strings.csv.import" <<EOF
[remap]

importer="csv_translation"
type="Translation"

[deps]

files=["res://strings.en.translation", "res://strings.pt.translation"]

source_file="res://strings.csv"
dest_files=["res://strings.en.translation", "res://strings.pt.translation"]

[params]

compress=$1
delimiter=0
unescape_keys=false
unescape_translations=true
EOF
}

# phase a — whatever the editor writes on its own, with no .import file present.
import_pass "default"
run_phase a

# phase b — compress=false, from a clean slate so the option is really applied.
rm -f "$PROJ/strings.en.translation" "$PROJ/strings.pt.translation"
rm -rf "$PROJ/.godot"
write_import "false"
import_pass "compress=false"
run_phase b

# phase c — the same option written as 0, which is what hand-editing produces.
rm -f "$PROJ/strings.en.translation" "$PROJ/strings.pt.translation"
rm -rf "$PROJ/.godot"
write_import "0"
import_pass "compress=0"
run_phase c

exit "$FAILED"
