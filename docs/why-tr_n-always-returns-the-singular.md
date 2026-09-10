# Why `tr_n()` always returns the singular

The plural is in `strings.csv`. It has its own row, spelled exactly the way the
call spells it. `tr_n("APPLE", "APPLES", 5)` returns the singular anyway. There
is no error, no warning, and no empty string — just the wrong word, with the
right count next to it.

Every claim below was measured by [`verify_plurals.sh`](verify_plurals.sh) on
Godot **4.2, 4.3, 4.4 and 4.7** stable, run on 2026-09-10: 18/18 on each of the
four. The ids (`N1`, `N2`, …) are the ids the script prints, so you can re-run
any single line on your own binary. Nothing here is a spelling problem, and
nothing here is fixed by a rebuild.

## A CSV translation has no plurals to select from

The CSV importer produces an `OptimizedTranslation` (`N1`). Only a gettext
catalogue produces the class that carries plural forms. So there is no plural
table for `tr_n()` to read, and the engine falls back to handing you the
singular.

Both of your rows do arrive. `tr("APPLE")` gives the translated singular and
`tr("APPLES")` gives the translated plural (`N2`). The data is in the game the
whole time (`N6`). That is what makes this expensive to find: nothing is
missing, so every check you run says the import worked.

What `tr_n()` does with it:

- `n = 1` gives the correct singular (`N3`). This is why the bug survives code
  review — the first case anyone tries is right.
- `n = 5` gives that same singular (`N4`).
- So does every other count measured, from 0 to 1000 (`N5`). There is no count
  that reaches the plural row.

Moving the call does not help. `Node.tr_n()`, `Object.tr_n()` and
`TranslationServer.translate_plural()` all return the same string (`N7`).

For a language with more than two forms, the gap is wider still: Russian needs
three, and a CSV serves one of them to every count (`N8`). The number of forms a
language requires is not something the CSV format can express, so no amount of
extra rows fixes it.

## The other plural failure, so you can rule it out first

A key that is in **no** translation at all fails differently. At `n = 1` you get
the source singular back; at `n = 5` you get the source **plural** back (`N9`,
`N10`) — untranslated, in your development language.

That gives you a two-second diagnosis before you open anything:

| What the player sees at n=5 | What it means |
|---|---|
| Translated, but singular | The translation is a CSV. This page. |
| Untranslated source plural | The key is not in any loaded translation. |

## The method that takes your plurals and throws them away

`Translation.add_plural_message()` exists on 4.2, 4.3, 4.4 and 4.7 alike
(`N11`), so finding it in the docs or in autocomplete tells you nothing about
whether it will work.

On 4.2, 4.3 and 4.4 it accepts `["maca", "macas"]`, returns no error, and then
the base `Translation` class selects form 0 forever: `n = 5` still gives `maca`
(`N14`). On 4.7 the same two lines are honoured and `n = 5` gives `macas`.

The same version boundary changes an answer you may already be shipping. A plain
`Translation` built with `add_message()` only, asked for `n = 5`, returns the
translated singular on 4.4 and the **untranslated source plural** on 4.7 (`N12`).
A build that was quietly printing the wrong grammar starts quietly printing
English.

The CSV path does not follow that change (`N13`). On one 4.7 binary,
`OptimizedTranslation` and `Translation` give different answers to the identical
call — so what you get depends on how the translation was built, not on the
engine version alone.

## What actually fixes it

A `.po` file. Same keys, same locale, same two strings:

```po
msgid ""
msgstr ""
"Language: pt\n"
"Content-Type: text/plain; charset=UTF-8\n"
"Plural-Forms: nplurals=2; plural=(n != 1);\n"

msgid "APPLE"
msgid_plural "APPLES"
msgstr[0] "maca"
msgstr[1] "macas"
```

Now `n = 1` gives `maca`, and `n = 5` and `n = 0` both give `macas` (`N16`). The
`Plural-Forms` header is what picks the form, and it is per-language: the same
file for Russian with `nplurals=3` gives a different form for 1, for 3 and for 5
— and gives 11 the same form as 5 (`N17`), which is the rule Russian has and
which no `if n == 1` in your game code has.

Two things to know before you migrate:

- The importer names the class `TranslationPO` on 4.2–4.4 and plain
  `Translation` on 4.7 (`N15`). Any tooling of yours that checks that class name
  breaks on upgrade.
- **Remove the CSV from the project's translation list.** With both the CSV and
  the `.po` loaded for the same locale, `tr_n(..., 5)` was measured returning the
  CSV's singular (`N18`). Adding the `.po` next to the CSV is not a half-fix that
  half-works; it is decided by which translation the server reaches first, and
  the CSV is still in the list.

You do not have to move every string. Keep the CSV for everything and move only
the keys that are counted — but move each such key out of the CSV, not into both
files.

## Re-run it on your own build

```sh
docs/verify_plurals.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

It builds a throwaway project in a temp directory, writes the CSV and the two
`.po` files, runs a real editor import pass, and prints PASS or FAIL for each of
the 18 claims with the value it measured. It exits non-zero if any claim stops
holding, so a newer Godot tells you exactly which line of this page went stale.

## Related

- [Why a key that IS in your CSV still shows up untranslated](why-a-key-in-your-csv-still-shows-untranslated.md)
  — `tr()` and the node's own `text` do not go through the same door.
- [Why a row in `strings.csv` never reaches the player](why-a-row-in-strings-csv-never-reaches-the-player.md)
  — the rows the importer drops without saying so.
- [Why your untranslated string comes out in another language](why-your-untranslated-string-comes-out-in-another-language.md)
  — where the source plural in `N10` goes when a fallback is configured.

---

Part of **[LocGuard Lite](../README.md)** — free localization QA for Godot 4.
It extracts **both** keys of every `tr_n(` call, the singular and the plural, so
a plural key you forgot to add is reported as missing rather than shipped. It
does not detect the CSV case on this page: there, both keys are present and the
selection is what fails.
