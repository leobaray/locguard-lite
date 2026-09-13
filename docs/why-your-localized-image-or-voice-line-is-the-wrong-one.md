# Why your localized image or voice line is the wrong one — Brazilian audio in Lisbon, the original in your menu, and nothing printed

Text goes through `tr()`. Everything else — the title logo with words baked in,
the voiced line, the sign texture, the flag on the language button — goes
through a different mechanism: **Project Settings → Localization → Remaps**
(`internationalization/locale/translation_remaps`). You map `res://logo.png` to
`res://logo_pt.png` for `pt`, and `load("res://logo.png")` hands back the
Portuguese file when the locale is Portuguese.

It mostly works. The failures are the quiet kind: a remap that is skipped
without a word, a Brazilian recording served to a player in Portugal who has
no Brazilian locale anywhere in their settings, and a copy of the resource that
the engine updates on one version and not on another.

Every claim below was measured by
[`verify_resource_remaps.sh`](verify_resource_remaps.sh) on Godot **4.2, 4.3,
4.4 and 4.7** stable, run on 2026-09-12. The script builds a throwaway project
with a real remap table and runs it headless. The ids (`R1`, `R2`, …) are the
ids the script prints. The remapped files are text `.tres` resources, so no
import pass is involved; textures and audio go through the same
`ResourceLoader` path remap, but only `.tres` was measured.

## What works, and works better than you would guess

- Under `pt`, `load("res://flag.tres")` returns the contents of
  `res://flag_pt.tres`, and `resource_path` still reads `res://flag.tres`
  (`R1`). Nothing in your code needs to know the second file exists.
- **Switching the language reloads what you already hold.** A reference loaded
  under `en` is the same object after `TranslationServer.set_locale("pt")` and
  now carries the Portuguese data (`R2`). There is no need to re-`load()` on a
  language change.
- That includes resources inside a scene: a `PackedScene` loaded under `en`
  instantiates with the Portuguese resource after the switch (`R3`), and a
  `const X = preload(...)` follows the locale in both directions (`R4`).

Same on all four versions. If your remapped image is not changing, the table
below is where to look — not the cache.

## Where it goes wrong

**A key without `res://` is ignored, silently.** Write the source path as
`"logo.tres"` instead of `"res://logo.tres"` (easy to do when you edit
`project.godot` by hand or generate it) and the original is loaded under every
locale (`R8`). Nothing about that key appears anywhere in the output (`R8b`).

**A missing target falls back to the original, with a warning.** If
`res://logo_pt.tres` is not in the project — renamed, not committed, left out of
the export filter — the player gets the original (`R7`) and the log gets a
`WARNING`, not an error, naming both paths (`R7b`). On a build without a
console, that is invisible.

**A `pt_BR`-only remap is served to every Portuguese player.** List a file only
for `pt_BR` and set the locale to `pt` or `pt_PT`: both get the Brazilian file
(`R9`). The match is by language first. If you record separate voice lines for
Portugal, you must list them — with both `pt_BR` and `pt` listed, `pt_BR` gets
its own, and `pt_PT` and `pt` get the `pt` entry (`R10`). A locale with no
matching language at all, such as `es`, gets the original (`R11`).

**The table is read once, at startup.** Adding an entry with
`ProjectSettings.set_setting("internationalization/locale/translation_remaps", …)`
at runtime changes nothing for subsequent loads (`R12`). A mod loader or a
DLC pack that wants to add localized assets cannot do it by editing that
setting.

**Copies are not updated — and what counts as a copy changed in 4.3.**
`duplicate()` taken under `en` stays English after the switch, on every
version (`R5`). A `ResourceLoader.load(path, "", CACHE_MODE_IGNORE)` taken
under `en` stays English **on 4.2** and is reloaded to Portuguese **on 4.3,
4.4 and 4.7** (`R6`). If you took an uncached copy precisely so you could edit
it without touching the shared one, upgrading from 4.2 means a language change
now overwrites your edits with the file on disk.

## What to check in your own project

1. Every key in `translation_remaps` starts with `res://`.
2. Every target path exists in the exported `.pck` — grep the export log or
   list the pack, since the fallback only warns.
3. For any language with regional variants you care about (`pt`, `es`, `fr`,
   `zh`), there is a plain-language entry, not only the regional one.
4. Localized assets you modify at runtime are `duplicate()`d, not loaded with
   `CACHE_MODE_IGNORE`, if they must survive a language change on 4.3+.

## Reproducing

```
docs/verify_resource_remaps.sh /path/to/Godot_v4.2-stable_linux.x86_64
docs/verify_resource_remaps.sh /path/to/Godot_v4.3-stable_linux.x86_64
docs/verify_resource_remaps.sh /path/to/Godot_v4.4-stable_linux.x86_64
docs/verify_resource_remaps.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

15 claim ids (`R0`–`R12` from the GDScript, `R7b`/`R8b` read off the engine
log), 15/15 on each of the four versions, no skips; `R6` carries the one
per-version expectation. The summary line is the gate, and a run that does not
reach it reports an error rather than a pass. `LG_SELFTEST=1` flips one
expectation on purpose so you can confirm the harness can fail.
