extends SceneTree

# Asks a real Godot 4 binary why a RichTextLabel shows the KEY while the very
# same key, on the very same frame, translates fine on a Label.
#
# The short version this file measures: a RichTextLabel has two doors for text,
# and only one of them is translated. `text` is looked up as ONE WHOLE STRING,
# so wrapping a key in a single tag turns it into a key nobody wrote down.
# `append_text()` / `add_text()` are never looked up at all -- and the next
# locale change silently throws that content away.
#
# Claim ids (R*) are the ones cited in
# docs/why-your-richtextlabel-shows-the-key-instead-of-the-translation.md.
# Every check prints PASS/FAIL. The engine's exit code is NOT the gate -- Godot
# exits 0 on a GDScript parse error -- so the gate is the summary line at the
# end. If it is missing, nothing was measured.
#
# The translations are the ones the engine's own CSV importer produced from
# strings.csv, loaded from the .translation files, not literals typed here.
# Everything version-dependent is addressed dynamically so the file still
# parses on 4.2, which has neither atr() nor auto_translate_mode.

var failures := 0
var passes := 0
var notes: Array[String] = []
var minor := 0

func check(id: String, what: String, ok: bool) -> void:
	if ok:
		passes += 1
		print("PASS  %s  %s" % [id, what])
	else:
		failures += 1
		print("FAIL  %s  %s" % [id, what])

func note(s: String) -> void:
	notes.append(s)

func has_prop(n, pname: String) -> bool:
	for p in n.get_property_list():
		if p.name == pname:
			return true
	return false

func mk(bb: bool) -> RichTextLabel:
	var r := RichTextLabel.new()
	root.add_child(r)
	r.bbcode_enabled = bb
	return r

func _init() -> void:
	var vi := Engine.get_version_info()
	minor = int(vi.minor)
	print("BUILD %s" % vi.string)

	for loc in ["en", "de"]:
		var t = load("res://strings.%s.translation" % loc)
		if t == null:
			print("FAIL  R--  strings.%s.translation did not load; nothing below would mean anything" % loc)
			print("RICHTEXT BBCODE: 1 FAIL / 0 PASS")
			quit(1)
			return
		TranslationServer.add_translation(t)
	TranslationServer.set_locale("de")
	check("R--", "the imported German table is live (tr(\"GREET\") = %s)" % tr("GREET"), tr("GREET") == "Hallo")

	# ---- the door that works -------------------------------------------------
	var r := mk(true)
	r.text = "GREET"
	await process_frame
	check("R1", "a bare key in .text reaches the player translated (on screen: %s)" % r.get_parsed_text(),
		r.get_parsed_text() == "Hallo")

	var lbl := Label.new()
	root.add_child(lbl)
	lbl.text = "GREET"
	await process_frame

	# ---- the whole string is the key ----------------------------------------
	r.text = "[b]GREET[/b]"
	await process_frame
	check("R2", "wrapping that same key in one [b] tag makes it untranslatable: the player reads %s, bold, with no error" % r.get_parsed_text(),
		r.get_parsed_text() == "GREET")

	r.text = "Score: GREET"
	await process_frame
	check("R3", "a key sitting inside a sentence is never looked up either (on screen: %s)" % r.get_parsed_text(),
		r.get_parsed_text() == "Score: GREET")

	r.text = "GREET"
	await process_frame
	check("R4", "the lookup is the ENTIRE .text, matched literally: the same three characters translate alone (%s) and not one character further" % r.get_parsed_text(),
		r.get_parsed_text() == "Hallo")

	# ---- so the markup has to live in the CSV --------------------------------
	r.text = "QUEST"
	await process_frame
	var quest := r.get_parsed_text()
	check("R5", "which forces the markup into the translator's cell: QUEST reaches the player parsed, tags gone (%s)" % quest,
		quest == "Finde den Schluessel." and not quest.contains("["))

	# ---- and a translator can break it, silently -----------------------------
	r.text = "BROKEN"
	await process_frame
	var broken := r.get_parsed_text()
	check("R6", "a translator who closed [b] with [/i] ships the literal tag INTO the sentence the player reads (%s)" % broken,
		broken.contains("[/i]"))

	r.text = "SWAPPED"
	await process_frame
	var swapped := r.get_parsed_text()
	check("R7", "a translator who swapped the open and close tags ships the literal [/b] too (%s)" % swapped,
		swapped.contains("[/b]"))

	var rno := mk(false)
	rno.text = "QUEST"
	await process_frame
	check("R8", "turning bbcode_enabled off does not protect you: the same cell now shows every bracket raw (%s)" % rno.get_parsed_text(),
		rno.get_parsed_text() == "Finde den [b]Schluessel[/b].")

	# ---- the door that is never translated at all ----------------------------
	var ra := mk(true)
	ra.append_text("GREET")
	await process_frame
	check("R9", "append_text() with the exact key that just worked is never looked up (on screen: %s)" % ra.get_parsed_text(),
		ra.get_parsed_text() == "GREET")

	var rb := mk(true)
	rb.clear()
	rb.push_bold()
	rb.add_text("GREET")
	rb.pop()
	await process_frame
	check("R10", "add_text() behaves the same (on screen: %s); building text from code opts you out of translation without saying so" % rb.get_parsed_text(),
		rb.get_parsed_text() == "GREET")

	# ---- .text does not describe what is on screen ---------------------------
	var rc := mk(true)
	rc.text = "GREET"
	rc.append_text(" GREET")
	await process_frame
	check("R11", "on one node, one frame, the same key gives two answers at once: %s" % rc.get_parsed_text(),
		rc.get_parsed_text() == "Hallo GREET")
	check("R12", "and .text reports neither of them -- it still reads %s, so a test that asserts on .text measures nothing the player sees" % rc.text,
		rc.text == "GREET")

	# ---- the locale change eats the appended half ----------------------------
	TranslationServer.set_locale("en")
	await process_frame
	check("R13", "switching locale silently DESTROYS everything appended: the line becomes %s -- the appended half is gone, not re-translated" % rc.get_parsed_text(),
		rc.get_parsed_text() == "Hello")
	var app_after := ra.get_parsed_text()
	if minor <= 2:
		check("R14", "on 4.%d the append-only node does not survive the switch either: it is now EMPTY (%d characters left)" % [minor, app_after.length()],
			app_after == "")
	else:
		check("R14", "from 4.3 on the append-only node survives the switch untouched, because it has nothing in .text to re-parse (%s)" % app_after,
			app_after == "GREET")

	# ---- 4.2 empties the whole label ----------------------------------------
	var wiped := rb.get_parsed_text()
	if minor <= 2:
		check("R15", "on 4.%d that same locale change empties a push/add_text label COMPLETELY (parsed text is now %d characters)" % [minor, wiped.length()],
			wiped == "")
		note("On 4.2 a RichTextLabel whose content came from code -- append_text(), or clear()/push_*/add_text() -- goes BLANK the moment the player changes language, whether or not .text is set. From 4.3 on that content survives; only the appended half of a mixed node is dropped.")
	else:
		check("R15", "from 4.3 on the same push/add_text content survives the locale change (%s); on 4.2 the label goes blank instead" % wiped,
			wiped == "GREET")

	# ---- the fix, measured --------------------------------------------------
	var rd := mk(true)
	TranslationServer.set_locale("de")
	await process_frame
	rd.append_text("[b]%s[/b]" % tr("GREET"))
	await process_frame
	check("R16", "translating at the call site instead -- append_text(\"[b]%%s[/b]\" %% tr(\"GREET\")) -- is what puts German on screen (%s)" % rd.get_parsed_text(),
		rd.get_parsed_text() == "Hallo")

	# ---- auto_translate_mode still applies ----------------------------------
	var re := mk(true)
	if has_prop(re, "auto_translate_mode"):
		re.set("auto_translate_mode", 2) # DISABLED
		re.text = "GREET"
		await process_frame
		check("R17", "the .text door still obeys auto_translate_mode: DISABLED on the label alone brings the key back (%s)" % re.get_parsed_text(),
			re.get_parsed_text() == "GREET")
	else:
		re.call("set_auto_translate", false)
		re.text = "GREET"
		await process_frame
		check("R17", "on 4.%d the pre-4.3 set_auto_translate(false) does the same to the .text door (%s)" % [minor, re.get_parsed_text()],
			re.get_parsed_text() == "GREET")

	print("---")
	for n in notes:
		print("NOTE  %s" % n)
	if failures == 0:
		print("RICHTEXT BBCODE: ALL PASS (%d checks)" % passes)
	else:
		print("RICHTEXT BBCODE: %d FAIL / %d PASS" % [failures, passes])
	quit(1 if failures > 0 else 0)
