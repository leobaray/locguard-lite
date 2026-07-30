extends SceneTree
# Can a user of the free addon actually GET to the paid product?
#
# Why this exists: LocGuard Lite is the funnel. It is free so that it can sit in
# someone's editor and end with a click through to LocGuard Pro ($12), and that
# entire conversion path is ONE node: the promo LinkButton at the bottom of the
# dock. Until 2026-07-30 nothing measured it. verify.sh's `funnel` stage is
# about the opposite direction — it keeps Lite from reporting the Pro-only
# rules — and `runtime` only asserts the scanner's findings. A Lite that finds
# exactly missing-key/empty-translation and sends nobody anywhere is green on
# all six original stages. The string literal that IS the business model was
# checked by nothing.
#
# What this measures, on the SHIPPED bytes (verify.sh unpacks the Asset Library
# download into this project, not the worktree):
#   * the control the plugin actually docks is the one carrying the CTA,
#   * the CTA is a real clickable button, not a Label that looks like one,
#   * its destination is the paid page from funnel.json, exactly,
#   * its label leads with the product name, and
#   * at a narrow dock the clipped-visible band is still tall and wide enough
#     to read and hit.
#
# HOW: EditorPlugin cannot be instantiated outside the editor ("Can't inherit
# from a virtual class"), so we compile the shipped plugin.gd against a stub
# base class that records add_control_to_dock() calls. Exactly ONE line differs
# from the shipped file (`extends`), and check 1 proves that. Everything else —
# the node tree, the theme, the fonts, the layout maths — is the real engine.
# If a future turn adds another EditorPlugin API call to the plugin, this stage
# stops compiling: extend STUB below. Do not delete the stage.
#
# NEVER emit the CTA's `pressed` signal here. LinkButton.uri means the engine
# calls OS.shell_open() on press, which opens the PUBLIC product page — the one
# thing operators are forbidden to open, because those page views are live
# analytics. Reading `uri` off the node is the wiring; opening it is not.
#
# Usage (from verify.sh):  godot --headless --path <proj> --script test_upsell_lite.gd
#   LG_UPSELL_EXPECT_FAIL=<check-name>  seeded-regression mode: verify.sh points
#   this at a deliberately broken copy and requires THAT check (and only that
#   check) to be the one that reddens.

const PLUGIN_PATH := "res://addons/locguard_lite/plugin.gd"
const HARNESS_PATH := "res://.upsell_harness.gd"
const STUB_PATH := "res://.upsell_stub.gd"

# The editor-only surface plugin.gd touches. Recording the dock call is the
# point: it proves the control we measure is the control users get.
const STUB := """extends Node
const DOCK_SLOT_RIGHT_BL := 2
var docked: Array = []
func add_control_to_dock(slot: int, c: Control) -> void: docked.append([slot, c])
func remove_control_from_docks(_c: Control) -> void: pass
"""

var _fails: Array[String] = []
var _dock: Control
var _cta: Object
var _contract: Dictionary
var _frames := 0


func check(name: String, ok: bool, detail: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + name + " — " + detail)
	if not ok:
		_fails.append(name)


func _initialize() -> void:
	var cf := FileAccess.open("res://funnel.json", FileAccess.READ)
	if cf == null:
		print("FAIL  no funnel.json in the project — nothing to check the CTA against.")
		quit(1)
		return
	_contract = JSON.parse_string(cf.get_as_text())
	cf.close()

	# ---------------------------------------------------- 1. shipped-source
	# Everything below measures a compiled copy of the shipped plugin. If that
	# copy ever differs by more than the base class, this stage is measuring
	# something users do not have.
	var pf := FileAccess.open(PLUGIN_PATH, FileAccess.READ)
	if pf == null:
		print("FAIL  no %s in the download — the addon has no plugin script at all." % PLUGIN_PATH)
		quit(1)
		return
	var src := pf.get_as_text()
	pf.close()
	var harness := src.replace("extends EditorPlugin", "extends \"%s\"" % STUB_PATH)
	var diff := 0
	var a := src.split("\n")
	var b := harness.split("\n")
	if a.size() != b.size():
		diff = 9999
	else:
		for i in a.size():
			if a[i] != b[i]:
				diff += 1
	check("shipped-source", diff == 1,
		"harness differs from the shipped plugin.gd in %d line(s) (must be 1: the base class)" % diff)

	FileAccess.open(STUB_PATH, FileAccess.WRITE).store_string(STUB)
	FileAccess.open(HARNESS_PATH, FileAccess.WRITE).store_string(harness)

	var scr = load(HARNESS_PATH)
	if scr == null:
		print("FAIL  the shipped plugin.gd does not compile (see the parse errors above).")
		_finish()
		return
	var plugin = scr.new()

	# --------------------------------------------------------- 2. docked
	# _enter_tree() is what the editor calls. Measuring _build_dock() directly
	# would stay green on a plugin that builds a beautiful dock and docks a
	# different, empty control.
	plugin._enter_tree()
	var docked: Array = plugin.docked
	check("docked", docked.size() == 1,
		"_enter_tree() added %d control(s) to the editor docks (must be 1)" % docked.size())
	if docked.size() != 1:
		_finish()
		return
	_dock = docked[0][1]

	# ------------------------------------------------------ 3. cta-exists
	# "Has a uri" is the definition of the CTA: it is the property the engine
	# reads on press. A Label styled to look like a link has no uri and would
	# fail here — which is the point.
	var links: Array = []
	for n in _all(_dock):
		if n is LinkButton:
			links.append(n)
	check("cta-exists", links.size() == 1,
		"%d LinkButton(s) in the docked control (must be exactly 1: the upsell)" % links.size())
	if links.size() != 1:
		_finish()
		return
	_cta = links[0]

	# --------------------------------------------------- 4. cta-clickable
	# Geometry can be perfect and the click still die: a disabled button, or one
	# with MOUSE_FILTER_IGNORE, renders identically and swallows nothing.
	var clickable: bool = (_cta is BaseButton) and not _cta.disabled \
		and _cta.mouse_filter != Control.MOUSE_FILTER_IGNORE
	check("cta-clickable", clickable,
		"%s disabled=%s mouse_filter=%d (0=STOP, 2=IGNORE: a click would pass straight through)"
			% [_cta.get_class(), _cta.disabled, _cta.mouse_filter])

	# ------------------------------------------------------ 5. destination
	var paid: String = _contract.paid_url
	check("destination", _cta.uri == paid,
		"CTA opens %s (contract: %s)" % [("<empty>" if _cta.uri == "" else _cta.uri), paid])

	# ------------------------------------------------------------ 6. label
	# The dock clips long labels, so the words that identify the product have to
	# come FIRST. A CTA reading "Learn more →" converts nobody.
	var ident: String = _contract.cta_identity_text
	check("label", _cta.text.begins_with(ident),
		"label \"%s\" must lead with \"%s\"" % [_cta.text, ident])

	# add the docked control to a real viewport so the theme, fonts and
	# container maths run for real; measured in _process once layout settles.
	root.add_child(_dock)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false

	# ------------------------------------------------- 7. visible-band
	# The editor gives the dock a fixed width and clips what does not fit. What
	# matters is not the button's nominal rect but the part of it the user can
	# see and hit at a dock that narrow.
	var narrow: float = float(_contract.narrow_dock_width_px)
	_dock.size = Vector2(max(narrow, _dock.get_combined_minimum_size().x), 600.0)
	var cta := _cta as Control
	var band := cta.get_global_rect().intersection(Rect2(Vector2.ZERO, Vector2(narrow, 600.0)))
	var font: Font = cta.get_theme_font("font")
	var fsize: int = cta.get_theme_font_size("font_size")
	var ident_w: float = font.get_string_size(
		_contract.cta_identity_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var full_w: float = font.get_string_size(
		cta.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var visible_ok: bool = cta.is_visible_in_tree() \
		and band.size.y >= cta.get_global_rect().size.y - 0.5 \
		and band.size.x >= ident_w
	check("visible-band", visible_ok,
		"visible=%s band=%.0fx%.0f at a %.0fpx dock; \"%s\" needs %.0fpx"
			% [cta.is_visible_in_tree(), band.size.x, band.size.y, narrow,
				_contract.cta_identity_text, ident_w])
	print("  INFO the full label needs %.0fpx; anything past %.0fpx is clipped at a %.0fpx dock"
		% [full_w, narrow, narrow])

	_finish()
	return true


func _finish() -> void:
	var expect := OS.get_environment("LG_UPSELL_EXPECT_FAIL")
	print("FAILED-CHECKS: " + ("(none)" if _fails.is_empty() else ",".join(_fails)))
	if expect != "":
		# seeded-regression mode: the seed must redden its own check and no other
		var ok: bool = _fails.size() == 1 and _fails[0] == expect
		print("SEED: expected only %s to redden — %s" % [expect, "as expected" if ok else "NOT what happened"])
		print("UPSELL: " + ("SEED OK" if ok else "SEED WRONG"))
		quit(0 if ok else 1)
		return
	print("UPSELL: " + ("ALL PASS" if _fails.is_empty() else "%d FAIL" % _fails.size()))
	quit(1 if _fails.size() > 0 else 0)


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out += _all(c)
	return out
