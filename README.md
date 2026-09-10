# LocGuard Lite

Free in-editor localization checker for Godot 4. Scans your project for
strings passed to `tr()` / `Tr()` / scene text properties and cross-checks
them against your translation CSV, flagging two things:

- **missing-key** (error) — a string is used in code/scenes but has no row
  in the translation CSV.
- **empty-translation** (warning) — a key exists in the CSV but a locale's
  value is blank.

Verified headless against Godot **4.3, 4.4 and 4.7** stable — run on 2026-09-07, the
seven stages of `verify.sh` report ALL VERIFICATION PASSED on each of the three binaries.

**4.2 is not claimed, and two separate things block it**, both measured in the same run:
the engine does not resolve the core script's `class_name` in a headless run (`Parse Error:
Identifier "LocGuardLiteCore" not declared in the current scope`), and the fixture's
`.translation` files are built by 4.7, so 4.2 refuses them for using resource format
version 6. Fixing only the first would not produce a green 4.2 run. Nothing on 4.2 has
been measured end to end.

## Measured docs

- **[Why the locale change does not update the UI](docs/why-the-locale-change-does-not-update-the-ui.md)**
  — the three answers the forums give to "I called `TranslationServer.set_locale()`
  and nothing on screen changed" are not measured. This one is: 16 claims run on
  4.3, 4.4 and 4.7 (16/16 on each), including the trap that a locale nobody
  translated does *not* show the keys — it silently serves the fallback locale,
  so the screen looks fine in English and the wrong locale is invisible. Comes
  with [`verify_locale_change.sh`](docs/verify_locale_change.sh), which runs
  every claim on your own binary.

- **[Why the translation is not loading for my locale](docs/why-the-translation-is-not-loading-for-my-locale.md)**
  — a CSV column headed `pt-br` does not import as Brazilian Portuguese: the
  engine drops a lowercase country code, so it becomes plain `pt`, while `pt-BR`
  (one capital letter apart) becomes `pt_BR`. A column headed `PT_BR` imports
  without error into a file no locale can ever select. 22 claims run on 4.2, 4.3,
  4.4 and 4.7 (22/22 on each), through the engine's own CSV importer, including
  the ranking change in 4.4 that can alter what a `pt_PT` player reads with no
  edit on your side. Comes with
  [`verify_locale_matching.sh`](docs/verify_locale_matching.sh).

- **[Why editing `strings.csv` changes nothing in your game](docs/why-editing-strings-csv-changes-nothing.md)**
  — the import usually worked and nothing loads the result: after importing a
  CSV, `internationalization/locale/translations` is still empty, so `tr()`
  returns the key in every locale with no error at all. And deleting a column
  deletes nothing — the `.translation` it produced stays on disk, stays listed
  in the project settings and keeps answering with the text of a column that no
  longer exists, so a language you removed still ships. 14 claims run on 4.2,
  4.3, 4.4 and 4.7 (14/14 on each), every import done by the binary under test.
  Comes with [`verify_csv_reimport.sh`](docs/verify_csv_reimport.sh).

- **[Why a row in `strings.csv` never reaches the player](docs/why-a-row-in-strings-csv-never-reaches-the-player.md)**
  — a blank cell does not ship a blank string, it ships the KEY, which is
  indistinguishable from a key that was never in the CSV. Two rows with the same
  key silently become one (the last wins, no error, no warning). Keys are never
  trimmed. And `tr()` accepts a context while `tr_n()` accepts a plural and a
  count: against a CSV-backed translation all three are discarded, so two "Open"
  strings disambiguated by context collapse into one and every plural returns
  the singular. 24 claims run on 4.2, 4.3, 4.4 and 4.7 (24/24 on each), every
  import done by the binary under test. Comes with
  [`verify_csv_silent_drops.sh`](docs/verify_csv_silent_drops.sh).

- **[Why a key that IS in your CSV still shows up untranslated](docs/why-a-key-in-your-csv-still-shows-untranslated.md)**
  — `tr()` and the text the node actually shows do not go through the same door.
  `tr()` always translates; the node's own `text` goes through `atr()`, which
  obeys `auto_translate_mode`, so the same node answers two different things in
  the same frame and the one you typed into your script is the one that lies.
  One ancestor set to Disabled takes out a whole subtree with no error and no
  warning, the deprecated `auto_translate` bool set back to `true` writes
  `ALWAYS` instead of `INHERIT` and permanently opts the node out of its
  parent, and a change reaches already-drawn descendants only on the next
  frame — two identical sibling subtrees, same code, opposite answers. 23
  claims run on 4.3 and 4.4, 24 on 4.7 and a separate 6 on 4.2, which has none
  of the feature. Ends with the one `grep` that finds it in your project. Comes
  with [`verify_auto_translate.sh`](docs/verify_auto_translate.sh).

- **[Why your untranslated string comes out in another language](docs/why-your-untranslated-string-comes-out-in-another-language.md)**
  — a missing translation does not look missing. Every Godot 4 project boots
  with `internationalization/locale/fallback` set to `en`, so an untranslated
  string is served in the fallback language instead of showing its key, and a
  half-translated screen looks like one bug per string rather than one missing
  row. An empty cell is stored but counts as absent at lookup, so a blank
  translation shows fluent text in the wrong language and has no visible
  symptom at all. The fallback is a locale and not a search order, the setting
  is read once at startup so writing it at runtime does nothing, and
  `TranslationServer.set_fallback()` — the answer every forum gives — does not
  exist in Godot 4 and takes the whole script down with a parse error. 12 claims
  on the default boot and 13 on each of two more, run on 4.2, 4.3, 4.4 and 4.7,
  every binary booted three times because a startup setting cannot be measured
  any other way. Comes with
  [`verify_translation_fallback.sh`](docs/verify_translation_fallback.sh).

- **[Why `tr_n()` always returns the singular](docs/why-tr_n-always-returns-the-singular.md)**
  — the plural is in `strings.csv`, in its own row, spelled the way the call
  spells it, and `tr_n("APPLE", "APPLES", 5)` returns the singular anyway. The
  CSV importer produces an `OptimizedTranslation`, which has no plural table, so
  there is nothing for the count to select and every count from 0 to 1000 gets
  form one. Both rows are imported and `tr()` reaches either of them the whole
  time, which is why the import check always says everything is fine. A key that
  is in no translation fails the opposite way — untranslated source *plural* at
  n=5 — so the two screens tell you which cause to rule out. `add_plural_message()`
  exists on 4.2, 4.3 and 4.4 and silently discards what you pass it; on 4.7 it
  works, and on 4.7 a plain `Translation` also starts answering the untranslated
  English plural where 4.4 answered the translated singular. A `.po` fixes it,
  and loading it *next to* the CSV does not. 18 claims, run on 4.2, 4.3, 4.4 and
  4.7. Comes with [`verify_plurals.sh`](docs/verify_plurals.sh).

## Install

**Godot Asset Library** (recommended) — search "LocGuard Lite" in the editor's
AssetLib tab, or install from
[the listing](https://godotengine.org/asset-library/asset/5378). The download
contains only `addons/locguard_lite/`, so nothing lands in your project root.

Or manually:

1. Copy `addons/locguard_lite` into your project's `addons/` folder.
2. Project Settings → Plugins → enable "LocGuard Lite".
3. Open the "LocGuard Lite" dock (bottom-right by default) and click
   **Scan project**. Double-click a finding to open the offending file.

## What LocGuard Pro adds

LocGuard Lite is a trimmed-down slice of
[LocGuard Pro](https://blobsmith.itch.io/locguard). Pro adds:

- **placeholder drift** — catches `%d`/`%s`/`{0}`/`{name}` mismatches between
  locales.
- **BBCode checks** — flags unclosed/mismatched/stray `[b]`, `[color]`, etc.
- **orphan keys** — CSV rows that are never referenced in code or scenes.
- **CLI + CI** — a headless command-line runner so the same checks gate
  your pull requests, not just the editor.

Get it: https://blobsmith.itch.io/locguard

## License

MIT — see [LICENSE](LICENSE).


## More from the studio

- **[Blobsmith](https://blobsmith.itch.io/blobsmith)** — draw 6 tiles, get a full 47-blob autotile sheet + a wired Godot 4 TileSet ([free in-browser version](https://blobsmith.itch.io/blobsmith-lite))
- **[LocGuard](https://github.com/leobaray/locguard)** — localization QA linter for Godot 4: missing keys, placeholder drift, broken BBCode ([Pro: in-editor dock + CI gate](https://blobsmith.itch.io/locguard))
- **[Blobsmith Autotile Wirer](https://github.com/leobaray/blobsmith-autotile-wirer)** — free addon that wires a 47-blob sheet into a TileSet inside the editor
- **[The nine Godot 4 scanners, one zip](https://blobsmith.lbwma.com/godot-scanners/)** — free MIT Node scripts that read a Godot 4 project without opening it: missing font glyphs (project and CSV), frozen translations, plural forms the CSV cannot serve, POT gaps, tile seams, collision holes, draw order, and which tile terrain painting will choose. No install and no account
- **[blobsmith.lbwma.com](https://blobsmith.lbwma.com/)** — the studio site: every release in one place, plus free browser tools (nonogram solver, puzzle generators) and printable PDFs
