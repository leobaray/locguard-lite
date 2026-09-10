#!/usr/bin/env bash
# Runs every claim in docs/why-the-csv-your-spreadsheet-saved-translates-nothing.md
# against a real Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_spreadsheet_csv.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds a throwaway project in a temp directory, so nothing here touches your
# own files. That project carries the SAME two-language table nine times, saved
# the nine ways a spreadsheet offers to save it: UTF-8, UTF-8 with a byte order
# mark, CRLF line endings, semicolon delimiter, UTF-16 "Unicode text", ANSI /
# Latin-1, a header cell with a stray space, a trailing comma on the header row,
# and a hyphenated locale name. The claim being measured is that some of those
# are refused, some are accepted unchanged, and one is accepted and quietly
# rewrites the text — and that the console tells you apart from the last group
# only while you are looking at the editor.
#
# The engine's own exit code is NOT the gate. Godot exits 0 on a GDScript parse
# error, and the editor import pass exits 0 whether or not it imported anything.
# So the gate is the summary line — if the measuring pass did not reach the end
# and print it, nothing was measured, and that is reported as an error, never as
# a pass.
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

config/name="LocGuardSpreadsheetCheck"
EOF

# The reference. One accented word and one accented word followed by a space,
# because those are the two shapes that come apart differently further down.
printf 'keys,en,pt\n'                 >  "$PROJ/plain.csv"
printf 'HELLO,Hello,Olá\n'            >> "$PROJ/plain.csv"
printf 'BYE,Bye,Até mais\n'           >> "$PROJ/plain.csv"

# "CSV UTF-8 (comma delimited)" in Excel: the same bytes with a byte order mark
# in front of the first header cell.
printf '\xEF\xBB\xBF'                 >  "$PROJ/bom.csv"
cat "$PROJ/plain.csv"                 >> "$PROJ/bom.csv"

# Saved on Windows, or by a tool that writes DOS line endings.
sed 's/$/\r/' "$PROJ/plain.csv"       >  "$PROJ/crlf.csv"

# "CSV" in a spreadsheet running under a locale whose list separator is a
# semicolon — most of continental Europe and Brazil.
printf 'keys;en;pt\n'                 >  "$PROJ/semi.csv"
printf 'HELLO;Hello;Olá\n'            >> "$PROJ/semi.csv"
printf 'BYE;Bye;Até mais\n'           >> "$PROJ/semi.csv"

# "Unicode Text (*.txt)" renamed to .csv — UTF-16 little endian with a BOM.
printf '\xFF\xFE'                     >  "$PROJ/utf16.csv"
iconv -f UTF-8 -t UTF-16LE < "$PROJ/plain.csv" >> "$PROJ/utf16.csv"

# "CSV (Comma delimited)" — the plain one, which on Windows is ANSI, not UTF-8.
iconv -f UTF-8 -t ISO-8859-1 < "$PROJ/plain.csv" > "$PROJ/latin1.csv"

# A header row a human typed, with one space after a comma.
printf 'keys,en, pt\n'                >  "$PROJ/space.csv"
printf 'HELLO,Hello,Olá\n'            >> "$PROJ/space.csv"

# A header row with a trailing comma — a spreadsheet that kept an empty column.
printf 'keys,en,pt,\n'                >  "$PROJ/trail.csv"
printf 'HELLO,Hello,Olá,\n'           >> "$PROJ/trail.csv"

# A locale written the way the web writes it, with a hyphen.
printf 'keys,en,pt-BR\n'              >  "$PROJ/dash.csv"
printf 'HELLO,Hello,Olá\n'            >> "$PROJ/dash.csv"

cp "$HERE/verify_spreadsheet_csv.gd" "$PROJ/verify_spreadsheet_csv.gd"

# Import pass. The .translation files are the artefact every claim is about, and
# the baseline's absence means nothing was measured. The absence of the others
# is itself a measurement, so only the baseline is gated here.
"$GODOT" --headless --path "$PROJ" --editor --quit-after 300 > "$PROJ/import_log.txt" 2>&1
for f in plain.pt.translation plain.en.translation; do
  if [ ! -f "$PROJ/$f" ]; then
    echo "ERROR: the import pass produced no $f — nothing to measure." >&2
    printf '%s\n' "$(tail -5 "$PROJ/import_log.txt")" >&2
    exit 3
  fi
done

out="$("$GODOT" --headless --path "$PROJ" --script verify_spreadsheet_csv.gd -- 2>&1)"
echo "$out" | grep -E '^(---|BUILD |PASS |FAIL |NOTE |SPREADSHEET)'
if [ "$(printf '%s\n' "$out" | grep -c '^SPREADSHEET: ')" -eq 0 ]; then
  echo "ERROR: the measuring pass did not finish — no claim was measured. Full output:" >&2
  printf '%s\n' "$out" >&2
  exit 3
fi
printf '%s\n' "$out" | grep -q '^SPREADSHEET: ALL PASS' || exit 1
exit 0
