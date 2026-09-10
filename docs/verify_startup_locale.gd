extends SceneTree

# Measures every claim in docs/why-your-game-starts-in-the-wrong-language.md.
#
# One process can only boot with one machine locale, so this script does not run
# the whole page at once: the shell script next to it launches the same binary
# once per scenario and sets LGCASE to say which scenario this process is. Each
# case prints the S-ids that belong to it and a CASEEND line; the shell script
# is the thing that decides whether the page as a whole passed.

var failures := 0
var seen := 0

func check(id: String, claim: String, got, want) -> void:
	seen += 1
	if got == want:
		print("PASS  %s  %s" % [id, claim])
	else:
		failures += 1
		print("FAIL  %s  %s\n        expected: %s\n        got:      %s" % [id, claim, str(want), str(got)])

func minor() -> int:
	return int(Engine.get_version_info()["minor"])

func _initialize() -> void:
	var c := OS.get_environment("LGCASE")
	print("CASE  %s   godot %s   LANG=%s" % [c, Engine.get_version_info()["string"], OS.get_environment("LANG")])

	match c:
		"machine_pt":
			# A Brazilian machine, a project that ships a `pt` column and no
			# `pt_BR` one. The strings arrive; what the engine REPORTS about
			# itself is where the surprise is.
			check("S1", "LANG=pt_BR.UTF-8 with only a `pt` column shipped: tr() serves Portuguese",
				tr("GREET"), "Ola")
			check("S2", "at boot TranslationServer.get_locale() is the machine string `pt_BR`, not the `pt` that is serving",
				TranslationServer.get_locale(), "pt_BR")
			check("S2b", "and `pt_BR` is not among the loaded locales, so get_locale() is not a membership test",
				TranslationServer.get_loaded_locales().has("pt_BR"), false)
			check("S3", "get_loaded_locales() is the shipped list, unchanged by the machine locale",
				TranslationServer.get_loaded_locales(), PackedStringArray(["en", "pt", "de"]))
			TranslationServer.set_locale("de")
			check("S21", "set_locale() at runtime moves both get_locale() and the next tr()",
				[TranslationServer.get_locale(), tr("GREET")], ["de", "Hallo"])

		"machine_unmatched":
			# A Japanese machine and a project with no Japanese at all.
			check("S4", "LANG=ja_JP.UTF-8 with no ja shipped: tr() returns the fallback text, no error",
				tr("GREET"), "Hello")
			check("S5", "...while get_locale() still answers `ja_JP` — the value a language menu reads disagrees with the screen",
				TranslationServer.get_locale(), "ja_JP")

		"machine_lowercase":
			check("S6", "OS.get_locale() hands back the raw environment value `pt_br`, keeping the country Godot itself drops",
				OS.get_locale(), "pt_br")
			check("S6b", "...while TranslationServer resolved the same value to `pt`",
				TranslationServer.get_locale(), "pt")

		"machine_posix":
			check("S7", "LANG=C: OS.get_locale() and OS.get_locale_language() both answer `C`, which is not a language code",
				[OS.get_locale(), OS.get_locale_language()], ["C", "C"])
			check("S7b", "so `OS.get_locale_language() == \"en\"` is false on a plainly English machine",
				OS.get_locale_language() == "en", false)
			check("S8", "TranslationServer resolves `C` to `en` anyway and serves English",
				[TranslationServer.get_locale(), tr("GREET")], ["en", "Hello"])

		"machine_no_lang":
			check("S9", "LANG unset entirely: OS.get_locale() answers `en` in every version measured",
				OS.get_locale(), "en")

		"machine_empty_lang":
			check("S10", "LANG set to the empty string: OS.get_locale() is empty in every version measured",
				OS.get_locale(), "")
			if minor() >= 7:
				check("S10b", "4.7: TranslationServer recovers and reports `en`",
					TranslationServer.get_locale(), "en")
			else:
				check("S10b", "4.2/4.3/4.4: TranslationServer is left with an EMPTY locale string",
					TranslationServer.get_locale(), "")

		"env_lc_all_only":
			check("S11", "LC_ALL alone (LANG unset) does not select the locale",
				TranslationServer.get_locale(), "en")
		"env_language_only":
			check("S12", "LANGUAGE alone does not select the locale",
				TranslationServer.get_locale(), "en")
		"env_lc_messages_only":
			check("S13", "LC_MESSAGES alone does not select the locale",
				TranslationServer.get_locale(), "en")
		"env_lc_all_vs_lang":
			check("S14", "LC_ALL set next to LANG does not override LANG",
				[TranslationServer.get_locale(), tr("GREET")], ["pt_BR", "Ola"])

		"flag_de":
			check("S15", "-l de overrides the machine locale",
				[TranslationServer.get_locale(), tr("GREET")], ["de", "Hallo"])
		"flag_unshipped":
			check("S16", "-l ja is accepted for a locale you do not ship: reported as `ja`, text falls back",
				[TranslationServer.get_locale(), tr("GREET")], ["ja", "Hello"])
		"setting_test":
			check("S17", "locale/test in project.godot overrides the machine locale",
				[TranslationServer.get_locale(), tr("GREET")], ["de", "Hallo"])
		"flag_beats_test":
			check("S18", "-l wins over locale/test",
				[TranslationServer.get_locale(), tr("GREET")], ["en", "Hello"])

		"fallback_de":
			check("S19", "locale/fallback=de: an unmatched machine gets German — the English default is a setting, not a rule",
				tr("GREET"), "Hallo")
		"fallback_unshipped":
			check("S20", "locale/fallback naming a locale you do not ship: the unmatched machine shows the raw KEY",
				tr("GREET"), "GREET")
			check("S20b", "...with no error: the run is otherwise ordinary",
				TranslationServer.get_locale(), "ja_JP")

		_:
			print("FAIL  ????  unknown case %s" % c)
			failures += 1

	print("CASEEND %s %d checked %d failed" % [c, seen, failures])
	quit(0 if failures == 0 else 1)
