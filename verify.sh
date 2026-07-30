#!/bin/bash
# LocGuard Lite — verification gate (7 stages).
#
# Lite is the free funnel to LocGuard Pro ($12). Until 2026-07-29 it was the
# only published artifact of the studio with NO gate at all: test_verify_lite.gd
# has been sitting in the repo since day 1 and was run by exactly nobody.
#
# WHAT THIS GATE IS FOR, in order of how much money each stage protects:
#
#   upsell   — the free addon must still REACH the paid product. Its entire
#              conversion path is one node, the promo LinkButton at the bottom
#              of the dock, and its destination was a string literal inside
#              plugin.gd checked by nothing. Note this is the OPPOSITE
#              direction from `funnel` below, which is about withholding paid
#              rules; the two names are easy to confuse and neither covers the
#              other. Lite could send every user nowhere — dead link, hidden
#              button, a Label that merely looks like one — and stages 1-6
#              would all be green.
#   funnel   — Lite must stay a STRICT SUBSET of Pro. If Lite ever starts
#              reporting placeholder-printf / bbcode-imbalance / orphan-key,
#              we are giving away the $12 product for free and nothing else in
#              the studio would notice. Checked against Pro's own CLI on the
#              SAME fixture, not against a hardcoded list, so that seeding a
#              new defect in the shared fixture can't quietly desync the two.
#   published— what the Asset Library ACTUALLY serves to users, byte-compared
#              against what we build today. The AL entry pins a commit; a fix
#              committed here reaches users only when moderation approves the
#              re-submit. This stage is the difference between "we fixed it"
#              and "users have it".
#   shipped  — the download must contain addons/locguard_lite/ and NOTHING
#              else. Godot's AL installer unpacks into the user's project root,
#              so every stray root file is a file we drop into someone's game.
#   manifest / runtime / entry — the addon parses, actually runs on real Godot
#              4.7, and the entry we monitor is the entry we published.
#
# DESIGN DECISION THAT MUST SURVIVE FUTURE TURNS (same rule as site/verify.sh):
# the `published` stage compares CONTENT, not commit ids. The AL entry will
# always lag our HEAD by at least one moderation round, and a README-only
# commit produces a byte-identical archive (README is export-ignored). Gating
# on `download_commit == HEAD` would be red forever for no user-visible reason,
# and the natural "fix" for a forever-red gate is to loosen it until it's
# green — which is how false-greens are born. Content equality is the thing
# that actually matters to the person clicking Install.
#
# Usage:  bash verify.sh          (GODOT=... to override the engine binary)

set -uo pipefail
cd "$(dirname "$0")"

GODOT="${GODOT:-/sistemas/blobsmith/tools/godot/Godot_v4.7-stable_linux.x86_64}"
PRO=/sistemas/locguard
PRO_FIXTURE="$PRO/test/fixtures/godot-proj"
ASSET_ID=5378
ADDON=addons/locguard_lite

FAILED=0
fail() { echo "FAIL: $*"; FAILED=1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------- 1. shipped
echo "== shipped (what the Asset Library download contains) =="

# The AL download is a GitHub archive of a commit, so .gitattributes
# export-ignore decides what lands in the user's project. Build it the same way
# GitHub does and assert the exact path set.
git archive --format=zip HEAD > "$TMP/head.zip" 2>/dev/null \
  || { fail "git archive HEAD failed — is this a git repo?"; }

GOT=$(unzip -Z1 "$TMP/head.zip" 2>/dev/null | grep -v '/$' | sort)
WANT=$(printf '%s\n' \
  "$ADDON/LICENSE" \
  "$ADDON/lite_core.gd" \
  "$ADDON/plugin.cfg" \
  "$ADDON/plugin.gd" | sort)

if [ "$GOT" = "$WANT" ]; then
  echo "PASS: download ships exactly $ADDON/ (4 files, nothing at project root)"
else
  echo "--- expected:"; printf '%s\n' "$WANT" | sed 's/^/      /'
  echo "--- got:";      printf '%s\n' "$GOT"  | sed 's/^/      /'
  fail "the download does not match the intended file set."
  echo "      Godot unpacks this into the user's project ROOT. Anything listed"
  echo "      above outside $ADDON/ is a file we drop into someone else's game"
  echo "      (this is exactly what locguard-lite#1 was reported about)."
fi

# A leaked screenshot would still "only" be one stray path, so bound the size
# too: the addon is ~5KB of GDScript and the repo carries 400KB+ of PNGs.
ZBYTES=$(stat -c%s "$TMP/head.zip" 2>/dev/null || echo 0)
if [ "$ZBYTES" -gt 65536 ]; then
  fail "download is ${ZBYTES}B (>64KB) — something binary leaked past .gitattributes."
else
  echo "PASS: download is ${ZBYTES}B (source-only, under the 64KB ceiling)"
fi

# --------------------------------------------------------------- 2. manifest
echo "== manifest (plugin.cfg the editor will read) =="

CFG_VER=$(sed -n 's/^version="\(.*\)"$/\1/p' "$ADDON/plugin.cfg" | head -1)
CFG_SCRIPT=$(sed -n 's/^script="\(.*\)"$/\1/p' "$ADDON/plugin.cfg" | head -1)
CFG_NAME=$(sed -n 's/^name="\(.*\)"$/\1/p' "$ADDON/plugin.cfg" | head -1)

[ -n "$CFG_NAME" ]   || fail "plugin.cfg has no name="
[ -n "$CFG_SCRIPT" ] || fail "plugin.cfg has no script="
echo "$CFG_VER" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || fail "plugin.cfg version=\"$CFG_VER\" is not semver — the AL entry mirrors this string."

# script= is resolved relative to the addon dir; if it isn't in the archive the
# plugin cannot be enabled at all after install.
if unzip -Z1 "$TMP/head.zip" 2>/dev/null | grep -qx "$ADDON/$CFG_SCRIPT"; then
  echo "PASS: plugin.cfg -> $CFG_SCRIPT is present in the download"
else
  fail "plugin.cfg points at $CFG_SCRIPT, which is NOT in the download."
fi

# locguard-lite#1 (the AL reviewer) required the licence to travel WITH the
# addon, because the root LICENSE is export-ignored out of the download.
if unzip -Z1 "$TMP/head.zip" 2>/dev/null | grep -qx "$ADDON/LICENSE"; then
  echo "PASS: LICENSE travels inside the addon (reviewer requirement, issue #1)"
else
  fail "no LICENSE inside $ADDON/ — the download would ship unlicensed."
fi
echo "  manifest: $CFG_NAME $CFG_VER (script=$CFG_SCRIPT)"

# ---------------------------------------------------------------- 3. runtime
echo "== runtime (real Godot 4.7, seeded fixture) =="

# The fixture is BORROWED from Pro rather than copied into this repo on
# purpose: one set of seeded defects, so Lite and Pro can be compared on
# identical input in stage 4. A private copy here would drift and both suites
# would still be green while disagreeing about reality.
if [ ! -d "$PRO_FIXTURE" ]; then
  fail "Pro fixture missing at $PRO_FIXTURE — cannot verify Lite against real input."
elif [ ! -x "$GODOT" ]; then
  fail "Godot binary not executable at $GODOT"
else
  PROJ="$TMP/proj"
  mkdir -p "$PROJ"
  # everything from the Pro fixture except its addon and its .godot cache.
  # DROPPING .godot IS LOAD-BEARING: global_script_class_cache.cfg in the Pro
  # fixture registers LocGuardCore -> addons/locguard/. Godot trusts that cache,
  # so carrying it over makes `LocGuardLiteCore` undeclared and the whole stage
  # fails for a reason that has nothing to do with Lite.
  (cd "$PRO_FIXTURE" && tar -cf - --exclude=addons --exclude=.godot .) | (cd "$PROJ" && tar -xf -)
  # ...plus the Lite addon exactly as users receive it (unpack the download,
  # don't copy the worktree: this verifies the shipped bytes, not our source).
  unzip -q "$TMP/head.zip" -d "$PROJ"
  cp test_verify_lite.gd "$PROJ/"
  # the fixture enables Pro's plugin; Lite must stand alone.
  sed -i 's|^enabled=.*|enabled=PackedStringArray("res://addons/locguard_lite/plugin.cfg")|' \
    "$PROJ/project.godot"
  # import pass: builds the class cache for the addon we just unpacked.
  "$GODOT" --headless --path "$PROJ" --import >/dev/null 2>&1

  # NOT piped to grep: a crashed engine that prints nothing must fail loudly.
  # (Pro's suite learned this on 29/07 — piping hid a non-zero exit.)
  OUT=$("$GODOT" --headless --path "$PROJ" --script test_verify_lite.gd 2>&1)
  RC=$?
  if [ $RC -ne 0 ]; then
    printf '%s\n' "$OUT" | sed 's/^/      /'
    fail "test_verify_lite.gd exited $RC on the shipped addon."
  elif ! printf '%s\n' "$OUT" | grep -q "VERIFY: ALL PASS"; then
    printf '%s\n' "$OUT" | sed 's/^/      /'
    fail "test_verify_lite.gd did not report ALL PASS."
  else
    printf '%s\n' "$OUT" | grep -E '^(PASS|RULES:)' | sed 's/^/  /'
    echo "PASS: the shipped addon runs on real Godot 4.7 and finds the seeded defects"
  fi
  LITE_RULES=$(printf '%s\n' "$OUT" | sed -n 's/^RULES: //p' | head -1)
fi

# ----------------------------------------------------------------- 4. funnel
echo "== funnel (Lite must be a strict subset of Pro) =="

if [ -z "${LITE_RULES:-}" ]; then
  fail "no rule counts from the runtime stage — cannot compare Lite against Pro."
else
  PRO_RULES=$(cd "$PRO" && node src/cli.js test/fixtures/godot-proj --source en --json 2>/dev/null | python3 -c "
import json,sys,collections
d=json.load(sys.stdin)
print(json.dumps(dict(sorted(collections.Counter(x['rule'] for x in d['findings']).items())),separators=(',',':')))
")
  python3 - "$LITE_RULES" "$PRO_RULES" <<'PY'
import json, sys
lite = json.loads(sys.argv[1]); pro = json.loads(sys.argv[2])
FREE = {"missing-key", "empty-translation"}          # what Lite is allowed to do
PAID = set(pro) - FREE                               # what customers pay for
bad = 0
leaked = sorted(set(lite) & PAID)
if leaked:
    print("FAIL: Lite reports Pro-only rules: %s" % ", ".join(leaked))
    print("      Those rules are the reason LocGuard Pro costs $12. Shipping them")
    print("      in the free addon gives the paid product away.")
    bad = 1
extra = sorted(set(lite) - FREE - PAID)
if extra:
    print("FAIL: Lite reports rules Pro does not have at all: %s" % ", ".join(extra))
    bad = 1
for r in sorted(FREE & set(pro)):
    if lite.get(r, 0) != pro[r]:
        print("FAIL: %s — Pro finds %d, Lite finds %d on the same project."
              % (r, pro[r], lite.get(r, 0)))
        print("      Lite under-reporting is worse than useless: it tells a user")
        print("      their project is clean when it isn't.")
        bad = 1
if not bad:
    print("PASS: Lite = %s ; Pro-only rules withheld: %s"
          % (", ".join(sorted(lite)), ", ".join(sorted(PAID)) or "(none)"))
sys.exit(bad)
PY
  [ $? -eq 0 ] || FAILED=1
fi

# ----------------------------------------------------------------- 5. upsell
echo "== upsell (the free addon can still reach the paid product) =="

# Lite is free for one commercial reason: to end with a click through to
# LocGuard Pro. Nothing measured that until 30/07. Stage 4 is named `funnel`
# but guards the other direction (don't give the $12 rules away), and stage 3
# only asserts what the scanner finds — an addon whose promo link is dead,
# hidden, aimed at the free CLI repo, or replaced by a Label that merely looks
# like a link stays green on every other stage in this file.
#
# Measured on the SHIPPED bytes: $PROJ already holds the unzipped download, not
# the worktree. The checker compiles the real plugin.gd against a stub base
# class (EditorPlugin cannot be instantiated outside the editor) and asserts
# the harness differs from the shipped file by exactly one line.
if [ ! -d "${PROJ:-}" ]; then
  fail "the runtime stage never built a project — cannot check the upsell path."
else
  cp test_upsell_lite.gd funnel.json "$PROJ/"
  UOUT=$("$GODOT" --headless --path "$PROJ" --script test_upsell_lite.gd 2>&1)
  URC=$?
  printf '%s\n' "$UOUT" | grep -E '^(  (ok|FAIL|INFO)|FAILED-CHECKS)' | sed 's/^/  /'
  if [ $URC -ne 0 ] || ! printf '%s\n' "$UOUT" | grep -q "UPSELL: ALL PASS"; then
    printf '%s\n' "$UOUT" | grep -vE '^(  (ok|FAIL|INFO)|FAILED-CHECKS)' | sed 's/^/      /'
    fail "the free addon does not reach the paid product."
    echo "      Everything else in this suite can be green while Lite converts nobody."
  else
    echo "PASS: the shipped addon's dock still hands the user to $(python3 -c "import json;print(json.load(open('funnel.json'))['paid_url'])")"
  fi

  # And the checker must be able to fail — four ways, because four different
  # things kill an upsell and one alarm wired to all of them proves nothing.
  # Each seed must redden its OWN check (LG_UPSELL_EXPECT_FAIL enforces "that
  # check and no other"), so a checker that just always fails cannot pass here.
  while IFS=: read -r sname swant swhat; do
    [ -n "$sname" ] || continue
    SEEDP="$TMP/seed-$sname"
    rm -rf "$SEEDP"; cp -r "$PROJ" "$SEEDP"
    python3 - "$SEEDP/$ADDON/plugin.gd" "$sname" <<'PY' || { FAILED=1; continue; }
import sys
path, kind = sys.argv[1], sys.argv[2]
src = open(path, encoding='utf-8').read()
URI = 'promo.uri = "https://blobsmith.itch.io/locguard"'
if kind == 'loop':
    # the one typo that costs every sale: the paid page and the free CLI repo
    # sit two lines apart in the README and end in the same word
    old, new = URI, 'promo.uri = "https://github.com/leobaray/locguard"'
elif kind == 'dead':
    src = src.replace('var promo := LinkButton.new()', 'var promo := Label.new()')
    old, new = '\t' + URI + '\n', ''
elif kind == 'hidden':
    old, new = URI, URI + '\n\tpromo.visible = false'
elif kind == 'ignored':
    old, new = URI, URI + '\n\tpromo.mouse_filter = Control.MOUSE_FILTER_IGNORE'
else:
    print('FAIL: unknown seed %s' % kind); sys.exit(1)
if src.count(old) != 1:
    print('FAIL: seed %s cannot be applied — plugin.gd no longer contains its anchor.' % kind)
    print('      The seeds are how we know the upsell checks can fail. Re-anchor them.')
    sys.exit(1)
open(path, 'w', encoding='utf-8').write(src.replace(old, new, 1))
PY
    SOUT=$(LG_UPSELL_EXPECT_FAIL="$swant" "$GODOT" --headless --path "$SEEDP" --script test_upsell_lite.gd 2>&1)
    if printf '%s\n' "$SOUT" | grep -q "UPSELL: SEED OK"; then
      echo "PASS: seed '$sname' ($swhat) reddens $swant, and only $swant"
    else
      printf '%s\n' "$SOUT" | grep -E '^(  (ok|FAIL)|FAILED-CHECKS|SEED)' | sed 's/^/      /'
      fail "seed '$sname' did not redden $swant alone — the upsell checks are not measuring what they claim."
    fi
  done <<'SEEDS'
loop:destination:the promo points at the free CLI repo
dead:cta-exists:a Label that only looks like a link
hidden:visible-band:the promo is hidden
ignored:cta-clickable:the promo ignores the mouse, pixel-perfect and unclickable
SEEDS
fi

# -------------------------------------------------------------- 6. published
echo "== published (what the Asset Library serves vs what we build) =="

API=$(curl -s --max-time 20 "https://godotengine.org/asset-library/api/asset/$ASSET_ID")
DL=$(printf '%s' "$API" | python3 -c "import json,sys; print(json.load(sys.stdin).get('download_url',''))" 2>/dev/null)

if [ -z "$DL" ]; then
  fail "could not read download_url for asset $ASSET_ID from the Asset Library API."
else
  curl -sL --max-time 60 -o "$TMP/served.zip" "$DL"
  if [ ! -s "$TMP/served.zip" ]; then
    fail "the Asset Library download URL returned nothing: $DL"
  else
    # Compare path -> sha256, stripping each archive's top-level prefix dir.
    python3 - "$TMP/served.zip" "$TMP/head.zip" <<'PY'
import zipfile, hashlib, sys
def manifest(path, strip_prefix):
    out = {}
    with zipfile.ZipFile(path) as z:
        for n in z.namelist():
            if n.endswith('/'): continue
            key = n.split('/', 1)[1] if strip_prefix else n
            out[key] = hashlib.sha256(z.read(n)).hexdigest()
    return out
served = manifest(sys.argv[1], True)    # GitHub wraps in <repo>-<sha>/
built   = manifest(sys.argv[2], False)
extra   = sorted(set(served) - set(built))
missing = sorted(set(built) - set(served))
diff    = sorted(k for k in set(served) & set(built) if served[k] != built[k])
if not (extra or missing or diff):
    print("PASS: the Asset Library serves exactly what we build today (%d files)" % len(built))
    sys.exit(0)
print("FAIL: users are NOT getting what this repo builds.")
for k in extra:   print("      + served, should not exist: %s" % k)
for k in missing: print("      - built, never reaches users: %s" % k)
for k in diff:    print("      ~ same path, different bytes: %s" % k)
print("      The AL entry pins one commit; a fix here is invisible to users")
print("      until the re-submitted edit clears moderation.")
sys.exit(1)
PY
    [ $? -eq 0 ] || FAILED=1
  fi
fi

# ------------------------------------------------------------------ 7. entry
echo "== entry (the listing we monitor is the listing we published) =="

REPO_URL=$(git config --get remote.origin.url 2>/dev/null | sed 's/\.git$//;s|^git@github.com:|https://github.com/|')
printf '%s' "$API" | ASSET_ID="$ASSET_ID" CFG_VER="$CFG_VER" REPO_URL="$REPO_URL" python3 -c "
import json, os, sys
try: d = json.load(sys.stdin)
except Exception: print('FAIL: asset %s returned no JSON' % os.environ['ASSET_ID']); sys.exit(1)
bad = 0
aid, want_ver, repo = os.environ['ASSET_ID'], os.environ['CFG_VER'], os.environ['REPO_URL']
if str(d.get('asset_id')) != aid:
    print('FAIL: asked for asset %s, got %s' % (aid, d.get('asset_id'))); bad = 1
browse = (d.get('browse_url') or '').rstrip('/')
if repo and browse != repo.rstrip('/'):
    print('FAIL: asset %s points at %s, this repo is %s' % (aid, browse, repo))
    print('      A listing pointing at another repo serves another product.')
    bad = 1
if d.get('version_string') != want_ver:
    print('WARN: listing shows %s, plugin.cfg says %s (expected while an edit is in moderation)'
          % (d.get('version_string'), want_ver))
if not bad:
    print('PASS: asset %s = %r v%s -> %s' % (aid, d.get('title'), d.get('version_string'), browse))
sys.exit(bad)
"
[ $? -eq 0 ] || FAILED=1

echo
if [ $FAILED -eq 0 ]; then
  echo "ALL VERIFICATION PASSED"
else
  echo "VERIFICATION FAILED"
fi
exit $FAILED
