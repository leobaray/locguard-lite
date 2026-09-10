#!/usr/bin/env bash
# Runs every claim in
# docs/why-your-untranslated-string-comes-out-in-another-language.md against a
# real Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_translation_fallback.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds THREE throwaway projects in temp directories, so nothing here
# touches your own files, and it needs no .csv/.po import pass: the translations
# are built in memory with Translation.add_message(), which is the same object
# the importer produces.
#
# Three projects and not one, because internationalization/locale/fallback is
# read at STARTUP: F12 and F13 are claims about the setting, and a claim about a
# boot-time setting cannot be measured by writing that setting at runtime (F11
# is the measurement that says so). The three boots are: the default, "fr", and
# the empty string.
#
# The engine's own exit code is NOT the gate. Godot exits 0 on a GDScript parse
# error, so a build that runs not one claim would still look green. The gate is
# the summary line: if the script did not reach the end and print it, nothing
# was measured, and that is reported as an error, never as a pass.
set -uo pipefail

GODOT="${1:-}"
if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
  echo "usage: $0 /path/to/godot-binary" >&2
  exit 2
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

rc=0

run_one() {
  # $1 = label, $2 = the [internationalization] block (may be empty)
  local label="$1" block="$2"
  local proj="$ROOT/$label"
  mkdir -p "$proj"
  {
    printf 'config_version=5\n\n[application]\n\nconfig/name="LocGuardFallbackCheck"\n'
    [ -n "$block" ] && printf '\n%s\n' "$block"
  } > "$proj/project.godot"
  cp "$HERE/verify_translation_fallback.gd" "$proj/verify_translation_fallback.gd"

  echo "=== boot: $label"
  local out
  out="$("$GODOT" --headless --path "$proj" --script verify_translation_fallback.gd 2>&1)"
  echo "$out" | grep -E '^(Godot Engine v|---|PASS |FAIL |NOTE |TRANSLATION FALLBACK)'

  if [ "$(printf '%s\n' "$out" | grep -c '^TRANSLATION FALLBACK: ')" -eq 0 ]; then
    echo "ERROR: the script did not finish under '$label' -- no claim was measured. Full output:" >&2
    printf '%s\n' "$out" >&2
    rc=3
    return
  fi
  printf '%s\n' "$out" | grep -q '^TRANSLATION FALLBACK: ALL PASS' || rc=1
}

run_one default ''
run_one fallback-fr '[internationalization]

locale/fallback="fr"'
run_one fallback-off '[internationalization]

locale/fallback=""'

exit "$rc"
