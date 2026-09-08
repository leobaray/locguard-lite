# "I changed the locale and nothing on screen changed" — what Godot 4 actually does

Every forum answer to this question is one of three, and none of them is
measured:

1. *"Reload the scene."*
2. *"Walk the tree and re-assign every string."*
3. *"It just works — you did something wrong."*

All sixteen statements below were measured on **Godot 4.3, 4.4 and 4.7**
(16/16 identical on each) by
[`verify_locale_change.gd`](verify_locale_change.gd). Run it on your own
binary:

```
docs/verify_locale_change.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

It builds a throwaway project in a temp directory and needs no imported `.csv`
or `.po` — the translations are built in memory with
`Translation.add_message()`, which is the same object the importer produces.
Godot 4.2 and earlier are reported as a **SKIP**, not a pass: they have no
`Node.auto_translate_mode`, the script does not compile, and Godot still exits
0 — so the gate is the summary line, never the engine's exit code.

## The short answer

Nothing on screen is "the translation". `tr()` is a function that returns a
**String**, and a String is a value, not a live binding. Whatever you did with
that value — put it in a variable, assigned it to `Label.text` — is a copy that
was correct at the moment you asked, and stays that way forever.

The engine *does* re-translate the text you left as a **key**, and it *does*
tell every node in the tree that the locale moved. What it never does is
rewrite a string you already resolved yourself.

## What was measured

### `tr()` returns a value, and values do not move

- **L1** — `tr("GREETING")` returns the active locale's message. With
  `locale=en`, it is `Hello`.
- **L2** — a String captured from `tr()` does **not** follow a later
  `set_locale()`: the captured copy is still `Hello` while a fresh `tr()` call
  in the same frame already returns `Ola`. This is the whole bug, in one line.

### What the engine does and does not rewrite

- **L3** — a `Label` whose `text` was assigned **the result of `tr()`** keeps
  the old text after the locale changes (`text == "Hello"`). This is the
  mistake that produces the question.
- **L4** — a `Label` whose `text` was assigned **the key** keeps the key in
  `.text` (`"GREETING"`). The engine never rewrites the property, in either
  case — so reading `.text` back tells you nothing about what is on screen.
- **L5** — but what that Label *displays* does follow the locale:
  `label.atr(label.text)` returns `Ola`. `atr()` is the auto-translation the
  control performs when it draws; it is the honest way to ask "what is
  actually rendered".
- **L13** — the same holds for `PopupMenu`: `add_item("ITEM")` stores the key,
  `get_item_text(0)` gives you back `ITEM` after the locale change, and
  `menu.atr(...)` gives `Objeto`. Code that reads item text back and compares
  it against a translated string will never match.

### The notification, and who never receives it

- **L6** — a `Control` inside the tree receives
  `NOTIFICATION_TRANSLATION_CHANGED` (measured: exactly one per
  `set_locale()`).
- **L7** — a `Control` **outside** the tree receives it zero times. A node you
  built with `.new()` and kept in a variable — a pooled dialog, a screen not
  added yet — never hears about the change, and will draw the previous locale
  the moment you add it back.
- **L8** — `auto_translate_mode = AUTO_TRANSLATE_MODE_DISABLED` makes
  `atr()` return the key verbatim. This is the opt-out that turns a
  proper-noun label into a permanent `PLAYER_NAME` on screen.

### The failure that looks like success

- **L9** — a key with no message in the active locale comes back as **the key
  itself**: `tr("MISSING") == "MISSING"`.
- **L10** — `set_locale("xx")` for a locale nobody translated is **accepted**;
  `get_locale()` reports it back. No error, no warning.
- **L11** — and it does **not** show the keys. It silently serves the
  **fallback locale's** messages (`internationalization/locale/fallback`,
  default `en`): `tr("GREETING")` returns `Hello`. The screen looks perfectly
  fine in English, so a locale that was never applied is invisible.
- **L11b** — it is the fallback locale *specifically*, not "whichever
  translation happens to be loaded": remove the `en` translation while `pt` is
  still loaded, and the key finally surfaces.
- **L11c** — writing `internationalization/locale/fallback` at runtime does
  **not** move the fallback. After setting it to `pt` and calling
  `set_locale()` again, `tr("GREETING")` is still `Hello`. The server read
  that setting at startup; changing it in code looks like it should work and
  does nothing.
- **L12** — a region code resolves the language-only translation:
  `set_locale("pt_BR")` with only a `pt` translation loaded returns `Ola`, and
  `get_locale()` reports `pt_BR`.

### What actually fixes it

- **L14** — re-running `tr()` after the change is what produces fresh text.

There is no refresh call to find, because there is nothing stale to refresh:
the engine's copy is already correct, and yours is the one that is old. So the
fix has exactly two shapes, and which one you need depends on L3 vs L4:

```gdscript
# 1. Preferred: never resolve it yourself. Leave the key in the property and
#    let the control translate at draw time (L4/L5). Then set_locale() is
#    already enough — nothing to do.
$Label.text = "GREETING"

# 2. If you must build the string in code (formatting, concatenation), rebuild
#    it when the locale moves — react to the notification, not to a timer.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		$Label.text = tr("SCORE_FMT") % score
```

Shape 2 only reaches nodes that are in the tree (L7). Anything you are holding
outside it has to be refreshed when you add it back.

## Notes recorded by the run

```
NOTE fallback setting internationalization/locale/fallback = en
NOTE set_locale(pt_BR) -> get_locale()=pt_BR, tr(GREETING)=Ola
NOTE PopupMenu item: get_item_text=ITEM, atr=Objeto
```

## Finding the strings this page is about

The failure in L3 is invisible at runtime and obvious in the source: a `tr()`
whose result is stored instead of a key left in place. The free
[LocGuard Lite](../README.md) addon lists every translatable string it finds in
`.gd`, `.cs` and `.tscn` and which of them have no entry in your CSV — which is
the other half of "the locale changed and the screen did not": the key was
never translated at all (L9).

---

*Measured on Godot 4.3.stable, 4.4.stable and 4.7.stable, x86_64 Linux, with
`docs/verify_locale_change.sh`. If a newer build changes any of this, the
script will tell you which line stopped holding.*
