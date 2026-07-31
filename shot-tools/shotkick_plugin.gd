@tool
extends EditorPlugin

# Temporary helper used only to produce the store screenshot: waits for the
# editor to settle, brings the "LocGuard Lite" dock tab to the front and
# presses its real "Scan project" button, so the shot shows the genuine Lite
# findings (2 rules) AND the promo LinkButton — the two things the previous
# preview (a shot of the Pro dock) misrepresented.


func _enter_tree() -> void:
	_kick()


func _kick() -> void:
	await get_tree().create_timer(10.0).timeout
	EditorInterface.open_scene_from_path("res://ui.tscn")
	await get_tree().create_timer(4.0).timeout
	EditorInterface.set_main_screen_editor("2D")
	var scene := EditorInterface.get_edited_scene_root()
	if scene != null and scene.get_child_count() > 0:
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(scene.get_child(0))
		print("SHOTKICK: node selected")

	var dock := _find_by_name(EditorInterface.get_base_control(), "LocGuard Lite")
	if dock == null:
		print("SHOTKICK: dock not found")
		return
	var parent := dock.get_parent()
	if parent is TabContainer:
		(parent as TabContainer).current_tab = dock.get_index()
		print("SHOTKICK: tab selected")
	await get_tree().process_frame
	# Wide enough that both columns and the full CTA label read without
	# ellipsis; still a realistic right-dock width.
	dock.custom_minimum_size.x = 460
	await get_tree().process_frame
	var btn := _find_scan_button(dock)
	if btn == null:
		print("SHOTKICK: button not found")
		return
	btn.emit_signal("pressed")
	await get_tree().create_timer(1.0).timeout
	print("SHOTKICK: scan pressed")


func _find_by_name(node: Node, target: String) -> Control:
	if node.name == target and node is Control:
		return node
	for c in node.get_children():
		var r := _find_by_name(c, target)
		if r != null:
			return r
	return null


func _find_scan_button(node: Node) -> Button:
	if node is Button and (node as Button).text == "Scan project":
		return node
	for c in node.get_children():
		var r := _find_scan_button(c)
		if r != null:
			return r
	return null
