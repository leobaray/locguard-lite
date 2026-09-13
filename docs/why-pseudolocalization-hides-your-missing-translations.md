# Why pseudolocalization hides your missing translations

You tick **Project Settings → Internationalization → Pseudolocalization → Use
Pseudolocalization**, run the game, and every line comes out as
`[Ĥéłłô ŵôŕłd́]`. It looks like proof that everything goes through `tr()`.

It is not. On Godot 4.2, 4.3, 4.4 and 4.7 the switch also accents strings that
are in **no** translation table, so the one thing you wanted to spot — text
nobody translated — looks exactly like text somebody did. Out of the box it
also breaks your BBCode, breaks `{name}` placeholders, skips `tr_n()`, and adds
two characters of length. This page measures each of those and gives a
25-line wrapper that pseudolocalizes only what is really translated.

Every claim below has an id and is checked by
[`verify_pseudolocalization.sh`](verify_pseudolocalization.sh) against a real
binary:

```
docs/verify_pseudolocalization.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

13 assertions, 13/13 on 4.2, 4.3, 4.4 and 4.7.

## What the built-in switch does

**P1 — it works on `tr()`.** With `use_pseudolocalization=true` in
`project.godot`, a table entry `HELLO` → `Hello world` comes back as
`[Ĥéłłô ŵôŕłd́]`.

**P2 — a string in no table gets the same treatment.** `tr("Not in any
table")` is `[йôŧ íή áήý ŧáḅłé]`, and so is `TranslationServer.translate()`. A
Label whose text was never added to your CSV is accented and bracketed like
every translated one. Pseudolocalization shows that text passes through the
translation *call*, not that a translation *exists*.

**P3 — `tr_n()` is never pseudolocalized.** `tr_n("Apple", "Apples", n)` gives
plain `Apple` / `Apples` with the switch on, so plural lines are the ones that
look untouched.

**P4 — `expansion_ratio` defaults to `0`.** The only change in length is the
`[` and `]`. Raising it pads with underscores at the ends — `0.3` gives
`[_Ĥéłłô ŵôŕłd́_]`, `1.0` gives `[_____Ĥéłłô ŵôŕłd́_____]` — so no word gets
longer and word-wrap inside the line is not exercised.

**P5 — BBCode tag names get accents.** An entry `[b]Bold[/b] {name}` comes back
as `[[ḅ]ßôłd́[/ḅ] {ήám̀é}]`, and a RichTextLabel prints `[ḅ]` and `[/ḅ]` as
visible text.

**P6 — `skip_placeholders` protects `%d` but not `{name}`.** `tr("Score: %d") %
42` is `[Ŝćôŕé: 42]`, but after pseudolocalization `{name}` is `{ήám̀é}`, so
`.format({"name": "Ana"})` has nothing to fill.

**P7 — it can be toggled at runtime.** Setting
`TranslationServer.pseudolocalization_enabled` and calling
`TranslationServer.reload_pseudolocalization()` updates Labels and
RichTextLabels already on screen within one frame, in both directions.
`expansion_ratio` changed through `ProjectSettings.set_setting()` is picked up by
the same reload.

**P8 — at the default ratio, the Label grows by the brackets only.** A Label
showing `Hello world` goes from 89 px to 100 px (99 px on 4.7), 11–12%. That is
not a length test.

**P9 — the table itself is not pseudolocalized.**
`TranslationServer.get_translation_object("en").get_message(key)` returns `""`
for a missing key and the real text for a present one, with the switch on. That
is the handle the recipe uses.

## The recipe

Leave the built-in switch **off** and wrap each loaded table instead. Only
messages the table really has are pseudolocalized; BBCode tags, `{name}` and
`%d` are swapped for `%s` (which `skip_placeholders` keeps) before the accents
go on, then put back.

```gdscript
class PseudoTable extends Translation:
	var base: Translation
	var re := RegEx.new()

	func _init(from: Translation) -> void:
		base = from
		locale = from.locale
		re.compile("\\[[^\\]]*\\]|\\{[^}]*\\}|%[-+ 0-9.]*[a-zA-Z%]")

	func _get_message(src_message: StringName, context: StringName) -> StringName:
		var msg := String(base.get_message(src_message, context))
		return StringName(pseudo(msg) if msg != "" else "")

	func _get_plural_message(src_message: StringName, src_plural_message: StringName, n: int, context: StringName) -> StringName:
		var msg := String(base.get_plural_message(src_message, src_plural_message, n, context))
		return StringName(pseudo(msg) if msg != "" else "")

	func pseudo(s: String) -> String:
		var kept := []
		for m in re.search_all(s):
			kept.append(m.get_string())
		var masked := re.sub(s, "%s", true)
		return TranslationServer.pseudolocalize(masked) % kept
```

Swap it in with `TranslationServer.remove_translation(t)` /
`add_translation(PseudoTable.new(t))` for each table, in an autoload, in a QA
build only. The `prefix`, `suffix` and `expansion_ratio` settings still apply,
through `pseudolocalize()`.

**R1** — with `expansion_ratio` 0.3, `tr("HELLO")` is `[_Ĥéłłô ŵôŕłd́_]` and
`tr("Not in any table")` stays plain `Not in any table`. Untranslated text is
now the text that does *not* look strange.

**R2** — markup survives: `tr("RICH")` is `[_[b]ßôłd́[/b] {name}_]`, a
RichTextLabel renders it without visible tags, and `.format()` fills `{name}`.

**R3** — `%d` still works: `[_Ŝćôŕé: 42_]`.

**R4 — do the swap before the UI exists.** On 4.3, 4.4 and 4.7 a node that was
already showing the text keeps the old string after
`remove_translation`/`add_translation`. On 4.2 it picks up the wrapper. An
autoload runs before your first scene, so it works on all four.

Limits, stated: `tr_n()` through the wrapper was not measured (P3 is about the
built-in switch); only a `Translation` built in code was measured, not one
imported from CSV or `.po`; exported builds were not measured.

## The assert for your own suite

```gdscript
assert(not TranslationServer.pseudolocalize("Hi {name}").contains("{name}"),
	"pseudolocalize() now keeps {name}; the markup masking in PseudoTable may be unnecessary")
```

If that assert ever fails, a future Godot started protecting brace
placeholders — re-run
[`verify_pseudolocalization.sh`](verify_pseudolocalization.sh) and see which of
P2–P6 still hold.

## Related

- [Why a key that IS in your CSV still shows up untranslated](why-a-key-in-your-csv-still-shows-untranslated.md)
- [Why your RichTextLabel shows the key instead of the translation](why-your-richtextlabel-shows-the-key-instead-of-the-translation.md)
- [Why your translated line comes out empty, or as another line's text](why-your-translated-line-comes-out-empty.md)
