extends SceneTree
## Drives the fleet action bar through the main scene: it shows with a fleet selection, and its
## buttons set orders, detach, merge, send home and deselect, and it stays clear of the army bar.
## Run: godot --headless --path . -s res://tests/fleet_action_bar_test.gd

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
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	gs.set_player("GBR")
	await process_frame
	var panel: Node = get_first_node_in_group("navy_panel")
	var bar: Node = get_first_node_in_group("fleet_action_bar")
	_check(bar != null, "the fleet bar exists")
	_check(not bar.visible, "it is hidden while nothing is selected")

	var grand = null
	for f in gs.fleets.values():
		if f.tag == "GBR" and f.display_name == "Grand Fleet":
			grand = f
	_check(grand != null and grand.ships.size() >= 2, "the Grand Fleet has several squadrons")
	var ids: Array[int] = [grand.id]
	panel.select_fleets(ids)
	await process_frame
	_check(bar.visible and bar._ids == ids, "selecting a fleet brings the bar up")
	_check(bar._title.text.contains("Grand Fleet") and bar._title.text.contains("ships"), "and names it (%s)" % bar._title.text)
	_check(bar._merge.disabled and not bar._detach.disabled, "one fleet can be detached from, not merged")
	_check(bar.get_global_rect().end.y <= root.get_visible_rect().size.y, "it sits on the screen")

	# Orders.
	bar._fill_orders()
	var Nav = load("res://scripts/sim/navy.gd")
	var missions: Array = Nav.cfg.missions.keys()
	_check(bar._orders.get_popup().item_count == missions.size(), "Orders lists every standing order")
	var other: String = "patrol" if grand.mission != "patrol" else "blockade"
	bar._on_orders(missions.find(other))
	_check(grand.mission == other, "choosing an order sets it (%s)" % other)

	# Detach one squadron, then merge back.
	var ships: int = grand.ships.size()
	bar._fill_detach()
	_check(bar._detach.get_popup().item_count >= 1, "Detach lists the types in the fleet")
	bar._on_detach(0)
	await process_frame
	_check(grand.ships.size() == ships - 1 and panel._selected.size() == 1 and panel._selected[0] != grand.id, "Detach splits a squadron off and selects it")
	var both: Array[int] = [grand.id, panel._selected[0]]
	panel.select_ids(both)
	await process_frame
	_check(bar._ids == both and not bar._merge.disabled, "the bar follows a bigger selection and Merge opens")
	bar._on_merge()
	await process_frame
	var just_grand: Array[int] = [grand.id]
	_check(grand.ships.size() == ships and panel._selected == just_grand, "Merge puts the fleet together again")

	# With armies selected too the fleet bar rises above the army bar.
	var army_bar: Node = get_first_node_in_group("army_action_bar")
	var mine = null
	for a in gs.armies.values():
		if a.tag == "GBR":
			mine = a
			break
	var army_ids: Array[int] = [mine.id]
	army_bar.set_selection(army_ids)
	await process_frame
	await process_frame
	_check(army_bar.visible and bar.visible, "both bars can show at once")
	_check(bar.get_global_rect().end.y <= army_bar.get_global_rect().position.y + 1.0, "the fleet bar sits above the army bar")
	army_bar.set_selection([] as Array[int])

	bar._deselect.pressed.emit()
	await process_frame
	_check(not bar.visible and panel._selected.is_empty(), "Deselect clears the selection and hides the bar")

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_settings.cfg"))
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
