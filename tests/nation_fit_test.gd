extends SceneTree
## WINDOWED
## Checks that the Nation screen fits the view: every tab, the tabs themselves (they wrap onto a second row when there is
## no room for one) and the right edge of each page (the Economy tab's spending column) lie inside it. The interface is
## laid out at the project's 1280x720 and scaled (display/window/stretch canvas_items), so this holds for 1600x900 and
## any other window of that shape.
## Needs a real window (the layout of a headless run is not the screen's):
##   godot --path . -s res://tests/nation_fit_test.gd --windowed --resolution 1280x720

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://fit_test_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	gs.set_player("GER")
	gs.ai_enabled = false
	await process_frame
	var screen: Node = get_first_node_in_group("nation_screen")
	var view: Vector2 = screen.get_viewport_rect().size
	for title: String in ["Overview", "Economy", "Build", "Military", "Navy", "Diplomacy", "Focus", "Rankings", "History"]:
		screen.open_page(title)
		for i in 4:
			await process_frame
		var r: Rect2 = screen.get_global_rect()
		_check(r.position.x >= 0.0 and r.end.x <= view.x + 0.5 and r.end.y <= view.y + 0.5, "the %s tab lies inside the view (%d to %d of %d)" % [title, roundi(r.position.x), roundi(r.end.x), roundi(view.x)])
	screen.open_page("Economy")
	for i in 4:
		await process_frame
	var eco: Node = get_first_node_in_group("economy_panel")
	var right := 0.0
	for c in eco.find_children("*", "Label", true, false):
		if c.is_visible_in_tree() and c.text.begins_with("-"):
			right = maxf(right, (c as Control).get_global_rect().end.x)
	_check(right > 0.0 and right <= screen.get_global_rect().end.x + 0.5, "and the spending figures stand inside the window (%d of %d)" % [roundi(right), roundi(screen.get_global_rect().end.x)])
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
