extends SceneTree

# Asks a real Godot 4 binary what happens when a TRANSLATED string and the
# `%` that fills it stop agreeing.
#
# This is the failure with no bad string in it. Every row of the CSV is
# present, every key resolves, every locale imports. What the translator
# changed is the punctuation the programmer never sent to review: `%s` became
# `%d`, the two placeholders swapped places because the target language puts
# the number first, or the sentence gained a literal per-cent sign. tr() still
# returns the right translated sentence for the right key. The `%` that runs
# next is the one that fails.
#
# What the player gets when it fails is NOT the sentence and NOT an error
# dialog:
#
#   * on a statically typed call site the expression yields the empty string,
#     so the line is simply not on the screen — and on 4.2 and 4.3 it yields
#     text belonging to an EARLIER format in the same code path, so the player
#     reads a sentence from somewhere else in the game;
#   * on an untyped call site it yields null, and the assignment that follows
#     (`label.text = ...`) raises and stops the rest of that function, so every
#     line set up after it is left unconfigured too.
#
# The engine prints one line in the Output and nothing else — no import
# warning, no editor diagnostic, no crash. The message text itself changed
# between 4.3 and 4.4, which is measured by verify_format_placeholders.sh.
#
# Claim ids (F*) are the ones cited in
# docs/why-your-translated-line-comes-out-empty.md. Every check prints
# PASS/FAIL and the script exits non-zero if any fails, so a newer Godot tells
# you which line stopped holding.
#
# The CSV is written by verify_format_placeholders.sh and imported by a real
# editor pass before this file runs, so every claim about a translated string
# is a claim about the resource the importer actually produced.

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

# An untyped call site: both operands are Variant, which is what most game code
# looks like before anyone adds type hints.
func dyn(s, v):
	return s % v

# A statically typed call site. The return type is what forces the empty string.
func typed(s: String, v: Variant) -> String:
	return s % v

# Returns a literal without the parser being able to fold the `%` that follows
# it, so the operator runs at runtime exactly as it would on a tr() result.
func src(i: int) -> String:
	var t := ["ALPHA %d gold", "BETA 100% sure", "GAMMA %d silver", "DELTA 50% off"]
	return t[i]


# Runs four formats — two that work, two that fail — with nothing whatsoever in
# between, so that what a failed `%` leaves behind is measured on its own and
# not on top of this script's own formatting.
func leak_probe() -> Array:
	var a: String = src(0) % 7
	var b: String = src(1) % []
	var c: String = src(2) % 9
	var d: String = src(3) % []
	return [a, b, c, d]

func _initialize() -> void:
	print("---")
	print("BUILD %s" % vi.string)
	var older_percent: bool = vi.major == 4 and vi.minor <= 3
	# Taken first: every claim about a leaked value has to be measured before
	# this script's own PASS lines do any formatting of their own.
	var leak := leak_probe()

	# ---- the translated rows, straight out of the importer -----------------
	TranslationServer.set_locale("en")
	var en_score := tr("SCORE_MSG")
	var en_pct := tr("PCT_MSG")
	TranslationServer.set_locale("de")
	var de_score := tr("SCORE_MSG")
	var de_count := tr("COUNT_MSG")
	var de_plain := tr("PLAIN_MSG")
	TranslationServer.set_locale("fr")
	var fr_score := tr("SCORE_MSG")
	var fr_pct := tr("PCT_MSG")
	var fr_named := tr("NAMED_MSG")

	check("F1", "the importer carried every row through verbatim — fr SCORE_MSG is '%s', the reordered form the translator typed, not a rejected row and not the key" % fr_score,
		fr_score == "%d points marques par %s")
	check("F2", "tr() itself never fails here: SCORE_MSG resolves in en, de and fr ('%s' / '%s' / '%s'), so a missing-key scan sees a clean project" % [en_score, de_score, fr_score],
		en_score != "SCORE_MSG" and de_score != "SCORE_MSG" and fr_score != "SCORE_MSG")

	# ---- the source language works, which is why nobody sees this ----------
	check("F3", "en: '%s' %% [\"Ann\", 10] = '%s'" % [en_score, typed(en_score, ["Ann", 10])],
		typed(en_score, ["Ann", 10]) == "Ann scored 10 points")
	check("F4", "de kept the order, so it works too: '%s'" % typed(de_score, ["Ann", 10]),
		typed(de_score, ["Ann", 10]) == "Ann hat 10 Punkte erzielt")

	# ---- the same line, one language further --------------------------------
	var fr_typed := typed(fr_score, ["Ann", 10])
	check("F5", "fr put the number first (%%d before %%s), which is normal French word order — the format fails and the typed call site returns the empty string (length %d), so the line is simply absent from the screen" % fr_typed.length(),
		fr_typed == "")
	var fr_dyn = dyn(fr_score, ["Ann", 10])
	check("F6", "the SAME failure on an untyped call site returns null (typeof = %d), not the empty string — `label.text = <that>` raises 'Invalid set index' and stops the rest of the function, leaving every line set up after it unconfigured" % typeof(fr_dyn),
		typeof(fr_dyn) == TYPE_NIL)

	# ---- a translation with no placeholder at all can still break the line --
	check("F7", "de PLAIN_MSG is '%s' — no placeholder anywhere, just a per-cent sign in ordinary prose. Filling it fails all the same: '%s' (length %d)" % [de_plain, typed(de_plain, []), typed(de_plain, []).length()],
		de_plain == "100% sicher" and typed(de_plain, []) == "")
	check("F8", "fr PCT_MSG is '%s' — the translator dropped one of the doubled per-cent signs the source had (%s), and that single character is the whole defect" % [fr_pct, en_pct],
		en_pct == "%d%% complete" and fr_pct == "%d% termine" and typed(fr_pct, 50) == "")

	# ---- and the mismatch that is NOT an error ------------------------------
	check("F9", "de COUNT_MSG changed %%d to %%s and nothing breaks: '%s' %% 3 = '%s'. A placeholder audit that only looks for failures at runtime will never see this one — the number is printed by the string formatter, which is why it also silently drops locale-aware integer formatting" % [de_count, typed(de_count, 3)],
		de_count == "%s Gegenstaende" and typed(de_count, 3) == "3 Gegenstaende")
	check("F10", "the reverse is fatal: a %%d handed a word returns null on an untyped site (typeof = %d)" % typeof(dyn("%d objets", "trois")),
		typeof(dyn("%d objets", "trois")) == TYPE_NIL)

	# ---- counting, both directions ------------------------------------------
	check("F11", "one argument too many fails: '%%d items' %% [3, 99] -> typeof %d" % typeof(dyn("%d items", [3, 99])),
		typeof(dyn("%d items", [3, 99])) == TYPE_NIL)
	check("F12", "one argument too few fails: '%%s scored %%d' %% [\"Ann\"] -> typeof %d. A translation that adds a placeholder the code never passes lands here" % typeof(dyn("%s scored %d", ["Ann"])),
		typeof(dyn("%s scored %d", ["Ann"])) == TYPE_NIL)

	# ---- the value a failed format leaves behind, by engine version ---------
	var a: String = leak[0]
	var b: String = leak[1]
	var c: String = leak[2]
	var d: String = leak[3]
	check("F13", "the two formats that work in that sequence return their own text, '%s' and '%s'" % [a, c],
		a == "ALPHA 7 gold" and c == "GAMMA 9 silver")
	if older_percent:
		check("F14", "on %s the failed format returned neither its own text ('BETA 100%% sure') nor nothing: it returned '%s', a string that belongs to another part of the program. The player reads text from somewhere else in the game, on the line where this one should have been" % [vi.string, b],
			b != "BETA 100% sure" and b != "")
		check("F15", "the second failure does the same and picks up whatever ran last: '%s'. Which string leaks is not a property of the broken line, so the same bug shows a different sentence depending on what the game did just before" % d,
			d != "DELTA 50% off" and d != "")
	else:
		check("F14", "on %s the failed format returns its own unfilled text, '%s' — the raw placeholder is on screen, which at least points at the line that is broken" % [vi.string, b],
			b == "BETA 100% sure")
		check("F15", "and it is stable: the second failure also returns its own text, '%s'" % d,
			d == "DELTA 50% off")

	# ---- the form that survives translation ---------------------------------
	check("F16", "the same sentence with named placeholders survives the reorder the %% form could not: fr NAMED_MSG '%s' .format() = '%s'" % [fr_named, fr_named.format({"who": "Ann", "pts": 10})],
		fr_named == "{pts} points pour {who}" and fr_named.format({"who": "Ann", "pts": 10}) == "10 points pour Ann")
	check("F17", "but .format() fails the other way: a placeholder the code does not supply is left on the screen as literal text, '%s', and the engine prints nothing at all about it" % "{b}".format({}),
		"I {a} {b}".format({"a": 1}) == "I 1 {b}")

	note("Lite's two rules are missing-key and empty-translation. Neither of them")
	note("looks at placeholders: every row above is clean to Lite. Comparing the")
	note("placeholder set of each translation against its source column is")
	note("LocGuard Pro's placeholder-printf / -index / -named.")

	print("---")
	if failures == 0:
		print("FORMAT PLACEHOLDERS: ALL PASS (%d/%d)" % [passes, passes])
		quit(0)
	else:
		print("FORMAT PLACEHOLDERS: %d FAIL, %d PASS" % [failures, passes])
		quit(1)
