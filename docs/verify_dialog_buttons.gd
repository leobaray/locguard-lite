# Measures every claim in docs/why-the-ok-button-stays-in-english.md against a
# real Godot 4 binary. Run it through docs/verify_dialog_buttons.sh, which
# builds the throwaway project this script expects.
#
# The project has a strings.csv whose keys are the ENGLISH LITERALS the engine
# ships inside AcceptDialog, ConfirmationDialog and FileDialog. Nothing here
# asserts what those literals are: the script reads them off the real node and
# reports them, so a build that changed one is visible instead of silently
# passing.
extends SceneTree

var _fails: Array[String] = []
var _passes := 0
var _notes: Array[String] = []
var _skips: Array[String] = []

# `atr()` does not exist before 4.3. Calling a missing method from a --script
# SceneTree on 4.2 does not raise: it takes the process down without flushing
# the print that came before it, so every claim that reads the DRAWN string has
# to be gated on this flag rather than tried and caught.
var _has_atr := false

func check(id: String, got, want, what: String) -> void:
	if got == want:
		_passes += 1
		print("PASS ", id, " ", what, " -> ", got)
	else:
		_fails.append(id)
		print("FAIL ", id, " ", what, " -> got ", got, " want ", want)

func skip(id: String, why: String) -> void:
	_skips.append(id)
	print("SKIP ", id, " ", why)

func drawn(id: String, node, source: String, want: String, what: String) -> void:
	if not _has_atr:
		skip(id, what + " — this build has no atr(); the drawn string is not readable here")
		return
	check(id, node.atr(source), want, what)

func note(id: String, what: String, value) -> void:
	_notes.append(id)
	print("NOTE ", id, " ", what, " -> ", value)

func _init() -> void:
	var v := Engine.get_version_info()
	var build := "%d.%d" % [v.major, v.minor]
	print("BUILD ", v.string)

	var probe := Control.new()
	_has_atr = probe.has_method("atr")
	probe.free()
	if not _has_atr:
		print("NOTE this build predates Control.atr(); claims about the DRAWN string are skipped, not passed")

	TranslationServer.set_locale("pt_BR")

	# D1 — the premise. The project's own translation is loaded and answering.
	check("D1", TranslationServer.get_locale(), "pt_BR", "locale set by the game")
	check("D2", TranslationServer.get_loaded_locales(), PackedStringArray(["pt_BR"]),
		"the CSV produced exactly one locale")

	# D3..D5 — the four english literals ARE in this CSV and DO translate when
	# asked through the normal path. So nothing below can be blamed on a missing
	# row or a locale mismatch.
	check("D3", tr("OK"), "Certo", "tr() on the literal OK")
	check("D4", tr("Cancel"), "Cancelar", "tr() on the literal Cancel")
	check("D5", tr("Alert!"), "Alerta!", "tr() on the literal Alert!")

	# D6 — a string the engine uses but this CSV does NOT carry comes back
	# unchanged. The engine ships no runtime translation of its own for it.
	check("D6", tr("Open"), "Open", "a dialog literal absent from the CSV")

	var ad := AcceptDialog.new()
	var ok_button := ad.get_ok_button()

	# D7 — what the property says. This is the value a developer reads while
	# debugging, and it is english even though the translation is loaded.
	check("D7", ok_button.text, "OK", "AcceptDialog ok button .text")

	# D8 — what the screen says. Button draws atr(text), not text. Same node,
	# same frame, two different answers.
	drawn("D8", ok_button, ok_button.text, "Certo",
		"AcceptDialog ok button as drawn")

	# D9 — the window title takes the same path.
	check("D9", ad.title, "Alert!", "AcceptDialog .title")
	drawn("D10", ad, ad.title, "Alerta!", "AcceptDialog title as drawn")

	var cd := ConfirmationDialog.new()
	var cancel_button := cd.get_cancel_button()
	check("D11", cancel_button.text, "Cancel", "ConfirmationDialog cancel .text")
	drawn("D12", cancel_button, cancel_button.text, "Cancelar",
		"ConfirmationDialog cancel as drawn")

	# D13..D15 — FileDialog is where the version trap lives. The english literal
	# the engine puts on the accept button is NOT the same across 4.x, so the CSV
	# row that translated this button on one build does nothing on another.
	var fd := FileDialog.new()
	var fd_ok := fd.get_ok_button()
	var fd_literal: String = fd_ok.text
	note("D13", "FileDialog accept-button literal on this build", fd_literal)

	var expected_literal := "Save" if build in ["4.4", "4.5", "4.6", "4.7"] else "OK"
	check("D14", fd_literal, expected_literal,
		"FileDialog literal expected for the " + build + " line")

	# D15 — and it does translate, because THIS csv happens to carry both rows.
	# A project that only carried "OK" would regress to english on 4.4+.
	drawn("D15", fd_ok, fd_literal, tr(fd_literal),
		"FileDialog accept button as drawn")

	# D16 — the regression, stated as a measurement rather than a warning: the
	# row that worked on the 4.2/4.3 line ("OK") is not the row this build asks
	# for, on builds where the literal changed.
	var csv_row_that_used_to_work := "OK"
	check("D16", fd_literal == csv_row_that_used_to_work, build in ["4.2", "4.3"],
		"does the old CSV row still match this build's FileDialog literal")

	# D17 — auto_translate_mode is INHERIT on a freshly constructed dialog, so
	# the drawing path above is the default behaviour, not something opted into.
	# The property does not exist before 4.3; report instead of failing there.
	if ad.has_method("set_auto_translate_mode"):
		check("D17", ad.auto_translate_mode, 0,
			"AcceptDialog auto_translate_mode is INHERIT by default")
	else:
		note("D17", "auto_translate_mode absent on this build (pre-4.3)", "skipped")

	# D18 — ok_button_text as a property is NOT a stable read across 4.x. On the
	# 4.7 line it comes back empty on a fresh dialog while the button underneath
	# still says OK. Code that compares it to "OK" changes behaviour on upgrade.
	var prop_value: String = ad.ok_button_text
	note("D18", "AcceptDialog.ok_button_text on a fresh dialog", "'" + prop_value + "'")
	var prop_is_empty := prop_value == ""
	check("D19", prop_is_empty, build == "4.7",
		"is ok_button_text empty on a fresh dialog")

	# D20 — and the button it points at is not empty on any build, so the empty
	# property is a reporting difference, not a different button.
	check("D20", ok_button.text, "OK", "the button behind the property")

	# D21 — setting the property writes through to the button on every build.
	ad.ok_button_text = "Cancel"
	check("D21", ok_button.text, "Cancel", "ok_button_text writes through")
	drawn("D22", ok_button, ok_button.text, "Cancelar",
		"and the written value is translated the same way")

	# D23 — a button you add yourself takes the identical path. There is no
	# separate rule for engine buttons versus your own.
	var extra := ad.add_button("Cancel", false, "x")
	drawn("D23", extra, extra.text, "Cancelar", "add_button text as drawn")

	print("---")
	print("passes=", _passes, " fails=", _fails.size(), " skips=", _skips.size(), " notes=", _notes.size())
	if _fails.is_empty():
		print("DIALOG BUTTONS: ALL PASS")
	else:
		print("DIALOG BUTTONS: FAILED ", ", ".join(_fails))
	quit(0 if _fails.is_empty() else 1)
