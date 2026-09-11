# Why the OK and Cancel buttons stay in English

You shipped a translated game. Your labels, your menus and your dialogue all
come out in the player's language. Then the game opens a confirmation box and
the two buttons at the bottom say **OK** and **Cancel**, in English, on a build
where everything else is translated.

The usual guess is that those strings live inside the engine and you cannot
reach them. That guess is wrong, and this page measures why. Every claim below
is checked by
[`verify_dialog_buttons.sh`](verify_dialog_buttons.sh) on Godot **4.2, 4.3,
4.4 and 4.7**, official Linux builds:

```
docs/verify_dialog_buttons.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

The script builds a throwaway project, so it touches nothing of yours. It
exits non-zero if any claim fails on your build.

**On 4.2 the claims about what the screen shows are skipped, not passed.**
`Control.atr()` arrived in 4.3. There is no way to read the drawn string on 4.2
from a script, and calling the missing method does not raise an error there — it
takes the headless process down without flushing the line printed before it. So
the script detects the absence and reports those ids as `SKIP`. A skip is not a
pass and is never counted as one.

## The short version

The buttons are translated by **your** CSV, not by the engine. The engine puts
an English literal on the button, and the button draws that literal through the
normal auto-translate path — the same path your own labels use. So a row in
your CSV whose key is exactly `OK` does translate the OK button.

The two things that actually go wrong:

1. **The property lies about the screen.** `button.text` stays `OK` forever.
   The translated string never appears in any property you can print, so
   debugging by printing tells you the translation failed when it did not.
2. **The key you need changes between engine versions.** The literal on the
   `FileDialog` accept button is `OK` on the 4.2 and 4.3 line and `Save` on
   4.4 and later. A project that translated that button on 4.3 goes back to
   English on 4.4, with no error, no warning and no failed import.

## The premise: nothing here is a missing row

The check project loads one `pt_BR` translation containing the English literals
as keys (`D1`, `D2`). Asked through the ordinary path, all of them answer:

| claim | call | result |
|---|---|---|
| `D3` | `tr("OK")` | `Certo` |
| `D4` | `tr("Cancel")` | `Cancelar` |
| `D5` | `tr("Alert!")` | `Alerta!` |

And a literal the engine uses but this CSV does not carry comes back unchanged
(`D6`: `tr("Open")` → `Open`). The engine ships **no** runtime translation of
its own for these strings. The editor's translated interface is a different
thing and is not in your export. If a dialog button comes out translated in
your game, it is because your table answered.

## The property and the screen disagree

On a freshly constructed `AcceptDialog`, in the same frame, with `pt_BR` loaded:

| claim | read | result |
|---|---|---|
| `D7` | `ok_button.text` | `OK` |
| `D8` | `ok_button.atr(ok_button.text)` | `Certo` |
| `D9` | `dialog.title` | `Alert!` |
| `D10` | `dialog.atr(dialog.title)` | `Alerta!` |

`Button` draws `atr(text)`, not `text`. So one node answers two different
things depending on which you ask, and the one you reach for while debugging is
the one that never changes. `ConfirmationDialog` behaves identically: the
cancel button reads `Cancel` and draws `Cancelar` (`D11`, `D12`).

This is the same `atr()` mechanism described in
[why a key that IS in your CSV still shows up untranslated](why-a-key-in-your-csv-still-shows-untranslated.md).
The dialog does not opt into it — `auto_translate_mode` is `INHERIT` on a fresh
dialog (`D17`), so this is the default behaviour, not a setting you turned on.

## The version trap

`FileDialog` is where a translated project silently regresses. The English
literal the engine puts on its accept button is not the same across 4.x:

| build | `FileDialog` accept-button literal (`D13`) |
|---|---|
| 4.2 | `OK` |
| 4.3 | `OK` |
| 4.4 | `Save` |
| 4.7 | `Save` |

`D14` asserts the literal expected for the build line, and `D15` confirms the
button draws whatever that build's literal translates to. `D16` states the
consequence as a measurement: the CSV row that matched this button on the
4.2/4.3 line stops matching on 4.4 and later.

Nothing reports this. The import succeeds, the CSV is valid, the locale is
right, every other string still translates, and one button in your file picker
is back in English. It is exactly the failure shape this repo keeps finding:
**the symptom is "it works", and the loss is silent.**

There is a second version difference worth knowing before you write code
against it. `AcceptDialog.ok_button_text` on a *fresh* dialog reads `OK` on
4.3 and 4.4, and reads **empty** on 4.7 (`D18`, `D19`) — while the button
underneath still says `OK` on every build (`D20`). So `if dialog.ok_button_text
== "OK"` changes behaviour on upgrade even though the dialog did not. Writing
to the property works everywhere: it writes through to the button (`D21`) and
the written value is translated by the same path (`D22`), and a button you add
yourself with `add_button()` is treated identically (`D23`).

## What to actually do

- **Put the engine's English literals in your table as keys.** For the common
  dialogs that means `OK`, `Cancel`, `Alert!`, and — for `FileDialog` on 4.4
  and later — `Save`, plus `Open` if you use the open modes.
- **Keep the old key when you upgrade.** Adding `Save` does not let you drop
  `OK`: the two builds want different rows, and a row that matches nothing
  costs you nothing.
- **Do not debug this by printing `button.text`.** It is `OK` whether your
  translation works or not. Print `button.atr(button.text)`, which is what the
  screen gets.
- **Set the text yourself if you want one key.** Assigning
  `dialog.ok_button_text = "dialog_ok"` makes the button use a key you control,
  and takes it out of the engine's literal entirely — at the cost of doing it
  on every dialog.

## What LocGuard Lite does and does not cover

Honestly stated, as on every page here: the free addon scans **your** strings.
It does not know which English literals the engine will put on a dialog in the
build you are exporting with, so it will not tell you that `Save` is missing
from your table on 4.4. That gap is real and it is written down here rather
than left implied.

## Reproducing

```
docs/verify_dialog_buttons.sh /path/to/Godot_v4.2-stable_linux.x86_64
docs/verify_dialog_buttons.sh /path/to/Godot_v4.3-stable_linux.x86_64
docs/verify_dialog_buttons.sh /path/to/Godot_v4.4-stable_linux.x86_64
docs/verify_dialog_buttons.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

Each run prints one line per claim id used on this page and a summary line.
The summary line is the gate: if the script does not reach it, nothing was
measured, and the script reports that as an error rather than a pass.
