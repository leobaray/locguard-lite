extends SceneTree
# Every claim in docs/why-pseudolocalization-hides-your-missing-translations.md,
# measured. Run through verify_pseudolocalization.sh, which builds the project
# this script expects (pseudolocalization switched on in project.godot).

var fails := 0

func check(id: String, ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + id + " — " + what)
	if not ok:
		fails += 1

# The recipe from the doc: wrap each real table. Only messages that exist get
# pseudolocalized, and markup is swapped for %s (which skip_placeholders keeps)
# before the accents go on, then put back.
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

func _init() -> void:
	var TS = TranslationServer
	var minor: int = Engine.get_version_info().minor

	var t := Translation.new()
	t.locale = "en"
	t.add_message("HELLO", "Hello world")
	t.add_message("RICH", "[b]Bold[/b] {name}")
	t.add_message("SCORE", "Score: %d")
	TS.add_translation(t)
	TS.set_locale("en")

	var hello := tr("HELLO")
	check("P1", TS.get("pseudolocalization_enabled") == true and hello == "[Ĥéłłô ŵôŕłd́]",
		"use_pseudolocalization=true in project.godot turns tr('HELLO') into %s" % hello)

	var missing := tr("Not in any table")
	# LG_SELFTEST=1 flips this one expectation, to prove the harness can fail.
	var p2: bool = missing != "Not in any table" and missing == TS.pseudolocalize("Not in any table") and String(TS.translate("Not in any table")) == missing
	if OS.get_environment("LG_SELFTEST") == "1":
		p2 = not p2
	check("P2", p2,
		"a string that is in NO table gets the same treatment: %s — a missing translation looks translated" % missing)

	var n1 := tr_n("Apple", "Apples", 1)
	var n2 := tr_n("Apple", "Apples", 2)
	check("P3", n1 == "Apple" and n2 == "Apples",
		"tr_n() is never pseudolocalized: %s / %s" % [n1, n2])

	var ratio0 := TS.pseudolocalize("Hello world")
	ProjectSettings.set_setting("internationalization/pseudolocalization/expansion_ratio", 0.3)
	TS.reload_pseudolocalization()
	var ratio3 := TS.pseudolocalize("Hello world")
	ProjectSettings.set_setting("internationalization/pseudolocalization/expansion_ratio", 1.0)
	TS.reload_pseudolocalization()
	var ratio10 := TS.pseudolocalize("Hello world")
	ProjectSettings.set_setting("internationalization/pseudolocalization/expansion_ratio", 0.0)
	TS.reload_pseudolocalization()
	check("P4", ProjectSettings.get_setting("internationalization/pseudolocalization/expansion_ratio") == 0.0
		and ratio0.length() == 14 and ratio3 == "[_Ĥéłłô ŵôŕłd́_]" and ratio10 == "[_____Ĥéłłô ŵôŕłd́_____]",
		"expansion_ratio defaults to 0, so only the brackets are added; 0.3 gives %s and 1.0 gives %s — padding at the ends, no word gets longer" % [ratio3, ratio10])

	var rich := tr("RICH")
	var label := Label.new()
	label.text = "HELLO"
	root.add_child(label)
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.text = "RICH"
	root.add_child(rtl)
	await process_frame
	var parsed_on := rtl.get_parsed_text()
	check("P5", rich.begins_with("[[ḅ]") and parsed_on.contains("[ḅ]"),
		"BBCode tag names get accents: tr('RICH') = %s, and RichTextLabel prints the tags as text: %s" % [rich, parsed_on])

	var score := tr("SCORE") % 42
	var greet := tr("RICH").format({"name": "Ana"})
	check("P6", score == "[Ŝćôŕé: 42]" and greet.contains("{") and not greet.contains("{name}") and not greet.contains("Ana"),
		"skip_placeholders protects %%d (%s) but not {name}: format() no longer fills it: %s" % [score, greet])

	var w_on := label.get_minimum_size().x
	TS.set("pseudolocalization_enabled", false)
	TS.reload_pseudolocalization()
	await process_frame
	var w_off := label.get_minimum_size().x
	var parsed_off := rtl.get_parsed_text()
	TS.set("pseudolocalization_enabled", true)
	TS.reload_pseudolocalization()
	await process_frame
	var w_back := label.get_minimum_size().x
	check("P7", w_off < w_on and w_back == w_on and parsed_off == "Bold {name}" and rtl.get_parsed_text() == parsed_on,
		"TranslationServer.pseudolocalization_enabled + reload_pseudolocalization() updates live nodes within a frame: Label width %s -> %s -> %s" % [w_on, w_off, w_back])
	check("P8", w_on - w_off <= 0.15 * w_off,
		"with the default ratio the Label grows only %s px on %s (%d%%): the brackets, nothing more" % [w_on - w_off, w_off, int(round(100.0 * (w_on - w_off) / w_off))])

	var raw := TS.get_translation_object("en").get_message("Not in any table")
	check("P9", String(raw) == "" and String(TS.get_translation_object("en").get_message("HELLO")) == "Hello world",
		"the table itself is not pseudolocalized: get_translation_object('en').get_message() is '%s' for the missing string, so a missing key can still be told apart" % raw)

	# Recipe: built-in switch off, each table wrapped.
	TS.set("pseudolocalization_enabled", false)
	TS.reload_pseudolocalization()
	ProjectSettings.set_setting("internationalization/pseudolocalization/expansion_ratio", 0.3)
	TS.reload_pseudolocalization()
	TS.remove_translation(t)
	TS.add_translation(PseudoTable.new(t))
	TS.set_locale("en")
	await process_frame
	var r_hello := tr("HELLO")
	var r_missing := tr("Not in any table")
	check("R1", r_hello == "[_Ĥéłłô ŵôŕłd́_]" and r_missing == "Not in any table",
		"with the recipe, a real translation is pseudolocalized (%s) and a missing one stays plain English (%s)" % [r_hello, r_missing])
	var r_rich := tr("RICH")
	var rtl2 := RichTextLabel.new()
	rtl2.bbcode_enabled = true
	rtl2.text = "RICH"
	root.add_child(rtl2)
	await process_frame
	check("R2", r_rich.contains("[b]") and r_rich.contains("[/b]") and r_rich.format({"name": "Ana"}).contains("Ana") and rtl2.get_parsed_text().contains("ßôłd́") and not rtl2.get_parsed_text().contains("[b]"),
		"and markup survives: tr('RICH') = %s, a RichTextLabel shows %s, format() fills {name}" % [r_rich, rtl2.get_parsed_text()])
	var r_score := tr("SCORE") % 42
	check("R3", r_score.contains("42") and r_score.begins_with("[") and r_score != "Score: 42",
		"%%d still works: %s" % r_score)
	var stale := rtl.get_parsed_text()
	if minor == 2:
		check("R4", stale == rtl2.get_parsed_text(),
			"on 4.2, a node that existed before the tables were swapped picks up the wrapper: %s" % stale)
	else:
		check("R4", stale == "Bold {name}",
			"on 4.%d, a node that existed before add/remove_translation() keeps its old text (%s): install the wrapper before the UI is built" % [minor, stale])

	print("PSEUDOLOCALIZATION: " + ("ALL PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails else 0)
