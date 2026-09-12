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

- **[Why your game starts in the wrong language on someone else's machine](docs/why-your-game-starts-in-the-wrong-language.md)**
  — `TranslationServer.get_locale()` reports what the machine asked for, not what
  the engine is serving: on a `pt_BR` machine with only a `pt` column it answers
  `pt_BR`, a string that is not in `get_loaded_locales()`, so the membership test
  every language menu is written with is comparing a request to a shipping list.
  On a machine with no matching language at all it still answers that machine's
  locale while the screen shows the fallback. `OS.get_locale_language()` returns
  the literal `C` on build servers and minimal images, so `== "en"` is false
  there. Only `LANG` is read — `LC_ALL`, `LANGUAGE` and `LC_MESSAGES` do nothing,
  alone or beside it, so a locale you reproduced by exporting `LC_ALL` was never
  reproduced. `locale/fallback` naming a locale you do not ship puts raw keys on
  screen for every unmatched player, silently. 26 claims across 16 process
  launches, run on 4.2, 4.3, 4.4 and 4.7. Comes with
  [`verify_startup_locale.sh`](docs/verify_startup_locale.sh).

- **[Why the context you pass to `tr()` changes nothing](docs/why-the-context-you-pass-to-tr-changes-nothing.md)**
  — the second argument of `tr()` means two different things depending on which
  importer answered. A CSV translation has no context table, so it does not miss
  on a context, it discards it and returns the one string it has. A `.po` keeps
  `msgctxt`, and a context it does not carry returns the raw key instead of
  falling back to the no-context entry sitting in the same file. Ship both and
  the answer is decided by the order `project.godot` lists them: CSV first makes
  every contextual entry in your catalogue unreachable, and hides a `msgctxt`
  you never wrote until someone reorders the list. A CSV column headed `context`
  imports as a *language* named `context` that the engine will happily select.
  Two API shifts land here too: a `.po` is `TranslationPO` on 4.2-4.4 and plain
  `Translation` on 4.7, and `get_translated_message_list()` shows 1 of 3 entries
  on the older binaries. 23 claims, run on 4.2, 4.3, 4.4 and 4.7. Comes with
  [`verify_context.sh`](docs/verify_context.sh).

- **[Why the CSV your spreadsheet saved translates nothing](docs/why-the-csv-your-spreadsheet-saved-translates-nothing.md)**
  — the same table saved nine ways by a spreadsheet, and what each one ships. A
  byte order mark and CRLF line endings, the two everyone blames, change nothing.
  A semicolon delimiter and UTF-16 produce no `.translation` file at all, so the
  language is simply absent from the exported build. The expensive one is ANSI /
  Latin-1: it imports successfully and every accented word comes back altered —
  on 4.2-4.4 a trailing `á` becomes a plain space, so `Olá` ships as `Ol`, with
  no error at lookup time and the ASCII columns of the same file untouched. And
  the header row is the locale list, spelled literally: `keys,en, pt` creates a
  locale named `" pt"` that loads, reports as loaded, and never matches
  `set_locale("pt")`. A trailing comma is dropped from 4.3 on and voids the whole
  file on 4.2. 22 claims, run on 4.2, 4.3, 4.4 and 4.7. Comes with
  [`verify_spreadsheet_csv.sh`](docs/verify_spreadsheet_csv.sh).

- **[Why the translation works for you and not for your teammate](docs/why-the-translation-works-for-you-and-not-for-your-teammate.md)**
  — the running game never reads your CSV. The import writes one
  `.translation` per language column into your source tree, and those are the
  only files that matter at run time: delete the `.import` file, or the CSV
  itself, and the game still translates. Delete the `.translation` files and it
  ships keys. The silent failure is a stale `.translation` beside an edited CSV,
  which serves last week's text with no error and no warning, so the person with
  the editor open never sees it and the build server always does. Across
  versions the generated file is one-directional: 4.2 refuses a file written by
  4.3, 4.4 or 4.7 and falls back to the key. And on 4.2 and 4.3 the import is
  not reproducible — three reimports of the same table, with the uid unchanged,
  wrote three different files, so tracking them means an unmergeable binary diff
  per contributor. 18 claims, run on 4.2, 4.3, 4.4 and 4.7. Comes with
  [`verify_generated_files.sh`](docs/verify_generated_files.sh).

- **[Why the OK and Cancel buttons stay in English](docs/why-the-ok-button-stays-in-english.md)**
  — those strings are not locked inside the engine. The engine puts an English
  literal on the button and the button draws it through the same auto-translate
  path your own labels use, so a row keyed exactly `OK` does translate it. Two
  things go wrong. The property lies about the screen: `button.text` stays `OK`
  forever, so debugging by printing tells you the translation failed when it
  did not, while `button.atr(button.text)` returns the translated string in the
  same frame. And the key changes between engine versions: the `FileDialog`
  accept button is `OK` on the 4.2 and 4.3 line and `Save` on 4.4 and later, so
  a project that translated that button on 4.3 goes back to English on 4.4 with
  no error, no warning and no failed import. 23 claims, run on 4.2, 4.3, 4.4
  and 4.7 — 21/21 on 4.3, 4.4 and 4.7, and on 4.2 the claims that need
  `Control.atr()` are reported as skipped, never as passed. Comes with
  [`verify_dialog_buttons.sh`](docs/verify_dialog_buttons.sh).

- **[Why your translation shows boxes, or nothing at all](docs/why-your-translation-shows-boxes-or-nothing.md)**
  — the table is fine and the font is not. The font the engine ships with
  covers Latin, Cyrillic and Greek and has no glyph for Han, Hiragana, Thai or
  Arabic, and its Hebrew coverage changes between 4.4 and 4.5. When a font
  cannot draw a character Godot borrows one from the operating system it is
  running on, so the glyph on your screen comes from your machine and not from
  your project: the same build shows text on yours and empty boxes on a
  player's. Nothing catches it — `tr()` returns the right string,
  `get_string_size()` returns a positive width, a `Label` reserves room for it,
  and the engine prints no error or warning at all. 26 assertions plus 3
  machine-dependent notes, run on 4.2, 4.3, 4.4 and 4.7 — 26/26 on each, no
  skips. Comes with
  [`verify_font_coverage.sh`](docs/verify_font_coverage.sh).

- **[Why your translated line comes out empty, or as another line's text](docs/why-your-translated-line-comes-out-empty.md)**
  — the row is there, `tr()` returns it, and the `%` that fills it fails,
  because the translator moved the placeholders where their language puts
  them, or deleted one half of a doubled `%%`, or just wrote `100% sicher` in
  ordinary prose. What the player gets is not an error: on a typed call site
  the empty string, so the line is absent and the layout closes up; on an
  untyped one `null`, whose assignment to `label.text` raises and stops the
  rest of that `_ready()`; and on 4.2 and 4.3 a string belonging to another
  part of the program, so the screen shows text from somewhere else. Nothing
  compares a translation's placeholders with its source column at import time
  or any other time, the Output wording differs between call sites and changed
  in 4.4, and a `%d` turned into `%s` never fails at all. 21 assertions run on
  4.2, 4.3, 4.4 and 4.7 — 21/21 on each, no skips. Comes with
  [`verify_format_placeholders.sh`](docs/verify_format_placeholders.sh).

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
