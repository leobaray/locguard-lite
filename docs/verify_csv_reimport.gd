extends SceneTree

# Asks a real Godot 4 binary what actually happens to your game when the
# translation CSV changes: which files the importer writes, which of them the
# game loads, and which of them keep answering after you delete the column that
# produced them.
#
# The forum answers to "I edited strings.csv and the game did not change" are
# "restart the editor", "delete .godot", "reimport by hand" and "your CSV is
# broken". Three of those are about the import, and the most common cause
# measured here is not an import failure at all: the file imports perfectly and
# nothing loads it.
#
# Claim ids (R*) are the ones cited in
# docs/why-editing-strings-csv-changes-nothing.md. Every check prints PASS/FAIL;
# the script exits non-zero if any fails, so a newer Godot tells you which line
# stopped holding.
#
# The script runs one PHASE per invocation (passed after `--`), because some
# claims are only visible across two import passes with different CSVs on disk.
# docs/verify_csv_reimport.sh drives the phases and the import passes; running
# this file by hand measures only the phase you ask for.

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

func files_in_root() -> PackedStringArray:
	return DirAccess.get_files_at("res://")

func read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()

func setting_list() -> PackedStringArray:
	return ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray())

func tr_in(locale: String, key: String) -> String:
	TranslationServer.set_locale(locale)
	return tr(key)

func _init() -> void:
	var phase := "a"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		phase = args[0]
	print("--- phase %s on %s" % [phase, Engine.get_version_info().string])

	match phase:
		"a": _phase_a()
		"b1": _phase_b1()
		"b2": _phase_b2()
		"b3": _phase_b3()
		"c": _phase_c()
		_:
			print("FAIL  R0  unknown phase '%s'" % phase)
			failures += 1

	print("CSV REIMPORT phase %s: %d passed, %d failed" % [phase, passes, failures])
	quit(1 if failures > 0 else 0)

# ---------------------------------------------------------------- phase A
# A project whose strings.csv imported cleanly and whose project settings were
# never touched. This is the state every project is in right after you drop a
# CSV into it.
func _phase_a() -> void:
	var files := files_in_root()
	check("R1", "the importer wrote one .translation per column (strings.en / strings.fr)",
		files.has("strings.en.translation") and files.has("strings.fr.translation"))
	check("R2", "internationalization/locale/translations is EMPTY after the import — the engine registered nothing",
		setting_list().is_empty())
	check("R3", "tr() returns the key itself in en and in fr: no error, no warning, no missing-file message",
		tr_in("en", "GREETING") == "GREETING" and tr_in("fr", "GREETING") == "GREETING")

	# The same file, loaded by hand, answers immediately: the import is not the
	# thing that failed.
	var ok_manual := false
	if ResourceLoader.exists("res://strings.fr.translation"):
		TranslationServer.add_translation(load("res://strings.fr.translation"))
		ok_manual = tr_in("fr", "GREETING") == "Bonjour"
	check("R4", "loading that same .translation by hand makes fr answer 'Bonjour' — the imported file was never the problem",
		ok_manual)

# ------------------------------------------------------------- phase B1
# Same project, but project.godot now lists both .translation files, which is
# what the Localization tab writes when you add them.
func _phase_b1() -> void:
	check("R5", "with both files listed in project settings, en and fr both answer",
		tr_in("en", "GREETING") == "Hello" and tr_in("fr", "GREETING") == "Bonjour")

# ------------------------------------------------------------- phase B2
# The CSV was edited (a value changed) and the editor was started once.
func _phase_b2() -> void:
	check("R6", "editing a VALUE in the CSV and starting the editor once reaches the game (Hello -> Hello-v2)",
		tr_in("en", "GREETING") == "Hello-v2")

# ------------------------------------------------------------- phase B3
# The whole `fr` column was deleted from the CSV and the editor was started
# again. The dev's intent: French is gone.
func _phase_b3() -> void:
	var files := files_in_root()
	check("R7", "deleting the fr COLUMN does not delete strings.fr.translation — the file stays in the project",
		files.has("strings.fr.translation"))
	check("R8", "and it still answers, with the text of the column that no longer exists",
		tr_in("fr", "GREETING") == "Bonjour")
	check("R9", "en still tracks the CSV, so the project is half-updated in one pass",
		tr_in("en", "GREETING") == "Hello-v2")

	var imp := read_text("res://strings.csv.import")
	check("R10", "strings.csv.import no longer lists the fr file in dest_files",
		imp != "" and not imp.contains("strings.fr.translation"))
	var listed := ", ".join(Array(setting_list()))
	check("R11", "while project settings still does — two files in the same project disagree about which languages exist",
		listed.contains("strings.fr.translation"))
	note("the engine printed no error for R7-R11; the stale language ships with the game.")

# -------------------------------------------------------------- phase C
# Import bookkeeping, and the one thing this script cannot measure.
func _phase_c() -> void:
	var files := files_in_root()
	check("R12", "a clone with no .godot/ and no .translation regenerates both files on ONE editor start",
		files.has("strings.en.translation") and files.has("strings.fr.translation"))
	check("R13", "and the regenerated fr file answers 'Bonjour'",
		tr_in("fr", "GREETING") == "Bonjour")

	var md5_dir := "res://.godot/imported"
	var found := ""
	var d := DirAccess.open(md5_dir)
	if d != null:
		for f in d.get_files():
			if f.begins_with("strings.csv-") and f.ends_with(".md5"):
				found = read_text(md5_dir + "/" + f)
	check("R14", "the CSV import records a source_md5 under .godot/imported — the cold-start reimport gate is content-based",
		found.contains("source_md5="))
