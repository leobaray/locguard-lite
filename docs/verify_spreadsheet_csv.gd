extends SceneTree

# Asks a real Godot 4 binary what happens to a translation table between the
# spreadsheet that saved it and the string the player reads.
#
# The nine files under measurement hold the SAME two-language table. They differ
# only in the options a spreadsheet offers when it writes a CSV: encoding,
# delimiter, line endings, and whatever the header row picked up on the way. The
# result splits into three groups, and the middle one is the expensive one:
#
#   * refused — the semicolon file and the UTF-16 file produce no .translation
#     at all, so the locale does not exist in the shipped game;
#   * accepted unchanged — the byte order mark and the CRLF line endings, the
#     two suspects everyone starts with, change nothing;
#   * accepted and rewritten — the Latin-1 file imports like any other file and
#     every accented word comes out altered, with no error at lookup time.
#
# A fourth group is neither: the header row IS the locale list, so a stray space
# in a header cell produces a locale literally named " pt", which the game loads,
# reports as loaded, and never matches when you ask for "pt".
#
# Claim ids (E*) are the ones cited in
# docs/why-the-csv-your-spreadsheet-saved-translates-nothing.md. Every check
# prints PASS/FAIL and the script exits non-zero if any fails, so a newer Godot
# tells you which line stopped holding.
#
# Two claims are version-dependent and are written that way on purpose. The
# UTF-8 error recovery changed between 4.4 and 4.7 (an older engine swallows the
# byte that follows the bad one; 4.7 does not), and the trailing empty header
# column is fatal to the whole file on 4.2 and merely ignored from 4.3 on. The
# script reads Engine.get_version_info() and checks the claim that applies to
# the binary it is running on, printing the measured bytes either way. A checker
# that hard-codes one engine's answer reports its own age, not the engine.
#
# The CSVs are written by verify_spreadsheet_csv.sh and imported by a real
# editor pass before this file runs, so every claim is a claim about the
# resource the importer actually produced.

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

func msg(t: Translation, key: String) -> String:
	return String(t.get_message(key))

func bytes(s: String) -> String:
	return str(s.to_utf8_buffer())

func produced(prefix: String) -> Array:
	# Every .translation the importer wrote for one source CSV, by file name.
	# Absence is the measurement for the refused files, so this reads the
	# directory rather than guessing locale names.
	var out := []
	var d := DirAccess.open("res://")
	if d == null:
		return out
	for f in d.get_files():
		if f.begins_with(prefix + ".") and f.ends_with(".translation"):
			out.append(f)
	out.sort()
	return out

func only(res: Array) -> void:
	# Leaves the server holding exactly these translations, in this order.
	TranslationServer.clear()
	for r in res:
		TranslationServer.add_translation(r)

func _initialize() -> void:
	print("---")
	print("BUILD %s" % vi.string)
	# UTF-8 error recovery changed after 4.4: an older engine consumes the byte
	# that follows an invalid one, 4.7 replaces in place and keeps it.
	var newer: bool = vi.major > 4 or (vi.major == 4 and vi.minor >= 5)
	# The trailing empty header column is fatal to the whole file on 4.2 only.
	var v42: bool = vi.major == 4 and vi.minor == 2

	var plain_pt: Translation = load("res://plain.pt.translation")
	var plain_en: Translation = load("res://plain.en.translation")
	if plain_pt == null or plain_en == null:
		print("SPREADSHEET: ERROR — the baseline did not load; nothing was measured.")
		quit(1)
		return

	# ------------------------------------------------------------------- E1
	# The reference every other file is compared against.
	check("E1", "the UTF-8 baseline imported as %s for locale '%s', HELLO=%s BYE=%s" % [
		plain_pt.get_class(), plain_pt.locale, bytes(msg(plain_pt, "HELLO")),
		bytes(msg(plain_pt, "BYE"))],
		plain_pt.get_class() == "OptimizedTranslation" and plain_pt.locale == "pt"
		and msg(plain_pt, "HELLO") == "Olá" and msg(plain_pt, "BYE") == "Até mais")

	# ------------------------------------------------------------------ E2-E5
	# The two suspects that are not the problem.
	var bom_pt: Translation = load("res://bom.pt.translation")
	check("E2", "a UTF-8 byte order mark still produces bom.pt.translation, locale '%s'" % [
		"none" if bom_pt == null else bom_pt.locale],
		bom_pt != null and bom_pt.locale == "pt")
	check("E3", "with the BOM, HELLO=%s and BYE=%s — byte-identical to the baseline" % [
		"n/a" if bom_pt == null else bytes(msg(bom_pt, "HELLO")),
		"n/a" if bom_pt == null else bytes(msg(bom_pt, "BYE"))],
		bom_pt != null and msg(bom_pt, "HELLO") == msg(plain_pt, "HELLO")
		and msg(bom_pt, "BYE") == msg(plain_pt, "BYE"))

	var crlf_pt: Translation = load("res://crlf.pt.translation")
	check("E4", "CRLF line endings still produce crlf.pt.translation, locale '%s'" % [
		"none" if crlf_pt == null else crlf_pt.locale],
		crlf_pt != null and crlf_pt.locale == "pt")
	check("E5", "with CRLF, BYE=%s (length %d) — no trailing carriage return in the last column" % [
		"n/a" if crlf_pt == null else bytes(msg(crlf_pt, "BYE")),
		0 if crlf_pt == null else msg(crlf_pt, "BYE").length()],
		crlf_pt != null and msg(crlf_pt, "BYE") == msg(plain_pt, "BYE")
		and msg(crlf_pt, "BYE").length() == 8)

	# ------------------------------------------------------------------ E6-E8
	# The files the importer refuses. Nothing is written, so nothing ships.
	check("E6", "the semicolon-delimited file produced %s" % [str(produced("semi"))],
		produced("semi").is_empty())
	check("E7", "the UTF-16 file produced %s" % [str(produced("utf16"))],
		produced("utf16").is_empty())
	only([])
	TranslationServer.set_locale("pt")
	check("E8", "with that locale absent, translate('HELLO') returns %s — the key, raw" % [
		TranslationServer.translate("HELLO")],
		String(TranslationServer.translate("HELLO")) == "HELLO")

	# ----------------------------------------------------------------- E9-E13
	# The file that imports and is wrong. This is the group that costs money.
	var l1_pt: Translation = load("res://latin1.pt.translation")
	var l1_en: Translation = load("res://latin1.en.translation")
	check("E9", "the Latin-1 file DID import: latin1.pt.translation, locale '%s', files %s" % [
		"none" if l1_pt == null else l1_pt.locale, str(produced("latin1"))],
		l1_pt != null and l1_pt.locale == "pt" and produced("latin1").size() == 2)
	check("E10", "its HELLO is %s, the baseline's is %s — not the same string" % [
		"n/a" if l1_pt == null else bytes(msg(l1_pt, "HELLO")), bytes(msg(plain_pt, "HELLO"))],
		l1_pt != null and msg(l1_pt, "HELLO") != msg(plain_pt, "HELLO"))

	var l1_hello := "" if l1_pt == null else msg(l1_pt, "HELLO")
	var l1_bye := "" if l1_pt == null else msg(l1_pt, "BYE")
	if newer:
		check("E11", "on 4.5+ the accented byte becomes U+FFFD in place: HELLO=%s (length %d)" % [
			bytes(l1_hello), l1_hello.length()],
			l1_hello == "Ol�" and l1_hello.length() == 3)
		check("E12", "and the space after it survives: BYE=%s (length %d)" % [
			bytes(l1_bye), l1_bye.length()],
			l1_bye == "At� mais" and l1_bye.length() == 8)
	else:
		check("E11", "on 4.2-4.4 the accented byte at end of field becomes a plain SPACE: HELLO=%s (length %d)" % [
			bytes(l1_hello), l1_hello.length()],
			l1_hello == "Ol " and l1_hello.length() == 3)
		check("E12", "and mid-field it eats the byte after it: BYE=%s (length %d) — no space before 'mais'" % [
			bytes(l1_bye), l1_bye.length()],
			l1_bye == "At�mais" and l1_bye.length() == 7)

	check("E13", "the ASCII column of the same file is untouched: latin1.en HELLO=%s" % [
		"n/a" if l1_en == null else bytes(msg(l1_en, "HELLO"))],
		l1_en != null and msg(l1_en, "HELLO") == msg(plain_en, "HELLO")
		and msg(l1_en, "BYE") == msg(plain_en, "BYE"))
	check("E14", "and the damaged string answers like any other: non-empty, no error, length %d" % [
		l1_hello.length()],
		l1_hello.length() > 0 and l1_hello != "HELLO")

	# ---------------------------------------------------------------- E15-E19
	# The header row is the locale list, and it is taken literally.
	var sp: Translation = load("res://space. pt.translation")
	check("E15", "a header cell written ' pt' produced %s" % [str(produced("space"))],
		produced("space") == ["space. pt.translation", "space.en.translation"])
	check("E16", "its locale is '%s' — the space is part of the locale name" % [
		"none" if sp == null else sp.locale],
		sp != null and sp.locale == " pt")
	only([sp])
	TranslationServer.set_locale("pt")
	check("E17", "asking for 'pt' with only that loaded returns %s — the key, raw" % [
		TranslationServer.translate("HELLO")],
		String(TranslationServer.translate("HELLO")) == "HELLO")
	TranslationServer.set_locale(" pt")
	check("E18", "asking for ' pt', space included, returns %s — the data was there all along" % [
		bytes(String(TranslationServer.translate("HELLO")))],
		String(TranslationServer.translate("HELLO")) == "Olá")

	var dash: Translation = load("res://dash.pt_BR.translation")
	check("E19", "a header cell written 'pt-BR' is normalised to locale '%s' in %s" % [
		"none" if dash == null else dash.locale, str(produced("dash"))],
		dash != null and dash.locale == "pt_BR"
		and produced("dash") == ["dash.en.translation", "dash.pt_BR.translation"])

	# ---------------------------------------------------------------- E20-E21
	# A trailing comma on the header row: fatal on 4.2, ignored from 4.3.
	var tr_pt: Translation = load("res://trail.pt.translation")
	var tr_en: Translation = load("res://trail.en.translation")
	if v42:
		check("E20", "on 4.2 the trailing empty column voids the file: trail.pt reports locale '%s' and HELLO=%s" % [
			"none" if tr_pt == null else tr_pt.locale,
			"n/a" if tr_pt == null else bytes(msg(tr_pt, "HELLO"))],
			tr_pt != null and tr_pt.locale == "en" and msg(tr_pt, "HELLO") == "")
		check("E21", "and the English column goes with it: trail.en HELLO=%s" % [
			"n/a" if tr_en == null else bytes(msg(tr_en, "HELLO"))],
			tr_en != null and msg(tr_en, "HELLO") == "")
	else:
		check("E20", "from 4.3 the trailing empty column is dropped: trail.pt locale '%s', HELLO=%s" % [
			"none" if tr_pt == null else tr_pt.locale,
			"n/a" if tr_pt == null else bytes(msg(tr_pt, "HELLO"))],
			tr_pt != null and tr_pt.locale == "pt" and msg(tr_pt, "HELLO") == "Olá")
		check("E21", "and the English column survives: trail.en HELLO=%s" % [
			"n/a" if tr_en == null else bytes(msg(tr_en, "HELLO"))],
			tr_en != null and msg(tr_en, "HELLO") == "Hello")

	# -------------------------------------------------------------------- E22
	# Nine source files, and the count of what shipped is not nine times two.
	var all := []
	var d := DirAccess.open("res://")
	for f in d.get_files():
		if f.ends_with(".translation"):
			all.append(f)
	all.sort()
	check("E22", "nine CSVs produced %d .translation files: %s" % [all.size(), str(all)],
		all.size() == 14)

	note("the import pass runs a real editor; on 4.4 it writes every file and then aborts on an unrelated progress-dialog assert, so this script gates on the files, never on the editor's exit code.")
	note("get_message_count() is not used here: OptimizedTranslation does not keep the message texts, and 4.7 warns and answers 0.")

	print("---")
	if failures == 0:
		print("SPREADSHEET: ALL PASS (%d/%d)" % [passes, passes])
		quit(0)
	else:
		print("SPREADSHEET: %d FAIL / %d PASS" % [failures, passes + failures])
		quit(1)
