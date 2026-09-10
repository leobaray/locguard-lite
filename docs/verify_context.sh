#!/usr/bin/env bash
# Runs every claim in docs/why-the-context-you-pass-to-tr-changes-nothing.md
# against a real Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_context.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds a throwaway project in a temp directory, so nothing here touches your
# own files. That project carries the same key three ways — as a CSV row with no
# context, as a .po with three msgctxt variants of one msgid, and as a CSV whose
# author tried to put the context in a column — because the claim being measured
# is that the second argument of tr() means three different things depending on
# which of those files answered.
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

config/name="LocGuardContextCheck"
EOF

# The CSV a project actually ships. There is no column for a context here,
# because the CSV importer has nowhere to put one.
printf 'keys,en,pt\n'            >  "$PROJ/strings.csv"
printf 'OPEN,Open,Abrir\n'       >> "$PROJ/strings.csv"
printf 'CLOSE,Close,Fechar\n'    >> "$PROJ/strings.csv"

# The same key as a gettext catalogue, which is the format that carries msgctxt.
# One msgid, three entries: the bare one and two contexts.
cat > "$PROJ/pt.po" <<'EOF'
msgid ""
msgstr ""
"Language: pt\n"
"Content-Type: text/plain; charset=UTF-8\n"

msgid "OPEN"
msgstr "Abrir"

msgctxt "Menu"
msgid "OPEN"
msgstr "Abrir-menu"

msgctxt "Door"
msgid "OPEN"
msgstr "Destrancar"
EOF

# The CSV written by someone who read that tr() takes a context and reached for
# the only place a CSV has to put anything: another column.
printf 'keys,context,en,pt\n'           >  "$PROJ/ctxcol.csv"
printf 'OPEN,Menu,Open,Abrir-menu\n'    >> "$PROJ/ctxcol.csv"

cp "$HERE/verify_context.gd" "$PROJ/verify_context.gd"

# Import pass. The .translation files are the artefact every CSV claim is about,
# so their absence means nothing was measured.
"$GODOT" --headless --path "$PROJ" --editor --quit-after 200 > "$PROJ/import_log.txt" 2>&1
for f in strings.pt.translation ctxcol.context.translation; do
  if [ ! -f "$PROJ/$f" ]; then
    echo "ERROR: the import pass produced no $f — nothing to measure." >&2
    printf '%s\n' "$(tail -5 "$PROJ/import_log.txt")" >&2
    exit 3
  fi
done

out="$("$GODOT" --headless --path "$PROJ" --script verify_context.gd -- 2>&1)"
echo "$out" | grep -E '^(---|BUILD |PASS |FAIL |NOTE |CONTEXT)'
if [ "$(printf '%s\n' "$out" | grep -c '^CONTEXT: ')" -eq 0 ]; then
  echo "ERROR: the measuring pass did not finish — no claim was measured. Full output:" >&2
  printf '%s\n' "$out" >&2
  exit 3
fi
printf '%s\n' "$out" | grep -q '^CONTEXT: ALL PASS' || exit 1
exit 0
