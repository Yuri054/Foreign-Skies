extends SceneTree
## Headless test of the province panel: hidden until something is selected, then the owner,
## the figures, the buildings and the forces of a province, and the borders of a sea zone.
## Run: godot --headless --path . -s res://tests/province_panel_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GameState")
	var map: Node = root.get_node("MapData")
	load("res://scripts/ui/ui_settings.gd").path = "user://test_settings.cfg"
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("GER")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	var panel: Control = get_first_node_in_group("province_panel")
	_check(panel != null and not panel.visible, "the panel is hidden until something is selected")

	var coastal := 0
	var inland := 0
	for id in range(1, gs.province_owner.size()):
		if gs.province_owner[id] == "GER":
			if coastal == 0 and map.get_province(id).coastal:
				coastal = id
			elif inland == 0 and not map.get_province(id).coastal:
				inland = id
	main.map_view.select(coastal)
	await process_frame
	var text: String = panel.plain_text()
	_check(panel.visible, "selecting a province shows it")
	_check(map.get_province(coastal).name in text and gs.nations["GER"].display_name in text, "it names the province and its owner")
	for word in ["People", "Output", "Recruits", "Infrastructure"]:
		_check(word in text, "it has a %s row" % word)
	_check("coast" in text, "a coastal province says so")

	main.map_view.select(coastal)
	await process_frame
	await process_frame
	_check(panel.size.y >= panel.get_combined_minimum_size().y, "clicking the same province again keeps the background as tall as the text (%s)" % panel.size)

	main.map_view.select(inland)
	await process_frame
	await process_frame
	_check(panel.size.y >= panel.get_combined_minimum_size().y, "and so does a different one")
	_check("coast" not in panel.plain_text(), "an inland one does not")

	var zone := 0
	for z in range(1, map.sea_zones.size()):
		zone = z
		break
	main.map_view.select_zone(zone)
	await process_frame
	text = panel.plain_text()
	_check(panel.visible and "Sea zone" in text and "Borders" in text, "a sea zone shows its borders")

	main.map_view.select(0)
	await process_frame
	_check(not panel.visible, "clicking nothing hides it")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
