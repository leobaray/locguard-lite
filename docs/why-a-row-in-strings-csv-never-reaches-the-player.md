# Why a row in `strings.csv` never reaches the player

A key shows up on screen instead of the text. The CSV has that key. The file
imported. The usual answers — "check your locale", "reimport", "the key is
misspelled" — assume that a row in the CSV became a message and that the extra
arguments of `tr()` do something.

Both assumptions are measured below and both fail. Rows are dropped, collapsed
and made unreachable without one error or warning, and two of the arguments in
the `tr()` signature are accepted by the CSV path and then discarded.

Everything here is measured, not remembered. The claim ids (`D1`…`D24`) are the
checks in [`verify_csv_silent_drops.gd`](verify_csv_silent_drops.gd); run
[`verify_csv_silent_drops.sh`](verify_csv_silent_drops.sh) against your own
binary and it prints the same list with PASS/FAIL for your version:

```
docs/verify_csv_silent_drops.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

**Measured on Godot 4.2, 4.3, 4.4 and 4.7 stable (official Linux builds),
2026-09-09: 24/24 on each of the four.** Every import in the run is performed by
that same binary as a headless editor, so what you read below is the real
importer, not a description of it.

The CSV used is eight data rows and seven distinct keys, all shapes that appear
in hand-maintained files, none of them invalid CSV:

```csv
keys,en,pt
GREETING,Hello,Ola
EMPTY_CELL,,Vazio
DUP,first-en,first-pt
DUP,second-en,second-pt
 SPACED ,spaced-en,spaced-pt
QUOTED,"with, comma",virgula
LINE\nBREAK,two-line-en,two-line-pt
ESCAPED,first\nsecond,pri\nseg
```

---

## 1. The three rows that do not survive the import

The baseline holds: a plain row answers through `tr()` exactly as documented
(`D4`). This page is about the other seven rows.

**A blank cell does not ship a blank string — it ships the key.** `EMPTY_CELL`
has an English cell that is empty, and `tr("EMPTY_CELL")` returns
`"EMPTY_CELL"` on all four builds (`D5`). This is the single most misleading
result on this page: the untranslated string is not quietly missing from the UI,
it is loudly present as an identifier, and it is indistinguishable from a key
that was never in the CSV at all (`D16`). A translator who leaves a cell for
later has produced the same symptom as a typo.

**Two rows with the same key become one, and the last one wins.**
`tr("DUP")` returns `second-en` (`D6`). The first row is gone. The import that
dropped it printed no error and no warning (`D7`) — the only trace is a
`reimport | strings.csv` progress line, the same one a clean file produces. A
CSV that grew by merge or by copy-paste can carry a shadowed row for months.

**A key is not trimmed.** The row written as `` SPACED `` is stored with its
spaces, so `tr("SPACED")` returns `"SPACED"` and only `tr(" SPACED ")` reaches
the text (`D8`). Spreadsheets add these spaces; nothing removes them.

Quoting works as you would expect: a quoted field keeps its comma (`D9`).

## 2. `\n` means two different things on the two sides of the comma

The importer's defaults are `unescape_keys=false` and
`unescape_translations=true`, and the consequence is not symmetric:

- in a **key**, `\n` stays two literal characters, so GDScript has to escape the
  backslash — `tr("LINE\\nBREAK")` matches and `tr("LINE\nBREAK")` does not
  (`D10`);
- in a **value**, the same `\n` becomes a real newline (`D11`).

One CSV row, one pair of characters, two opposite readings depending on which
column it sits in.

## 3. The arguments `tr()` accepts and the CSV path ignores

`tr()` takes a context and `tr_n()` takes a plural form and a count. Against a
CSV-backed translation, all three are accepted and discarded:

- `tr("GREETING", "menu")` returns the no-context message (`D12`), and so does
  `get_message("GREETING", "menu")` on the resource (`D13`) — one message
  answers for every context, so disambiguating two "Open" strings by context
  silently collapses them into one;
- `tr_n("GREETING", "GREETINGS", 1)` and `tr_n(..., 2)` return the same singular
  message (`D14`), as does `get_plural_message()` (`D15`).

Context and plurals are a gettext PO feature. The CSV importer has no column for
either, and nothing anywhere reports the mismatch — the call compiles, runs, and
returns a plausible string.

One asymmetry worth knowing when you read a bug report: a missing key through
`tr()` comes back as the key, but a missing key through `tr_n()` comes back as
the **plural** argument (`D17`). The same absent string surfaces under two
different names depending on which function asked for it.

## 4. Why you cannot list the keys that shipped

By default the importer does not write a `Translation`. It writes an
`OptimizedTranslation` (`D1`), which stores hashes instead of keys: on a shipped
build `get_message_count()` is `0` and `get_message_list()` is empty (`D2`).
`get_translated_message_list()` still returns every value (`D3`), so a tool
reading the shipped file can see all the text and none of the identifiers that
select it. Lookup works; enumeration is gone.

Re-importing the same CSV with `compress=false` produces a plain `Translation`
whose keys are readable (`D19`), and that readback is what confirms sections 1
and 3 at the storage level: the duplicate key appears exactly once (`D20`) and
the untrimmed key keeps its spaces (`D21`).

**The empty-cell row is stored differently across versions, and it does not
matter to the player.** On 4.2, 4.3 and 4.4 the row is kept with an empty
message — present in the key list, and still not returned by `tr()` (`D22`). On
4.7 the row is dropped at import and is not in the key list at all (`D22`).
Either way the player sees the key (`D23`), which is why this difference has
never produced a distinguishable bug report.

One spelling trap sits next to this. The default `.import` file writes the same
boolean two ways: `compress=true` on 4.2–4.4 and `compress=1` on 4.7 (`D18`).
Both values are read identically by all four builds (`D24`); only the text the
editor writes differs. Grepping a project for `compress=true` will skip every
CSV last imported by 4.7.

## 5. What this means for a QA pass

The failures on this page share one property: the game runs, nothing is logged,
and the artefact on screen is a key. That makes them invisible to a runtime
check and visible in the CSV, before the import:

- a row whose cell for a shipping locale is empty;
- a key that appears on more than one row;
- a key with leading or trailing whitespace;
- a `tr()` call with a context argument, or a `tr_n()` call, in a project whose
  translations all come from CSV.

[LocGuard Lite](https://github.com/leobaray/locguard-lite) checks the CSV
against the strings your code and scenes actually use — missing keys and empty
values are in it today. The duplicate-key, untrimmed-key and
context/plural-against-CSV cases above are **not** rules in it yet; saying so
plainly is the point of this page, and this measurement is what those rules
would have to be built on.

## Related

- [Why editing `strings.csv` changes nothing in your game](why-editing-strings-csv-changes-nothing.md)
  — the import succeeds and nothing in the project loads the result.
- [Why the translation is not loading for my locale](why-the-translation-is-not-loading-for-my-locale.md)
  — a column headed `pt-br` does not import as Brazilian Portuguese.
- [Why the locale change does not update the UI](why-the-locale-change-does-not-update-the-ui.md)
  — `TranslationServer.set_locale()` and what does not move when you call it.
- [Why your untranslated string comes out in another language](why-your-untranslated-string-comes-out-in-another-language.md)
  — the same blank cell in a non-fallback column, where it shows fluent text in
  the wrong language instead of the key.
