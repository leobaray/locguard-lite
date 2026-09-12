# Why your RichTextLabel shows the key instead of the translation

The key is in `strings.csv`. The locale is right. A `Label` next to it, with the
same key, shows the German. The `RichTextLabel` shows `GREET` — in bold, because
the `[b]` around it worked fine.

Every claim below was measured by
[`verify_richtext_bbcode.sh`](verify_richtext_bbcode.sh) on Godot **4.2, 4.3,
4.4 and 4.7** stable, run on 2026-09-12: 18/18 on each of the four builds, no
skips. The ids (`R1`, `R2`, …) are the ids the script prints, so you can re-run
any single line on your own binary. The German strings come out of the `.csv`
through the engine's own importer, not from literals typed into the script.

## A RichTextLabel has two doors, and only one is translated

This is the whole page.

- `text` is translated. A bare key assigned to `text` reaches the player as the
  translation (`R1`), the same as on any other Control.
- `append_text()` is **not**. The exact same key, on the same node, one line
  later, arrives on screen as the key (`R9`). `add_text()` behaves the same way
  (`R10`).

So one node answers two different things at once. Set `text` to `GREET` and
append `" GREET"`, and the player reads **`Hallo GREET`** — one key translated,
one key raw, same frame, same table (`R11`).

And `text` reports neither of them. It still reads `GREET` (`R12`). A test that
asserts on `label.text` is measuring the string you typed, never the string on
screen. The property that answers honestly is `get_parsed_text()`, which is what
this page measures throughout.

## The lookup is the whole string, matched literally

`GREET` alone translates (`R1`, `R4`). `[b]GREET[/b]` does not (`R2`): the
engine looks up the entire contents of `text` as one key, and `[b]GREET[/b]` is
a key nobody put in the table. You get the key, styled correctly, with no error
and no warning.

The same applies to a key with anything around it. `"Score: GREET"` is looked up
whole, misses, and ships as-is (`R3`).

This is engine issue
[#82833](https://github.com/godotengine/godot/issues/82833) — RichTextLabel does
not translate strings placed in between tags — and it is still the behaviour on
4.7.

## Which pushes your markup into the translator's spreadsheet

Because the tag cannot sit outside the key, it has to sit inside the value. The
row has to read `Finde den [b]Schluessel[/b].`, and it works: the player gets
the sentence, parsed, with the tags gone (`R5`).

You have now put BBCode in a cell that a translator edits by hand, and nothing
anywhere checks it.

- A translator who closes `[b]` with `[/i]` ships the literal characters `[/i]`
  into the middle of the sentence the player reads (`R6`).
- A translator who swaps the opening and closing tags ships a literal `[/b]`
  (`R7`).
- The import of that table is completely silent. All four rows, two of them
  with broken tag pairs, import into two locales without one word from the
  editor (`R0`).

Turning `bbcode_enabled` off does not save you. The same cell then shows every
bracket raw on screen (`R8`). Whichever way the flag is set, a translator's
typo in a tag is a visible defect that no tool in the chain reports.

## The part that costs you the afternoon: the locale change deletes text

Everything that came in through `append_text()` is destroyed when the player
changes language, on every build tested (`R13`).

A node with `text = "GREET"` and an appended `" GREET"` reads `Hallo GREET`.
Switch to English and it reads **`Hello`**. The appended half is not
re-translated and not left alone — it is gone. `text` is re-applied to a label
that was cleared, and nothing that was not in `text` comes back.

This is the shape of every chat log, combat log, quest journal and dialogue
history built with `append_text()` in a loop: the content survives until the
first time somebody opens the language menu.

On **4.2 it is worse**: a RichTextLabel whose content came from code goes
completely blank on a locale change, whether or not `text` was ever set
(`R14`, `R15`). From 4.3 on, an append-only node survives; only the appended
half of a mixed node is dropped.

## What to do

- **Translate at the call site, not at the property.** `append_text("[b]%s[/b]"
  % tr("GREET"))` is what puts German on screen (`R16`). `tr()` always
  translates and does not care which door you use — that asymmetry is measured
  on the companion page,
  [why a key that IS in your CSV still shows up untranslated](why-a-key-in-your-csv-still-shows-untranslated.md).
- **Keep the tags outside the key and inside your format string.** Store
  `Schluessel` in the CSV and write the `[b]` in code. The translator never
  sees markup, so the translator cannot break it.
- **If markup must live in the CSV, compare tags between each translation and
  its source column, in CI.** Same shape as the placeholder check on
  [why your translated line comes out empty](why-your-translated-line-comes-out-empty.md):
  it is a text operation over the table, it does not need the game to run, and
  it catches the wrong-tag and swapped-tag cases in one pass.
- **Never rebuild a RichTextLabel's content once and assume it stays.** Connect
  to the locale change and rebuild it, or keep the source data and re-render.
  Assume the label will be emptied behind your back.
- **Do not assert on `.text` in tests.** It does not describe the screen
  (`R12`). `get_parsed_text()` does.

## What LocGuard Lite does and does not cover

Honestly stated, as on every page here: Lite has two rules, `missing-key` and
`empty-translation`. Neither of them looks at BBCode, and neither of them can
see a call site, so **every row and every node on this page passes Lite
clean**. The broken `[/i]` row is a perfectly valid non-empty translation of a
key that exists.

Comparing the tag set of every translation against its source column is
LocGuard Pro's `bbcode-imbalance`. If you would rather not buy anything, the
third bullet above is a text comparison over your own CSV and you can write it
in an afternoon; this page exists so that you know the check is worth writing.
Nothing on the market, Pro included, catches the `append_text()` half of this
page — that one is a call-site problem, and the only defence is the habit.

## Reproducing

```
docs/verify_richtext_bbcode.sh /path/to/Godot_v4.2-stable_linux.x86_64
docs/verify_richtext_bbcode.sh /path/to/Godot_v4.3-stable_linux.x86_64
docs/verify_richtext_bbcode.sh /path/to/Godot_v4.4-stable_linux.x86_64
docs/verify_richtext_bbcode.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

18 claim ids: 17 measured inside the game and one (`R0`) measured around it,
over the editor's own import pass. 18 passes, 0 fails, 0 skips on each of the
four builds. Two ids are written with a version branch on purpose, because 4.2
genuinely answers differently; the run prints the measured value either way.
The summary line is the gate: if the script does not reach it, nothing was
measured, and the script reports that as an error rather than a pass.
