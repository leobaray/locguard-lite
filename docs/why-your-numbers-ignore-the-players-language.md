# Why your numbers ignore the player's language

Your game is translated. Every label switches to German. And the score still
reads `1234567.89`, the price field still wants a dot, and a German player who
types `1234,5` into a SpinBox-backed field gets `1234`.

Nothing is broken, and nothing warns you. Godot 4 translates **text**; it does
not format **numbers**. The one function whose name promises it,
`format_number`, changes digits, not separators. This page measures exactly
what the engine does on 4.2, 4.3, 4.4 and 4.7, and gives a 30-line recipe that
does the rest.

Every claim below has an id and is checked by
[`verify_number_format.sh`](verify_number_format.sh) against a real binary:

```
docs/verify_number_format.sh /path/to/Godot_v4.7-stable_linux.x86_64
```

12 assertions, 12/12 on 4.2, 4.3, 4.4 and 4.7.

## What the engine does

**N1 — `str()`, `String.num()`, `"%.2f" %` and `tr()` never look at the locale.**
After `TranslationServer.set_locale()` to `en`, `de`, `fr` or `ar`, all four give
the same text: `1234.5`, `1234.50`. A number passed through `tr()` comes back
unchanged, because it is not a key in any table.

**N2 — `TextServer.format_number()` adds no grouping and keeps the `.`.**
`format_number("-1234567.89", lang)` for `de`, `fr`, `pt_BR`, `es` and `ru`
returns `-1234567.89` — the input, byte for byte. No `1.234.567,89`, no
`1 234 567,89`.

**N3 — what it does change is the digits.** For languages with their own
digits it substitutes them: `ar` → `١٢٣٤٫٥`, `fa` → `۱۲۳۴٫۵`, `bn` → `১২৩৪.৫`.
Arabic and Persian also get the Arabic decimal separator `٫`; Bengali keeps `.`.

**N4 — `hi` and `th` keep Latin digits.** `format_number("1234.5", "hi")` and
`"th"` both return `1234.5`, so "Devanagari/Thai digits" is not something you
get for free either.

**N5 — without a language argument, `format_number` ignores `set_locale()`.**
Under `set_locale("ar")`, `format_number("1234.5")` returns Latin `1234.5`. The
language parameter is not "defaults to the current locale" in practice: pass
`TranslationServer.get_locale()` yourself.

**N6 — `parse_number()` reverses N3.** `parse_number("١٢٣٤٫٥", "ar")` is
`"1234.5"`. It undoes digit substitution; it does not undo grouping, because
there was none.

**N7 — `"1234,5".to_float()` is `1234`, with no error.** The fraction is
silently dropped, and `is_valid_float()` is `false` — which nothing checks
unless you do.

**N8 — a thousands dot becomes a decimal point.** `"1.234,5".to_float()` is
`1.234` and `"1.234".to_int()` is `1`. A player who types a German-formatted
amount gets a value a thousand times smaller.

**N9 — `TranslationServer.format_number()` exists only on 4.7.** It is absent
on 4.2, 4.3 and 4.4. On 4.7 it returns what the TextServer does (`ar` →
`١٢٣٤٫٥`, `de` → `-1234567.89`), so it is the same N2 behaviour under a
friendlier name — not locale formatting.

## The recipe

Separators by language, then let the TextServer swap the digits. Extend the
table with the languages you ship.

```gdscript
const SEPARATORS := {
	"en": [",", "."], "de": [".", ","], "pt": [".", ","], "es": [".", ","],
	"it": [".", ","], "fr": [" ", ","], "ru": [" ", ","],
	"ar": ["٬", "٫"], "fa": ["٬", "٫"],
}

static func format_for(value: float, decimals: int, locale: String) -> String:
	var lang := locale.get_slice("_", 0)
	var sep: Array = SEPARATORS.get(lang, SEPARATORS["en"])
	var s := String.num(absf(value), decimals)
	if decimals > 0 and not s.contains("."):
		s += "." + "0".repeat(decimals)
	var whole := s.get_slice(".", 0)
	var frac := s.get_slice(".", 1) if s.contains(".") else ""
	var grouped := ""
	for i in whole.length():
		if i > 0 and (whole.length() - i) % 3 == 0:
			grouped += sep[0]
		grouped += whole[i]
	var out: String = ("-" if value < 0 else "") + grouped + ((sep[1] + frac) if frac != "" else "")
	var digits: String = TextServerManager.get_primary_interface().format_number("0123456789", lang)
	for d in 10:
		out = out.replace(str(d), digits[d])
	return out

static func parse_for(text: String, locale: String) -> float:
	var lang := locale.get_slice("_", 0)
	var sep: Array = SEPARATORS.get(lang, SEPARATORS["en"])
	var s: String = TextServerManager.get_primary_interface().parse_number(text, lang)
	s = s.replace(sep[0], "").replace(" ", "").replace(sep[1], ".")
	return s.to_float() if s.is_valid_float() else NAN
```

Call it with `TranslationServer.get_locale()` (N5), and re-run it on
`NOTIFICATION_TRANSLATION_CHANGED` like any other text.

**R1** — it gives `en` `-1,234,567.89`, `de_DE` `-1.234.567,89`, `fr`
`1 234 567,89` (narrow no-break space U+202F, so the number never wraps) and
`ar` `١٬٢٣٤٬٥٦٧٫٨٩`.

**R2** — `parse_for` reads all of them back, and reads a German `1234,5` as
`1234.5` instead of N7's `1234`.

**R3** — `parse_for("12a,5", "de")` is `NAN`, not a partial number. Check
`is_nan()` and reject the input.

Limits, stated: grouping is always by three (Indian `12,34,567` lakh grouping
is not handled), and dates are out of scope — `Time` returns ISO strings and
integer weekdays/months, so month names are a translation-table job.

## The assert for your own suite

```gdscript
assert(not "1234,5".is_valid_float(), "to_float() will silently drop this fraction")
assert(TextServerManager.get_primary_interface().format_number("1234567.89", "de") == "1234567.89",
	"format_number does not group; format numbers yourself")
```

If the second assert ever fails, a future Godot started formatting numbers —
delete your recipe and re-run [`verify_number_format.sh`](verify_number_format.sh).

## Related

- [Why the locale change does not update the UI](why-the-locale-change-does-not-update-the-ui.md)
- [Why your Arabic build comes out mirrored](why-your-arabic-build-comes-out-mirrored.md)
- [Why your translation shows boxes, or nothing at all](why-your-translation-shows-boxes-or-nothing.md)
