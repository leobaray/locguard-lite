# Measures every claim in docs/why-your-translation-shows-boxes-or-nothing.md
# against a real Godot 4 binary. Run it through docs/verify_font_coverage.sh,
# which builds the throwaway project this script expects.
#
# The project carries a strings.csv with a Chinese, Russian, Hebrew and Thai
# column, so the translation itself is never in doubt: tr() is measured first
# and only then the font is asked whether it can draw what tr() returned.
#
# Two things make this measurable without a window. The glyph a shaped line
# ends up using carries the RID of the font it came from, so "the glyph is not
# from your font" is a number, not an impression. And `allow_system_fallback`
# is the exact switch the engine uses to borrow a font from the operating
# system, so turning it off reproduces, on this machine, the machine of a
# player who does not have that font installed.
extends SceneTree

var _fails: Array[String] = []
var _passes := 0
var _notes: Array[String] = []
var _skips: Array[String] = []

var _ts := TextServerManager.get_primary_interface()

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

func note(id: String, what: String, value) -> void:
	_notes.append(id)
	print("NOTE ", id, " ", what, " -> ", value)

# Shapes one string with one font and returns the glyph dictionaries. The RIDs
# are freed here: a leaked shaped-text RID prints an ERROR at exit, and this
# script is also gated on producing no engine error.
func shape(font: Font, s: String, size: int = 16) -> Array:
	var rid := _ts.create_shaped_text()
	_ts.shaped_text_add_string(rid, s, font.get_rids(), size)
	_ts.shaped_text_shape(rid)
	var glyphs: Array = _ts.shaped_text_get_glyphs(rid).duplicate(true)
	_ts.free_rid(rid)
	return glyphs

func _init() -> void:
	var v := Engine.get_version_info()
	var build := "%d.%d" % [v.major, v.minor]
	print("BUILD ", v.string)

	TranslationServer.set_locale("zh")

	# F1..F4 — the premise. The translation is loaded, selected and correct.
	# Everything below is about text that IS translated.
	check("F1", TranslationServer.get_locale(), "zh", "locale set by the game")
	check("F2", tr("PLAY"), "开始游戏", "tr() in Chinese")
	TranslationServer.set_locale("th")
	check("F3", tr("PLAY"), "เริ่มเกม", "tr() in Thai")
	TranslationServer.set_locale("zh")
	check("F4", tr("PLAY") == "PLAY", false, "the Chinese string is not the key")

	var font: Font = ThemeDB.fallback_font
	note("F5", "the default theme font", "%s / %s" % [font.get_font_name(), font.get_font_style_name()])

	# F6..F9 — what the font that ships with the engine can draw. These four
	# are the scripts a European or Brazilian team checks first, and they work.
	check("F6", font.has_char("A".unicode_at(0)), true, "has_char latin A")
	check("F7", font.has_char("á".unicode_at(0)), true, "has_char latin a-acute")
	check("F8", font.has_char("Д".unicode_at(0)), true, "has_char cyrillic DE")
	check("F9", font.has_char("Ω".unicode_at(0)), true, "has_char greek OMEGA")

	# F10..F13 — and what it cannot. Same font, same engine, no error anywhere.
	check("F10", font.has_char("开".unicode_at(0)), false, "has_char han KAI")
	check("F11", font.has_char("あ".unicode_at(0)), false, "has_char hiragana A")
	check("F12", font.has_char("ก".unicode_at(0)), false, "has_char thai KO KAI")
	check("F13", font.has_char("م".unicode_at(0)), false, "has_char arabic MEEM")

	# F14 — a coverage difference between builds, not a constant. The default
	# font gained Hebrew after 4.4, so the same project loses or keeps that
	# script depending on which engine built it.
	var hebrew_expected := build == "4.7" or build == "4.5" or build == "4.6"
	check("F14", font.has_char("א".unicode_at(0)), hebrew_expected,
		"has_char hebrew ALEF (4.2/4.3/4.4 no, 4.5+ yes)")

	# F15 — the switch that decides where a glyph the font lacks comes from. It
	# is on by default, and nothing in a new project turns it off.
	check("F15", font.get("allow_system_fallback"), true,
		"allow_system_fallback on the default theme font")

	# --- with the switch ON: this machine, the developer's machine ------------

	var latin_on := shape(font, "A")
	var han_on := shape(font, "开")
	check("F16", latin_on.size(), 1, "one glyph shaped for latin A")
	check("F17", han_on.size(), 1, "one glyph shaped for han KAI")

	var own_rid: RID = font.get_rids()[0]
	# F18 — the control. Latin comes from the project's own font, so a later
	# claim of "not from your font" is a discriminating measurement.
	check("F18", latin_on[0]["font_rid"] == own_rid, true, "latin A is drawn by the theme font itself")
	# F19 — the payload. The Chinese glyph is never the theme font's, whatever
	# this machine happens to have installed.
	check("F19", han_on[0]["font_rid"] == own_rid, false, "han KAI is NOT drawn by the theme font")

	if han_on[0]["font_rid"].is_valid():
		note("F20", "on this machine the engine borrowed an OS font for han KAI, rid",
			han_on[0]["font_rid"])
		note("F21", "OS sans-serif reported to the engine", OS.get_system_font_path("sans-serif", 400, 0, false))
	else:
		note("F20", "this machine has no OS font covering han KAI either; the borrowed-font case is not observable here", "RID()")

	# --- with the switch OFF: the player who lacks that OS font --------------

	font.set("allow_system_fallback", false)
	var latin_off := shape(font, "A")
	var han_off := shape(font, "开")

	# F22 — the control still holds: Latin is unaffected by the switch.
	check("F22", latin_off[0]["font_rid"] == own_rid, true, "latin A still drawn by the theme font")
	check("F23", latin_off[0]["index"], latin_on[0]["index"], "latin A keeps the same glyph id")

	# F24..F26 — what the player gets. No font at all, an index that is the
	# codepoint itself rather than a glyph id, and a positive advance: the line
	# is laid out, spaced and centred around text that cannot be read.
	check("F24", han_off[0]["font_rid"].is_valid(), false, "han KAI is drawn by no font at all")
	check("F25", han_off[0]["index"], "开".unicode_at(0), "the glyph id is the codepoint, not a glyph")
	check("F26", han_off[0]["advance"] > 0.0, true, "the unreadable glyph still advances the line")

	# F27..F28 — every automatic size check a project can run passes. The
	# string measures wider than zero and a Label reserves room for it.
	var measured := font.get_string_size("开始游戏", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	check("F27", measured.x > 0.0, true, "get_string_size of the unreadable string is not zero")
	var label := Label.new()
	label.text = tr("PLAY")
	check("F28", label.get_minimum_size().x > 0.0, true, "a Label reserves width for the unreadable string")
	label.free()

	# F29 — and tr() is still right. A scan that looks for untranslated strings
	# has nothing to report here: the string was translated, delivered, laid
	# out, and is not on the screen.
	check("F29", tr("PLAY"), "开始游戏", "tr() after everything above")

	font.set("allow_system_fallback", true)

	print("---")
	print("passes=", _passes, " fails=", _fails.size(), " notes=", _notes.size(), " skips=", _skips.size())
	if _fails.is_empty():
		print("FONT COVERAGE: ALL PASS")
	else:
		print("FONT COVERAGE: FAILED ", _fails)
	quit(0 if _fails.is_empty() else 1)
