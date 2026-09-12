# Why your Arabic build mirrors the whole interface, or refuses to, and your code says nothing either way

You add Arabic. The strings arrive, the font has the glyphs, `tr()` returns the
right sentence. You run the build and the entire interface is inside out: the
back button is on the right, the health bar fills the other way, the inventory
row you carefully ordered reads backwards. You did not write a line of code about
any of it.

Then a teammate on a different Godot version runs the same build and the
interface is not mirrored at all.

Both are the engine working as designed. Selecting a right-to-left locale flips
the layout of every `Control` in your game, and the condition under which it
flips changed between versions. Nothing is printed when it happens, and the
notification you would subscribe to in order to react to it exists and is never
delivered.

Every claim below was measured by [`verify_rtl_layout.sh`](verify_rtl_layout.sh)
on Godot **4.2, 4.3, 4.4 and 4.7** stable, run on 2026-09-12. The script builds
throwaway projects, imports them with the binary under test, runs them headless
and reads the positions back off real `Control` nodes after the engine's own
layout pass. The ids (`M1`, `M2`, …) are the ids the script prints, so you can
re-run any single line against your own binary.

## The text is not the problem

The Arabic string itself is handled correctly on every version tested. Shaped
through the same text server a `Label` uses, `"مرحبا Godot!"` comes back as a
reversed glyph run — the last glyph in the run is the first code point of the
string — with an inferred direction of right-to-left (`M1`).

So if your Arabic looks wrong, do not start with the font, the encoding or the
CSV. Start with the box the text is sitting in.

## What actually happens when the player picks Arabic

One `HBoxContainer` 400px wide, two buttons, `layout_direction` left at its
default of Inherited. Before: the first child sits at `x=0`. You call
`TranslationServer.set_locale("ar")`. After: the first child sits at `x=349`
(`M2`).

Nothing else changed. No setting, no code, no scene edit. Every container, every
anchor, every alignment in the tree flipped, because `is_layout_rtl()` became
true for the whole window.

Two details matter for debugging it:

- **It is synchronous.** The positions have already changed in the same frame as
  the `set_locale()` call, before any `await` (`M3`). This is unlike
  `auto_translate_mode`, whose effect on already-drawn descendants lands on the
  next frame — see
  [why a key that IS in your CSV still shows up untranslated](why-a-key-in-your-csv-still-shows-untranslated.md).
- **It is silent.** Zero errors and zero warnings naming layout, direction or
  mirroring in the run that mirrored the interface (`M4`).

## The notification exists and never arrives

`Control.NOTIFICATION_LAYOUT_DIRECTION_CHANGED` is real. It is constant `49` on
4.2, 4.3, 4.4 and 4.7 alike. It is the obvious thing to override if you want to
re-point an icon or re-order something by hand when the layout flips.

Measured on a `Control` subclass — the object it would be delivered to — while
that exact node moved from `x=0` to `x=349`: the notification never came (`M5`).
What the node did receive was `NOTIFICATION_TRANSLATION_CHANGED` (`2010`), which
tells you the language changed and says nothing about the layout.

If you need to react to the mirror, react to `2010` and ask `is_layout_rtl()`
yourself. Waiting for `49` is waiting for nothing.

## The version split: the same build, the same player, opposite layouts

Here is the part that turns into a bug report you cannot reproduce.

A locale is selected that **no loaded translation covers** — Hebrew in a project
that shipped English and Arabic. This is not an exotic case: it is what a
language menu written ahead of the translators looks like, and it is exactly what
an export that dropped one `.translation` produces (see
[why your exported game is not translated](why-your-exported-game-is-not-translated.md)).

| engine | `is_layout_rtl()` | what the player sees |
|---|---|---|
| 4.2, 4.3, 4.4 | `false` | English text, normal layout |
| 4.7 | `true` | English text, mirrored layout |

Measured as `M9`. On 4.2 through 4.4 the mirror requires the locale to be among
`TranslationServer.get_loaded_locales()`. On 4.7 the locale string alone decides
it. `is_locale_right_to_left("he")` returns true on all four.

The consequence is measured too (`M10`): the untranslated locale still gets a
layout decision. On 4.7 the player reads left-to-right English inside a
right-to-left interface — a screen where every single string is the wrong
language and the layout insists it is not.

This also means **upgrading the engine can mirror screens that were never
mirrored before**, in precisely the locales your translators have not finished.

## Mirroring you did by hand gets mirrored again

Before the engine did this for you, the way to support Arabic was to do it
yourself: reverse the child order, swap the anchors, move the icon.

That work is applied *on top of* the engine's mirror, not instead of it. A row
whose two children were added in reverse order in code comes out with the first
child back on the left of the second (`A.x=294`, `B.x=349`) inside a row that is
itself right-aligned (`M11`). Two mirrors cancel. You end up with the original
reading order pinned to the wrong edge — which looks like a subtle spacing bug
rather than like the double negative it is.

If you inherited a project with hand-rolled right-to-left support, that code is
now actively wrong, and it became wrong on the day the Arabic `.translation`
started loading.

## Textures move, they never flip

An icon inside the mirrored row is repositioned (`x=258`) and its `flip_h` stays
`false` (`M12`).

So the mirror moves your back arrow to the right side of the screen and leaves it
pointing left. Same for progress chevrons, next/previous buttons, swipe hints and
anything else whose meaning is in its direction. There is no engine setting for
this. The art has to be flipped by you, keyed off `is_layout_rtl()`.

## The four modes, and the one whose name lies

`Control.layout_direction` has these values (`M8`):

| value | 4.2 / 4.3 | 4.4 / 4.7 |
|---|---|---|
| 0 | `LAYOUT_DIRECTION_INHERITED` | `LAYOUT_DIRECTION_INHERITED` |
| 1 | `LAYOUT_DIRECTION_LOCALE` | `LAYOUT_DIRECTION_APPLICATION_LOCALE` (`LOCALE` kept as an alias) |
| 2 | `LAYOUT_DIRECTION_LTR` | `LAYOUT_DIRECTION_LTR` |
| 3 | `LAYOUT_DIRECTION_RTL` | `LAYOUT_DIRECTION_RTL` |
| 4 | — | `LAYOUT_DIRECTION_SYSTEM_LOCALE` |

The rename kept the integer at `1`, so your `.tscn` files survive the upgrade in
both directions. Code does not: a script that writes
`Control.LAYOUT_DIRECTION_APPLICATION_LOCALE` fails to **parse** on 4.2 and 4.3,
which means the whole script fails to load and the node it was attached to does
nothing at all — not a runtime error you can catch.

`LAYOUT_DIRECTION_SYSTEM_LOCALE` (4.4+) is the trap. It sounds like the right
choice and it reads the player's **operating system** locale, not the language
they picked in your menu. Measured with the game's locale set to Arabic, mode 4
stays left-to-right (`M7`). Pick it and your Arabic-speaking player on an English
Windows install gets an unmirrored interface forever.

`LAYOUT_DIRECTION_LTR` (2) is the one you do want sometimes: it pins a subtree
unmirrored while the rest of the interface flips (`M6`). Use it on a code view, a
version string, a phone-number field — anything whose order is not natural
language.

## The project setting that stopped working

`internationalization/rendering/force_right_to_left_layout_direction` exists to
let you look at a mirrored interface without a single Arabic string. It is still
in Project Settings, and `ProjectSettings.get_setting()` still reads it back as
`true` after you set it.

It works on 4.2. From 4.3 on it does nothing: root window `is_layout_rtl()` stays
`false`, the row stays at `x=0` (`M13`). Measured on 4.3, 4.4 and 4.7.

So the switch built for previewing this problem is, on every currently
recommended version, a switch that reports success and has no effect. To see the
mirrored layout you have to actually load a right-to-left translation — or, on
4.7, just select the locale.

## How to check your project

Two calls answer the question, and neither of them is reading a position or a
`text` property (`M14`):

```gdscript
# what the language wants
TextServerManager.get_primary_interface().is_locale_right_to_left(locale)

# what this node actually got
some_control.is_layout_rtl()
```

A check worth putting in your own test suite, because it catches the version
split above before a player does:

```gdscript
func _rtl_sanity(locale: String) -> void:
	TranslationServer.set_locale(locale)
	var wants := TextServerManager.get_primary_interface().is_locale_right_to_left(locale)
	var got := get_tree().root.is_layout_rtl()
	assert(wants == got,
		"locale %s wants rtl=%s and the window says %s" % [locale, wants, got])
```

Run it for every locale in your language menu, including the ones with no
translation yet. On 4.2 through 4.4 that assert fires for any right-to-left
locale you have not translated — which is the correct alarm, because your menu
offers a language your layout will not serve.

And grep for the hand-rolled mirroring that is now double:

```
grep -rn "is_layout_rtl\|LAYOUT_DIRECTION\|move_child" --include="*.gd" .
```

## What LocGuard Lite does and does not cover

The scanners in this repository read your project's strings: keys, CSV rows,
`tr()` call sites, `.translation` files. None of that sees this. The layout is
not a string, and the failure is not in your table — the table is correct, and so
is the text drawn from it.

This page exists so that you know to write the assert above. The mirror is not a
bug to fix; it is a behaviour to decide about, once, for every locale in your
menu.

## Reproducing

```
docs/verify_rtl_layout.sh /path/to/Godot_v4.2-stable_linux.x86_64
docs/verify_rtl_layout.sh /path/to/Godot_v4.3-stable_linux.x86_64
docs/verify_rtl_layout.sh /path/to/Godot_v4.4-stable_linux.x86_64
docs/verify_rtl_layout.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

14 claim ids; 13 plus one skip on 4.2 and 4.3, which have no
`LAYOUT_DIRECTION_SYSTEM_LOCALE` to measure. Every number is read back from a
real node after the engine placed it. The summary line is the gate, and a run
that does not reach it reports an error rather than a pass. `LG_SELFTEST=1` flips
one expectation on purpose so you can confirm the harness can fail.

One detail the script has to handle and your build machine may too: a
`.translation` written by 4.4 is refused by 4.2 (`format version (6) ... not
supported`), so each binary gets its own freshly imported project. A shared
directory would have measured "no translation loaded" on the older engine — which
is one of the cases on this page, and would have been recorded in the wrong
place.
