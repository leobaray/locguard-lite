# Why the CSV your spreadsheet saved translates nothing

Your translator sent back `strings.csv`. You dropped it in, the editor
reimported, and one of three things happened: the language is not in the game at
all, or it is there and every accented word is broken, or the language list has
an entry you cannot select. The file opens correctly in the spreadsheet. Nothing
in the game printed an error.

The table is not the problem. The **save dialog** is. A spreadsheet offers half a
dozen ways to write a CSV, Godot's importer accepts some of them, refuses others,
and accepts one of them while quietly rewriting your text.

Every claim below was measured by
[`verify_spreadsheet_csv.sh`](verify_spreadsheet_csv.sh) on Godot **4.2, 4.3, 4.4
and 4.7** stable, run on 2026-09-10: 22/22 on each of the four. The nine files
under measurement hold the same two-row table — `HELLO → Olá` and
`BYE → Até mais` — saved nine ways, with the clean UTF-8 one as the reference
every other file is compared against (`E1`). The ids are the ids the script
prints, so you can re-run any single line on your own binary.

## The two things you are about to blame, and neither is guilty

Start here, because these are the first two searches everyone runs.

**A UTF-8 byte order mark changes nothing.** "CSV UTF-8 (comma delimited)" in
Excel puts three bytes in front of the first header cell. The importer still
writes `bom.pt.translation`, still names the locale `pt`, and the strings come
back byte-identical to the clean file (`E2`, `E3`). The BOM does not attach
itself to your first key.

**CRLF line endings change nothing.** A file saved on Windows does not leave a
carriage return on the end of the last column. `Até mais` comes back as eight
characters from the CRLF file and eight from the LF file, same bytes (`E4`,
`E5`).

If your language is missing or mangled, stop converting line endings. It is one
of the next three.

## Group 1 — the files that are refused, and take the language with them

**A semicolon-delimited file imports to nothing.** A spreadsheet running under a
locale whose list separator is `;` — most of continental Europe, and Brazil —
writes `keys;en;pt` when you click "CSV". Godot reads that as a single column,
fails with `ERR_PARSE_ERROR`, and writes **no** `.translation` file at all
(`E6`). Not an empty one. None.

**"Unicode Text" is UTF-16, and does the same** (`E7`).

The console line for both is a red `Error importing 'res://strings.csv'` in the
editor's output panel. Once the project is exported, there is no console. What
the player gets is `E8`: the locale does not exist, so `translate("HELLO")`
returns `HELLO` — the key, in capitals, on the screen.

This is the *good* outcome of the three, because it is total. Nobody ships a
build where every string is an identifier without noticing.

## Group 2 — the file that imports, and is wrong

Now the one that costs money.

The plain "CSV (Comma delimited)" option on Windows writes **ANSI**, not UTF-8.
That file **imports successfully**: `latin1.pt.translation` exists, its locale is
`pt`, the import produced exactly the two files it should (`E9`). Every
mechanical check you can run at build time passes.

And the text is not your text (`E10`):

| Engine | `tr("HELLO")` — you wrote `Olá` | `tr("BYE")` — you wrote `Até mais` |
|---|---|---|
| 4.2, 4.3, 4.4 | `Ol ` — the `á` became a **plain space** (`E11`) | `At�mais` — the `é` became `U+FFFD` **and ate the space after it**, 7 characters (`E12`) |
| 4.7 | `Ol�` — replacement character, 3 characters (`E11`) | `At� mais` — replacement character, space kept, 8 characters (`E12`) |

Two things make this the expensive one.

**The damage is invisible to code.** The mangled string is non-empty, is not the
key, and is returned like any other translation with no error at lookup time
(`E14`). A QA pass that looks for missing keys, empty strings or raw identifiers
finds nothing here.

**The damage is invisible in review.** On 4.2 through 4.4 a word ending in an
accent comes back with a trailing *space* instead — `Ol ` reads as `Ol` in any
UI. On a language list, a menu label or a button, a reviewer skimming a build
sees a plausible word with one letter missing and reads past it.

**And only part of the file is affected**, which is why the file looks fine when
you spot-check it. The English column of the same file is byte-identical to the
clean import (`E13`). Only the columns with accents move. The engine's whole
report on this is one grey `Unicode parsing error` line during import, in the
same panel that scrolls a hundred lines per reimport.

## Group 3 — the header row is your language list, taken literally

The first row of the CSV is not documentation. Every cell after the first
*creates a locale*, spelled exactly as written.

**A space in a header cell creates a locale with a space in its name.** A header
typed `keys,en, pt` — one space after a comma, the shape a human types — produces
a file called `space. pt.translation` whose `locale` is `" pt"` (`E15`, `E16`).
Nothing rejects it. The engine loads it and reports it as loaded.

Then `set_locale("pt")` never matches it, and `translate("HELLO")` returns the
raw key (`E17`) — while `set_locale(" pt")`, space included, returns `Olá`
perfectly (`E18`). The data shipped. The name is one character off, in a
character that does not render.

**A hyphen is fine.** `pt-BR` in a header cell is normalised to the locale
`pt_BR` on all four builds (`E19`), so writing the locale the way the web writes
it costs nothing.

**A trailing comma is fine from 4.3, and fatal on 4.2.** A spreadsheet that kept
an empty column writes `keys,en,pt,`. From 4.3 on, the empty column is reported
as an invalid locale and dropped, and the rest of the file imports correctly
(`E20`, `E21`). On **4.2**, the same file voids everything: `trail.pt.translation`
exists, but it reports its locale as `en` and every string in it is empty
(`E20`, `E21`). Two resources both claiming to be English, both holding nothing,
from a file that opens correctly in the spreadsheet.

## What to check, in the order that finds it fastest

1. **Count the files.** Nine CSVs in the measured project produced fourteen
   `.translation` files, not eighteen (`E22`). Do the same arithmetic on yours:
   number of source CSVs × number of locale columns. If the count is short, a
   file was refused — that is group 1, and the delimiter is the first suspect.
2. **Read the header row as bytes, not as text.** `head -1 strings.csv | cat -A`
   shows you the separator, the trailing comma and the spaces you cannot see in
   the spreadsheet. Anything after the first comma is going to become a locale
   name.
3. **Print the loaded locales at runtime, not in the editor.**
   `print(TranslationServer.get_loaded_locales())` in the exported build. A
   locale you cannot select is usually sitting right there with a space in it.
4. **Grep the CSV for a non-ASCII byte.**
   `grep -P '[\x80-\xFF]' strings.csv | head` shows the accented rows;
   `file strings.csv` tells you whether they are UTF-8. If it says
   `ISO-8859 text`, you are in group 2 and the shipped strings are already
   wrong. `iconv -f ISO-8859-1 -t UTF-8` fixes the file; re-importing without
   converting does not.
5. **Re-import after any fix.** The `.translation` file is the artefact the game
   loads, and correcting the CSV without an import pass changes nothing —
   see [Why editing `strings.csv` changes nothing in your
   game](why-editing-strings-csv-changes-nothing.md).

The one instruction worth giving a translator: **save as UTF-8, comma
delimited**, and send the file back without opening it in a second tool.

## Re-run this on your own binary

```
docs/verify_spreadsheet_csv.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

It builds a throwaway project in a temp directory, writes the nine CSVs, runs a
real editor import pass, and prints PASS or FAIL for each of the 22 claims with
the bytes it measured. It exits non-zero if any claim stops holding, so a newer
Godot tells you exactly which line of this page went stale.

Two limits it states rather than hides: on 4.4 the headless editor import pass
writes every file and then aborts on an unrelated progress-dialog assert, so the
script gates on the files produced and never on the editor's exit code; and
`get_message_count()` is not used anywhere, because `OptimizedTranslation` does
not keep the message texts and 4.7 warns and answers 0.

## Related

- [Why a row in `strings.csv` never reaches the player](why-a-row-in-strings-csv-never-reaches-the-player.md)
  — the rows that are lost inside a file that saved correctly: blank cells,
  duplicate keys, untrimmed keys.
- [Why the translation is not loading for my locale](why-the-translation-is-not-loading-for-my-locale.md)
  — what a column heading has to say for the engine to match it to a player.
- [Why editing `strings.csv` changes nothing in your game](why-editing-strings-csv-changes-nothing.md)
  — the import pass between the file you fixed and the build you ran.
- [Why the context you pass to `tr()` changes nothing](why-the-context-you-pass-to-tr-changes-nothing.md)
  — the other way a header cell invents something: a column called `context`
  imports as a selectable language.

---

Part of **[LocGuard Lite](../README.md)** — free localization QA for Godot 4.
It reports keys that no loaded translation carries. It does not detect the cases
on this page: a refused file leaves no keys to report, and a mangled string is a
present, non-empty translation as far as any checker can tell.
