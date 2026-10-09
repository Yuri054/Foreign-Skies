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
	_check(bar._front.get_popup().item_count == 1 and bar._front.get_popup().is_item_disabled(0), "with no front the menu says to draw one")
	var front_cmd = load("res://scripts/sim/designate_front.gd")
	gs.set_war("FRA", "GER", true)
	gs.issue(front_cmd.new("FRA", "Test front", [] as Array[int], "GER"))
	bar._fill_fronts()
	if gs.fronts.size() > 0:
		_check(bar._front.get_popup().item_count == gs.fronts.size(), "a front appears in the menu")
		bar._on_front(0)
		await process_frame
		var assigned = gs.armies[panel._selected[0]]
		_check(assigned.front_id != 0 and not bar._release.disabled, "Assign to front puts the army on it, and Release opens")
		bar._on_release()
		await process_frame
		_check(gs.armies[panel._selected[0]].front_id == 0, "Release takes it off")

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
