# Why editing `strings.csv` changes nothing in your game

You edited the translation CSV, ran the game, and the old text is still on the
screen. The four answers you will find are "restart the editor", "delete
`.godot/`", "reimport it by hand" and "your CSV is malformed". Three of them are
about the import — and in the most common version of this problem the import
worked perfectly and **nothing in your project loads the result**.

Everything below is measured, not remembered. The claim ids (`R1`…`R14`) are
the checks in [`verify_csv_reimport.gd`](verify_csv_reimport.gd); run
[`verify_csv_reimport.sh`](verify_csv_reimport.sh) against your own binary and
it will print the same list with PASS/FAIL for your version:

```
docs/verify_csv_reimport.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

**Measured on Godot 4.2, 4.3, 4.4 and 4.7 stable (official Linux builds),
2026-09-08: 14/14 on each of the four.** Every import in the run is done by that
same binary as a headless editor, so "what the importer does" is the real
importer, not a description of it.

---

## 1. The import succeeds and the game still shows the key

Drop `strings.csv` into a project and the importer writes one file per column
(`R1`): a CSV headed `keys,en,fr` becomes `strings.en.translation` and
`strings.fr.translation`, right next to the CSV.

What it does **not** do is register them. After the import,
`internationalization/locale/translations` is still empty (`R2`) — the setting
the engine actually reads at startup. So `tr("GREETING")` returns `GREETING`,
in every locale, with no error, no warning and no message about a missing file
(`R3`). The screen shows your key names and the Output panel shows nothing.

The proof that the CSV is fine: load that exact file by hand and it answers
immediately (`R4`).

```gdscript
TranslationServer.add_translation(load("res://strings.fr.translation"))
TranslationServer.set_locale("fr")
print(tr("GREETING"))   # Bonjour
```

You are not meant to do that in a shipping project — the fix is **Project →
Project Settings → Localization → Translations → Add**, which writes the files
into that setting. But it tells you which half of the pipeline is broken, and
it is never the half people blame.

With the files listed, both locales answer (`R5`).

## 2. Value edits do reach the game — after a cold start

Change a value in the CSV, start the editor once, run: the new text is there
(`R6`). The import is content-gated, not name-gated: the CSV import records a
`source_md5` under `.godot/imported/` (`R14`), so a cold start notices the file
changed and reimports it.

That is also why the "delete `.godot/`" advice is harmless here: a clone with no
`.godot/` and no `.translation` files at all — the usual `.gitignore` for a team
repo — rebuilds every one of them on a single editor start (`R12`, `R13`).

There is a real open bug about the *other* case: a CSV edited in an external
editor **while Godot is running** is not picked up until a restart or a manual
reimport ([godotengine/godot#115486][i], reported on 4.6, with an open fix in
[#115595][p]). This document does not measure that one and does not claim it,
in either direction: a headless editor imports nothing that appears while it is
running — not an edited file and not a brand new one — so a headless run cannot
tell "the engine missed the change" apart from "there was no scan at all". The
verifier prints that control as a NOTE. If your edit is not showing up, restart
the editor once before believing anything else.

## 3. The part that ships broken: deleting a column deletes nothing

This is the failure worth the page. Delete the `fr` column from the CSV — the
whole language, the way you would when a translation is dropped or a column is
renamed — and reimport.

- `strings.fr.translation` **is still there** (`R7`). Nothing removes it.
- It still answers, with the text of the column that no longer exists (`R8`).
- `en` in the same file did update, so one pass leaves the project half-updated
  (`R9`).
- `strings.csv.import` drops the file from `dest_files` (`R10`) while
  `project.godot` still lists it in `internationalization/locale/translations`
  (`R11`). Two files in your project now disagree about which languages exist.
- The engine says nothing at all about any of this.

The consequence is not a missing translation, which someone would notice; it is
a **language that keeps shipping after you removed it**, frozen at the text it
had on the day you deleted the column. Rename `fr` to `fr_CA` and you get the
same thing with an extra name: the old file stays, still listed, still
answering `fr`.

The cleanup is manual, and it is two steps, not one: delete the orphan
`*.translation` file **and** remove its line from Project Settings →
Localization → Translations. Doing only the second leaves a file the exporter
no longer packs; doing only the first leaves a setting pointing at a file that
is gone.

## 4. What this means for a QA pass

Three of the failures above are invisible to a test that runs the game and
reads the screen, because in all three the screen is *plausible*: keys look
like a missing-translation bug you would catch, but a stale locale looks like a
finished translation, and a dropped column looks like nothing at all.

They are visible in the files, which is where a linter can look:

- a `.translation` on disk with no matching column in any CSV — orphan;
- a path in `internationalization/locale/translations` that does not exist —
  dead entry;
- a CSV imported into a project that lists none of its outputs — the case in
  section 1.

[LocGuard Lite](https://github.com/leobaray/locguard-lite) checks the CSV
against the strings your code and scenes actually use (missing keys, empty
values); the three checks above are file-level and are **not** in it today —
naming that honestly is the point of this page, and this measurement is what a
rule would have to be built on.

## Related

- [Why the translation is not loading for my locale](why-the-translation-is-not-loading-for-my-locale.md)
  — a column headed `pt-br` does not import as Brazilian Portuguese, measured
  through the same importer.
- [Why the locale change does not update the UI](why-the-locale-change-does-not-update-the-ui.md)
  — `TranslationServer.set_locale()` and what does not move when you call it.

[i]: https://github.com/godotengine/godot/issues/115486
[p]: https://github.com/godotengine/godot/pull/115595
