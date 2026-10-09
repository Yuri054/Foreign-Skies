extends SceneTree
## Drives the army action bar through the main scene: it shows with a selection, and its buttons
## merge, split, detach, assign to a front, release, halt, change the symbol and deselect.
## Run: godot --headless --path . -s res://tests/army_action_bar_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://test_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var map: Node = root.get_node("MapData")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var Mil = load("res://scripts/sim/military.gd")
	var panel: Node = get_first_node_in_group("military_panel")
	var bar: Node = get_first_node_in_group("army_action_bar")
	_check(bar != null, "the action bar exists")
	gs.set_player("FRA")
	await process_frame
	_check(not bar.visible, "it is hidden while nothing is selected")

	var nancy := 0
	for id in range(1, gs.province_owner.size()):
		if map.provinces[id].name == "Meurthe-et-Moselle":
			nancy = id
	main.map_view.select(nancy)
	await process_frame
	_check(bar.visible and bar._ids == panel._selected, "selecting an army brings it up")
	_check(bar._title.text.contains("men") and bar._title.text.contains("Meurthe-et-Moselle"), "and names the army (%s)" % bar._title.text)
	_check(bar._merge.disabled and not bar._split.disabled and not bar._detach.disabled, "one army can be split or detached from, not merged")
	_check(bar._release.disabled and not bar._front.disabled, "it is on no front, so only assigning is open")
	_check(bar._halt.disabled, "and it is not marching, so there is nothing to halt")
	var rect: Rect2 = bar.get_global_rect()
	var palette: Control = get_first_node_in_group("map_modes")
	await process_frame
	rect = bar.get_global_rect()
	_check(rect.position.x >= palette.get_global_rect().end.x and rect.end.y <= root.get_visible_rect().size.y, "it sits at the bottom, clear of the map modes (x %d)" % rect.position.x)

	# Split in half, then merge back.
	var army = gs.armies[panel._selected[0]]
	var units: int = army.units.size()
	bar._on_split()
	await process_frame
	_check(panel._selected.size() == 2 and army.units.size() < units, "Split divides the army and selects both halves")
	_check(bar._ids == panel._selected and not bar._merge.disabled, "the bar follows, and now Merge is open")
	bar._on_merge()
	await process_frame
	_check(panel._selected.size() == 1 and gs.armies[panel._selected[0]].units.size() == units, "Merge puts them together again")
	# Detach one type.
	army = gs.armies[panel._selected[0]]
	bar._fill_detach()
	var popup: PopupMenu = bar._detach.get_popup()
	_check(popup.item_count >= 1 and popup.get_item_text(0).contains("(of "), "Detach lists the unit types of the army (%s)" % popup.get_item_text(0))
	bar._on_detach(0)
	await process_frame
	_check(panel._selected.size() == 2, "Detach splits one unit off")
	bar._on_merge()
	await process_frame

	# Fronts.
	bar._fill_fronts()
	var menu: PopupMenu = bar._front.get_popup()
	_check(menu.item_count == 2 and menu.get_item_id(0) == bar.DRAW_FRONT and menu.get_item_id(1) == bar.FACE_FRONT, "with no front and no war the menu offers to draw one or to face a nation")
	gs.set_war("FRA", "GER", true)
	bar._fill_fronts()
	var face_id := -1
	for i in menu.item_count:
		if menu.get_item_text(i).begins_with("Face German"):
			face_id = menu.get_item_id(i)
	_check(face_id >= bar.NEW_FRONT_BASE and gs.fronts.is_empty(), "at war it offers a new front against the enemy it borders")
	bar._on_front(face_id)
	await process_frame
	var assigned = gs.armies[panel._selected[0]]
	_check(gs.fronts.size() == 1 and assigned.front_id != 0 and not bar._release.disabled, "choosing it makes the front and puts the army on it, and Release opens")
	bar._on_release()
	await process_frame
	_check(gs.armies[panel._selected[0]].front_id == 0, "Release takes it off")
	bar._fill_fronts()
	var assign_id := -1
	for i in menu.item_count:
		if menu.get_item_text(i).begins_with("Assign to"):
			assign_id = menu.get_item_id(i)
	_check(assign_id == 0, "the front is now in the menu to assign to")
	bar._on_front(assign_id)
	await process_frame
	_check(gs.armies[panel._selected[0]].front_id == gs.fronts.keys()[0], "and assigns")
	# Draw a line from the bar: the armies go on it when it is finished.
	bar._on_release()
	var fronts_before: int = gs.fronts.size()
	bar._on_front(bar.DRAW_FRONT)
	await process_frame
	_check(panel._drawing and panel._assign_new and panel.visible and panel._tabs.current_tab == 1, "Draw opens the Fronts tab in drawing mode")
	panel.set_province(nancy)
	var neighbour := 0
	for n in Mil.neighbors(nancy):
		if gs.province_owner[n] == "FRA":
			neighbour = n
	panel.set_province(neighbour)
	panel._finish_drawing()
	await process_frame
	_check(gs.fronts.size() == fronts_before + 1 and gs.armies[panel._selected[0]].front_id != 0, "finishing the line makes the front and puts the selected army on it")
	bar._on_front(bar.FACE_FRONT)
	_check(panel._picking_nation and panel._assign_new, "Face a nation waits for a click on that nation")
	panel._end_drawing()

	# March and halt.
	var dest := 0
	for n in Mil.neighbors(nancy):
		if gs.province_owner[n] == "FRA":
			dest = n
	panel.order_move(dest)
	await process_frame
	_check(not bar._halt.disabled, "a marching army can be halted")
	bar._on_halt()
	await process_frame
	var marching = gs.armies[panel._selected[0]]
	_check(marching.path.is_empty() and bar._halt.disabled, "Halt stops it")

	# Symbol.
	bar._fill_symbols()
	bar._on_symbol(bar._symbol_ids.find("guard"))
	_check(gs.armies[panel._selected[0]].icon == "guard", "Symbol changes the marker")

	# Several armies at once, and deselect.
	main.map_view.select(nancy)
	panel.select_in_rect(Rect2(Vector2.ZERO, Vector2(100000, 100000)))
	await process_frame
	_check(bar.visible and panel._selected.size() > 3 and bar._title.text.contains("armies"), "a box selection shows the total (%s)" % bar._title.text)
	_check(bar._merge.disabled, "armies in different provinces cannot merge")
	bar._deselect.pressed.emit()
	await process_frame
	_check(not bar.visible and panel._selected.is_empty(), "Deselect clears the selection and hides the bar")

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_settings.cfg"))
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
