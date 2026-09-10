extends SceneTree

# Asks a real Godot 4 binary what the second argument of tr() — the message
# context — actually does, once the string it has to find came out of the
# importer.
#
# The question ("I pass a context and nothing changes") is usually answered with
# a spelling fix or a rebuild. Neither is the problem. There are two translation
# back-ends in the engine and they disagree about what a context is:
#
#   * the CSV importer produces an OptimizedTranslation, which has no context
#     table at all — so it does not MISS on a context, it IGNORES it, and
#     returns the one string it has for that key;
#   * the .po importer keeps msgctxt — so a context it does not know is a miss,
#     and a miss returns the key raw, with no fall back to the no-context entry.
#
# Both are loaded into the same TranslationServer by the same call. Which one
# answers first is decided by the order add_translation() was called, so the
# same tr("KEY", &"Ctx") can return the contextual string, the non-contextual
# string, or the key itself, in one project, with no error printed for any of
# the three.
#
# Claim ids (X*) are the ones cited in
# docs/why-the-context-you-pass-to-tr-changes-nothing.md. Every check prints
# PASS/FAIL and the script exits non-zero if any fails, so a newer Godot tells
# you which line stopped holding.
#
# Two claims are version-dependent and are written that way on purpose: the .po
# resource was renamed between 4.4 and 4.7, and the message list it exposes
# changed with it. The script reads Engine.get_version_info() and checks the
# claim that applies to the binary it is running on, printing the measured value
# either way. A checker that hard-codes one engine's answer reports its own age,
# not the engine.
#
# The CSVs and the .po are written by verify_context.sh and imported by a real
# editor pass before this file runs, so every claim about the CSV path is a
# claim about the resource the importer actually produced.

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
	# Leaves the server holding exactly these translations, in this order.
	TranslationServer.clear()
	for r in res:
		TranslationServer.add_translation(r)

func _initialize() -> void:
	print("---")
	print("BUILD %s" % vi.string)
	# The .po resource was renamed to plain Translation in 4.5.
	var newer: bool = vi.major > 4 or (vi.major == 4 and vi.minor >= 5)

	var csv_pt: Translation = load("res://strings.pt.translation")
	var po: Translation = load("res://pt.po")
	var ctx_locale: Translation = load("res://ctxcol.context.translation")
	var ctx_en: Translation = load("res://ctxcol.en.translation")

	if csv_pt == null or po == null or ctx_locale == null:
		print("CONTEXT: ERROR — a resource under measurement did not load; nothing was measured.")
		quit(1)
		return

	# ---------------------------------------------------------------- X1-X2
	# What the CSV importer produced, and why counting it lies.
	check("X1", "the CSV importer produced a %s for locale '%s', holding %s" % [
		csv_pt.get_class(), csv_pt.locale, csv_pt.get_translated_message_list()],
		csv_pt.get_class() == "OptimizedTranslation" and csv_pt.locale == "pt"
		and csv_pt.get_translated_message_list().size() == 2)

	check("X2", "that resource answers get_message_count() = %d while it holds %d messages — the count is not the number of strings, so an audit that trusts it reports an empty file" % [
		csv_pt.get_message_count(), csv_pt.get_translated_message_list().size()],
		csv_pt.get_message_count() == 0 and csv_pt.get_translated_message_list().size() == 2)

	# ---------------------------------------------------------------- X3-X6
	# The CSV path does not miss on a context. It ignores it.
	var m_plain := csv_pt.get_message("OPEN")
	var m_ctx := csv_pt.get_message("OPEN", &"Menu")
	check("X3", "csv.get_message(\"OPEN\") is '%s'" % m_plain, m_plain == "Abrir")
	check("X4", "csv.get_message(\"OPEN\", &\"Menu\") is '%s' — the SAME string. The context argument is discarded, not looked up" % m_ctx,
		m_ctx == "Abrir" and m_ctx == m_plain)

	only([csv_pt])
	TranslationServer.set_locale("pt")
	var s_ctx := TranslationServer.translate("OPEN", &"Menu")
	check("X5", "with only the CSV loaded, TranslationServer.translate(\"OPEN\", &\"Menu\") is '%s'" % s_ctx,
		s_ctx == "Abrir")
	var n := Node.new()
	var t_ctx := n.tr("OPEN", &"Menu")
	check("X6", "the scripting entry point agrees: Node.tr(\"OPEN\", &\"Menu\") is '%s'. Nothing anywhere reports that a context was asked for and thrown away" % t_ctx,
		t_ctx == "Abrir")
	n.free()

	# ---------------------------------------------------------------- X7-X12
	# The .po path keeps contexts, and a context it does not know is a hard miss.
	only([po])
	TranslationServer.set_locale("pt")
	check("X7", "the .po importer produced a %s for locale '%s' with get_message_count() = %d — three entries for ONE msgid, told apart only by msgctxt" % [
		po.get_class(), po.locale, po.get_message_count()],
		po.get_message_count() == 3 and po.locale == "pt")

	var p_plain := TranslationServer.translate("OPEN")
	var p_menu := TranslationServer.translate("OPEN", &"Menu")
	var p_door := TranslationServer.translate("OPEN", &"Door")
	var p_nope := TranslationServer.translate("OPEN", &"Nope")
	var p_close := TranslationServer.translate("CLOSE", &"Menu")
	check("X8", "po translate(\"OPEN\") is '%s' — the entry with no msgctxt" % p_plain, p_plain == "Abrir")
	check("X9", "po translate(\"OPEN\", &\"Menu\") is '%s'" % p_menu, p_menu == "Abrir-menu")
	check("X10", "po translate(\"OPEN\", &\"Door\") is '%s' — same key, third string" % p_door, p_door == "Destrancar")
	check("X11", "po translate(\"OPEN\", &\"Nope\") is '%s' — an unknown context returns the KEY, raw on the player's screen. It does not fall back to the entry with no context, which is right there in the same file" % p_nope,
		p_nope == "OPEN")
	check("X12", "po translate(\"CLOSE\", &\"Menu\") is '%s' — CLOSE is only in the CSV, so through the .po alone it is raw too" % p_close,
		p_close == "CLOSE")

	# ---------------------------------------------------------------- X13-X16
	# Both files in one project. The order of add_translation() decides.
	only([csv_pt, po])
	TranslationServer.set_locale("pt")
	var csv_first := TranslationServer.translate("OPEN", &"Menu")
	check("X13", "CSV added first, then the .po: translate(\"OPEN\", &\"Menu\") is '%s'. The CSV answered, so the .po's contextual entry is never reached" % csv_first,
		csv_first == "Abrir")

	only([po, csv_pt])
	TranslationServer.set_locale("pt")
	var po_first := TranslationServer.translate("OPEN", &"Menu")
	check("X14", ".po added first, then the CSV: the same call is '%s'" % po_first, po_first == "Abrir-menu")

	check("X15", "so the same call, on the same two files, returns '%s' or '%s' depending only on the order add_translation() ran — and add_translation() runs in the order project.godot lists the files" % [
		csv_first, po_first], csv_first != po_first)

	only([csv_pt, po])
	TranslationServer.set_locale("pt")
	var rescued := TranslationServer.translate("CLOSE", &"Menu")
	check("X16", "the reverse also hides: translate(\"CLOSE\", &\"Menu\") is '%s' — the CSV answers a call the .po alone would have left raw, so a missing msgctxt entry can be invisible for as long as some CSV carries the key" % rescued,
		rescued == "Fechar")

	# ---------------------------------------------------------------- X17-X21
	# What happens when the context is put where it cannot go: a CSV column.
	check("X17", "a CSV column headed 'context' imported as a LOCALE: ctxcol.context.translation exists, with locale '%s'" % ctx_locale.locale,
		ctx_locale.locale == "context")
	check("X18", "and its 'translation' of OPEN is the literal word %s — the context value became a translated string in an invented language" % [
		ctx_locale.get_translated_message_list()],
		ctx_locale.get_translated_message_list() == PackedStringArray(["Menu"]))
	var std := TranslationServer.standardize_locale("context")
	check("X19", "TranslationServer.standardize_locale(\"context\") is '%s' — the engine takes it as a language name and reports nothing" % std,
		std == "context")

	only([ctx_locale])
	TranslationServer.set_locale("context")
	var fake := TranslationServer.translate("OPEN")
	check("X20", "and it is selectable: after set_locale(\"context\") the locale is '%s' and translate(\"OPEN\") is '%s'" % [
		TranslationServer.get_locale(), fake],
		TranslationServer.get_locale() == "context" and fake == "Menu")

	if ctx_en == null:
		note("X21 skipped: ctxcol.en.translation did not load on this binary; the claim below is about column shifting, not about the extra locale, which X17-X20 measured.")
	else:
		check("X21", "the real columns are unharmed: ctxcol.en.translation is locale '%s' holding %s. Nothing shifted — the file simply ships one extra language nobody wrote" % [
			ctx_en.locale, ctx_en.get_translated_message_list()],
			ctx_en.locale == "en" and ctx_en.get_translated_message_list() == PackedStringArray(["Open"]))

	# ---------------------------------------------------------------- X22-X23
	# Version-dependent: what a .po IS, as far as code can tell.
	var po_class := po.get_class()
	var has_po_class := ClassDB.class_exists("TranslationPO")
	if newer:
		check("X22", "on %s a .po loads as class '%s' and ClassDB.class_exists(\"TranslationPO\") is %s — code that branches on the class name stops recognising gettext catalogues here" % [
			vi.string, po_class, has_po_class],
			po_class == "Translation" and has_po_class == false)
	else:
		check("X22", "on %s a .po loads as class '%s' and ClassDB.class_exists(\"TranslationPO\") is %s" % [
			vi.string, po_class, has_po_class],
			po_class == "TranslationPO" and has_po_class == true)

	var listed := po.get_translated_message_list().size()
	if newer:
		check("X23", "on %s get_translated_message_list() on that .po returns %d of its %d entries" % [
			vi.string, listed, po.get_message_count()],
			listed == 3)
	else:
		check("X23", "on %s get_translated_message_list() on that .po returns %d of its %d entries — the contextual ones are not in the list, so a tool that audits a catalogue through that list sees one string in three" % [
			vi.string, listed, po.get_message_count()],
			listed == 1)

	print("---")
	if failures == 0:
		print("CONTEXT: ALL PASS (%d/%d)" % [passes, passes])
		quit(0)
	else:
		print("CONTEXT: %d FAIL, %d PASS" % [failures, passes])
		quit(1)
