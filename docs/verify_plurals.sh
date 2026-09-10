#!/usr/bin/env bash
# Runs every claim in docs/why-tr_n-always-returns-the-singular.md against a real
# Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_plurals.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds a throwaway project in a temp directory, so nothing here touches your
# own files. That project contains the same two strings three ways — as a CSV
# with a singular row and a plural row, as a .po with msgid_plural, and as a .po
# for a language with three plural forms — because the claim being measured is
# that the same data reaches tr_n() from one of those files and not from the
# other.
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

config/name="LocGuardPluralsCheck"
EOF

# The CSV a project actually ships: the singular and the plural are both there,
# each in its own row, spelled exactly as the tr_n() call spells them.
printf 'keys,en,pt,ru\n'                          >  "$PROJ/strings.csv"
printf 'APPLE,Apple,maca,ru-one\n'                >> "$PROJ/strings.csv"
printf 'APPLES,Apples,macas,ru-many\n'            >> "$PROJ/strings.csv"

# The same two strings as a gettext catalogue, which is the format that carries
# a plural rule. Two forms for Portuguese.
cat > "$PROJ/pt.po" <<'EOF'
msgid ""
msgstr ""
"Language: pt\n"
"Content-Type: text/plain; charset=UTF-8\n"
"Plural-Forms: nplurals=2; plural=(n != 1);\n"

msgid "APPLE"
msgid_plural "APPLES"
msgstr[0] "maca"
msgstr[1] "macas"
EOF

# Three forms for Russian, with the rule the language actually has — the reason
# a count-based if-statement in game code is not a substitute for the header.
cat > "$PROJ/ru.po" <<'EOF'
msgid ""
msgstr ""
"Language: ru\n"
"Content-Type: text/plain; charset=UTF-8\n"
"Plural-Forms: nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);\n"

msgid "APPLE"
msgid_plural "APPLES"
msgstr[0] "ru-one"
msgstr[1] "ru-few"
msgstr[2] "ru-many"
EOF

cp "$HERE/verify_plurals.gd" "$PROJ/verify_plurals.gd"

# Import pass. The .translation files are the artefact every CSV claim is about,
# so their absence means nothing was measured.
"$GODOT" --headless --path "$PROJ" --editor --quit-after 200 > "$PROJ/import_log.txt" 2>&1
for f in strings.pt.translation strings.ru.translation; do
  if [ ! -f "$PROJ/$f" ]; then
    echo "ERROR: the import pass produced no $f — nothing to measure." >&2
    printf '%s\n' "$(tail -5 "$PROJ/import_log.txt")" >&2
    exit 3
  fi
done

out="$("$GODOT" --headless --path "$PROJ" --script verify_plurals.gd -- 2>&1)"
echo "$out" | grep -E '^(---|BUILD |PASS |FAIL |NOTE |PLURALS)'
if [ "$(printf '%s\n' "$out" | grep -c '^PLURALS: ')" -eq 0 ]; then
  echo "ERROR: the measuring pass did not finish — no claim was measured. Full output:" >&2
  printf '%s\n' "$out" >&2
  exit 3
fi
printf '%s\n' "$out" | grep -q '^PLURALS: ALL PASS' || exit 1
exit 0
