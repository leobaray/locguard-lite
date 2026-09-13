# Why your Chinese, Japanese or Thai text does not wrap

The English build is fine. The Chinese build has one line running off the edge
of the dialog box, the Japanese one grows the panel to 500 px, and a script that
sizes the box from `get_line_count()` gets `1`. The usual guess is that Godot
cannot break text with no spaces in it.

It can. On 4.2, 4.3, 4.4 and 4.7 the engine breaks Chinese between characters,
keeps `。` and `っ` off the start of a line, and splits Thai between dictionary
words — with every autowrap mode, with or without `Control.language`. What goes
wrong is around it: the Label default, the frame you did not wait for, and a
~4.5 MB data file that a default export leaves out.

Every claim below has an id and is checked by
[`verify_cjk_line_breaking.sh`](verify_cjk_line_breaking.sh) against a real binary:

```
docs/verify_cjk_line_breaking.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

12 assertions, 12/12 on 4.2, 4.3, 4.4 and 4.7. The line breaks are measured at
16 px with the default font; the export claims use `--export-pack`, so no export
template is needed to run it.

## What is actually wrong

**W2 — a Label does not wrap unless you ask.** `autowrap_mode` defaults to
`AUTOWRAP_OFF`. A Chinese sentence in a 120 px Label stays one line and the
Label's minimum width becomes 496 px. English has the same default; it just
tends to be shorter, or the box was sized to it by hand.

**W1 — `get_line_count()` is `1` until a frame has passed.** Set the text and ask
straight away and both the non-wrapping and the `AUTOWRAP_WORD_SMART` Label say
`1`. After one `await get_tree().process_frame`, the wrapping one says `5`. Code
that sizes a dialog in the same function that sets the translated text sizes it
for one line.

**S1 — the editor binary carries the break data built in.** The running binary
reports `ICU / HarfBuzz / Graphite (Built-in)` and uses `icudt73l.dat` (4.2),
`icudt75l.dat` (4.3) or `icudt_godot.dat` (4.4, 4.7) — a file that is not in
your project. Everything in the next section depends on it.

**E1 — a default export does not pack that file.**
`internationalization/locale/include_text_server_data` is `false` by default,
and a pack exported that way contains no `icudt*.dat` (about 1.3 KB for an empty
project).

**E2 — turning the setting on packs it, at about 4.5 MB.** With
`include_text_server_data=true` the same pack contains the `.dat` above and grows
by 4 421 264 to 4 805 520 bytes depending on the version.

This page does not measure export templates: whether a given template has its
own built-in copy depends on how it was built. If Japanese or Thai wraps in the
editor and not in the exported game, E1 is the difference between the two, and
E2 is the switch.

## What the engine does for you

**W3 — Chinese breaks between any two characters.** In a box 7 characters wide,
`这是一个很长的中文句子…` comes out as `这是一个很长的` / `中文句子用来测` / … —
7 per line, no spaces needed.

**W4 — the autowrap mode does not matter for it.** `AUTOWRAP_WORD`,
`AUTOWRAP_WORD_SMART` and `AUTOWRAP_ARBITRARY` all give the same 5 lines.

**W5 — `。` and `，` never start a line.** When `これは日本語の文` exactly fills
8 characters, the line ends at `の` and `文。` moves down together; the same
happens to `点，` in Chinese.

**W6 — neither does a small `っ`.** `東京都の人口はと` fills 8 characters and
the next one is `っ`, so `と` moves down with it: `東京都の人口は` / `とっても多いで`.

**W7 — Thai breaks between words, not inside them.**
`นี่คือประโยคภาษาไทยที่ยาวมากเพื่อทดสอบการตัดบรรทัดอัตโนมัติ` in 120 px becomes
`นี่คือประโยคภาษา` / `ไทยที่ยาวมากเพื่อ` / `ทดสอบการตัด` / `บรรทัดอัตโนมัติ` —
dictionary word boundaries, although the sentence has no spaces.

**W8 — `Control.language` does not change any of it.** With the language left
empty, W3, W5 and W7 give the same breaks as with `zh`, `ja` and `th`: the
script of the text decides.

## The fix

```gdscript
# Every Label/RichTextLabel that shows translated text:
label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # W2

# Measure after the layout ran, not in the same call:
label.text = tr("INTRO")
await get_tree().process_frame                          # W1
panel.custom_minimum_size.y = label.get_line_count() * label.get_line_height()
```

And in **Project Settings → Internationalization → Locale**, turn on
**Include Text Server Data** (E2) if you ship Chinese, Japanese, Korean, Thai,
Lao, Khmer or Burmese — or check an exported build before you decide you do
not need it.

## The assert for your own suite

```gdscript
assert(ProjectSettings.get_setting("internationalization/locale/include_text_server_data"),
	"the export will not pack the line-break data (E1)")
assert(Label.new().autowrap_mode == TextServer.AUTOWRAP_OFF,
	"if this fails, a future Godot wraps Labels by default — re-run the .sh")
```

## Related

- [Why your translation shows boxes, or nothing at all](why-your-translation-shows-boxes-or-nothing.md)
- [Why your exported game is not translated](why-your-exported-game-is-not-translated.md)
- [Why the locale change does not update the UI](why-the-locale-change-does-not-update-the-ui.md)
