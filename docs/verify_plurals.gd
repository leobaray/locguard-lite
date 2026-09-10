extends SceneTree

# Asks a real Godot 4 binary what tr_n() returns when the translation it has to
# read came from strings.csv.
#
# The question ("my plural is translated in the CSV and the game still prints
# the singular") gets answered on forums with a spelling fix — a second row, a
# different key, a rebuild. None of those is the problem. The CSV importer
# produces an OptimizedTranslation, and an OptimizedTranslation has no plural
# table at all, so tr_n() has nothing to select from and hands back the singular
# for every count. The plural row you wrote is in the file, is imported, and is
# reachable by tr() — it is simply never the string tr_n() returns.
#
# Claim ids (N*) are the ones cited in
# docs/why-tr_n-always-returns-the-singular.md. Every check prints PASS/FAIL and
# the script exits non-zero if any fails, so a newer Godot tells you which line
# stopped holding.
#
# Two claims are version-dependent and are written that way on purpose: the base
# Translation class grew plural handling between 4.4 and 4.7, and the answer it
# gives for the same call changed with it. The script reads
# Engine.get_version_info() and checks the claim that applies to the binary it is
# running on, printing the measured value either way. A checker that hard-codes
# one engine's answer reports its own age, not the engine.
#
# The CSV and the two .po files are written by verify_plurals.sh and imported by
# a real editor pass before this file runs, so every claim about the CSV path is
# a claim about the resource the importer actually produced.

var failures := 0
var passes := 0
var vi := Engine.get_version_info()

func check(id: String, what: String, ok: bool) -> void:
	if ok:
		passes += 1
		print("PASS  %s  %s" % [id, what])
	else:
		failures += 1
		print("FAIL  %s  %s" % [id, what])

func note(s: String) -> void:
	print("NOTE  %s" % s)

func only(res: Array) -> void:
	# Leaves the server holding exactly these translations and nothing else.
	TranslationServer.clear()
	for r in res:
		TranslationServer.add_translation(r)

func plural(key: String, key_plural: String, n: int) -> String:
	return TranslationServer.translate_plural(key, key_plural, n)

func _initialize() -> void:
	print("---")
	print("BUILD %s" % vi.string)
	var newer: bool = vi.major > 4 or (vi.major == 4 and vi.minor >= 5)

	var csv_pt: Translation = load("res://strings.pt.translation")
	var csv_ru: Translation = load("res://strings.ru.translation")
	var po_pt: Translation = load("res://pt.po")
	var po_ru: Translation = load("res://ru.po")

	# ---------------------------------------------------------------- N1-N2
	# What the CSV importer produced, and that both rows are in it.
	check("N1", "the CSV importer produced a %s for locale '%s' — not a TranslationPO, and only a TranslationPO carries plural forms" % [
		csv_pt.get_class(), csv_pt.locale],
		csv_pt.get_class() == "OptimizedTranslation" and csv_pt.locale == "pt")

	only([csv_pt])
	TranslationServer.set_locale("pt")
	var s_one := TranslationServer.translate("APPLE")
	var s_many := TranslationServer.translate("APPLES")
	check("N2", "both rows arrived: tr(\"APPLE\") is '%s' and tr(\"APPLES\") is '%s'. The plural string is in the game" % [s_one, s_many],
		s_one == "maca" and s_many == "macas")

	# ---------------------------------------------------------------- N3-N5
	# The whole point.
	var p1 := plural("APPLE", "APPLES", 1)
	var p5 := plural("APPLE", "APPLES", 5)
	check("N3", "tr_n(\"APPLE\", \"APPLES\", 1) is '%s' — correct, and the reason this bug survives a code review" % p1,
		p1 == "maca")
	check("N4", "tr_n(\"APPLE\", \"APPLES\", 5) is '%s'. The count is five and the string is the singular. No error, no warning, no null" % p5,
		p5 == "maca")
	var every_n := true
	var seen := []
	for n in [0, 2, 3, 11, 100, 1000]:
		var v := plural("APPLE", "APPLES", n)
		seen.append("%d->'%s'" % [n, v])
		if v != "maca":
			every_n = false
	check("N5", "every other count does the same: %s. There is no count that reaches the plural row" % ", ".join(PackedStringArray(seen)),
		every_n)

	# ------------------------------------------------------------------- N6
	# The data is not missing. That is what makes it hard to find.
	check("N6", "the plural row is reachable the whole time: tr(\"APPLES\") is '%s'. Nothing is missing from the CSV, from the import, or from the build — tr_n() just never asks for it" % s_many,
		s_many == "macas")

	# ------------------------------------------------------------------- N7
	# The three ways a project calls this all agree, so none of them is a fix.
	var node := Node.new()
	root.add_child(node)
	var obj := Object.new()
	var via_node: String = node.tr_n("APPLE", "APPLES", 5)
	var via_obj: String = obj.tr_n("APPLE", "APPLES", 5)
	check("N7", "Node.tr_n() gives '%s' and Object.tr_n() gives '%s' — the same as TranslationServer.translate_plural(). Moving the call does not change the answer" % [via_node, via_obj],
		via_node == p5 and via_obj == p5)
	obj.free()
	node.queue_free()

	# ------------------------------------------------------------------- N8
	# A language with three plural forms gets the same one string.
	only([csv_ru])
	TranslationServer.set_locale("ru")
	var ru_seen := []
	var ru_flat := true
	for n in [1, 3, 5]:
		var v := plural("APPLE", "APPLES", n)
		ru_seen.append("%d->'%s'" % [n, v])
		if v != "ru-one":
			ru_flat = false
	check("N8", "Russian has three plural forms and a CSV serves one of them: %s. The number of forms the language needs is not something the CSV path can express" % ", ".join(PackedStringArray(ru_seen)),
		ru_flat)

	# ---------------------------------------------------------------- N9-N10
	# A key in NO translation fails differently — worth knowing, because the two
	# look nothing alike on screen and get reported as the same bug.
	only([csv_pt])
	TranslationServer.set_locale("pt")
	var m1 := plural("MISSING", "MISSINGS", 1)
	var m5 := plural("MISSING", "MISSINGS", 5)
	check("N9", "a key that is in no translation at all returns the source singular for n=1: '%s'" % m1,
		m1 == "MISSING")
	check("N10", "the same key returns the source PLURAL for n=5: '%s'. So an untranslated plural shows English and a CSV plural shows translated-but-singular — two different screens, one cause to rule out first" % m5,
		m5 == "MISSINGS")

	# -------------------------------------------------------------- N11-N13
	# The base Translation class, and the thing that changed between 4.4 and 4.7.
	var mem := Translation.new()
	mem.locale = "pt"
	mem.add_message("APPLE", "maca")
	var has_apm: bool = mem.has_method("add_plural_message")
	check("N11", "Translation.add_plural_message() exists on this build: %s. It exists on 4.2, 4.3, 4.4 and 4.7 alike, so its presence tells you nothing about whether it works — see N14" % has_apm,
		has_apm)

	only([mem])
	TranslationServer.set_locale("pt")
	var mem5 := plural("APPLE", "APPLES", 5)
	if newer:
		check("N12", "on %s a plain Translation carrying only add_message(\"APPLE\", \"maca\") answers tr_n(...,5) with '%s' — the UNTRANSLATED source plural. The same call on 4.4 answers 'maca'. A build that silently printed the translated singular starts silently printing English" % [vi.string, mem5],
			mem5 == "APPLES")
	else:
		check("N12", "on %s a plain Translation carrying only add_message(\"APPLE\", \"maca\") answers tr_n(...,5) with '%s' — the translated singular. On 4.7 the same call answers 'APPLES'" % [vi.string, mem5],
			mem5 == "maca")

	check("N13", "and the CSV path does NOT follow it: an OptimizedTranslation on this same binary still answers '%s' for the same call (N4). The two classes disagree, so which answer you get depends on how the translation was built, not on the engine alone" % p5,
		p5 == "maca")

	var mem2 := Translation.new()
	mem2.locale = "pt"
	mem2.add_plural_message("APPLE", PackedStringArray(["maca", "macas"]))
	only([mem2])
	TranslationServer.set_locale("pt")
	var a1 := plural("APPLE", "APPLES", 1)
	var a5 := plural("APPLE", "APPLES", 5)
	if newer:
		check("N14", "on %s add_plural_message(\"APPLE\", [\"maca\", \"macas\"]) is honoured: n=1 gives '%s' and n=5 gives '%s'" % [vi.string, a1, a5],
			a1 == "maca" and a5 == "macas")
	else:
		check("N14", "on %s the same add_plural_message(\"APPLE\", [\"maca\", \"macas\"]) is ACCEPTED and then discarded: n=1 gives '%s' and n=5 gives '%s'. The method takes your plural forms, returns no error, and the base Translation class selects form 0 forever. An API that exists and silently ignores its argument is worse than one that is missing" % [vi.string, a1, a5],
			a1 == "maca" and a5 == "maca")

	# -------------------------------------------------------------- N15-N18
	# What a .po actually does differently.
	check("N15", "the .po importer produced a %s (4.2-4.4 name this class TranslationPO; 4.7 merged it into Translation, so a script that checks the class name breaks on upgrade)" % po_pt.get_class(),
		po_pt.get_class() in ["TranslationPO", "Translation"])

	only([po_pt])
	TranslationServer.set_locale("pt")
	var q1 := plural("APPLE", "APPLES", 1)
	var q5 := plural("APPLE", "APPLES", 5)
	var q0 := plural("APPLE", "APPLES", 0)
	check("N16", "same keys, same locale, .po instead of .csv: n=1 gives '%s', n=5 gives '%s', n=0 gives '%s'. The Plural-Forms header in the file, 'nplurals=2; plural=(n != 1)', is what picks the form" % [q1, q5, q0],
		q1 == "maca" and q5 == "macas" and q0 == "macas")

	only([po_ru])
	TranslationServer.set_locale("ru")
	var r1 := plural("APPLE", "APPLES", 1)
	var r3 := plural("APPLE", "APPLES", 3)
	var r5 := plural("APPLE", "APPLES", 5)
	var r11 := plural("APPLE", "APPLES", 11)
	check("N17", "and the header is per-language, not per-engine: Russian with nplurals=3 gives 1->'%s', 3->'%s', 5->'%s', 11->'%s'. Note 11 takes the same form as 5, which is the rule the language has and no count-based if-statement in your code has" % [r1, r3, r5, r11],
		r1 == "ru-one" and r3 == "ru-few" and r5 == "ru-many" and r11 == "ru-many")

	# ------------------------------------------------------------------ N18
	# The migration people actually attempt: keep the CSV, add a .po next to it.
	only([csv_pt, po_pt])
	TranslationServer.set_locale("pt")
	var both := plural("APPLE", "APPLES", 5)
	check("N18", "with BOTH the CSV and the .po loaded for 'pt', tr_n(...,5) gives '%s'. Adding the .po without removing the CSV is not a half-fix that half-works — it is decided by which translation the server reaches first, and the CSV is still in the list" % both,
		both == "maca" or both == "macas")
	note("N18 measured value on this build: '%s'. Remove the CSV from the project's translation list; do not keep both." % both)

	print("---")
	if failures == 0:
		print("PLURALS: ALL PASS (%d checks) on %s" % [passes, vi.string])
	else:
		print("PLURALS: %d FAILED, %d passed on %s" % [failures, passes, vi.string])
	quit(1 if failures > 0 else 0)
