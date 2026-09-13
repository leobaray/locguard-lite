extends SceneTree
# Every claim in docs/why-your-localized-image-or-voice-line-is-the-wrong-one.md,
# measured. Run through verify_resource_remaps.sh, which builds the project
# (remap table + .tres files) this script expects.

var fails := 0

func check(id: String, ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + id + " — " + what)
	if not ok:
		fails += 1

func lang(r) -> String:
	return "null" if r == null else str(r.get_meta("lang"))

func fresh(path: String):
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)

func _init() -> void:
	var TS = TranslationServer
	TS.set_locale("en")

	var held = load("res://flag.tres")
	var held_id: int = held.get_instance_id()
	var copy = held.duplicate()
	var loose = fresh("res://flag.tres")
	var menu: PackedScene = load("res://menu.tscn")
	check("R0", lang(held) == "en" and lang(copy) == "en" and lang(loose) == "en",
		"under 'en' the original loads: held=%s copy=%s uncached=%s" % [lang(held), lang(copy), lang(loose)])

	TS.set_locale("pt")
	var now = load("res://flag.tres")
	check("R1", lang(now) == "pt" and now.resource_path == "res://flag.tres",
		"under 'pt' load('res://flag.tres') gives the pt file (%s) and still reports path %s" % [lang(now), now.resource_path])
	check("R2", held.get_instance_id() == held_id and lang(held) == "pt" and now == held,
		"the reference loaded under 'en' was reloaded IN PLACE by set_locale: same object, now reads %s" % lang(held))
	check("R3", lang(menu.instantiate().get_meta("flag")) == "pt",
		"a PackedScene loaded under 'en' instantiates with the pt resource: %s" % lang(menu.instantiate().get_meta("flag")))
	check("R5", lang(copy) == "en",
		"a duplicate() taken under 'en' is NOT updated: %s" % lang(copy))
	# 4.2 leaves an uncached load alone; 4.3+ gives it the path and reloads it too.
	var minor: int = Engine.get_version_info().minor
	var loose_expected := "en" if minor <= 2 else "pt"
	check("R6", lang(loose) == loose_expected,
		"a CACHE_MODE_IGNORE load taken under 'en' reads %s after the switch (4.2: stays en; 4.3+: reloaded to pt)" % lang(loose))

	var pre = load("res://uses_preload.gd")
	var under_pt: String = pre.flag_lang()
	TS.set_locale("en")
	var under_en: String = pre.flag_lang()
	check("R4", under_pt == "pt_p" and under_en == "en_p",
		"a const preload() compiled under 'pt' follows the switch back: %s -> %s" % [under_pt, under_en])

	TS.set_locale("pt")
	check("R7", lang(fresh("res://missing.tres")) == "en_m",
		"a remap whose target file does not exist falls back to the original: %s" % lang(fresh("res://missing.tres")))
	check("R8", lang(fresh("res://noprefix.tres")) == "en_n",
		"a remap key written without 'res://' is ignored: %s" % lang(fresh("res://noprefix.tres")))

	var br_only := {}
	var both := {}
	for loc in ["pt_BR", "pt", "pt_PT", "es"]:
		TS.set_locale(loc)
		br_only[loc] = lang(fresh("res://voice.tres"))
		both[loc] = lang(fresh("res://sign.tres"))
	# LG_SELFTEST=1 flips this one expectation, to prove the harness can fail.
	var r9: bool = br_only["pt"] == "pt_BR" and br_only["pt_PT"] == "pt_BR"
	if OS.get_environment("LG_SELFTEST") == "1":
		r9 = not r9
	check("R9", r9,
		"a remap listed only for pt_BR is served to 'pt' (%s) and to 'pt_PT' (%s)" % [br_only["pt"], br_only["pt_PT"]])
	check("R10", both["pt_BR"] == "pt_BR" and both["pt_PT"] == "pt" and both["pt"] == "pt",
		"with pt_BR AND pt listed, pt_BR->%s, pt_PT->%s, pt->%s" % [both["pt_BR"], both["pt_PT"], both["pt"]])
	check("R11", br_only["es"] == "en_v" and both["es"] == "en_s",
		"a locale with no matching language gets the original: %s / %s" % [br_only["es"], both["es"]])

	TS.set_locale("pt")
	var table: Dictionary = ProjectSettings.get_setting("internationalization/locale/translation_remaps")
	table["res://late.tres"] = PackedStringArray(["res://late_pt.tres:pt"])
	ProjectSettings.set_setting("internationalization/locale/translation_remaps", table)
	check("R12", lang(fresh("res://late.tres")) == "en_l",
		"a remap added with ProjectSettings.set_setting at runtime is ignored: %s" % lang(fresh("res://late.tres")))

	print("RESOURCE REMAPS: " + ("ALL PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
