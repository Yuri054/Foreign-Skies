extends SceneTree
## Drives the joint peace through the peace screen: the allies at war with the same enemy are listed with what they would
## ask, one can be left out, and Propose a joint peace makes the peace for everyone at the table.
## Run: godot --headless --path . -s res://tests/conference_ui_test.gd

var _failures := 0
var gs: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://test_settings.cfg"
	gs = root.get_node("GameState")
	var D = load("res://scripts/sim/diplomacy.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	gs.load_scenario("res://data/scenarios/jan_1900/")
	gs.wars.clear()
	gs.join_calls.clear()
	gs.set_player("GER")
	gs.ai_enabled = false
	gs.set_war("GER", "FRA", true, "none")
	var group: int = gs.war_between("GER", "FRA").war_group
	gs.set_war("AUH", "FRA", true, "ally_called", group)
	D._open_group(gs, "GER", "FRA", group)
	D._open_group(gs, "AUH", "FRA", group)
	var fra: Array = gs.nations["FRA"].provinces.duplicate()
	for i in 4:
		gs.province_controller[fra[i]] = "GER"
	for i in 3:
		gs.province_controller[fra[4 + i]] = "AUH"
	gs.nations["FRA"].war_support = 0.0
	var screen: Node = get_first_node_in_group("peace_screen")
	screen.open_war(gs.war_between("GER", "FRA").id)
	await process_frame
	await process_frame
	_check(screen._conf_box.visible and screen._conf_checks.has("AUH"), "the allies at the table are listed")
	_check(screen._conf_checks["AUH"].text.contains("asks for"), "with what they ask: %s" % screen._conf_checks["AUH"].text)
	screen._select_held()
	screen._on_joint()
	await process_frame
	_check(gs.war_between("GER", "FRA") == null and gs.war_between("AUH", "FRA") == null, "a joint peace ends both wars")
	_check(not screen.visible, "and closes the screen")

	# Leaving an ally out makes a separate peace for the rest.
	gs.set_war("GER", "FRA", true, "none")
	group = gs.war_between("GER", "FRA").war_group
	gs.set_war("AUH", "FRA", true, "ally_called", group)
	D._open_group(gs, "GER", "FRA", group)
	D._open_group(gs, "AUH", "FRA", group)
	gs.nations["FRA"].war_support = 0.0
	screen.open_war(gs.war_between("GER", "FRA").id)
	await process_frame
	await process_frame
	screen._conf_checks["AUH"].button_pressed = false
	screen._on_joint()
	await process_frame
	_check(gs.war_between("GER", "FRA") == null and gs.war_between("AUH", "FRA") != null, "an ally left out stays at war")

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
