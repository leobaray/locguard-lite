extends SceneTree
# Every in-engine claim in docs/why-your-chinese-japanese-or-thai-text-does-not-wrap.md,
# measured. Run through verify_cjk_line_breaking.sh, which builds the empty
# project this script expects and measures the export claims itself.

var fails := 0

func check(id: String, ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + id + " — " + what)
	if not ok:
		fails += 1

const ZH := "这是一个很长的中文句子用来测试自动换行是否正常工作没有任何空格"
const TH := "นี่คือประโยคภาษาไทยที่ยาวมากเพื่อทดสอบการตัดบรรทัดอัตโนมัติ"

# Line breaks the TextServer picks for `text` in a box `width` px wide, at 16 px
# with the default font.
static func lines(text: String, lang: String, width: float) -> Array:
	var ts = TextServerManager.get_primary_interface()
	var rid = ts.create_shaped_text()
	ts.shaped_text_add_string(rid, text, ThemeDB.fallback_font.get_rids(), 16, {}, lang)
	var brk = ts.shaped_text_get_line_breaks(rid, width, 0, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND)
	var out := []
	for i in range(0, brk.size(), 2):
		out.append(text.substr(brk[i], brk[i + 1] - brk[i]))
	ts.free_rid(rid)
	return out

func label(text: String, mode: int) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = mode
	l.custom_minimum_size = Vector2(120, 0)
	l.size = Vector2(120, 0)
	root.add_child(l)
	return l

func _init() -> void:
	var ts = TextServerManager.get_primary_interface()
	var cw: float = ThemeDB.fallback_font.get_string_size("中", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x

	check("S1", ts.has_feature(TextServer.FEATURE_USE_SUPPORT_DATA) and ts.get_support_data_filename().begins_with("icudt")
		and not FileAccess.file_exists("res://" + ts.get_support_data_filename()),
		"the running binary uses break data (%s) that is not in the project folder: %s" % [ts.get_support_data_filename(), ts.get_name()])

	var off := label(ZH, TextServer.AUTOWRAP_OFF)
	var smart := label(ZH, TextServer.AUTOWRAP_WORD_SMART)
	check("W1a", off.get_line_count() == 1 and smart.get_line_count() == 1,
		"right after setting text, get_line_count() is 1 for both labels (off=%d smart=%d)" % [off.get_line_count(), smart.get_line_count()])
	await process_frame
	await process_frame
	var w2: bool = off.get_line_count() == 1 and off.get_minimum_size().x > 400
	# LG_SELFTEST=1 flips this one expectation, to prove the harness can fail.
	if OS.get_environment("LG_SELFTEST") == "1":
		w2 = not w2
	check("W2", w2,
		"a Label's default autowrap_mode is OFF (%d): the Chinese line stays 1 line and its minimum width is %d px, not 120" % [Label.new().autowrap_mode, off.get_minimum_size().x])
	check("W1b", smart.get_line_count() == 5,
		"after a frame the same label with WORD_SMART reports 5 lines: %d" % smart.get_line_count())

	var zh7 := lines(ZH, "zh", cw * 7 + 0.5)
	check("W3", zh7.size() == 5 and zh7[0] == "这是一个很长的" and zh7.slice(0, 4).all(func(s): return s.length() == 7),
		"Chinese with no spaces breaks between any two characters, 7 per line: %s" % str(zh7))

	var same := true
	for mode in [TextServer.AUTOWRAP_WORD, TextServer.AUTOWRAP_ARBITRARY]:
		var l := label(ZH, mode)
		await process_frame
		same = same and l.get_line_count() == smart.get_line_count()
	check("W4", same, "WORD, WORD_SMART and ARBITRARY give the same 5 lines for Chinese")

	var ja := "これは日本語の文。次の文です"
	var ja8 := lines(ja, "ja", cw * 8 + 0.5)
	var ja7 := lines("中文句子测试标点，逗号开头行", "zh", cw * 8 + 0.5)
	check("W5", ja8[0] == "これは日本語の" and ja8[1].begins_with("文。") and ja7[0] == "中文句子测试标" and ja7[1].begins_with("点，"),
		"。 and ， never start a line: the character before them moves down with them: %s %s" % [str(ja8), str(ja7)])

	# 8 characters fit, and the 9th is っ: without the rule line 2 would start with it.
	var ja_small := lines("東京都の人口はとっても多いです", "ja", cw * 8 + 0.5)
	check("W6", ja_small[0] == "東京都の人口は" and ja_small[1].begins_with("とっ"),
		"a small っ does not start a line either: と moves down with it: %s" % str(ja_small))

	var th := lines(TH, "th", 120.0)
	check("W7", th == ["นี่คือประโยคภาษา", "ไทยที่ยาวมากเพื่อ", "ทดสอบการตัด", "บรรทัดอัตโนมัติ"],
		"Thai, which has no spaces, breaks between dictionary words, never inside one: %s" % str(th))

	check("W8", lines(TH, "", 120.0) == th and lines(ZH, "", cw * 7 + 0.5) == zh7 and lines(ja, "", cw * 8 + 0.5) == ja8,
		"leaving the language empty gives the same breaks: the script decides, not Control.language")

	print("CJK LINE BREAKING: " + ("ALL PASS" if fails == 0 else "%d FAIL" % fails))
	quit()
