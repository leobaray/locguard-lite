extends SceneTree

# Asks a real Godot 4 binary which translation actually answers a given locale,
# and what the engine does to the locale string you wrote before it looks.
#
# The question ("I added a Brazilian Portuguese column / .po and the game still
# shows English") is answered on forums with folklore: "name it pt_BR", "name it
# pt-BR", "use the exact code from the OS", "Godot only matches exact locales".
# None of those four is measured, and at least two of them are wrong. This file
# measures it.
#
# Claim ids (M*) are the ones cited in
# docs/why-the-translation-is-not-loading-for-my-locale.md. Every check prints
# PASS/FAIL; the script exits non-zero if any fails, so a newer Godot tells you
# which line stopped holding.
#
# The M1-M17 block needs no imported .csv or .po: the translations are built in
# memory with Translation.add_message(), which is the same object the CSV
# importer produces. The M20 block reads .translation files produced by a real
# import pass and is skipped (as a NOTE, never as a pass) when they are absent,
# so the file stays runnable from a bare project.

var failures := 0
var passes := 0
var notes: Array[String] = []

func check(id: String, what: String, ok: bool) -> void:
	if ok:
		passes += 1
		print("PASS  %s  %s" % [id, what])
	else:
		failures += 1
		print("FAIL  %s  %s" % [id, what])

func note(s: String) -> void:
	notes.append(s)
	print("NOTE  %s" % s)

func make_translation(locale: String, pairs: Dictionary) -> Translation:
	var t := Translation.new()
	t.locale = locale
	for k in pairs:
		t.add_message(k, pairs[k])
	return t

func only(pairs_by_locale: Dictionary) -> void:
	# Leaves the server holding exactly the given translations and nothing else.
	TranslationServer.clear()
	for loc in pairs_by_locale:
		TranslationServer.add_translation(make_translation(loc, pairs_by_locale[loc]))

func said(locale: String, key: String) -> String:
	TranslationServer.set_locale(locale)
	return TranslationServer.translate(key)

func _initialize() -> void:
	print("---")
	var vi := Engine.get_version_info()
	var v := float(vi.major) + float(vi.minor) / 100.0
	print("BUILD %s" % vi.string)

	# ------------------------------------------------------------- M1-M7
	# What the engine does to the locale string BEFORE it looks for anything.
	# This is the step every "just name it correctly" answer skips.

	check("M1", "standardize_locale('pt-br') = '%s' — a LOWERCASE country is dropped, not converted" % \
		TranslationServer.standardize_locale("pt-br"),
		TranslationServer.standardize_locale("pt-br") == "pt")

	check("M2", "standardize_locale('pt-BR') = '%s' — the same string with the country in caps keeps it" % \
		TranslationServer.standardize_locale("pt-BR"),
		TranslationServer.standardize_locale("pt-BR") == "pt_BR")

	check("M3", "standardize_locale('en-us') = '%s' and ('en-US') = '%s' — same rule, second language" % [
		TranslationServer.standardize_locale("en-us"), TranslationServer.standardize_locale("en-US")],
		TranslationServer.standardize_locale("en-us") == "en" and \
		TranslationServer.standardize_locale("en-US") == "en_US")

	check("M4", "standardize_locale('zh-hans-cn') = '%s' — script AND country dropped when lowercase" % \
		TranslationServer.standardize_locale("zh-hans-cn"),
		TranslationServer.standardize_locale("zh-hans-cn") == "zh")

	check("M5", "standardize_locale('PT_BR') = '%s' — an UPPERCASE language is left as written, not lowercased" % \
		TranslationServer.standardize_locale("PT_BR"),
		TranslationServer.standardize_locale("PT_BR") == "PT_BR")

	check("M6", "'PT_BR' is not a spelling of 'pt_BR': compare_locales('pt_BR','PT_BR') = %d, and ('pt','PT_BR') = %d" % [
		TranslationServer.compare_locales("pt_BR", "PT_BR"), TranslationServer.compare_locales("pt", "PT_BR")],
		TranslationServer.compare_locales("pt_BR", "PT_BR") == 0 and \
		TranslationServer.compare_locales("pt", "PT_BR") == 0)

	check("M7", "standardize_locale('no') = '%s' — 'no' is remapped to 'nb', so a file named 'no' answers 'nb'" % \
		TranslationServer.standardize_locale("no"),
		TranslationServer.standardize_locale("no") == "nb")

	# ------------------------------------------------------------- M8-M9
	# The same normalization runs on what you SET and on what you STORE.

	TranslationServer.set_locale("pt-br")
	check("M8", "set_locale('pt-br') then get_locale() = '%s' — the country you typed is gone at runtime too" % \
		TranslationServer.get_locale(),
		TranslationServer.get_locale() == "pt")

	var stored := make_translation("pt-BR", {})
	check("M9", "Translation.locale = 'pt-BR' stores '%s' — the setter standardizes, so the resource never keeps your spelling" % \
		stored.locale,
		stored.locale == "pt_BR")

	# ----------------------------------------------------------- M10-M15
	# Which loaded translation answers. Godot does NOT require an exact match.

	only({"pt": {"K": "generico"}})
	check("M10", "only 'pt' loaded, locale pt_BR -> '%s' — a country-less translation answers a country locale" % \
		said("pt_BR", "K"),
		said("pt_BR", "K") == "generico")

	only({"pt_BR": {"K": "brasil"}})
	check("M11", "only 'pt_BR' loaded, locale pt -> '%s' — and a country translation answers a country-less locale" % \
		said("pt", "K"),
		said("pt", "K") == "brasil")

	check("M12", "only 'pt_BR' loaded, locale pt_PT -> '%s' — even the WRONG country answers when it is the only one" % \
		said("pt_PT", "K"),
		said("pt_PT", "K") == "brasil")

	check("M13", "locale es with only 'pt_BR' loaded -> '%s' — an unrelated language gets the key itself back, untranslated" % \
		said("es", "K"),
		said("es", "K") == "K")

	only({"pt": {"A": "a-pt", "B": "b-pt"}, "pt_BR": {"A": "a-br"}})
	TranslationServer.set_locale("pt_BR")
	check("M14", "fall-through is per MESSAGE, not per file: locale pt_BR gives A='%s' (from pt_BR) and B='%s' (from pt, which pt_BR does not have)" % [
		TranslationServer.translate("A"), TranslationServer.translate("B")],
		TranslationServer.translate("A") == "a-br" and TranslationServer.translate("B") == "b-pt")

	only({"pt": {"K": "generico"}, "pt_BR": {"K": "brasil"}})
	check("M15", "with both 'pt' and 'pt_BR' loaded, locale pt_BR -> '%s' and locale pt -> '%s': the exact match wins on both sides" % [
		said("pt_BR", "K"), said("pt", "K")],
		said("pt_BR", "K") == "brasil" and said("pt", "K") == "generico")

	# ------------------------------------------------------------ M16-M17
	# The tie-break between two partial matches CHANGED between 4.3 and 4.4.
	# The claim is read off the build, not tabled as a constant.

	var s_ptbr_pt := TranslationServer.compare_locales("pt_BR", "pt")
	var s_ptbr_ptpt := TranslationServer.compare_locales("pt_BR", "pt_PT")
	note("compare_locales on this build: ('pt_BR','pt')=%d  ('pt_BR','pt_PT')=%d  ('en_US','en')=%d  ('pt_BR','pt_BR')=%d" % [
		s_ptbr_pt, s_ptbr_ptpt, TranslationServer.compare_locales("en_US", "en"),
		TranslationServer.compare_locales("pt_BR", "pt_BR")])

	check("M16", "a same-language partial match always scores above zero and below the exact match (%d < %d), so language is what selects and country only ranks" % [
		s_ptbr_pt, TranslationServer.compare_locales("pt_BR", "pt_BR")],
		s_ptbr_pt > 0 and s_ptbr_pt < TranslationServer.compare_locales("pt_BR", "pt_BR") and \
		TranslationServer.compare_locales("pt", "es") == 0)

	# The consequence: locale pt_PT, with 'pt' and 'pt_BR' both loaded and
	# neither an exact match. Before 4.4 the two candidates TIE, and the winner
	# is decided by the order they were added; from 4.4 the score separates them.
	var pt_first := said("pt_PT", "K")          # added order: pt, then pt_BR
	only({"pt_BR": {"K": "brasil"}, "pt": {"K": "generico"}})
	var br_first := said("pt_PT", "K")          # added order: pt_BR, then pt
	var s_ptpt_pt := TranslationServer.compare_locales("pt_PT", "pt")
	if s_ptpt_pt == s_ptbr_ptpt:
		check("M17", "on %s the two candidates for locale pt_PT TIE (pt scores %d, pt_BR scores %d), so nothing in the locale decides it" % [
			vi.string, s_ptpt_pt, s_ptbr_ptpt],
			true)
		check("M18", "and the tie is broken by ORDER OF LOADING, not by the locale: 'pt' then 'pt_BR' gives '%s', 'pt_BR' then 'pt' gives '%s' — same project, same player, two different strings" % [
			pt_first, br_first],
			pt_first == "brasil" and br_first == "generico")
		note("Before 4.4, what a pt_PT player reads depends on the order of internationalization/locale/translations in project.godot. From 4.4 on, both orders give the country-less 'pt' text. Upgrading changes the visible string with no edit on your side.")
	else:
		check("M17", "on %s the tie is gone: the country-less pt scores %d against pt_BR's %d for locale pt_PT, so 'no country' beats 'wrong country'" % [
			vi.string, s_ptpt_pt, s_ptbr_ptpt],
			s_ptpt_pt > s_ptbr_ptpt)
		check("M18", "and the order of loading no longer decides it: 'pt' then 'pt_BR' gives '%s', 'pt_BR' then 'pt' gives '%s' — the same string both ways" % [
			pt_first, br_first],
			pt_first == "generico" and br_first == "generico")
		note("On 4.2 and 4.3 the two score the same and the LAST loaded wins, so the same project shows a pt_PT player the pt_BR text when the translations array happens to end with it. Nothing in the project has to change for the visible string to change across that upgrade.")

	# ------------------------------------------------------------ M20-M23
	# The import pass: what a CSV COLUMN HEADER becomes on disk.

	var pt_file := "res://strings.pt.translation"
	if not ResourceLoader.exists(pt_file):
		note("SKIPPED M20-M23: no imported .translation next to this script, so the CSV column headers were not measured on this run (verify_locale_matching.sh does the import pass first).")
	else:
		var t_pt: Translation = load(pt_file)
		check("M20", "the CSV column written 'pt-br' imported to %s with locale '%s' and the text '%s' — the country you typed is not in the file name or in the resource" % [
			pt_file, t_pt.locale, t_pt.get_message("GREETING")],
			t_pt.locale == "pt" and t_pt.get_message("GREETING") == "from-column-pt-br")

		var t_ptbr: Translation = load("res://strings.pt_BR.translation")
		check("M21", "the column written 'pt-BR' imported to strings.pt_BR.translation with locale '%s' — one capital letter apart from M20 and a different file" % \
			t_ptbr.locale,
			t_ptbr.locale == "pt_BR" and t_ptbr.get_message("GREETING") == "from-column-pt-BR")

		var t_caps: Translation = load("res://strings.PT_BR.translation")
		check("M22", "the column written 'PT_BR' imported to a real file with locale '%s', and no locale can ever select it (compare_locales('pt_BR','%s')=%d)" % [
			t_caps.locale, t_caps.locale, TranslationServer.compare_locales("pt_BR", t_caps.locale)],
			t_caps.locale == "PT_BR" and TranslationServer.compare_locales("pt_BR", t_caps.locale) == 0)

		# Load all four imported files at once and ask what pt_BR and pt see.
		TranslationServer.clear()
		for f in ["res://strings.en.translation", "res://strings.pt.translation",
				"res://strings.pt_BR.translation", "res://strings.PT_BR.translation"]:
			TranslationServer.add_translation(load(f))
		check("M23", "with all four columns imported, locale pt_BR -> '%s' and locale pt -> '%s': the 'PT_BR' column is dead weight in the export and reaches nobody" % [
			said("pt_BR", "GREETING"), said("pt", "GREETING")],
			said("pt_BR", "GREETING") == "from-column-pt-BR" and \
			said("pt", "GREETING") == "from-column-pt-br")

	print("---")
	if failures == 0:
		print("LOCALE MATCHING: ALL PASS (%d checks, %d notes) on %s" % [passes, notes.size(), vi.string])
		quit(0)
	else:
		print("LOCALE MATCHING: %d FAILED of %d on %s" % [failures, passes + failures, vi.string])
		quit(1)
