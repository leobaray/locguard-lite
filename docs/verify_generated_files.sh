#!/usr/bin/env bash
# Runs every claim in
# docs/why-the-translation-works-for-you-and-not-for-your-teammate.md
# against real Godot 4 binaries. Exits non-zero if any claim fails.
#
#   docs/verify_generated_files.sh /path/to/Godot_v4.7-stable_linux.x86_64
#   docs/verify_generated_files.sh /path/to/4.2 /path/to/4.3 /path/to/4.4 /path/to/4.7
#
# The first binary measures everything that one engine can see on its own. The
# claims about what one engine's output does to another engine (M11, M12, M13,
# M17) need at least two, so with a single binary they are reported SKIP rather
# than quietly dropped.
#
# Every project used here is built in a temp directory, so nothing touches your
# own files. The engine's exit code is NOT the gate: Godot exits 0 on a GDScript
# parse error and the editor import pass exits 0 whether or not it imported
# anything. The gate is the per-case CASEEND line — a case that did not reach the
# end measured nothing, and that is reported as an error, never as a pass.
set -uo pipefail

GODOT="${1:-}"
if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
  echo "usage: $0 /path/to/godot-binary [more godot binaries...]" >&2
  exit 2
fi
shift
EXTRA_BINS=("$@")

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ALL_OUT="$WORK/all_out.txt"
: > "$ALL_OUT"
CASES_RUN=0

say() { printf '%s\n' "$*" | tee -a "$ALL_OUT"; }

# ---------------------------------------------------------------- the project
# Two languages, one key. The text is deliberately boring: every claim here is
# about which file on disk the engine ends up reading, not about the text.
build_project() {  # build_project <dir> [csv-body]
  local dir="$1"; local body="${2:-GREETING,Hello,Ola}"
  mkdir -p "$dir"
  cat > "$dir/project.godot" <<EOF
config_version=5

[application]

config/name="LocGuardTeammateCheck"

[internationalization]

locale/translations=PackedStringArray("res://strings.en.translation", "res://strings.pt.translation")
EOF
  printf 'keys,en,pt\n%s\n' "$body" > "$dir/strings.csv"
  cp "$HERE/verify_generated_files.gd" "$dir/verify_generated_files.gd"
}

import_pass() {  # import_pass <dir> <binary>
  "$2" --headless --path "$1" --editor --quit-after 300 > "$1/import_log.txt" 2>&1
}

run_case() {  # run_case <case> <dir> <binary>
  local case_name="$1" dir="$2" bin="$3"
  local out
  out="$(LGCASE="$case_name" "$bin" --headless --path "$dir" \
         --script verify_generated_files.gd 2>&1)"
  printf '%s\n' "$out" >> "$ALL_OUT"
  printf '%s\n' "$out" | grep -E '^(CASE |PASS |FAIL |        )'
  CASES_RUN=$((CASES_RUN + 1))
  if ! printf '%s\n' "$out" | grep -q "^CASEEND $case_name "; then
    echo "ERROR: case $case_name did not finish — nothing was measured there. Full output:" >&2
    printf '%s\n' "$out" >&2
    exit 3
  fi
}

# A claim measured by the shell itself (bytes on disk, two binaries), printed in
# the same shape the GDScript side prints so the roll-call sees one list.
shell_claim() {  # shell_claim <id> <desc> <ok:0|1> [detail]
  local id="$1" desc="$2" ok="$3" detail="${4:-}"
  if [ "$ok" = "1" ]; then say "PASS  $id  $desc"; else say "FAIL  $id  $desc"; fi
  [ -n "$detail" ] && say "        $detail"
  return 0
}
shell_skip() { say "SKIP  $1  $2"; }

md5of() { md5sum "$1" 2>/dev/null | cut -d' ' -f1; }

# ------------------------------------------------------------------ scenarios
build_project "$WORK/never"
run_case never_imported "$WORK/never" "$GODOT"

build_project "$WORK/base"
import_pass "$WORK/base" "$GODOT"
if [ ! -f "$WORK/base/strings.en.translation" ]; then
  echo "ERROR: the import pass produced no strings.en.translation — nothing below is measurable." >&2
  tail -5 "$WORK/base/import_log.txt" >&2
  exit 3
fi
run_case fresh_import "$WORK/base" "$GODOT"

# What a teammate actually clones: the tracked files, never .godot/.
clone_of() {  # clone_of <dest>
  rm -rf "$1"; mkdir -p "$1"
  cp "$WORK/base/project.godot" "$WORK/base/strings.csv" \
     "$WORK/base/strings.csv.import" "$WORK/base/verify_generated_files.gd" "$1/"
  cp "$WORK/base/strings.en.translation" "$WORK/base/strings.pt.translation" "$1/"
}

clone_of "$WORK/clone";        run_case no_godot_dir "$WORK/clone" "$GODOT"
clone_of "$WORK/notrans";      rm -f "$WORK/notrans"/*.translation
                               run_case no_translation_files "$WORK/notrans" "$GODOT"
clone_of "$WORK/noimport";     rm -f "$WORK/noimport/strings.csv.import"
                               run_case no_import_file "$WORK/noimport" "$GODOT"
clone_of "$WORK/nocsv";        rm -f "$WORK/nocsv/strings.csv"
                               run_case no_csv "$WORK/nocsv" "$GODOT"

# The silent one: the CSV moved on, the generated file did not.
clone_of "$WORK/stale"
printf 'keys,en,pt\nGREETING,BRAND NEW TEXT,Novo\n' > "$WORK/stale/strings.csv"
run_case stale_translation "$WORK/stale" "$GODOT"
import_pass "$WORK/stale" "$GODOT"
run_case after_editor_pass "$WORK/stale" "$GODOT"

# ------------------------------------------------- reproducibility (M15, M16)
# What a teammate's clone gets depends on whether the generated file is stable.
# It is not stable in the same way on every version, so the expectation here is
# per-version, and a version nobody measured is reported SKIP with what it did.
VER_FULL="$("$GODOT" --headless --version 2>/dev/null | head -1)"
VER_MM="$(printf '%s' "$VER_FULL" | cut -d. -f1,2)"
case "$VER_MM" in
  4.2|4.3) EXPECT_STABLE=0 ;;
  4.4|4.7) EXPECT_STABLE=1 ;;
  *)       EXPECT_STABLE=unknown ;;
esac

# M15: two projects that each import the same table from scratch.
build_project "$WORK/uid1"; import_pass "$WORK/uid1" "$GODOT"
build_project "$WORK/uid2"; import_pass "$WORK/uid2" "$GODOT"
U1="$(grep -o 'uid://[a-z0-9]*' "$WORK/uid1/strings.csv.import" | head -1)"
U2="$(grep -o 'uid://[a-z0-9]*' "$WORK/uid2/strings.csv.import" | head -1)"
DIFFBYTES="$(cmp -l "$WORK/uid1/strings.en.translation" "$WORK/uid2/strings.en.translation" 2>/dev/null | wc -l)"
M15_DETAIL="$VER_FULL: $U1 vs $U2, differing bytes = $DIFFBYTES"
case "$VER_MM" in
  4.2|4.3|4.4) [ "$U1" != "$U2" ] && [ "$DIFFBYTES" -gt 0 ] && ok=1 || ok=0
               shell_claim M15 "two projects importing the same table mint different uids and generate different bytes" "$ok" "$M15_DETAIL" ;;
  4.7)         [ "$U1" = "$U2" ] && [ "$DIFFBYTES" -eq 0 ] && ok=1 || ok=0
               shell_claim M15 "two projects importing the same table get the SAME uid and byte-identical files" "$ok" "$M15_DETAIL" ;;
  *)           shell_skip M15 "version not in the measured set — observed: $M15_DETAIL" ;;
esac

# M16: three reimports in a row of one project — same uid, same binary.
build_project "$WORK/det"; import_pass "$WORK/det" "$GODOT"
UD0="$(grep -o 'uid://[a-z0-9]*' "$WORK/det/strings.csv.import" | head -1)"
S1="$(md5of "$WORK/det/strings.en.translation")"
rm -rf "$WORK/det/.godot"; import_pass "$WORK/det" "$GODOT"
S2="$(md5of "$WORK/det/strings.en.translation")"
rm -rf "$WORK/det/.godot"; import_pass "$WORK/det" "$GODOT"
S3="$(md5of "$WORK/det/strings.en.translation")"
UD1="$(grep -o 'uid://[a-z0-9]*' "$WORK/det/strings.csv.import" | head -1)"
DISTINCT="$(printf '%s\n%s\n%s\n' "$S1" "$S2" "$S3" | sort -u | wc -l)"
M16_DETAIL="$VER_FULL: uid $UD0 -> $UD1, $DISTINCT distinct files from 3 reimports (${S1:0:8} ${S2:0:8} ${S3:0:8})"
if [ "$EXPECT_STABLE" = "1" ]; then
  [ "$DISTINCT" -eq 1 ] && [ "$UD0" = "$UD1" ] && ok=1 || ok=0
  shell_claim M16 "reimporting the same table three times rewrites the same bytes every time" "$ok" "$M16_DETAIL"
elif [ "$EXPECT_STABLE" = "0" ]; then
  [ "$DISTINCT" -eq 3 ] && [ "$UD0" = "$UD1" ] && ok=1 || ok=0
  shell_claim M16 "reimporting the same table writes DIFFERENT bytes every time, with the uid unchanged" "$ok" "$M16_DETAIL"
else
  shell_skip M16 "version not in the measured set — observed: $M16_DETAIL"
fi

# ------------------------------------------------- across engine versions (M11, M12, M13, M17)
if [ "${#EXTRA_BINS[@]}" -eq 0 ]; then
  shell_skip M11 "needs a second binary: pass more than one Godot to measure it"
  shell_skip M12 "needs a second binary: pass more than one Godot to measure it"
  shell_skip M13 "needs a second binary: pass more than one Godot to measure it"
  shell_skip M17 "needs a second binary: pass more than one Godot to measure it"
else
  ALL_BINS=("$GODOT" "${EXTRA_BINS[@]}")
  # M11: same table, same uid, one project per binary — do the bytes differ?
  sums=""; names=""
  i=0
  for b in "${ALL_BINS[@]}"; do
    d="$WORK/ver$i"; build_project "$d"; cp "$WORK/uid1/strings.csv.import" "$d/"
    import_pass "$d" "$b"
    sums="$sums $(md5of "$d/strings.en.translation")"
    names="$names $("$b" --headless --version 2>/dev/null | head -1)"
    i=$((i + 1))
  done
  uniq_n="$(printf '%s\n' $sums | sort -u | wc -l)"
  [ "$uniq_n" -eq "${#ALL_BINS[@]}" ] && ok=1 || ok=0
  shell_claim M11 "the same table imported by different engine versions produces different bytes" "$ok" \
    "$uniq_n distinct files from ${#ALL_BINS[@]} binaries:$names"
  [ "$uniq_n" -gt 1 ] && ok=1 || ok=0
  shell_claim M17 "the same uid does not make two engine versions agree on the bytes" "$ok" \
    "$uniq_n distinct files for one uid"

  # M12 / M13: feed each binary the file another one generated.
  refused=0; refused_total=0; accepted=0; accepted_total=0
  gi=0
  for gen in "${ALL_BINS[@]}"; do
    ri=0
    for run in "${ALL_BINS[@]}"; do
      if [ "$gi" -eq "$ri" ]; then ri=$((ri + 1)); continue; fi
      d="$WORK/cross"; rm -rf "$d"; mkdir -p "$d"
      cp "$WORK/ver$gi"/project.godot "$WORK/ver$gi"/strings.csv \
         "$WORK/ver$gi"/strings.csv.import "$WORK/ver$gi"/verify_generated_files.gd \
         "$WORK/ver$gi"/*.translation "$d/"
      out="$(LGCASE=probe "$run" --headless --path "$d" \
             --script verify_generated_files.gd 2>&1)"
      gname="$("${ALL_BINS[$gi]}" --headless --version 2>/dev/null | head -1 | cut -d. -f1,2)"
      rname="$("$run" --headless --version 2>/dev/null | head -1 | cut -d. -f1,2)"
      if printf '%s' "$out" | grep -q "format version"; then
        refused_total=$((refused_total + 1))
        printf '%s\n' "$out" | grep -q "not supported by your engine version" && refused=$((refused + 1))
        say "        generated by $gname, read by $rname: REFUSED"
      else
        accepted_total=$((accepted_total + 1))
        say "        generated by $gname, read by $rname: accepted"
      fi
      ri=$((ri + 1))
    done
    gi=$((gi + 1))
  done
  say "        cross-version loads: $refused_total refused, $accepted_total accepted"

  # Now the two directed claims, each on one prepared project.
  # Oldest binary reading the newest binary's file.
  d="$WORK/xrefuse"; rm -rf "$d"; mkdir -p "$d"
  last=$(( ${#ALL_BINS[@]} - 1 ))
  cp "$WORK/ver$last"/project.godot "$WORK/ver$last"/strings.csv \
     "$WORK/ver$last"/strings.csv.import "$WORK/ver$last"/verify_generated_files.gd \
     "$WORK/ver$last"/*.translation "$d/"
  run_case cross_read_refused "$d" "${ALL_BINS[0]}"
  # Newest binary reading the oldest binary's file.
  d="$WORK/xok"; rm -rf "$d"; mkdir -p "$d"
  cp "$WORK/ver0"/project.godot "$WORK/ver0"/strings.csv \
     "$WORK/ver0"/strings.csv.import "$WORK/ver0"/verify_generated_files.gd \
     "$WORK/ver0"/*.translation "$d/"
  run_case cross_read_ok "$d" "${ALL_BINS[$last]}"
fi

# ------------------------------------------------------------------ roll-call
# Every id on the page must have been measured exactly once. A claim that
# silently stopped being reached is the failure mode this catches.
IDS="M1 M2 M3 M4 M4b M5 M6 M7 M8 M9 M10 M11 M12 M13 M14 M15 M16 M17"
missing=0
for id in $IDS; do
  n=$(grep -cE "^(PASS|FAIL|SKIP)  $id  " "$ALL_OUT")
  if [ "$n" -ne 1 ]; then
    echo "ERROR: claim $id was measured $n times, expected exactly 1" >&2
    missing=1
  fi
done
[ "$missing" -eq 0 ] || exit 3

FAILED=$(grep -cE '^FAIL  ' "$ALL_OUT")
PASSED=$(grep -cE '^PASS  ' "$ALL_OUT")
SKIPPED=$(grep -cE '^SKIP  ' "$ALL_OUT")
echo "---"
if [ "$FAILED" -eq 0 ]; then
  echo "GENERATED FILES: ALL PASS ($PASSED claims, $SKIPPED skipped, $CASES_RUN scenarios)"
  exit 0
else
  echo "GENERATED FILES: $FAILED FAILURES ($PASSED passed, $SKIPPED skipped, $CASES_RUN scenarios)"
  exit 1
fi
