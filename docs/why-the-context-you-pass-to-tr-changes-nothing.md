# Why the context you pass to `tr()` changes nothing

You wrote `tr("OPEN", &"Menu")` because "open" is a button in one place and a
door in another. The button and the door still say the same word. No error, no
warning, no empty string — the context argument simply had no effect.

Or the opposite happened: you added a context and the key came out **raw**, in
capitals, on the player's screen, even though that key is translated and you can
see the translated string in the file.

Both are the same page, because Godot 4 has two translation back-ends and they
disagree about what a context is. Which one answers is not decided by your call.

Every claim below was measured by [`verify_context.sh`](verify_context.sh) on
Godot **4.2, 4.3, 4.4 and 4.7** stable, run on 2026-09-10: 23/23 on each of the
four. The ids (`X1`, `X2`, …) are the ids the script prints, so you can re-run
any single line on your own binary.

## A CSV does not miss on a context. It ignores it

The CSV importer produces an `OptimizedTranslation` (`X1`), and that class has
no context table at all. Ask it for a message with a context and it hands back
the one string it has for that key:

- `csv.get_message("OPEN")` is `Abrir` (`X3`).
- `csv.get_message("OPEN", &"Menu")` is `Abrir` — the same string (`X4`).

This is not a lookup that failed. It is a lookup that never happened. The same
answer comes through `TranslationServer.translate()` (`X5`) and through
`Node.tr()` (`X6`). Nothing at any layer reports that a context was asked for
and thrown away.

So on a CSV-only project, every context you write is dead code that looks alive.

## A `.po` keeps contexts, and a context it does not know is a hard miss

The gettext importer keeps `msgctxt`. One `msgid` with two contexts plus a bare
entry is **three** entries in the resource (`X7`), and each returns its own
string:

| Call | Returns |
|---|---|
| `translate("OPEN")` | `Abrir` (`X8`) |
| `translate("OPEN", &"Menu")` | `Abrir-menu` (`X9`) |
| `translate("OPEN", &"Door")` | `Destrancar` (`X10`) |
| `translate("OPEN", &"Nope")` | `OPEN` (`X11`) |

That last row is the one that costs you a bug report. A context the catalogue
does not carry returns the **key**, raw. It does **not** fall back to the
no-context entry for the same `msgid`, which is sitting in the same file, two
lines above. A typo in a context string is therefore indistinguishable, on
screen, from a missing translation.

## In one project, the order of the files decides the answer

Ship both — a CSV for the bulk and a `.po` for the strings that needed a context
— and the same call returns different text depending on which file was
registered first:

| Registration order | `translate("OPEN", &"Menu")` |
|---|---|
| CSV, then `.po` | `Abrir` (`X13`) |
| `.po`, then CSV | `Abrir-menu` (`X14`) |

The CSV answers everything, because it never misses (`X15`). Put it first and
every contextual entry in your catalogue becomes unreachable, silently, with
both files present, imported and correct.

The same mechanism hides the reverse problem. `translate("CLOSE", &"Menu")`
returns `Fechar` when a CSV carries `CLOSE` (`X16`), even though the `.po` has
no such entry and would have shown the raw key. A `msgctxt` you forgot to add
stays invisible for as long as some CSV happens to carry the key — and surfaces
the day someone reorders the translation list.

`add_translation()` runs in the order `project.godot` lists the files. That list
is edited by a dialog, by hand, and by version-control merges.

## Putting the context in a CSV column invents a language

There is nowhere in a CSV to put a context, so the obvious move is another
column:

```csv
keys,context,en,pt
OPEN,Menu,Open,Abrir-menu
```

The importer reads every column after the first as a **locale**. So it produces
a `.translation` file for a language called `context` (`X17`), whose translation
of `OPEN` is the literal word `Menu` (`X18`). No error is printed.

It is not an inert file, either. `TranslationServer.standardize_locale("context")`
returns `context` — the engine accepts it as a language name (`X19`) — and
`set_locale("context")` selects it, after which `tr("OPEN")` returns `Menu`
(`X20`). Your other columns are unharmed (`X21`). The project just ships one
extra language nobody wrote, which any locale-selection UI built from the
translation list will offer to players.

## Two things that changed between 4.4 and 4.7

If you are writing a tool or an editor plugin that inspects translations, these
will bite you before the contexts do.

- A `.po` loads as class `TranslationPO` on 4.2, 4.3 and 4.4, and as plain
  `Translation` on 4.7, where `ClassDB.class_exists("TranslationPO")` is
  `false` (`X22`). Code that branches on the class name stops recognising
  gettext catalogues, and stops recognising them *quietly* — the branch just
  never runs.
- `get_translated_message_list()` on that same `.po` returns **1** of its 3
  entries on 4.2–4.4 and **3** on 4.7 (`X23`). On the older binaries the
  contextual entries are not in the list, so an audit that walks a catalogue
  through that list sees one string in three.

While you are there: `OptimizedTranslation.get_message_count()` returns `0` on
all four binaries for a resource that holds two messages (`X2`). A check that
counts a CSV translation that way reports an empty file.

## What to do

- **Pick one back-end for any key that needs a context.** A context is a `.po`
  feature. If a key needs one, that key belongs in the catalogue and nowhere
  else — a duplicate row in a CSV will answer first and win.
- **If you must ship both, register the `.po` first** and treat the file order
  in `project.godot` as load-bearing, not cosmetic.
- **Grep your CSV-only project for a second argument to `tr(`.** Every one of
  them is doing nothing, and it has been doing nothing since the day it was
  written.
- **Never add a column to a CSV that is not a locale.** Anything you put there
  becomes a language.

## Re-run this page

```sh
docs/verify_context.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

It builds a throwaway project in a temp directory, writes the two CSVs and the
`.po`, runs a real editor import pass, and prints PASS or FAIL for each of the
23 claims with the value it measured. It exits non-zero if any claim stops
holding, so a newer Godot tells you exactly which line of this page went stale.

## Related

- [Why the translation is not loading for my locale](why-the-translation-is-not-loading-for-my-locale.md)
  — the other way a CSV column heading invents something: a `pt-br` column is
  not Brazilian Portuguese.
- [Why `tr_n()` always returns the singular](why-tr_n-always-returns-the-singular.md)
  — the same split back-end, on plurals instead of contexts.
- [Why a key that IS in your CSV still shows up untranslated](why-a-key-in-your-csv-still-shows-untranslated.md)
  — `tr()` and the node's own `text` do not go through the same door.
- [Why your untranslated string comes out in another language](why-your-untranslated-string-comes-out-in-another-language.md)
  — what happens to `X11`'s raw key when a fallback locale is configured.

---

Part of **[LocGuard Lite](../README.md)** — free localization QA for Godot 4.
It reports keys that no loaded translation carries. It does not detect the cases
on this page: there the key is present, and it is the context that is dropped,
ignored or answered by the wrong file.
