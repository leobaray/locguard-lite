extends SceneTree
# Every claim in docs/why-your-numbers-ignore-the-players-language.md,
# measured. Run through verify_number_format.sh, which builds the empty project
# this script expects.

var fails := 0

func check(id: String, ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + id + " — " + what)
	if not ok:
		fails += 1

# The recipe from the doc: separators by language, then the TextServer swaps
# the digits for the scripts that have their own.
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

func _init() -> void:
	var TS = TranslationServer
	var ts = TextServerManager.get_primary_interface()
	var minor: int = Engine.get_version_info().minor

	var seen := {}
	for loc in ["en", "de", "fr", "ar"]:
		TS.set_locale(loc)
		seen[loc] = "%s|%s|%s|%s" % [str(1234.5), String.num(1234.5, 2), "%.2f" % 1234.5, tr("1234.5")]
	check("N1", seen["de"] == seen["en"] and seen["fr"] == seen["en"] and seen["ar"] == seen["en"],
		"str(), String.num(), '%%.2f' and tr() give the same text under en, de, fr and ar: %s" % seen["de"])

	var latin := {}
	for lang in ["de", "fr", "pt_BR", "es", "ru"]:
		latin[lang] = ts.format_number("-1234567.89", lang)
	# LG_SELFTEST=1 flips this one expectation, to prove the harness can fail.
	var n2: bool = latin.values().all(func(v): return v == "-1234567.89")
	if OS.get_environment("LG_SELFTEST") == "1":
		n2 = not n2
	check("N2", n2,
		"TextServer.format_number('-1234567.89', de/fr/pt_BR/es/ru) adds no grouping and keeps the '.': %s" % str(latin.values()))

	var ar: String = ts.format_number("1234.5", "ar")
	var fa: String = ts.format_number("1234.5", "fa")
	var bn: String = ts.format_number("1234.5", "bn")
	check("N3", ar == "١٢٣٤٫٥" and fa == "۱۲۳۴٫۵" and bn == "১২৩৪.৫",
		"what format_number does change is the digits: ar=%s fa=%s bn=%s" % [ar, fa, bn])
	check("N4", ts.format_number("1234.5", "hi") == "1234.5" and ts.format_number("1234.5", "th") == "1234.5",
		"hi and th keep Latin digits: hi=%s th=%s" % [ts.format_number("1234.5", "hi"), ts.format_number("1234.5", "th")])

	TS.set_locale("ar")
	check("N5", ts.format_number("1234.5") == "1234.5",
		"with no language argument format_number ignores set_locale('ar'): %s" % ts.format_number("1234.5"))
	TS.set_locale("en")

	check("N6", ts.parse_number(ar, "ar") == "1234.5" and ts.parse_number(fa, "fa") == "1234.5",
		"parse_number turns the native digits back: %s / %s" % [ts.parse_number(ar, "ar"), ts.parse_number(fa, "fa")])

	check("N7", "1234,5".to_float() == 1234.0 and not "1234,5".is_valid_float(),
		"a German player's '1234,5' reads as %s: the fraction is dropped without an error" % "1234,5".to_float())
	check("N8", is_equal_approx("1.234,5".to_float(), 1.234) and "1.234".to_int() == 1,
		"'1.234,5'.to_float() = %s and '1.234'.to_int() = %s: a thousands dot becomes a decimal point" % ["1.234,5".to_float(), "1.234".to_int()])

	var has_trs: bool = TS.has_method("format_number")
	if minor >= 7:
		check("N9", has_trs and TS.call("format_number", "1234.5", "ar") == ar and TS.call("format_number", "-1234567.89", "de") == "-1234567.89",
			"4.7 adds TranslationServer.format_number, and it returns what TextServer does: ar=%s de=%s" % [TS.call("format_number", "1234.5", "ar") if has_trs else "-", TS.call("format_number", "-1234567.89", "de") if has_trs else "-"])
	else:
		check("N9", not has_trs, "TranslationServer.format_number does not exist on 4.%d" % minor)

	var r_en := format_for(-1234567.891, 2, "en")
	var r_de := format_for(-1234567.891, 2, "de_DE")
	var r_fr := format_for(1234567.891, 2, "fr")
	var r_ar := format_for(1234567.891, 2, "ar")
	check("R1", r_en == "-1,234,567.89" and r_de == "-1.234.567,89" and r_fr == "1 234 567,89" and r_ar == "١٬٢٣٤٬٥٦٧٫٨٩",
		"the recipe gives en=%s de=%s fr=%s ar=%s" % [r_en, r_de, r_fr.replace(" ", "<NNBSP>"), r_ar])
	check("R2", parse_for(r_de, "de") == -1234567.89 and parse_for(r_fr, "fr") == 1234567.89 and parse_for(r_ar, "ar") == 1234567.89 and parse_for("1234,5", "de") == 1234.5,
		"and parses them back: de=%s fr=%s ar=%s '1234,5'(de)=%s" % [parse_for(r_de, "de"), parse_for(r_fr, "fr"), parse_for(r_ar, "ar"), parse_for("1234,5", "de")])
	check("R3", is_nan(parse_for("12a,5", "de")),
		"and refuses text that is not a number instead of returning a partial value: %s" % parse_for("12a,5", "de"))

	print("NUMBER FORMAT: " + ("ALL PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
