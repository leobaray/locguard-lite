@tool
extends EditorPlugin

var _dock: Control


func _enter_tree() -> void:
	_dock = _build_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)


func _exit_tree() -> void:
	remove_control_from_docks(_dock)
	_dock.queue_free()


func _build_dock() -> Control:
	var root := VBoxContainer.new()
	root.name = "LocGuard Lite"

	var top := HBoxContainer.new()
	var scan := Button.new()
	scan.text = "Scan project"
	top.add_child(scan)
	var summary := Label.new()
	summary.text = "—"
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.clip_text = true
	top.add_child(summary)
	root.add_child(top)

	var tree := Tree.new()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.columns = 2
	tree.set_column_title(0, "Rule / key")
	tree.set_column_title(1, "Where")
	tree.column_titles_visible = true
	tree.hide_root = true
	root.add_child(tree)

	var promo := LinkButton.new()
	promo.text = "Get LocGuard Pro — placeholder QA, BBCode checks, CI gate →"
	promo.uri = "https://blobsmith.itch.io/locguard"
	root.add_child(promo)

	scan.pressed.connect(func() -> void:
		var res: Dictionary = LocGuardLiteCore.scan_project("res://")
		tree.clear()
		var troot := tree.create_item()
		if res.has("error"):
			summary.text = res.error
			return
		summary.text = "%d errors, %d warnings · %d keys used, %d in %s" % [
			res.errors, res.warnings, res.used_count, res.table_count, String(res.csv).get_file()]
		for f in res.findings:
			var it := tree.create_item(troot)
			var kl: String = ("✖ " if f.severity == "error" else "▲ ") + f.rule + "  " + String(f.get("key", ""))
			if f.has("locale"): kl += "  [%s]" % f.locale
			it.set_text(0, kl)
			it.set_text(1, "%s:%d" % [f.file, f.line] if f.has("file") else "")
			it.set_metadata(0, f)
	)

	tree.item_activated.connect(func() -> void:
		var it := tree.get_selected()
		if it == null: return
		var f: Dictionary = it.get_metadata(0)
		if f.has("file"):
			var res := load(f.file)
			if res: EditorInterface.edit_resource(res)
	)

	return root
