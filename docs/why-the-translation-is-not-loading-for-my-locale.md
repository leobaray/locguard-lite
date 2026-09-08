# Why the translation is not loading for my locale

You added a column (or a `.po`) for Brazilian Portuguese, set the locale, and
the game still shows English — or shows the wrong Portuguese. The usual forum
answers are "name it `pt_BR`", "name it `pt-BR`", "use the exact code the OS
reports", and "Godot only matches exact locales". Two of those four are wrong,
one is right for the wrong reason, and none of them is measured.

This page is measured. Every claim below has an id, and every id is a `check()`
in [`verify_locale_matching.gd`](verify_locale_matching.gd). Run it against your
own engine build:

```
docs/verify_locale_matching.sh /path/to/Godot_v4.4-stable_linux.x86_64
```

The script builds a throwaway project in a temp directory, writes a `strings.csv`
whose column headers are the four spellings people actually write, runs your
binary once in editor mode so the **real importer** produces the `.translation`
files, then runs the claims against them. It exits non-zero if any claim fails.

Measured 22/22 on **4.2, 4.3, 4.4 and 4.7** (official Linux builds). Two claims
read the build and assert different things on either side of 4.4, because the
engine's behaviour genuinely changed there — see M17/M18.

---

## The short answer

Godot never looks for the locale string you typed. It first rewrites it, and the
rewrite is **case-sensitive in a way nothing warns you about**: `pt-br` becomes
`pt`, while `pt-BR` becomes `pt_BR` (M1, M2). Then it does not require an exact
match at all: it scores every loaded translation against the locale and takes the
best one, so `pt` answers a `pt_BR` player and `pt_BR` answers a `pt` player
(M10, M11).

So the two failures people actually hit are the opposite of what the forum
answers assume:

- the translation **is** loaded, under a locale you did not intend (M1, M8, M20);
- or the translation can **never** be selected, because the header was written in
  a shape no locale matches (M5, M6, M22).

---

## What the engine does to your locale string first

**M1** — `standardize_locale("pt-br")` returns `"pt"`. A lowercase country code
is **dropped**, not corrected. You do not get a warning and you do not get
`pt_BR`; you get the country-less locale.

**M2** — `standardize_locale("pt-BR")` returns `"pt_BR"`. The same string with
the country in capitals keeps it. The difference between M1 and M2 is two
keystrokes and it decides whether your Brazilian column exists.

**M3** — the same rule, second language: `"en-us"` → `"en"`, `"en-US"` → `"en_US"`.

**M4** — `standardize_locale("zh-hans-cn")` returns `"zh"`. When the script and
country are lowercase, both are dropped, and a file you meant for Simplified
Chinese in China becomes plain Chinese.

**M5** — `standardize_locale("PT_BR")` returns `"PT_BR"`. An uppercase *language*
code is **not** lowercased. Nothing normalizes it into `pt_BR`.

**M6** — and `"PT_BR"` is not a spelling of `"pt_BR"`:
`compare_locales("pt_BR", "PT_BR")` is `0`, and `compare_locales("pt", "PT_BR")`
is `0`. Zero means no match at any level. A translation stored under `PT_BR` is
unreachable by every locale.

**M7** — `standardize_locale("no")` returns `"nb"`. Norwegian is remapped, so a
file named `no` answers players whose locale is `nb`.

**M8** — this is not a static-analysis quirk: `set_locale("pt-br")` followed by
`get_locale()` returns `"pt"` at runtime. The country you typed is gone before
any lookup happens.

**M9** — and it is not something you can preserve on the resource either.
Assigning `Translation.locale = "pt-BR"` stores `"pt_BR"`: the setter
standardizes, so the resource never keeps your spelling.

## Which loaded translation actually answers

Godot scores candidates instead of requiring equality. The consequences are worth
knowing before you add per-country files:

**M10** — with only `pt` loaded and the locale set to `pt_BR`, `tr()` returns the
`pt` text. A country-less translation answers a country locale.

**M11** — with only `pt_BR` loaded and the locale set to `pt`, `tr()` returns the
`pt_BR` text. It works in the other direction too.

**M12** — with only `pt_BR` loaded and the locale set to `pt_PT`, `tr()` still
returns the `pt_BR` text. The **wrong country** answers when it is the only
candidate in that language. This is why "it works" is not evidence that your
locale is set up correctly.

**M13** — with the locale set to `es` and only `pt_BR` loaded, `tr("K")` returns
`"K"`: an unrelated language gets the key itself back. Seeing raw keys on screen
means no translation in that *language* was loaded — it never means the country
code was wrong.

**M14** — the fall-through is per **message**, not per file. With `pt` holding
`A` and `B` and `pt_BR` holding only `A`, a `pt_BR` player gets `A` from `pt_BR`
and `B` from `pt`. A partial country file is a legitimate way to ship overrides;
you do not have to duplicate every string.

**M15** — with both `pt` and `pt_BR` loaded, the exact match wins on both sides:
locale `pt_BR` gets the `pt_BR` text, locale `pt` gets the `pt` text.

**M16** — a same-language partial match always scores above zero and below the
exact match (`compare_locales("pt_BR","pt_BR")` is `10`), while
`compare_locales("pt","es")` is `0`. The **language** is what makes a translation
eligible; the country only ranks the eligible ones.

## The ranking changed in 4.4, and it changes what players read

Take a `pt_PT` player with both a generic `pt` file and a `pt_BR` file loaded.
Neither is an exact match.

**M17** — on **4.2 and 4.3** the two candidates **tie** (`pt` scores 1, `pt_BR`
scores 1), so nothing about the locale decides it. On **4.4 and 4.7** the tie is
gone: `pt` scores 5 against `pt_BR`'s 4, and "no country" beats "wrong country".

**M18** — and on 4.2/4.3 the tie is broken by the **order the translations were
loaded**: `pt` then `pt_BR` returns the Brazilian text, `pt_BR` then `pt` returns
the generic text. Same project, same player, two different strings, decided by
the order of `internationalization/locale/translations` in `project.godot`. On
4.4 and 4.7 both orders return the generic `pt` text.

Practical reading: if you ship a generic `pt` **and** a `pt_BR`, upgrading a 4.3
project to 4.4 can change what a `pt_PT` (or any other non-Brazilian Portuguese)
player sees, with no edit on your side and nothing in the changelog pointing at
your project. The verifier reads the build and asserts the correct branch, so it
tells you which side you are on rather than repeating a number.

## What a CSV column header becomes on disk

These four claims run against files produced by your binary's own import pass,
from a `strings.csv` whose header row is `keys,en,pt-br,pt-BR,PT_BR`.

**M20** — the column written `pt-br` imports to `strings.pt.translation`, with
`locale == "pt"`. The country you typed is in neither the file name nor the
resource. If this is your only Portuguese column, every Portuguese player gets it
(by M10) — which looks like success until you add a real `pt_PT` and the two
start competing.

**M21** — the column written `pt-BR` imports to `strings.pt_BR.translation`, with
`locale == "pt_BR"`. One capital letter apart from M20, and a different file.

**M22** — the column written `PT_BR` imports to a real file with `locale ==
"PT_BR"`, which no locale can ever select (`compare_locales("pt_BR","PT_BR")` is
`0`, M6). The import **succeeds**. There is no error, no warning, and a
`.translation` sitting in your export that reaches nobody.

**M23** — with all four columns imported and loaded, locale `pt_BR` reads the
`pt-BR` column and locale `pt` reads the `pt-br` column. The `PT_BR` column is
dead weight, confirming M22 through the runtime path rather than the score alone.

---

## What to check, in order, when a locale looks untranslated

1. Print `TranslationServer.get_locale()` right after you set it. If it is
   shorter than what you typed, M1/M8 already happened.
2. Print `TranslationServer.get_loaded_locales()`. Anything in there with a
   capitalised language (`PT_BR`, `EN`) is unreachable (M5, M6) — fix the CSV
   header or the `.po` name, not the code.
3. If you see raw keys on screen, the *language* is missing, not the country
   (M13). If you see the wrong text, the language matched and the country ranked
   (M12, M17).
4. If you ship both a country-less and a country file for the same language,
   check your engine version before trusting what you see on a third country
   (M17, M18).

---

Part of [LocGuard Lite](https://github.com/leobaray/locguard-lite) — a free,
MIT-licensed Godot 4 addon that finds untranslated strings in your scenes and
scripts before players do. Companion page:
[why the locale change does not update the UI](why-the-locale-change-does-not-update-the-ui.md).
