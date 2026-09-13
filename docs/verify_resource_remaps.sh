#!/usr/bin/env bash
# Runs every claim in docs/why-your-localized-image-or-voice-line-is-the-wrong-one.md
# against a real Godot 4 binary. Exits non-zero if any claim fails.
#
#   docs/verify_resource_remaps.sh /path/to/Godot_v4.7-stable_linux.x86_64
#
# It builds a throwaway project in a temp directory. The remapped resources are
# text .tres files, so no import pass is needed; textures and audio streams go
# through the same ResourceLoader path remap, but only .tres is measured here.
#
# The gate is the summary line, not Godot's exit code: a GDScript parse error
# still exits 0 and measures nothing.
set -uo pipefail

GODOT="${1:-}"
if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
  echo "usage: $0 /path/to/godot-binary" >&2
  exit 2
fi
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(mktemp -d)"
trap 'rm -rf "$PROJ"' EXIT

res() { printf '[gd_resource type="Resource" format=3]\n\n[resource]\nmetadata/lang = "%s"\n' "$2" > "$PROJ/$1"; }
res flag.tres en;      res flag_pt.tres pt
res pflag.tres en_p;   res pflag_pt.tres pt_p
res missing.tres en_m
res noprefix.tres en_n; res noprefix_pt.tres pt_n
res voice.tres en_v;   res voice_br.tres pt_BR
res sign.tres en_s;    res sign_br.tres pt_BR; res sign_pt.tres pt
res late.tres en_l;    res late_pt.tres pt_l

cat > "$PROJ/menu.tscn" <<'EOF'
[gd_scene load_steps=2 format=3]

[ext_resource type="Resource" path="res://flag.tres" id="1"]

[node name="Menu" type="Node"]
metadata/flag = ExtResource("1")
EOF

cat > "$PROJ/uses_preload.gd" <<'EOF'
extends RefCounted
const FLAG = preload("res://pflag.tres")
static func flag_lang() -> String:
	return str(FLAG.get_meta("lang"))
EOF

cat > "$PROJ/project.godot" <<'EOF'
config_version=5

[application]

config/name="LocGuardResourceRemapCheck"

[internationalization]

locale/translation_remaps={
"noprefix.tres": PackedStringArray("res://noprefix_pt.tres:pt"),
"res://flag.tres": PackedStringArray("res://flag_pt.tres:pt"),
"res://missing.tres": PackedStringArray("res://missing_pt.tres:pt"),
"res://pflag.tres": PackedStringArray("res://pflag_pt.tres:pt"),
"res://sign.tres": PackedStringArray("res://sign_br.tres:pt_BR", "res://sign_pt.tres:pt"),
"res://voice.tres": PackedStringArray("res://voice_br.tres:pt_BR")
}
EOF

cp "$HERE/verify_resource_remaps.gd" "$PROJ/verify_resource_remaps.gd"

OUT="$("$GODOT" --headless --path "$PROJ" --script verify_resource_remaps.gd 2>&1)"
echo "$OUT" | grep -E '^(Godot Engine v|PASS |FAIL |RESOURCE REMAPS)'

if ! printf '%s\n' "$OUT" | grep -q '^RESOURCE REMAPS: '; then
  echo "ERROR: the script did not finish — no claim was measured. Full output:" >&2
  printf '%s\n' "$OUT" >&2
  exit 3
fi

FAILS=0
# R7b: the missing target is reported, as a WARNING only.
if printf '%s\n' "$OUT" | grep -q "Translation remap 'res://missing_pt.tres' does not exist. Falling back to 'res://missing.tres'"; then
  echo "PASS R7b — the missing target prints a WARNING (not an error) naming both paths"
else
  echo "FAIL R7b — no fallback warning for res://missing_pt.tres"; FAILS=1
fi
# R8b: the key without res:// is ignored without a word.
if printf '%s\n' "$OUT" | grep -q 'noprefix'; then
  echo "FAIL R8b — the engine said something about the noprefix.tres key"; FAILS=1
else
  echo "PASS R8b — nothing in the output mentions the ignored 'noprefix.tres' key"
fi

printf '%s\n' "$OUT" | grep -q '^RESOURCE REMAPS: ALL PASS' || exit 1
exit "$FAILS"
