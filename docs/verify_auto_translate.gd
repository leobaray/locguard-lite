extends SceneTree

# Asks a real Godot 4 binary why a key that IS in your translation can still
# reach the player untranslated, with no error, no warning and a green linter.
#
# The short version this file measures: tr() and the text the node actually
# shows do not go through the same door. tr() always translates. The node's own
# text goes through atr(), which obeys auto_translate_mode -- and that resolved
# state is remembered per node, so after you change an ancestor the descendants
# that already resolved once keep the old answer until the next frame.
#
# Claim ids (T*) are the ones cited in
# docs/why-a-key-in-your-csv-still-shows-untranslated.md.
# Every check prints PASS/FAIL. The engine's exit code is NOT the gate -- Godot
# exits 0 on a GDScript parse error -- so the gate is the summary line.
#
# Nothing here needs an imported .csv or .po: the translations are built in
# memory with Translation.add_message(), the same object the CSV importer
# produces. Everything is addressed dynamically (get/set/call by name) so the
# file still parses on 4.2, which has none of these symbols.

var failures := 0
var passes := 0
var notes: Array[String] = []

var INHERIT := 0
var ALWAYS := 1
var DISABLED := 2

var minor := 0

# carried from _initialize() into the next frame
var warm_kid = null
var cold_kid = null
var late_c = null
var early_c = null

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

func mk(loc: String, pairs: Dictionary) -> Translation:
	var t := Translation.new()
	t.locale = loc
	for k in pairs:
		t.add_message(k, pairs[k])
	return t

# A parent with one child, both fresh, both attached to the tree.
func make_pair() -> Array:
	var top = Control.new()
	var kid = Label.new()
	top.add_child(kid)
	root.add_child(top)
	return [top, kid]

# top -> a -> b -> c, all fresh, attached, never queried.
func make_chain() -> Dictionary:
	var top = Control.new()
	var a = Label.new()
	var b = Label.new()
	var c = Label.new()
	b.add_child(c)
	a.add_child(b)
	top.add_child(a)
	root.add_child(top)
	return {"top": top, "a": a, "b": b, "c": c}

func atr_of(n) -> String:
	return n.call("atr", "GREET")

func _initialize() -> void:
	print("---")
	minor = Engine.get_version_info().minor

	TranslationServer.add_translation(mk("en", {"GREET": "Hello", "APPLE": "apple", "APPLES": "apples"}))
	TranslationServer.add_translation(mk("pt", {"GREET": "Ola"}))
	TranslationServer.set_locale("pt")

	var feature_probe = Label.new()
	var has_atm: bool = has_prop(feature_probe, "auto_translate_mode")
	var has_atr: bool = feature_probe.has_method("atr")
	feature_probe.free()

	# ---------------------------------------------------------------- T1-T4
	# Two ways of asking the SAME node for the SAME key, in the same frame,
	# that disagree.
	var p1 = make_pair()
	if has_atm:
		p1[0].set("auto_translate_mode", DISABLED)
	else:
		p1[0].set("auto_translate", false)

	check("T1", "tr() on a node under a disabled ancestor still returns the translation (got %s)" % p1[1].tr("GREET"),
		p1[1].tr("GREET") == "Ola")
	check("T2", "TranslationServer.translate() ignores auto-translate entirely (got %s)" % TranslationServer.translate("GREET"),
		TranslationServer.translate("GREET") == "Ola")
	var plain := RefCounted.new()
	check("T3", "Object.tr() on a non-Node has no tree to inherit from and translates (got %s)" % plain.tr("GREET"),
		plain.tr("GREET") == "Ola")

	if not has_atr:
		# ------------------------------------------------------------ 4.2
		note("this build has no Node.atr() and no Node.auto_translate_mode; both arrived in 4.3.")
		check("T25", "on this build auto_translate is a plain bool that does not propagate: parent set to false, child still reads %s" % str(p1[1].get("auto_translate")),
			p1[1].get("auto_translate") == true)
		check("T26", "on this build no script-reachable method answers 'will this node translate?' (atr present: %s)" % str(has_atr),
			not has_atr)
		check("T27", "tr_n() against a plain (non-PO) Translation returns the singular message here (got %s)" % p1[1].tr_n("APPLE", "APPLES", 2),
			p1[1].tr_n("APPLE", "APPLES", 2) == "apple")
		return

	check("T4", "atr() on that same node in that same frame returns the KEY (got %s)" % atr_of(p1[1]),
		atr_of(p1[1]) == "GREET")

	# ---------------------------------------------------------------- T5-T6
	var fresh = Label.new()
	check("T5", "a fresh node defaults to INHERIT (%d) while the tree root is ALWAYS (%d)" % [
		fresh.get("auto_translate_mode"), root.get("auto_translate_mode")],
		fresh.get("auto_translate_mode") == INHERIT and root.get("auto_translate_mode") == ALWAYS)
	fresh.free()

	check("T6", "the three mode values are INHERIT=0, ALWAYS=1, DISABLED=2 in this build",
		ClassDB.class_get_integer_constant("Node", "AUTO_TRANSLATE_MODE_INHERIT") == INHERIT
		and ClassDB.class_get_integer_constant("Node", "AUTO_TRANSLATE_MODE_ALWAYS") == ALWAYS
		and ClassDB.class_get_integer_constant("Node", "AUTO_TRANSLATE_MODE_DISABLED") == DISABLED)

	# ---------------------------------------------------------------- T7
	# One ancestor takes out an entire subtree, at any depth.
	var ch = make_chain()
	ch["top"].set("auto_translate_mode", DISABLED)
	check("T7", "INHERIT is transitive: three levels under the disabled ancestor all return the key (a=%s b=%s c=%s)" % [
		atr_of(ch["a"]), atr_of(ch["b"]), atr_of(ch["c"])],
		atr_of(ch["a"]) == "GREET" and atr_of(ch["b"]) == "GREET" and atr_of(ch["c"]) == "GREET")

	# ---------------------------------------------------------------- T8-T10
	# A change reaches the node it is applied to at once. It reaches descendants
	# that have ALREADY resolved a state only at the next frame -- so the ORDER
	# of two settings inside one frame is observable on screen.
	var late = make_chain()
	late["top"].set("auto_translate_mode", DISABLED)
	late["b"].set("auto_translate_mode", ALWAYS)
	late_c = late["c"]
	check("T8", "an explicit ALWAYS under a disabled ancestor re-enables that node while its parent stays dark (b=%s a=%s)" % [
		atr_of(late["b"]), atr_of(late["a"])],
		atr_of(late["b"]) == "Ola" and atr_of(late["a"]) == "GREET")
	check("T9", "in that same frame the child of the re-enabled node is still dark: the change reached b, not c (c=%s)" % atr_of(late["c"]),
		atr_of(late["c"]) == "GREET")

	var early = make_chain()
	early["b"].set("auto_translate_mode", ALWAYS)
	early["top"].set("auto_translate_mode", DISABLED)
	early_c = early["c"]
	check("T10", "the SAME two settings applied in the opposite order give the opposite answer in the same frame (c=%s here, %s above)" % [
		atr_of(early["c"]), atr_of(late["c"])],
		atr_of(early["c"]) == "Ola")

	# ---------------------------------------------------------------- T11-T12
	# The cleanest form of the same mechanism: two identical sibling subtrees,
	# same code, opposite answers, decided only by whether the child was ever
	# asked before the ancestor changed.
	var warm_pair = make_pair()
	var cold_pair = make_pair()
	warm_kid = warm_pair[1]
	cold_kid = cold_pair[1]
	var warmed_value: String = atr_of(warm_kid)
	check("T11", "before any change both subtrees translate (first read of the warm one: %s)" % warmed_value,
		warmed_value == "Ola")
	warm_pair[0].set("auto_translate_mode", DISABLED)
	cold_pair[0].set("auto_translate_mode", DISABLED)
	check("T12", "same frame, same code: the child that was read once is stale (%s) and its never-read twin is not (%s)" % [
		atr_of(warm_kid), atr_of(cold_kid)],
		atr_of(warm_kid) == "Ola" and atr_of(cold_kid) == "GREET")

	# ---------------------------------------------------------------- T14-T16
	# The deprecated bool is not a view of this node's own setting.
	var dep = make_pair()
	dep[0].set("auto_translate_mode", DISABLED)
	check("T14", "the deprecated auto_translate getter reports the RESOLVED state, not the node's own: mode is INHERIT (%d) but the bool reads %s" % [
		dep[1].get("auto_translate_mode"), str(dep[1].get("auto_translate"))],
		dep[1].get("auto_translate_mode") == INHERIT and dep[1].get("auto_translate") == false)

	var rt = Label.new()
	root.add_child(rt)
	rt.set("auto_translate", false)
	var after_false = rt.get("auto_translate_mode")
	rt.set("auto_translate", true)
	var after_true = rt.get("auto_translate_mode")
	check("T15", "auto_translate = false writes DISABLED (got %d)" % after_false, after_false == DISABLED)
	check("T16", "auto_translate = true writes ALWAYS (%d), NOT back to INHERIT (%d): one round trip of the deprecated bool opts the node out of its parent for good" % [
		after_true, INHERIT],
		after_true == ALWAYS)

	# ---------------------------------------------------------------- T17-T19
	var w = Window.new()
	root.add_child(w)
	w.title = "GREET"
	check("T17", "Window.title stores the raw key and is read through atr() (title=%s, atr=%s)" % [w.title, atr_of(w)],
		w.title == "GREET" and atr_of(w) == "Ola")
	w.set("auto_translate_mode", DISABLED)
	check("T18", "a disabled Window keeps the key as its title text (atr=%s)" % atr_of(w),
		atr_of(w) == "GREET")

	check("T19", "atr() on a key that is in no translation returns the key unchanged (got %s)" % p1[1].call("atr", "NO_SUCH_KEY"),
		p1[1].call("atr", "NO_SUCH_KEY") == "NO_SUCH_KEY")

	# ---------------------------------------------------------------- T20-T23
	# Version-dependent answers. The build is read, not assumed.
	var has_cat: bool = p1[1].has_method("can_auto_translate")
	check("T20", "can_auto_translate() exists only from 4.7 on (this build is 4.%d, method present: %s)" % [minor, str(has_cat)],
		has_cat == (minor >= 7))
	if has_cat:
		check("T21", "can_auto_translate() answers false for a node under a disabled ancestor",
			p1[1].can_auto_translate() == false)
	else:
		note("4.%d has no can_auto_translate(): the only way to ask a node whether it will translate is to call atr() on a known key and compare." % minor)

	var atr_n_got: String = p1[1].call("atr_n", "APPLE", "APPLES", 2)
	if minor <= 3:
		check("T22", "on 4.3 a disabled atr_n() hands back the SINGULAR key even for n=2 (got %s)" % atr_n_got, atr_n_got == "APPLE")
	else:
		check("T22", "from 4.4 on a disabled atr_n() hands back the plural key for n=2 (got %s)" % atr_n_got, atr_n_got == "APPLES")

	# ---------------------------------------------------------------- T24
	# The one thing you can actually grep for: the mode is written to the .tscn
	# only when it is not the default, so a disabled node leaves a literal line
	# and an inheriting node leaves nothing at all.
	var sc_top = Control.new()
	sc_top.name = "Root"
	var sc_off = Label.new()
	sc_off.name = "Disabled"
	sc_off.text = "GREET"
	var sc_on = Label.new()
	sc_on.name = "Inheriting"
	sc_on.text = "GREET"
	sc_top.add_child(sc_off)
	sc_top.add_child(sc_on)
	sc_off.owner = sc_top
	sc_on.owner = sc_top
	sc_off.set("auto_translate_mode", DISABLED)
	var packed := PackedScene.new()
	var scene_text := ""
	if packed.pack(sc_top) == OK and ResourceSaver.save(packed, "user://locguard_at_check.tscn") == OK:
		var fh := FileAccess.open("user://locguard_at_check.tscn", FileAccess.READ)
		if fh != null:
			scene_text = fh.get_as_text()
	var off_block := scene_text.substr(scene_text.find("name=\"Disabled\""))
	var on_block := scene_text.substr(scene_text.find("name=\"Inheriting\""))
	check("T24", "the scene file records auto_translate_mode = %d for the disabled node and writes nothing for the inheriting one (greppable: %s)" % [
		DISABLED, str(off_block.contains("auto_translate_mode = %d" % DISABLED))],
		off_block.contains("auto_translate_mode = %d" % DISABLED) and not on_block.contains("auto_translate_mode"))

	var tr_n_got: String = p1[1].tr_n("APPLE", "APPLES", 2)
	if minor <= 4:
		check("T23", "tr_n() against a plain (non-PO) Translation returns the singular MESSAGE on 4.%d (got %s)" % [minor, tr_n_got], tr_n_got == "apple")
	else:
		check("T23", "from 4.7 on the same tr_n() call returns the plural KEY and logs an engine error (got %s)" % tr_n_got, tr_n_got == "APPLES")

func _process(_delta: float) -> bool:
	# T13 needs a frame boundary: the stale state is dropped between frames.
	if warm_kid != null:
		check("T13", "one frame later every stale node agrees with its twin: warm=%s cold=%s, and both orders of T9/T10 now read c=%s / %s" % [
			atr_of(warm_kid), atr_of(cold_kid), atr_of(late_c), atr_of(early_c)],
			atr_of(warm_kid) == "GREET" and atr_of(cold_kid) == "GREET"
			and atr_of(late_c) == "Ola" and atr_of(early_c) == "Ola")
	print("---")
	for n in notes:
		print("NOTE  %s" % n)
	if failures == 0:
		print("AUTO TRANSLATE: ALL PASS (%d checks)" % passes)
	else:
		print("AUTO TRANSLATE: %d FAIL / %d PASS" % [failures, passes])
	quit(1 if failures > 0 else 0)
	return true
