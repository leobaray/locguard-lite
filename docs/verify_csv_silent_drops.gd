extends SceneTree

# Asks a real Godot 4 binary which rows of a translation CSV ever become a
# message the player can reach, and which arguments of `tr()` the engine
# accepts and then ignores.
#
# The premise being tested is the one every "my string is not translated"
# thread assumes: that a row in strings.csv becomes a message, and that the
# extra arguments in the tr() signature do something. Both are measured here
# instead of assumed. Rows are dropped, collapsed and made unreachable without
# a single error, and two of the arguments in the signature are accepted and
# discarded by the CSV path.
#
# Claim ids (D*) are the ones cited in
# docs/why-a-row-in-strings-csv-never-reaches-the-player.md. Every check prints
# PASS/FAIL; the script exits non-zero if any fails, so a newer Godot tells you
# which line stopped holding.
#
# The script runs one PHASE per invocation (passed after `--`), because the
# claims about storage are only visible across import passes with different
# importer options on disk. docs/verify_csv_silent_drops.sh drives the phases
# and the import passes; running this file by hand measures only the phase you
# ask for.

var failures := 0
var passes := 0

func check(id: String, what: String, ok: bool) -> void:
	if ok:
		passes += 1
		print("PASS  %s  %s" % [id, what])
	else:
		failures += 1
		print("FAIL  %s  %s" % [id, what])

func note(s: String) -> void:
	print("NOTE  %s" % s)

func read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()

func english() -> Translation:
	var en := load("res://strings.en.translation")
	TranslationServer.add_translation(en)
	TranslationServer.set_locale("en")
	return en

func minor() -> int:
	return Engine.get_version_info().minor

func _init() -> void:
	var phase := "a"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		phase = args[0]
	print("--- phase %s on %s" % [phase, Engine.get_version_info().string])
	match phase:
		"a": _phase_a()
		"b": _phase_b()
		"c": _phase_c()
		_:
			print("unknown phase %s" % phase)
			quit(2)
			return
	print("CSV SILENT DROPS: %s (%d passed, %d failed)" % [
		"ALL PASS" if failures == 0 else "FAILURES", passes, failures])
	quit(1 if failures > 0 else 0)

# ------------------------------------------------------------------ phase A
# The default import. This is what ships unless you went and changed it.
func _phase_a() -> void:
	var en := english()

	check("D1", "the default CSV import produces an OptimizedTranslation, not a Translation",
		en.get_class() == "OptimizedTranslation")
	check("D2", "and an OptimizedTranslation reports zero messages and an empty key list — the keys are not in the file, only their hashes",
		en.get_message_count() == 0 and en.get_message_list().is_empty())
	check("D3", "while the translated VALUES are still listed, so a tool can read every string that ships and none of the keys that select them",
		en.get_translated_message_list().size() > 0)

	check("D4", "a plain row answers through tr()",
		tr("GREETING") == "Hello")
	check("D5", "a row whose cell is EMPTY puts the KEY on screen, not an empty string — the untranslated one looks like a bug, not like a blank",
		tr("EMPTY_CELL") == "EMPTY_CELL")
	check("D6", "two rows with the same key: the LAST one wins and the first is gone",
		tr("DUP") == "second-en")

	var log := read_text("res://import_log.txt")
	check("D7", "and the import that dropped it printed no error and no warning about the duplicate key",
		log != "" and not log.to_lower().contains("dup"))

	check("D8", "keys are not trimmed: a key typed with surrounding spaces is reachable only by retyping the spaces",
		tr("SPACED") == "SPACED" and tr(" SPACED ") == "spaced-en")
	check("D9", "a quoted field keeps its comma",
		tr("QUOTED") == "with, comma")

	check("D10", "\\n inside a KEY stays two literal characters (unescape_keys is false by default), so GDScript has to escape the backslash to reach it",
		tr("LINE\\nBREAK") == "two-line-en" and tr("LINE\nBREAK") != "two-line-en")
	check("D11", "\\n inside a VALUE becomes a real newline (unescape_translations is true by default) — the same two characters are data on one side of the comma and an escape on the other",
		tr("ESCAPED").contains("\n"))

	check("D12", "tr() accepts a context argument and the CSV path ignores it: the no-context message answers for every context",
		tr("GREETING", "menu") == "Hello")
	check("D13", "so does get_message() on the resource itself",
		en.get_message("GREETING", "menu") == "Hello")
	check("D14", "tr_n() accepts a plural and a count and ignores both: n=1 and n=2 return the same singular message",
		tr_n("GREETING", "GREETINGS", 1) == "Hello" and tr_n("GREETING", "GREETINGS", 2) == "Hello")
	check("D15", "get_plural_message() falls back to get_message() the same way",
		en.get_plural_message("GREETING", "GREETINGS", 2) == "Hello")

	check("D16", "a missing key comes back as the key",
		tr("MISSING_KEY") == "MISSING_KEY")
	check("D17", "but a missing key through tr_n() comes back as the PLURAL argument — the same absent string surfaces under two different names",
		tr_n("MISSING_KEY", "MISSING_PLURAL", 3) == "MISSING_PLURAL")
	note("D12-D15: context and plurals are a PO-file feature. The CSV importer has no column for either, and nothing reports the mismatch.")

	# The generated .import file is the only place the compression option is
	# written down, and the builds do not write it the same way. Asserted from
	# the running binary rather than tabled from one of them.
	var generated := read_text("res://strings.csv.import")
	if minor() >= 7:
		check("D18", "4.7 writes the default compression option as compress=1",
			generated.contains("compress=1"))
	else:
		check("D18", "4.2-4.4 write the SAME default as compress=true — one boolean, two spellings, so a search-and-replace across a project touched by two editor versions matches only half the files",
			generated.contains("compress=true"))

# ------------------------------------------------------------------ phase B
# Re-imported with compress=false. This is the only way to read the keys back.
func _phase_b() -> void:
	var en := english()
	check("D19", "re-imported with compress=false the same CSV produces a plain Translation",
		en.get_class() == "Translation")
	var keys := Array(en.get_message_list())
	check("D20", "whose key list is readable, and contains the duplicated key exactly once",
		keys.has("GREETING") and keys.count("DUP") == 1)
	check("D21", "and keeps the untrimmed key with its spaces",
		keys.has(" SPACED ") and not keys.has("SPACED"))

	# The empty cell is where the builds stop agreeing. Both branches are
	# asserted from the running binary, so this line is a measurement on any
	# build rather than a table copied from one.
	if minor() >= 7:
		check("D22", "4.7 drops the empty-cell row at import: it is not in the key list at all",
			not keys.has("EMPTY_CELL") and keys.size() == 6)
	else:
		check("D22", "4.2-4.4 KEEP the empty-cell row, storing an empty message that tr() still refuses to return — the row exists and is unreachable",
			keys.has("EMPTY_CELL") and keys.size() == 7 and en.get_message("EMPTY_CELL") == "")
	check("D23", "either way the player sees the key, so the storage difference never shows up as a different symptom",
		tr("EMPTY_CELL") == "EMPTY_CELL")

# ------------------------------------------------------------------ phase C
# The same option written the other way round, which is what a hand-edited
# .import file ends up containing.
func _phase_c() -> void:
	var en := english()
	check("D24", "compress=0 and compress=false are the same option to every build measured here — both produce a plain Translation, and only the spelling the editor writes differs (D18)",
		read_text("res://strings.csv.import").contains("compress=0") and en.get_class() == "Translation")
	note("D18/D24: the value is not the trap, the two spellings of it are. Grep a project for compress=true and a 4.7-imported CSV will not answer.")
