# Why your translation shows boxes, or nothing at all

Your Chinese translator sends the table back. You import it, run the game, and
the menu is full of empty rectangles. Or it is simply blank, with the right
amount of empty space where the words should be. Nothing in the Output panel
says anything is wrong.

The instinct is to go back to the table: wrong encoding, wrong column, the
import failed. This page measures what is actually happening, which is none of
those. Every claim below is checked by
[`verify_font_coverage.sh`](verify_font_coverage.sh) on Godot **4.2, 4.3, 4.4
and 4.7**, official Linux builds:

```
docs/verify_font_coverage.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

The script builds a throwaway project, so it touches nothing of yours. It
exits non-zero if any claim fails on your build.

## The short version

The translation is fine. The **font** is not. The font the engine ships with
covers Latin, Cyrillic and Greek, and does not cover Chinese, Japanese, Thai
or Arabic. When a font cannot draw a character, Godot quietly goes and borrows
one from the operating system it is running on. That is why it works on your
machine, and why what your player sees depends on which fonts happen to be
installed on theirs.

Nothing in the project changes between the two. There is no error, no warning,
no failed import, and every automatic measurement of the text still returns a
sensible number.

## The premise: the string really is translated

The check project imports a CSV with a Chinese, Thai, Russian and Hebrew
column through the engine's own importer, and asks for it the ordinary way
(`F1`–`F4`):

| claim | call | result |
|---|---|---|
| `F2` | `tr("PLAY")` with locale `zh` | `开始游戏` |
| `F3` | `tr("PLAY")` with locale `th` | `เริ่มเกม` |

So nothing below can be blamed on a missing row, a bad locale or a failed
import. The right string was found, returned, and handed to the screen.

## What the engine's own font can and cannot draw

`ThemeDB.fallback_font` is the font every new project uses until you set your
own; the run reports which font that is (`F5`). On all four builds it is Open
Sans. Asked directly, character by character
(`F6`–`F13`):

| character | script | `has_char` |
|---|---|---|
| `A` | Latin | yes |
| `á` | Latin, accented | yes |
| `Д` | Cyrillic | yes |
| `Ω` | Greek | yes |
| `开` | Han | **no** |
| `あ` | Hiragana | **no** |
| `ก` | Thai | **no** |
| `م` | Arabic | **no** |

This is the whole story in one table. A European or Brazilian team checks
Portuguese, Spanish, German and Russian, sees all four work, and concludes the
localization pipeline is sound. It is — for the four scripts that font covers.

**And the table is not the same on every build.** Hebrew `א` is absent on 4.2,
4.3 and 4.4 and present from 4.5 on (`F14`). The same project, the same table
and the same translator, exported with a different engine, keeps or loses an
entire script.

## Where the glyph on your screen actually comes from

Every font in Godot carries a switch called `allow_system_fallback`, and on the
default font it is on (`F15`). Nothing in a new project turns it off. With it
on, a character the font lacks is looked up in the fonts installed on the
machine running the game.

The shaped line records which font each glyph came from, so this is a number
rather than an impression. Shaping one Latin `A` and one Han `开` with the
project's own font (`F16`–`F19`):

| claim | glyph | drawn by |
|---|---|---|
| `F18` | `A` | the project's own font |
| `F19` | `开` | **never** the project's own font |

On the machine that produced this page the engine did find a Han font in the
operating system, and the run reports its id as a note (`F20`) together with
the system font the engine was given (`F21`). Those two lines are the only ones
on this page whose value depends on the machine — which is exactly the point
being made.

## The player who does not have that font

Turning `allow_system_fallback` off reproduces, on this machine, the machine of
a player who does not have the font. It is the same switch the engine itself
uses, not an approximation. With it off (`F22`–`F26`):

| claim | measurement | result |
|---|---|---|
| `F22` | `A` still drawn by the project's font | yes |
| `F23` | `A` keeps the same glyph id | yes |
| `F24` | `开` drawn by any font at all | **no** |
| `F25` | the glyph id for `开` | `24320`, the codepoint itself |
| `F26` | its advance width | greater than zero |

The Latin control is the important half of that table: the switch changes
nothing for `A`, so what it does to `开` is a real difference and not a broken
measurement.

A glyph id equal to the codepoint is not a glyph. It is the engine saying *I
have nothing to draw here*, and depending on the platform that comes out as an
empty rectangle, a question mark, or nothing. It still advances the line, so
the text is laid out, spaced and centred around characters that are not there.

## Why nothing you can automate catches it

This is the part that costs a release. With the glyph missing (`F27`–`F29`):

- `get_string_size()` on the untranslatable string returns a **positive width**.
  Every "does this label overflow its box" check passes.
- A `Label` holding it reports a **positive minimum size**. Every layout
  measurement passes.
- `tr()` still returns the correct Chinese. Every "find the untranslated
  string" scan, including ours, passes.
- The engine prints **nothing**. The script asserts this over the whole run:
  if the engine emits any error or warning while the missing glyph is shaped,
  the run fails rather than passes.

Translated, delivered, laid out, measured, silent — and not on the screen.

## What to do about it

- **Embed a font that covers the script you are shipping.** Add the `.ttf` or
  `.otf` to the project, set it as the default font in your theme, and the
  glyph stops depending on the player's machine. For Chinese, Japanese and
  Korean this is a large file, and that is the real cost of those languages.
- **Use `fallbacks` rather than one font per language.** A `Font` has a
  `fallbacks` array. Keep your Latin font as the main one and add the CJK or
  Thai font behind it, instead of swapping the theme font per locale.
- **Test with system fallback off.** Setting `allow_system_fallback = false` on
  your font while you develop turns "works here" into "works everywhere",
  because you stop borrowing from your own operating system.
- **Check the character, not the string.** `font.has_char(codepoint)` over the
  characters your table actually contains is a check you can run in a few lines
  and it is the only one on this page that would have caught the problem.

## What LocGuard Lite does and does not cover

Honestly stated, as on every page here: the free addon compares your keys
against your table. It does **not** open your font and ask whether the
characters in a translated column can be drawn, so a project whose Chinese
column is perfect and whose font has no Han glyphs passes it clean. That gap is
real, it is measured on this page (`F29`), and it is written down here rather
than left implied.

## Reproducing

```
docs/verify_font_coverage.sh /path/to/Godot_v4.2-stable_linux.x86_64
docs/verify_font_coverage.sh /path/to/Godot_v4.3-stable_linux.x86_64
docs/verify_font_coverage.sh /path/to/Godot_v4.4-stable_linux.x86_64
docs/verify_font_coverage.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

29 ids: 26 assertions and 3 notes whose value depends on the machine.
26 passes, 0 fails, 0 skips on each of the four builds. Each run prints one line
per claim id used on this page and a summary line. The summary line is the
gate: if the script does not reach it, nothing was measured, and the script
reports that as an error rather than a pass.
