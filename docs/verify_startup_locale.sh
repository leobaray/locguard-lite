#!/usr/bin/env bash
# Runs every claim in docs/why-your-game-starts-in-the-wrong-language.md against a
# real Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_startup_locale.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds a throwaway project in a temp directory, so nothing here touches your
# own files. The project ships three languages (en, pt, de) and no country
# variants, because the question on the page is what happens on a machine whose
# locale is not one of the three strings you shipped.
#
# A machine locale is chosen once, at process start, from the environment. So
# this cannot be one run: the script launches the binary once per scenario, with
# a different environment, command line or project.godot each time, and tells the
# GDScript which scenario it is through LGCASE.
#
# The engine's exit code is NOT the gate. Godot exits 0 on a GDScript parse error
# and the editor import pass exits 0 whether or not it imported anything. The gate
# is the per-case CASEEND line plus a roll-call of every claim id: a case that did
# not reach its end measured nothing, and that is reported as an error, never as a
# pass.
set -uo pipefail

GODOT="${1:-}"
if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
  echo "usage: $0 /path/to/godot-binary" >&2
  exit 2
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(mktemp -d)"
trap 'rm -rf "$PROJ"' EXIT

BASE_PROJECT='config_version=5

[application]

config/name="LocGuardStartupLocaleCheck"

[internationalization]

locale/translations=PackedStringArray("res://strings.en.translation", "res://strings.pt.translation", "res://strings.de.translation")
'
printf '%s' "$BASE_PROJECT" > "$PROJ/project.godot"

# Three languages, no country variants anywhere. The machine will ask for
# pt_BR, de_AT and ja_JP; none of those three strings is in this file.
printf 'keys,en,pt,de\n'          >  "$PROJ/strings.csv"
printf 'GREET,Hello,Ola,Hallo\n'  >> "$PROJ/strings.csv"

cp "$HERE/verify_startup_locale.gd" "$PROJ/verify_startup_locale.gd"

# Import pass, run by the binary under test. The .translation files are the
# artefact every claim is about, and their format is not shared between
# versions: importing with one binary and measuring with another measures the
# other binary's failure to read a foreign file, which is a different question.
"$GODOT" --headless --path "$PROJ" --editor --quit-after 200 > "$PROJ/import_log.txt" 2>&1
for f in strings.en.translation strings.pt.translation strings.de.translation; do
  if [ ! -f "$PROJ/$f" ]; then
    echo "ERROR: the import pass produced no $f — nothing to measure." >&2
    tail -5 "$PROJ/import_log.txt" >&2
    exit 3
  fi
done

ALL_OUT="$PROJ/all_out.txt"
: > "$ALL_OUT"
CASES_RUN=0

# run_case <case> <project.godot extra line, or -> <env assignments...> -- <extra godot args...>
run_case() {
  local case_name="$1"; shift
  local extra_setting="$1"; shift
  local -a envs=() args=()
  local seen_dashes=0
  for a in "$@"; do
    if [ "$a" = "--" ]; then seen_dashes=1; continue; fi
    if [ "$seen_dashes" = 1 ]; then args+=("$a"); else envs+=("$a"); fi
  done

  printf '%s' "$BASE_PROJECT" > "$PROJ/project.godot"
  if [ "$extra_setting" != "-" ]; then
    printf '%s\n' "$extra_setting" >> "$PROJ/project.godot"
  fi

  local out
  out="$(env -u LANG -u LC_ALL -u LANGUAGE -u LC_MESSAGES LGCASE="$case_name" "${envs[@]}" \
        "$GODOT" --headless --path "$PROJ" "${args[@]}" --script verify_startup_locale.gd 2>&1)"
  printf '%s\n' "$out" >> "$ALL_OUT"
  printf '%s\n' "$out" | grep -E '^(CASE |PASS |FAIL |CASEEND |        )'
  CASES_RUN=$((CASES_RUN + 1))
  if ! printf '%s\n' "$out" | grep -q "^CASEEND $case_name "; then
    echo "ERROR: case $case_name did not finish — nothing was measured there. Full output:" >&2
    printf '%s\n' "$out" >&2
    exit 3
  fi
}

run_case machine_pt            -                      LANG=pt_BR.UTF-8 --
run_case machine_unmatched     -                      LANG=ja_JP.UTF-8 --
run_case machine_lowercase     -                      LANG=pt_br.UTF-8 --
run_case machine_posix         -                      LANG=C --
run_case machine_no_lang       -                      --
run_case machine_empty_lang    -                      LANG= --
run_case env_lc_all_only       -                      LC_ALL=pt_BR.UTF-8 --
run_case env_language_only     -                      LANGUAGE=pt_BR --
run_case env_lc_messages_only  -                      LC_MESSAGES=pt_BR.UTF-8 --
run_case env_lc_all_vs_lang    -                      LANG=pt_BR.UTF-8 LC_ALL=de_DE.UTF-8 --
run_case flag_de               -                      LANG=pt_BR.UTF-8 -- -l de
run_case flag_unshipped        -                      LANG=pt_BR.UTF-8 -- -l ja
run_case setting_test          'locale/test="de"'     LANG=pt_BR.UTF-8 --
run_case flag_beats_test       'locale/test="de"'     LANG=pt_BR.UTF-8 -- -l en
run_case fallback_de           'locale/fallback="de"' LANG=ja_JP.UTF-8 --
run_case fallback_unshipped    'locale/fallback="ru"' LANG=ja_JP.UTF-8 --

echo "---"
echo "NOTE  S17/S18 were measured with an editor build (OS.has_feature(\"editor\") is"
echo "NOTE  true). Whether a release export template honours locale/test is NOT"
echo "NOTE  measured here — clear that field before shipping either way."

# Roll-call. Every id on the page must have been measured exactly once; a claim
# that silently stopped being reached is the failure mode this catches.
IDS="S1 S2 S2b S3 S4 S5 S6 S6b S7 S7b S8 S9 S10 S10b S11 S12 S13 S14 S15 S16 S17 S18 S19 S20 S20b S21"
missing=0
for id in $IDS; do
  n=$(grep -cE "^(PASS|FAIL)  $id  " "$ALL_OUT")
  if [ "$n" -ne 1 ]; then
    echo "ERROR: claim $id was measured $n times, expected exactly 1" >&2
    missing=1
  fi
done
[ "$missing" -eq 0 ] || exit 3

FAILED=$(grep -cE '^FAIL  ' "$ALL_OUT")
PASSED=$(grep -cE '^PASS  ' "$ALL_OUT")
if [ "$FAILED" -eq 0 ]; then
  echo "STARTUP LOCALE: ALL PASS ($PASSED claims, $CASES_RUN scenarios)"
  exit 0
else
  echo "STARTUP LOCALE: $FAILED FAILURES ($PASSED passed, $CASES_RUN scenarios)"
  exit 1
fi
