# Why your translated line comes out empty, or as another line's text

The German build looks finished. Then someone opens the score screen and the
sentence that should read *"Ann hat 10 Punkte erzielt"* is not there. Not
wrong, not garbled — absent. The label is empty and the layout has closed up
around it as if the text had never existed. The French build shows that same
line, but it shows a sentence from the tutorial instead.

Nothing is missing from the table. Every key resolves, every locale imports,
your linter is clean and the source language is perfect. This page measures
what is actually happening. Every claim below is checked by
[`verify_format_placeholders.sh`](verify_format_placeholders.sh) on Godot
**4.2, 4.3, 4.4 and 4.7**, official Linux builds:

```
docs/verify_format_placeholders.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

The script builds a throwaway project, so it touches nothing of yours. It
exits non-zero if any claim fails on your build.

## The short version

`tr()` did its job. The `%` that runs immediately after it did not.

A translator does not see `%s scored %d points` as code. They see a sentence
with two odd marks in it, and they translate the sentence — which in French
means putting the number first, because that is where French puts it:
`%d points marqués par %s`. The words are right. The order of the placeholders
is now wrong for `%`, which fills them strictly left to right and has no idea
that a language might reorder them.

What happens next is not an exception you can catch and not a crash. It is a
value: the empty string, or `null`, or a piece of text belonging to something
else entirely.

## The rows under test

The check project imports this CSV through the engine's own importer, so
every string below is one the engine produced, not a literal typed into a
test (`F1`, `F2`):

| key | `en` | what the translator changed |
|---|---|---|
| `SCORE_MSG` | `%s scored %d points` | `fr` reordered to `%d points marques par %s` |
| `PCT_MSG` | `%d%% complete` | `fr` dropped one per-cent: `%d% termine` |
| `COUNT_MSG` | `%d items` | `de` typed `%s Gegenstaende` |
| `PLAIN_MSG` | `All good` | `de` wrote `100% sicher` — ordinary prose |
| `NAMED_MSG` | `{who} scored {pts}` | `fr` reordered to `{pts} points pour {who}` |

The import is completely quiet (`F0`): the editor pass writes three
`.translation` files and says nothing about any of it. Nothing in Godot
compares the placeholders of a translation against the placeholders of its
source column, at import time or at any other time.

And `tr()` is not the problem (`F2`): it finds the key and returns the
translated sentence in all three locales. A scanner looking for missing keys
or empty cells — including LocGuard Lite — sees a clean project.

## What the player gets, by call site

The same broken row produces a different symptom depending on how the line of
code around it is typed. This is the part that makes the bug hard to search
for, because two developers hitting it describe two different problems.

| call site | result of the failed `%` | what the screen shows |
|---|---|---|
| typed (`func f(s: String) -> String`) | the empty string, length 0 (`F5`) | the line is gone; the layout closes up |
| untyped (`func f(s, v)`) | `null` (`F6`) | see below — the line never gets set at all |
| on 4.2 / 4.3, typed | another string entirely (`F14`) | text from elsewhere in the game |

The `null` case is the worst of the three (`F19`). `label.text = null` is not
a silent no-op: it raises *"Invalid set index 'text' (on base: 'Label') with
value of type 'Nil'"* and **stops the function it is in**. The measured run
proves it by putting a marker after the assignment; the marker never prints.
Every node your `_ready()` was going to configure after that line is left
untouched, so one bad translated row in one language turns into a half-built
screen, and the line that actually failed is several statements further up.

## The one that leaks other people's text

On 4.2 and 4.3, a failed `%` on a typed call site does not return its own
text and does not return nothing. It returns a string that was in flight
somewhere else in the program (`F14`, `F15`). In the measured run, a format
that should have produced `BETA 100% sure` produced `ALPHA %d gold`, and the
next one produced `GAMMA %d silver` — the neighbouring strings, unfilled.

Which string leaks is not a property of the broken line. It depends on what
the program formatted last, so the same defect shows a different sentence
depending on what the player did just before. That is why this reproduces as
"sometimes the wrong text appears" and never as a stable bug report.

From 4.4 on, the same failure returns the format string itself (`F14`,
`F15`): the player sees `%d points marqués par %s` on screen. Ugly, but it
names the line that is broken, which the older behaviour never does.

## A translation with no placeholder can break the line too

`PLAIN_MSG` has no placeholder in any language. The German translator wrote
`100% sicher` — a per-cent sign in ordinary prose, the way anyone writes it.
Filling that string fails exactly like the others and returns the empty
string (`F7`).

The same single character does it to `PCT_MSG`: the source correctly wrote
`%d%% complete` with the per-cent doubled, the translator saw a typo and
"fixed" it to `%d% termine`, and that one deleted character is the entire
defect (`F8`).

This is the reason a rule that only looks for placeholder *counts* is not
enough. There is no placeholder in `100% sicher` to count.

## And the mismatch that is not an error at all

`COUNT_MSG` in German turned `%d` into `%s`. It works (`F9`): `"%s Gegenstaende" % 3`
prints `3 Gegenstaende` and the engine says nothing, ever. The number is
rendered by the string formatter instead of the integer formatter, which is
fine in German and is not fine in a language where the digits or the grouping
differ.

So the drift is not visible at runtime in either direction: some of it fails
loudly, some of it fails silently, and some of it does not fail at all and
still ships the wrong thing. The failing directions, measured: a `%d` handed a
word (`F10`), one argument too many (`F11`), one argument too few (`F12`) —
the last of which is what happens when a translator *adds* a placeholder your
code never passes.

## What the Output panel gives you

One line per failure, and the wording is not one wording. The same defect is
reported as `SCRIPT ERROR: unsupported format character in operator '%'` from
an untyped call site (`F18`), and as `ERROR: ...` from a typed one — where the
text changed between versions (`F20`):

| build | typed call site wording |
|---|---|
| 4.2, 4.3 | `ERROR: unsupported format character` |
| 4.4, 4.7 | `ERROR: String formatting error: unsupported format character.` |

If you grep your CI logs for one of those three strings, the other two are
invisible to you. And none of them tells you which key, which locale or which
row: they report a variant operator, not a translation.

## What to do about it

- **Use named placeholders in anything a translator will touch.**
  `"{who} scored {pts}".format({...})` survives the reorder that broke the `%`
  version (`F16`), because the name travels with the hole. It is the only fix
  on this page that removes the class of bug rather than catching instances of
  it.
- **Know how the named form fails.** A placeholder your code does not supply
  is left on screen as literal `{pts}` text, and the engine prints nothing at
  all (`F17`). It is a visible defect rather than a missing line, which is
  better, but it is still not reported.
- **Send your translators the placeholders, not just the sentences.** Most
  translation tools can lock or highlight them if you tell them which ones
  exist. `%` and `{}` in a spreadsheet cell look like punctuation.
- **Compare the placeholder set of every translation against its source
  column, in CI.** That comparison is a text operation on the table. It does
  not need the game to run, and it is the only check that catches all three
  directions — the reorder, the deleted `%%`, and the `%d` that became `%s`.

## What LocGuard Lite does and does not cover

Honestly stated, as on every page here: Lite has two rules, `missing-key` and
`empty-translation`. Neither of them looks at placeholders, so **every row on
this page passes Lite clean** — that is asserted in the run, not assumed.

Comparing each translation's placeholder set against its source column is
LocGuard Pro's `placeholder-printf`, `placeholder-index` and
`placeholder-named`. If you would rather not buy anything, the last bullet
above is a text comparison over your own CSV and you can write it in an
afternoon; this page exists so that you know the check is worth writing.

## Reproducing

```
docs/verify_format_placeholders.sh /path/to/Godot_v4.2-stable_linux.x86_64
docs/verify_format_placeholders.sh /path/to/Godot_v4.3-stable_linux.x86_64
docs/verify_format_placeholders.sh /path/to/Godot_v4.4-stable_linux.x86_64
docs/verify_format_placeholders.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

21 claim ids: 17 measured inside the game, 4 measured around it (the import
pass, the two Output wordings, and the run that proves the function stops).
21 passes, 0 fails, 0 skips on each of the four builds. Three of the ids are
written with a version branch on purpose, because the answer genuinely differs
between 4.3 and 4.4; the run prints the measured value either way. The summary
line is the gate: if the script does not reach it, nothing was measured, and
the script reports that as an error rather than a pass.
