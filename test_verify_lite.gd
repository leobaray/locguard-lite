extends SceneTree
# LocGuard Lite must find exactly missing-key=4 and empty-translation=1,
# and nothing else (the Pro-only rules — orphan-key, placeholder-*,
# bbcode-imbalance — must not appear at all).
func _initialize() -> void:
	var res: Dictionary = LocGuardLiteCore.scan_project("res://")
	if res.has("error"):
		print("FAIL  scan error: ", res.error); quit(1); return
	var rules := {}
	for f in res.findings:
		rules[f.rule] = rules.get(f.rule, 0) + 1
	print("RULES: ", JSON.stringify(rules))
	var fails := 0
	var expect := {
		"missing-key": 4,          # MISSING_ONE + PLAY_LABEL + OPT_EASY + OPT_HARD
		"empty-translation": 1,    # EMPTY_ES
	}
	for rule in expect:
		if rules.get(rule, 0) != expect[rule]:
			print("FAIL  %s: expected %d got %d" % [rule, expect[rule], rules.get(rule, 0)])
			fails += 1
		else:
			print("PASS  %s = %d" % [rule, expect[rule]])
	if res.findings.size() == 5:
		print("PASS  findings.size() = 5 (nothing else)")
	else:
		print("FAIL  findings.size(): expected 5 got %d" % res.findings.size())
		fails += 1
	print("VERIFY: " + ("ALL PASS" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails > 0 else 0)
