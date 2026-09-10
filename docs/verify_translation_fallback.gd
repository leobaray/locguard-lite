extends SceneTree

# Asks a real Godot 4 binary what happens to a string the ACTIVE locale does not
# translate: does the player see the key, an empty line, or another language?
#
# The question ("my Portuguese build still shows English") is answered on forums
# with an API call — TranslationServer.set_fallback("en") — that does not exist
# in Godot 4 at all. A project that follows that answer does not misbehave: it
# fails to parse. So the first thing this file measures is what exists, using
# reflection only, before any claim about behaviour is made.
#
# Claim ids (F*) are the ones cited in
# docs/why-your-untranslated-string-comes-out-in-another-language.md. Every check
# prints PASS/FAIL; the script exits non-zero if any fails, so a newer Godot
# tells you which line stopped holding.
#
# No claim hard-codes the word "English". internationalization/locale/fallback is
# read at STARTUP, so the fallback language is a property of how this project was
# booted, and every claim below is written against whatever that value is —
# including the empty string, which turns the fallback off. That is what makes
# the same file meaningful across the three boots verify_translation_fallback.sh
# performs. A checker that hard-codes the value of a setting it does not control
# reports the environment, not the engine.
#
# The translations are built in memory with Translation.add_message(), which is
# the same object the CSV importer produces, so no .csv/.po import pass is
# needed and the file runs from a bare project.

var failures := 0
var passes := 0

# The fallback this project BOOTED with. Everything below is relative to it.
var fb := ""
var has_fb := false
# A language that is neither the active test locale nor the fallback.
var third := ""

func check(id: String, what: String, ok: bool) -> void:
	if ok:
		passes += 1
		print("PASS  %s  %s" % [id, what])
	else:
		failures += 1
		print("FAIL  %s  %s" % [id, what])

func note(s: String) -> void:
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
	print("BUILD %s" % vi.string)

	# --------------------------------------------------------------- F1-F2
	# What EXISTS. Measured by reflection, so that a wrong guess about the API
	# costs one failed claim instead of a parse error that measures nothing.

	var fallback_methods: Array = []
	for m in ClassDB.class_get_method_list("TranslationServer", true):
		if "fallback" in String(m.name):
			fallback_methods.append(String(m.name))
	check("F1", "TranslationServer exposes %d method whose name contains 'fallback' — the set_fallback()/get_fallback() pair every forum answer reaches for is Godot 3 and is not callable here (naming it is a PARSE error, so the whole script dies, not one line)" % fallback_methods.size(),
		fallback_methods.is_empty())

	var fb_setting = ProjectSettings.get_setting("internationalization/locale/fallback", "<UNSET>")
	check("F2", "the fallback lives in Project Settings, not in code: internationalization/locale/fallback = '%s', and its built-in default is '%s' — it is defined for you, so every project has this setting whether or not anyone chose a value" % [
		str(fb_setting), str(ProjectSettings.property_get_revert("internationalization/locale/fallback"))],
		str(fb_setting) != "<UNSET>" and str(ProjectSettings.property_get_revert("internationalization/locale/fallback")) == "en")

	# Why nobody has seen this setting: the editor only lists it under Advanced.
	var usage := 0
	for p in ProjectSettings.get_property_list():
		if String(p.name) == "internationalization/locale/fallback":
			usage = int(p.usage)
	check("F2b", "and the editor hides it: its usage flags are %d, without PROPERTY_USAGE_EDITOR_BASIC_SETTING (1024), so Project Settings shows it only with Advanced Settings on" % usage,
		usage > 0 and (usage & 1024) == 0)

	fb = "" if str(fb_setting) == "<UNSET>" else str(fb_setting)
	has_fb = fb != ""
	third = "fr" if fb != "fr" else "de"
	note("this project booted with locale/fallback='%s', so every claim below is stated against that value%s." % [
		fb, "" if has_fb else " (empty = the fallback is off)"])

	# --------------------------------------------------------------- F3-F5
	# The active locale translates nothing: what reaches the player.

	only({fb if has_fb else "en": {"K": "fallback-text"}})
	var f3 := said("es", "K")
	check("F3", "locale es, with a translation loaded for '%s' and nothing for es -> '%s'%s" % [
		fb if has_fb else "en", f3,
		" — an unrelated locale does not show the key, it shows the fallback language" if has_fb \
		else " — with the fallback off, the key itself is what reaches the player"],
		f3 == ("fallback-text" if has_fb else "K"))

	only({(fb if has_fb else "en"): {"A": "a-fb", "B": "b-fb"}, "pt_BR": {"A": "a-br"}})
	TranslationServer.set_locale("pt_BR")
	var f4a := TranslationServer.translate("A")
	var f4b := TranslationServer.translate("B")
	check("F4", "one locale, two keys, two different sources: locale pt_BR gives A='%s' (translated) and B='%s'%s — the decision is made per MESSAGE, not per file" % [
		f4a, f4b,
		" (from the fallback)" if has_fb else " (the raw key, fallback off)"],
		f4a == "a-br" and f4b == ("b-fb" if has_fb else "B"))

	only({(fb if has_fb else "en"): {"K": "fallback-text"}, third: {"K": "third-language"}})
	var f5 := said("de" if third != "de" else "it", "K")
	check("F5", "only the fallback locale is consulted: an unrelated locale, with both '%s' and '%s' loaded -> '%s' — a third loaded language is never tried" % [
		fb if has_fb else "en", third, f5],
		f5 == ("fallback-text" if has_fb else "K"))

	# --------------------------------------------------------------- F6-F8
	# The blank cell. This is the one that costs a shipped build: a translator
	# leaves a row empty, nothing errors, nothing is blank on screen, and the
	# player reads a language they did not pick.

	var t := make_translation("pt_BR", {"A": "", "B": "b-br"})
	check("F6", "an empty translation is really STORED: message_count=%d and get_message_list()=%s, with get_message('A') returning a %d-character string" % [
		t.get_message_count(), str(t.get_message_list()), t.get_message("A").length()],
		t.get_message_count() == 2 and t.get_message("A") == "")

	only({"pt_BR": {"A": ""}, (fb if has_fb else "en"): {"A": "a-fb"}})
	var f7 := said("pt_BR", "A")
	check("F7", "and it is treated as ABSENT at lookup time: locale pt_BR with A='' and a non-empty A in '%s' -> '%s'. The blank cell never produces a blank line, and nothing warns%s" % [
		fb if has_fb else "en", f7,
		": the player reads the fallback language" if has_fb else ""],
		f7 == ("a-fb" if has_fb else "A"))

	only({"pt_BR": {"A": ""}, (fb if has_fb else "en"): {"A": ""}})
	var f8 := said("pt_BR", "A")
	check("F8", "with the fallback cell blank too, the same lookup gives '%s' — the raw key, which is the symptom people actually report, and it means TWO cells are empty, not one" % f8,
		f8 == "A")

	# -------------------------------------------------------------- F9-F11
	# The limits of the fallback, and why editing the setting at runtime looks
	# like it does nothing.

	only({"pt_BR": {"B": "b"}, (fb if has_fb else "en"): {"B": "b-fb"}})
	check("F9", "a key absent from every loaded translation -> '%s': the key itself, which is the only case where the screen shows your identifier no matter how the fallback is configured" % \
		said("pt_BR", "ZZZ"),
		said("pt_BR", "ZZZ") == "ZZZ")

	only({"pt_BR": {"A": "a-br"}, third: {"B": "b-third"}})
	var f10 := said("pt_BR", "B")
	check("F10", "the fallback is a LOCALE, not 'any other file': locale pt_BR, key B present only in the loaded '%s', which is not the fallback -> '%s'" % [third, f10],
		f10 == "B")

	only({(fb if has_fb else "en"): {"K": "fallback-text"}, third: {"K": "third-language"}})
	var probe_locale := "de" if third != "de" else "it"
	var before := said(probe_locale, "K")
	ProjectSettings.set_setting("internationalization/locale/fallback", third)
	var after := said(probe_locale, "K")
	ProjectSettings.set_setting("internationalization/locale/fallback", fb)
	check("F11", "changing internationalization/locale/fallback at RUNTIME (to '%s') does nothing: '%s' before the change and '%s' after it, including after set_locale() runs again. The server reads the setting once, at startup" % [
		third, before, after],
		before == after)

	# ------------------------------------------------------------- F12-F13
	# What the setting does when it is chosen AT BOOT — the claim F11 proves
	# cannot be measured any other way.
	only({"en": {"K": "english"}, "fr": {"K": "francais"}})
	var boot_said := said("de", "K")
	if fb == "fr":
		check("F12", "booted with locale/fallback=\"fr\", a lookup that gives 'english' under the default gives '%s' — the setting, and only the setting, picks the language a player falls into" % boot_said,
			boot_said == "francais")
	elif not has_fb:
		check("F13", "booted with locale/fallback=\"\", the fallback is OFF: the same lookup gives '%s'. This is how you make a missing translation visible instead of invisible" % boot_said,
			boot_said == "K")
	else:
		note("F12-F13 not measured on this run: the project booted with locale/fallback='%s'. verify_translation_fallback.sh boots this file again with \"fr\" and with \"\" to measure them." % fb)

	print("---")
	if failures == 0:
		print("TRANSLATION FALLBACK: ALL PASS (%d checks) on %s, locale/fallback='%s'" % [passes, vi.string, fb])
	else:
		print("TRANSLATION FALLBACK: %d FAILED, %d passed on %s, locale/fallback='%s'" % [failures, passes, vi.string, fb])
	quit(1 if failures > 0 else 0)
