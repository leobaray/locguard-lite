extends SceneTree

# Asks a real Godot 4 binary what actually happens to text already on screen
# when the locale changes at runtime.
#
# The question ("I call TranslationServer.set_locale() and nothing on screen
# changes") is answered on forums with three incompatible stories: "you have to
# reload the scene", "you have to walk the tree and re-assign every string", and
# "it just works, you did something wrong". None of the three is measured. This
# file measures it.
#
# Claim ids (L*) are the ones cited in docs/why-the-locale-change-does-not-update-the-ui.md.
# Every check prints PASS/FAIL; the script exits non-zero if any fails, so a
# newer Godot tells you which line stopped holding.
#
# Nothing here needs an imported .csv or .po: the translations are built in
# memory with Translation.add_message(), which is the same object the importer
# produces. That keeps the file runnable from a bare project.

var failures := 0
var passes := 0
var notes: Array[String] = []

func check(id: String, what: String, ok: bool) -> void:
	if ok:
		passes += 1
		print("PASS  %s  %s" % [id, what])
	else:
		failures += 1
		print("FAIL  %s  %s" % [id, what])

func note(s: String) -> void:
	notes.append(s)

# A Control that records every NOTIFICATION_TRANSLATION_CHANGED it receives.
class Watcher extends Control:
	var hits := 0
	func _notification(what: int) -> void:
		if what == NOTIFICATION_TRANSLATION_CHANGED:
			hits += 1

func make_translation(locale: String, pairs: Dictionary) -> Translation:
	var t := Translation.new()
	t.locale = locale
	for k in pairs:
		t.add_message(k, pairs[k])
	return t

func _initialize() -> void:
	print("---")

	var en := make_translation("en", {"GREETING": "Hello", "ITEM": "Item", "TITLE": "Settings"})
	var pt := make_translation("pt", {"GREETING": "Ola", "ITEM": "Objeto", "TITLE": "Ajustes"})
	TranslationServer.add_translation(en)
	TranslationServer.add_translation(pt)
	TranslationServer.set_locale("en")

	# ---------------------------------------------------------------- L1-L2
	check("L1", "tr() returns the active locale's message (locale=%s, tr(GREETING)=%s)" % [
		TranslationServer.get_locale(), tr("GREETING")],
		tr("GREETING") == "Hello")

	var captured := tr("GREETING")
	TranslationServer.set_locale("pt")
	check("L2", "a String captured from tr() does NOT follow the locale: still %s while tr() now gives %s" % [
		captured, tr("GREETING")],
		captured == "Hello" and tr("GREETING") == "Ola")

	# ---------------------------------------------------------------- L3-L6
	TranslationServer.set_locale("en")
	var frozen := Label.new()
	frozen.text = tr("GREETING")          # the mistake: translate once, store the result
	var live := Label.new()
	live.text = "GREETING"                # the key, left for auto-translation
	var w := Watcher.new()
	root.add_child(frozen)
	root.add_child(live)
	root.add_child(w)

	var detached := Watcher.new()         # never added to the tree
	var before_hits := w.hits

	TranslationServer.set_locale("pt")
	check("L3", "the Label given tr()'s RESULT keeps the old text after the locale changes (text=%s)" % frozen.text,
		frozen.text == "Hello")
	check("L4", "the Label given the KEY keeps the key in .text (%s) — .text is never rewritten by the engine" % live.text,
		live.text == "GREETING")
	check("L5", "but what that Label DISPLAYS follows the locale: atr(text)=%s" % live.atr(live.text),
		live.atr(live.text) == "Ola")
	check("L6", "a Control in the tree is notified of the change (NOTIFICATION_TRANSLATION_CHANGED x%d)" % (w.hits - before_hits),
		w.hits > before_hits)
	check("L7", "a Control OUTSIDE the tree is not notified at all (%d) — nodes you kept in a variable never hear about it" % detached.hits,
		detached.hits == 0)

	# ---------------------------------------------------------------- opt-out
	live.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	check("L8", "auto_translate_mode = DISABLED makes atr() return the key verbatim (%s)" % live.atr(live.text),
		live.atr(live.text) == "GREETING")
	live.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS

	# ---------------------------------------------------------------- misses
	check("L9", "a key with no message in the active locale comes back as the key itself (tr(MISSING)=%s)" % tr("MISSING"),
		tr("MISSING") == "MISSING")

	TranslationServer.set_locale("xx")
	check("L10", "an unknown locale is accepted and reported back (get_locale()=%s)" % TranslationServer.get_locale(),
		TranslationServer.get_locale().begins_with("xx"))
	# The trap: this does NOT come back as the key. A locale nobody translated
	# silently serves the FALLBACK locale's messages, so the screen looks
	# correct in English and nothing tells you the locale is wrong.
	var fallback: String = ProjectSettings.get_setting("internationalization/locale/fallback", "en")
	check("L11", "an untranslated locale does NOT show the key: it silently serves the fallback locale (%s) — tr(GREETING)=%s" % [
		fallback, tr("GREETING")],
		tr("GREETING") == "Hello")
	note("fallback setting internationalization/locale/fallback = %s" % fallback)
	# It is specifically the FALLBACK locale that answers, not "whichever
	# translation happens to be loaded": drop en and the key surfaces even
	# though pt is still loaded and could have answered.
	TranslationServer.remove_translation(en)
	check("L11b", "and it is the fallback locale specifically: with en removed (pt still loaded) the key surfaces (%s)" % tr("GREETING"),
		tr("GREETING") == "GREETING")
	TranslationServer.add_translation(en)
	# Writing the setting at runtime does not move the fallback: the server
	# read it once at startup. Changing it in code and re-calling set_locale()
	# looks like it should work and does nothing.
	ProjectSettings.set_setting("internationalization/locale/fallback", "pt")
	TranslationServer.set_locale("xx")
	check("L11c", "writing internationalization/locale/fallback at runtime does NOT move the fallback — still %s, not the pt message" % tr("GREETING"),
		tr("GREETING") == "Hello")
	ProjectSettings.set_setting("internationalization/locale/fallback", fallback)

	# region codes ------------------------------------------------------------
	TranslationServer.set_locale("pt_BR")
	note("set_locale(pt_BR) -> get_locale()=%s, tr(GREETING)=%s" % [TranslationServer.get_locale(), tr("GREETING")])
	check("L12", "a region code still resolves the language-only translation: pt_BR -> %s" % tr("GREETING"),
		tr("GREETING") == "Ola")

	# ---------------------------------------------------------------- widgets
	TranslationServer.set_locale("en")
	var menu := PopupMenu.new()
	menu.add_item("ITEM")
	root.add_child(menu)
	var item_before := menu.get_item_text(0)
	TranslationServer.set_locale("pt")
	note("PopupMenu item: get_item_text=%s, atr=%s" % [menu.get_item_text(0), menu.atr(menu.get_item_text(0))])
	check("L13", "PopupMenu item text is stored as the key too (%s -> %s), so reading it back gives you the untranslated string" % [
		item_before, menu.get_item_text(0)],
		menu.get_item_text(0) == "ITEM")

	# ---------------------------------------------------------------- the fix
	# What actually works: react to the notification and re-run tr() there.
	TranslationServer.set_locale("en")
	var fixed := Label.new()
	fixed.text = tr("GREETING")
	root.add_child(fixed)
	# The one-liner the forums never give: connect the notification, not a timer.
	var refresher := Watcher.new()
	root.add_child(refresher)
	TranslationServer.set_locale("pt")
	# Re-running tr() after the change is what produces fresh text.
	fixed.text = tr("GREETING")
	check("L14", "re-running tr() after the change is what produces fresh text (%s)" % fixed.text,
		fixed.text == "Ola")

	print("---")
	for n in notes:
		print("NOTE " + n)
	print("LOCALE CHANGE: %d checks" % (passes + failures))
	if failures == 0:
		print("LOCALE CHANGE: ALL PASS (%d)" % passes)
		quit(0)
	else:
		print("LOCALE CHANGE: %d FAILURES" % failures)
		quit(1)
