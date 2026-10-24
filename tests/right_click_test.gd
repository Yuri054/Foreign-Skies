extends SceneTree
## Headless test of right-clicking a nation: the first click opens its country panel and puts the
## map in the Diplomacy mode seen from it, a click on another nation moves both, a second click
## on the same nation (or closing the panel) puts the map back as it was.
## Run: godot --headless --path . -s res://tests/right_click_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var gs: Node = root.get_node("GameState")
	for c in main.get_node("UI").get_children():
		if c.get_script() != null and "nation_picker" in c.get_script().resource_path:
			c.queue_free()
	gs.ai_enabled = false
	gs.set_player("FRA")
	await process_frame
	var view: Sprite2D = main.map_view
	var Mode = view.get_script().Mode
	var panel: Node = get_first_node_in_group("nation_stats")
	panel.close_window()
	view.set_mode(Mode.TERRAIN)
	var ger: int = gs.nations["GER"].provinces[0]
	var rus: int = gs.nations["RUS"].provinces[0]

	view.province_ordered.emit(ger)
	await process_frame
	_check(panel.visible and panel.shown_tag() == "GER", "the first right click opens Germany's panel")
	_check(view.mode == Mode.DIPLOMACY and view.diplomacy_viewpoint() == "GER", "and shows the Diplomacy mode seen from Germany")

	view.province_ordered.emit(rus)
	await process_frame
	_check(panel.shown_tag() == "RUS" and view.mode == Mode.DIPLOMACY and view.diplomacy_viewpoint() == "RUS", "another nation moves the panel and the point of view")

	view.province_ordered.emit(rus)
	await process_frame
	_check(not panel.visible, "right-clicking the same nation again closes the panel")
	_check(view.mode == Mode.TERRAIN and view.diplomacy_viewpoint() == "FRA", "and puts back the terrain map and your own point of view")

	view.province_ordered.emit(ger)
	await process_frame
	panel.close_window()
	await process_frame
	_check(view.mode == Mode.TERRAIN and view.diplomacy_viewpoint() == "FRA", "closing the panel with the X does the same")

	# A map mode picked meanwhile is left alone.
	view.province_ordered.emit(ger)
	await process_frame
	view.set_mode(Mode.POPULATION)
	view.province_ordered.emit(ger)
	await process_frame
	_check(not panel.visible and view.mode == Mode.POPULATION, "a map mode picked meanwhile stays")

	# Already in the Diplomacy mode: it stays there afterwards.
	view.set_mode(Mode.DIPLOMACY)
	view.province_ordered.emit(ger)
	await process_frame
	view.province_ordered.emit(ger)
	await process_frame
	_check(not panel.visible and view.mode == Mode.DIPLOMACY and view.diplomacy_viewpoint() == "FRA", "from the Diplomacy mode it comes back to your own point of view")

	# Your own nation is the Nation screen's business: the map and the country panel are left alone.
	view.set_mode(Mode.TERRAIN)
	var screen: Node = get_first_node_in_group("nation_screen")
	view.province_ordered.emit(gs.nations["FRA"].provinces[0])
	await process_frame
	_check(screen.visible and not panel.visible and view.mode == Mode.TERRAIN, "your own land opens the Nation screen and changes nothing on the map")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
