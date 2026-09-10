# Why your game starts in the wrong language on someone else's machine

It is right on your machine. A player in Brazil opens it and gets English. A
player on a locked-down office image gets English too. Someone on a German
system gets German menus in a build you thought only shipped English and
Portuguese. Nothing errors, nothing logs, and `TranslationServer.get_locale()`
in your own debug print says the locale is exactly what you expected.

The usual answers — "read `OS.get_locale()`", "compare it to your list",
"Godot defaults to English" — each describe a different engine than the one you
shipped. The value the engine reports and the text it is actually serving are
two separate things, and the code most projects write to bridge them compares
the wrong pair.

Every claim below was measured by
[`verify_startup_locale.sh`](verify_startup_locale.sh) on Godot **4.2, 4.3, 4.4
and 4.7** stable, run on 2026-09-10: 26/26 on each of the four, across 16
separate process launches, because a machine locale is chosen once at startup
and cannot be varied inside one run. The ids (`S1`, `S2`, …) are the ids the
script prints, so you can re-run any single line on your own binary.

The test project ships three languages — `en`, `pt`, `de` — and no country
variants at all. That is the ordinary case: almost nobody ships a `pt_BR`
column, and almost every player's machine asks for one.

## `get_locale()` reports the request, not the answer

On a machine with `LANG=pt_BR.UTF-8`, the Portuguese arrives: `tr()` returns the
`pt` column even though nothing named `pt_BR` was shipped (`S1`). The country is
dropped during matching and the language still wins.

But `TranslationServer.get_locale()` returns **`pt_BR`** (`S2`) — the string the
machine asked for, not the `pt` that is serving the text. And `pt_BR` is not in
`get_loaded_locales()` (`S2b`), which stays exactly the list you shipped no
matter what machine it runs on (`S3`).

So this, which is the shape almost every language menu and every "is this
language supported" check is written in, is wrong:

```gdscript
# Answers "no" on a machine that is, right now, showing Portuguese.
if TranslationServer.get_locale() in TranslationServer.get_loaded_locales():
	...
```

The two sides are not the same kind of value. The left is a request, in the
machine's spelling. The right is your shipping list.

## The case where it disagrees with the screen

Put the same build on a Japanese machine, with no Japanese shipped. `tr()`
returns the English fallback, with no error and no warning (`S4`). Reasonable.

`TranslationServer.get_locale()` still answers **`ja_JP`** (`S5`).

That is the whole bug report you will get from a player: *"the game says it is
in Japanese and it is in English."* Both halves are true. A settings screen
reading `get_locale()` prints Japanese; the labels next to it are English. If
you want to display the language the player is actually reading, `get_locale()`
is not the value — the loaded locale that matched is, and the only way to know
it is to do the matching yourself against `get_loaded_locales()`.

## `OS.get_locale()` is the environment, not a language code

`OS.get_locale()` hands back the raw value with nothing normalised. On
`LANG=pt_br.UTF-8` — lowercase country, which people really do have — it returns
`pt_br` (`S6`) while the TranslationServer has already resolved the same value
to `pt` (`S6b`). Two engine APIs, two different answers about the same machine,
in the same process.

The sharper case is `LANG=C`, which is what you get on build servers, minimal
Docker images, some SSH sessions and plenty of corporate Linux images.
`OS.get_locale()` and `OS.get_locale_language()` both return the literal string
**`C`** (`S7`). It is not a language code. This is false:

```gdscript
# False on a machine that is, by any human description, English.
if OS.get_locale_language() == "en":
	...
```

(`S7b`.) The TranslationServer does better with the same input: it resolves `C`
to `en` and serves English (`S8`).

Two more edges, because they behave differently from each other:

- `LANG` **unset entirely**: `OS.get_locale()` returns `en` on all four versions
  (`S9`).
- `LANG` **set to the empty string**: `OS.get_locale()` returns an empty string
  on all four (`S10`). On 4.7 the TranslationServer recovers and reports `en`;
  on 4.2, 4.3 and 4.4 it is left holding an **empty locale** (`S10b`). Same
  machine, same build, different engine version, different answer.

## Only `LANG` is read

This is the part that costs a day when you try to reproduce a player's report by
exporting a variable in a shell:

| Variable | Effect on Godot |
|---|---|
| `LANG` | Selects the locale (`S1`) |
| `LC_ALL` alone | None (`S11`) |
| `LANGUAGE` alone | None (`S12`) |
| `LC_MESSAGES` alone | None (`S13`) |
| `LC_ALL` set next to `LANG` | None — `LANG` still wins (`S14`) |

`LC_ALL` overriding everything else is the POSIX convention, and it is the first
thing anyone reaches for. Godot does not follow it. If you tested a locale by
setting `LC_ALL`, you tested nothing — the run you observed was your own default
locale, and it passed for that reason.

## The two overrides that do work, and one you must not ship

The command line flag works: `-l de` (or `--language de`) makes the game run in
German regardless of the machine (`S15`). It also accepts a locale you do not
ship — `-l ja` reports `ja` and serves the fallback text (`S16`) — so it will
never tell you that you asked for something that does not exist.

The project setting `internationalization/locale/test` also overrides the
machine locale (`S17`), and `-l` wins over it (`S18`).

`locale/test` is the field that quietly ruins a week. It is meant as a debug
override, it lives in `project.godot`, and it is invisible unless you look for
it: a value left there from a debugging session makes every one of your runs
report and serve that language while the machine locale is ignored. If your
whole team sees the wrong language and no player does — or the reverse — read
that line first.

**Measurement limit, stated rather than assumed:** `S17` and `S18` were measured
with an editor build (`OS.has_feature("editor")` is true). This page does not
measure whether a release export template honours `locale/test`, and you should
not depend on either answer: clear the field before shipping.

## `locale/fallback` decides what "wrong language" looks like

There is no English rule in the engine. There is a project setting, and it
happens to default to `en`.

Set `internationalization/locale/fallback` to `de` and the unmatched Japanese
machine gets **German** (`S19`). Whatever locale is named there is what every
player you did not translate for will read.

Name a locale you do not actually ship — a typo, or a language you removed and
forgot to unset — and the unmatched machine shows the **raw keys** (`S20`):
`GREET` on the button instead of any words at all. The run is otherwise
completely ordinary, with the machine locale reported as usual and no error
anywhere (`S20b`).

That is the single worst-looking failure in this whole page, it ships silently,
and it is one wrong string in one project setting.

## What to check, in order

1. `internationalization/locale/fallback` — does it name a locale you ship?
   If not, unmatched players see keys (`S20`).
2. `internationalization/locale/test` — is it empty? If not, it is deciding
   your language, not the machine (`S17`).
3. Any comparison of `TranslationServer.get_locale()` against
   `get_loaded_locales()` — it is comparing a request to a shipping list and
   will be wrong for every player with a country in their locale (`S2`, `S2b`).
4. Any comparison of `OS.get_locale_language()` against a language code — it
   returns `C` on a large class of machines (`S7`).
5. Reproduction commands that set `LC_ALL` — they measured nothing (`S11`,
   `S14`). Use `LANG`, or `-l`.

Changing the locale afterwards from code does work as documented:
`TranslationServer.set_locale("de")` moves both `get_locale()` and the next
`tr()` in the same frame (`S21`). What that does **not** do is update text
already on the screen — that is a separate problem, measured in
[why the locale change does not update the UI](why-the-locale-change-does-not-update-the-ui.md).

## Related pages in this repository

- [Why the translation is not loading for my locale](why-the-translation-is-not-loading-for-my-locale.md)
  — how a locale string is matched against the ones you shipped.
- [Why a key that IS in your CSV still shows up untranslated](why-a-key-in-your-csv-still-shows-untranslated.md)
- [Why your untranslated string comes out in another language](why-your-untranslated-string-comes-out-in-another-language.md)

---

Part of [LocGuard Lite](https://github.com/leobaray/locguard-lite), a free
Godot 4 addon that scans a project for localization problems. The verifier for
this page is [`verify_startup_locale.sh`](verify_startup_locale.sh); it builds a
throwaway project in a temp directory and touches nothing of yours.
