extends SceneTree
## Drives the briefing through the main scene: the Overview shows the cabinet briefing with a button to
## the tab that deals with each issue, the tension breakdown and its chart, the diplomacy panel says what
## a nation intends toward the player, and the peace screen says where the enemy stands.
## Run: godot --headless --path . -s res://tests/briefing_ui_test.gd

var _failures := 0
var gs: Node
var main: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _texts(node: Node, out: Array) -> Array:
	if node is Label:
		out.append(node.text)
	if node is Button:
		out.append(node.text)
	for c in node.get_children():
		_texts(c, out)
	return out


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://test_settings.cfg"
	gs = root.get_node("GameState")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.wars.clear()
	gs.join_calls.clear()
	gs.set_player("GER")
	gs.ai_enabled = false
	await process_frame
	root.get_node("Clock").advance_day()
	gs.nations["GER"].treasury = -30.0
	var screen: Node = get_first_node_in_group("nation_screen")
	var overview: Node = get_first_node_in_group("overview_panel")
	screen.open_page(overview)
	await process_frame
	await process_frame
	var texts := _texts(overview, [])
	_check("Cabinet briefing" in texts, "the Overview has a cabinet briefing")
	_check(texts.any(func(t: String) -> bool: return t.begins_with("The treasury is in debt")), "it lists the debt")
	_check("Open Economy" in texts, "with a button to the Economy tab")
	var found: Button = null
	for c in overview.find_children("*", "Button", true, false):
		if c.text == "Open Economy":
			found = c
	found.pressed.emit()
	await process_frame
	_check(screen.current_page() == screen.page_named("Economy"), "which opens that tab")
	gs.tension_history.assign([40.0, 41.0, 43.0, 44.0])
	screen.open_page(overview)
	await process_frame
	await process_frame
	_check(not overview.find_children("*", "TrendChart", true, false).is_empty(), "the tension chart is there")
	_check(_texts(overview, []).any(func(t: String) -> bool: return t.begins_with("Worst rivalries")), "and the worst rivalries")
	screen.close_screen()

	# The intent line in the diplomacy panel.
	gs.nations["GER"].treasury = 500.0
	var panel: Node = get_first_node_in_group("diplomacy_panel")
	screen.open_page(panel)
	panel.show_nation("FRA")
	await process_frame
	await process_frame
	var all_text := _texts(panel, [])
	_check(all_text.any(func(t: String) -> bool: return t.contains(gs.nations["FRA"].display_name) and (t.contains("attack") or t.contains("war with") or t.contains("war on"))), "the diplomacy panel says what France intends toward Germany")

	# The peace screen's line.
	gs.set_war("GER", "FRA", true, "none")
	var war: War = gs.war_between("GER", "FRA")
	var peace: Node = get_first_node_in_group("peace_screen")
	peace.open_war(war.id)
	await process_frame
	_check(peace._goal.visible and (peace._goal.text.contains("wants peace") or peace._goal.text.contains("will fight on")), "the peace screen says where the enemy stands: %s" % peace._goal.text)

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
