# Why your untranslated string comes out in another language

You ship a Portuguese build. A menu item is still in English. The key is not
missing — nothing on screen shows a raw identifier — so the obvious conclusion
is that the translation did not load, and the next hour goes into locale codes
and reimports.

The translation loaded. That English string is the engine's **fallback**, doing
exactly what it was configured to do by a setting nobody in the project chose.

Two things make this expensive. The fallback is on in every Godot 4 project by
default, and it hides the one symptom you would have recognised: a missing
translation never looks missing. And the API the forums tell you to reach for —
`TranslationServer.set_fallback()` — does not exist in Godot 4, so the fix that
sounds right does not run at all.

Everything here is measured, not remembered. The claim ids (`F1`…`F13`) are the
checks in [`verify_translation_fallback.gd`](verify_translation_fallback.gd);
run [`verify_translation_fallback.sh`](verify_translation_fallback.sh) against
your own binary and it prints the same list with PASS/FAIL for your version:

```
docs/verify_translation_fallback.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

**Measured on Godot 4.2, 4.3, 4.4 and 4.7 stable (official Linux builds),
2026-09-10.** Each binary is booted three times — with the default fallback,
with `"fr"`, and with the fallback turned off — because the setting is read at
startup and cannot be measured any other way (`F11`). That is 12 claims on the
default boot and 13 on each of the other two, all passing on all four builds,
with no difference in behaviour between versions.

---

## 1. The function you were told to call is not there

Search for a Godot fallback and you will be told to call
`TranslationServer.set_fallback("en")`. Measured against the four binaries,
`TranslationServer` exposes **zero** methods whose name contains `fallback`
(`F1`). The pair `set_fallback()` / `get_fallback()` is Godot 3.

This does not fail the way a wrong call usually fails. GDScript resolves method
names at parse time, so a single `set_fallback()` anywhere in a file stops the
**whole file** from loading:

```
SCRIPT ERROR: Parse Error: Static function "set_fallback()" not found in base "GDScriptNativeClass".
ERROR: Failed to load script "res://probe.gd" with error "Parse error".
```

Everything else in that script — including whatever you added to debug the
problem — stops running too. If you tried this and concluded "the fallback does
nothing in my project", the fallback is not what you measured.

The real control is a **project setting**: `internationalization/locale/fallback`.
It is defined in every project and its built-in default is `"en"` (`F2`) — so it
is doing something in your project whether or not anyone chose a value.

You have probably never seen it. Measured on all four builds, the setting
carries the editor usage flag but **not** `PROPERTY_USAGE_EDITOR_BASIC_SETTING`
(`F2b`), which is why Project Settings lists it only once **Advanced Settings**
is switched on, under Internationalization → Locale.

## 2. What the fallback actually does

**An unrelated locale reads the fallback language, not the key.** With a
translation loaded for the fallback locale and nothing for the player's locale,
the lookup returns the fallback text (`F3`). This is the whole illusion: the
screen is full of readable words, so nothing looks broken.

**The decision is made per message, not per file.** One locale, two keys: the
key your CSV translates comes back translated, and the key it does not comes
back in the fallback language — in the same frame, from the same loaded
translation (`F4`). A half-translated screen is not two bugs. It is one missing
row.

**Only the fallback locale is consulted.** Load the fallback language and a
third language, then set an unrelated locale: you get the fallback, never the
third (`F5`). "Godot tries the other translations" is not a thing it does.

**The fallback is a locale, not a search order.** A key that exists only in some
other loaded translation, and not in the fallback locale, comes back as the raw
key (`F10`). Having the string *somewhere* in the project buys you nothing.

**A key absent everywhere comes back as itself** (`F9`). That is the only case
where the player sees your identifier, which is why seeing an identifier is
comparatively good news: it is the one failure mode that is visible.

## 3. The blank cell, which is the version that ships

A translator leaves a cell empty. Nothing errors. The row is there.

The empty value is genuinely **stored** — the message count includes it, the key
is in `get_message_list()`, and `get_message()` hands back a zero-length string
(`F6`). But at lookup time an empty translation counts as **absent**, so the
lookup falls through to the fallback: the player reads the fallback language
(`F7`).

So the blank cell has no visible symptom at all. It does not blank the label. It
does not show the key. It shows a fluent sentence in the wrong language, on a
screen where every neighbouring string is correct. The only way to catch it is
to look at the CSV.

You see the raw key from a blank cell only when the **fallback cell is blank
too** (`F8`) — which is what happens when the empty column is the fallback
language itself. That is the case measured in
[Why a row in `strings.csv` never reaches the player](why-a-row-in-strings-csv-never-reaches-the-player.md)
(`D5`), where the empty cell is the English one. Same blank cell, two completely
different symptoms, decided by which column it is in.

## 4. Why editing the setting seems to do nothing

`TranslationServer` reads `internationalization/locale/fallback` **once, at
startup**. Writing it with `ProjectSettings.set_setting()` at runtime changes
nothing, and calling `set_locale()` again afterwards does not re-read it
(`F11`). A project booted with the fallback set to `"fr"` returns French where
the default boot returns English (`F12`) — same code, same translations, and the
only difference is the value the project started with.

Set it in Project Settings and restart. There is no runtime path.

## 5. Turning it off is a debugging tool

Boot with `internationalization/locale/fallback` set to the **empty string** and
the fallback is off: an untranslated string comes back as its own key (`F13`),
and every claim in section 2 collapses to the key (measured in the third boot of
the verifier).

That is worth doing deliberately during a localization pass, in a scratch
branch. With the fallback off, a missing translation is loud — the screen fills
with `MENU_START`-shaped strings you can see at a glance and count. With it on,
the same project looks finished.

Do not ship it that way. A player who hits a missing row should read *something*.
The point is that "looks fine when I play it" is not evidence that the
translation is complete, and with the default fallback it never can be.

---

## What to check, in order

1. **Is the string actually missing?** Look for the key in the CSV column for
   that locale. A wrong language on screen means missing or empty, not "not
   loaded".
2. **Is the cell empty rather than absent?** An empty cell behaves as absent
   (`F7`) and is invisible in the running game.
3. **Only then, suspect loading.** If *every* string in a locale is wrong, this
   page is not your problem — see the related pages below.
4. **Never** call `set_fallback()`. It does not exist and it takes the file down
   with it (`F1`).

[LocGuard Lite](https://github.com/leobaray/locguard-lite) reports both shapes
this page is about — `missing-key` for a string with no row, and
`empty-translation` for a locale cell left blank — from inside the editor,
before the build. Those are precisely the two states the fallback makes
invisible at runtime.

## Related

- [Why a row in `strings.csv` never reaches the player](why-a-row-in-strings-csv-never-reaches-the-player.md)
  — the blank cell seen from the other side, plus the rows the importer drops.
- [Why the translation is not loading for my locale](why-the-translation-is-not-loading-for-my-locale.md)
  — when *everything* is in the wrong language, the column header is usually why.
- [Why editing `strings.csv` changes nothing in your game](why-editing-strings-csv-changes-nothing.md)
  — the import succeeds and nothing in the project loads the result.
- [Why a key that IS in your CSV still shows up untranslated](why-a-key-in-your-csv-still-shows-untranslated.md)
  — `tr()` and the node's own `text` do not go through the same door.
