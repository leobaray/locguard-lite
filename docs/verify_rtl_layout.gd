# Reporter for docs/why-your-arabic-build-comes-out-mirrored.md.
#
# Runs inside a throwaway project built by docs/verify_rtl_layout.sh, prints one
# `LG_<NAME> <value>` line per measurement and ends with LG_END. The shell script
# is what turns those lines into claims; nothing is asserted here, so a missing
# LG_END means the run measured nothing rather than that a claim failed.
#
# Every number below comes from the engine's own layout pass: the positions are
# read back from real Control nodes after the frame that placed them, never
# computed by this script.
extends Node

const ROW_W := 400.0
const CASE := "LGCASE"

var _notes := []

func _notification(what: int) -> void:
	_notes.append(what)


# A row that records what the ENGINE tells it. The point of running the
# measurement from a Control subclass instead of from the Node above is that
# NOTIFICATION_LAYOUT_DIRECTION_CHANGED is a Control notification: if it is ever
# delivered, this is the object it would be delivered to.
class Spy extends HBoxContainer:
	var seen := []
	func _notification(what: int) -> void:
		seen.append(what)


# One horizontal row of two buttons, which is the smallest thing in a UI that
# can be mirrored: if the engine flips the layout, AAAA stops being the leftmost
# child. `mode` is written straight into layout_direction as an integer, because
# the enum member NAMES differ between 4.3 and 4.4 and this file has to parse on
# both (see LG_ENUMS).
func _row(mode: int) -> Array:
	var h := Spy.new()
	h.size = Vector2(ROW_W, 50.0)
	h.layout_direction = mode
	var b1 := Button.new()
	b1.text = "AAAA"
	var b2 := Button.new()
	b2.text = "BBBB"
	h.add_child(b1)
	h.add_child(b2)
	add_child(h)
	return [h, b1, b2]


func _has_control_const(name: String) -> bool:
	return Array(ClassDB.class_get_integer_constant_list("Control")).has(name)


func _ready() -> void:
	var ts := TextServerManager.get_primary_interface()
	var case_name := OS.get_environment(CASE)
	print("LG_CASE ", case_name)
	print("LG_VERSION ", Engine.get_version_info()["major"], ".", Engine.get_version_info()["minor"])

	# --- what the project actually has ---------------------------------------
	print("LG_LOADED ", ",".join(TranslationServer.get_loaded_locales()))
	print("LG_FORCE_SETTING ", ProjectSettings.get_setting(
		"internationalization/rendering/force_right_to_left_layout_direction", "ABSENT"))

	# --- the enum inventory, which is itself one of the findings --------------
	var names := []
	for k in ClassDB.class_get_integer_constant_list("Control"):
		if str(k).begins_with("LAYOUT_DIRECTION"):
			names.append(str(k) + "=" + str(ClassDB.class_get_integer_constant("Control", k)))
	names.sort()
	print("LG_ENUMS ", ",".join(names))
	print("LG_HAS_SYSTEM_LOCALE ", _has_control_const("LAYOUT_DIRECTION_SYSTEM_LOCALE"))
	print("LG_HAS_APPLICATION_LOCALE ", _has_control_const("LAYOUT_DIRECTION_APPLICATION_LOCALE"))
	print("LG_HAS_LAYOUT_DIRECTION_NOTIFICATION ", Array(
		ClassDB.class_get_integer_constant_list("Control")).has(
		"NOTIFICATION_LAYOUT_DIRECTION_CHANGED"))

	# --- is the Arabic text itself fine? -------------------------------------
	# Shaped through the engine's own text server, the same one a Label uses.
	# A reversed glyph run and an inferred direction of RTL mean the string is
	# being laid out as Arabic, whatever the interface around it does.
	var probe := "مرحبا Godot!"
	var rid := ts.create_shaped_text()
	ts.shaped_text_add_string(rid, probe, ThemeDB.fallback_font.get_rids(), 16)
	ts.shaped_text_shape(rid)
	var glyphs := ts.shaped_text_get_glyphs(rid)
	print("LG_SHAPE_GLYPHS ", glyphs.size())
	print("LG_SHAPE_FIRST_START ", glyphs[0]["start"])
	print("LG_SHAPE_LAST_START ", glyphs[glyphs.size() - 1]["start"])
	print("LG_SHAPE_DIR ", ts.shaped_text_get_inferred_direction(rid))
	ts.free_rid(rid)

	# --- the one probe that answers the question -----------------------------
	var asked := OS.get_environment("LGLOCALE")
	if asked == "":
		asked = "ar"
	print("LG_IS_RTL_LOCALE ", ts.is_locale_right_to_left(asked))
	print("LG_NOTIF_CONST ", ClassDB.class_get_integer_constant(
		"Control", "NOTIFICATION_LAYOUT_DIRECTION_CHANGED"))
	print("LG_WIN_RTL_BEFORE ", get_window().is_layout_rtl())

	# --- flip the language, then measure the interface -----------------------
	var before_row: Array = _row(0)
	await get_tree().process_frame
	var before_x: float = before_row[1].position.x
	before_row[0].seen.clear()
	TranslationServer.set_locale(asked)
	# Read BEFORE yielding: this is how you tell a synchronous relayout from one
	# that lands on the next frame.
	print("LG_BEFORE_X ", before_x)
	print("LG_SAMEFRAME_X ", before_row[1].position.x)
	print("LG_SAMEFRAME_RTL ", before_row[0].is_layout_rtl())
	print("LG_LOCALE ", TranslationServer.get_locale())
	print("LG_TR ", tr("GREET"))

	# every layout_direction mode the running engine knows
	var rows := {}
	for m in [0, 1, 2, 3]:
		rows[m] = _row(m)
	if _has_control_const("LAYOUT_DIRECTION_SYSTEM_LOCALE"):
		rows[4] = _row(4)

	# a mirror done by hand, the way a project had to do it before the engine
	# did it: the child order is reversed in code
	var swapped: Array = _row(0)
	swapped[0].move_child(swapped[2], 0)

	# an icon inside the mirrored row
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(32.0, 32.0)
	swapped[0].add_child(icon)

	# a label whose alignment was set to LEFT by hand
	var label := Label.new()
	label.text = tr("GREET")
	label.size = Vector2(300.0, 40.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(label)

	await get_tree().process_frame
	await get_tree().process_frame

	for m in rows:
		print("LG_MODE", m, "_X ", rows[m][1].position.x)
		print("LG_MODE", m, "_RTL ", rows[m][0].is_layout_rtl())
	print("LG_HANDSWAP_A_X ", swapped[1].position.x)
	print("LG_HANDSWAP_B_X ", swapped[2].position.x)
	print("LG_HANDSWAP_RTL ", swapped[0].is_layout_rtl())
	print("LG_ICON_FLIP_H ", icon.flip_h)
	print("LG_ICON_X ", icon.position.x)
	print("LG_LABEL_RTL ", label.is_layout_rtl())
	print("LG_LABEL_TEXT ", label.text)
	print("LG_ROW_W ", ROW_W)
	print("LG_WIN_RTL ", get_window().is_layout_rtl())
	var notif := ClassDB.class_get_integer_constant(
		"Control", "NOTIFICATION_LAYOUT_DIRECTION_CHANGED")
	print("LG_SPY_SAW_LAYOUT_NOTIF ", before_row[0].seen.has(notif))
	print("LG_SPY_SAW_TRANSLATION_NOTIF ", before_row[0].seen.has(2010))
	print("LG_SPY_NOTES ", ",".join(before_row[0].seen.map(func(n): return str(n))))
	print("LG_NOTES ", ",".join(_notes.map(func(n): return str(n))))
	print("LG_END")
	get_tree().quit()
