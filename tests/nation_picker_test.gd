extends SceneTree
## Headless test of choosing a nation on the map: the picker leaves the map live, a click on a
## province picks its owner, sea does nothing, and Play starts the game as that nation.
## Run: godot --headless --path . -s res://tests/nation_picker_test.gd

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
	load("res://scripts/ui/ui_settings.gd").path = "user://test_settings.cfg"
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	var Scen = load("res://scripts/sim/scenarios.gd")
	Scen.resume = false
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var picker: Control = get_first_node_in_group("nation_picker")
	_check(picker != null, "a new game opens the picker")
	_check(picker.mouse_filter == Control.MOUSE_FILTER_IGNORE, "it does not block the map")
	var bar: Node = get_first_node_in_group("top_bar")
	_check(gs.player_tag == "" and (bar != null and bar._nation.text == "Choosing a nation"), "no nation is played while choosing: the top bar says so, not the scenario's own nation (%s)" % (bar._nation.text if bar != null else "no bar"))
	_check(picker.chosen() == gs.scenario.get("default_player", ""), "the scenario's nation is only suggested")

	var fra := 0
	var ger := 0
	for id in range(1, gs.province_owner.size()):
		if fra == 0 and gs.province_owner[id] == "FRA":
			fra = id
		if ger == 0 and gs.province_owner[id] == "GER":
			ger = id
	main.map_view.select(ger)
	_check(picker.chosen() == "GER", "clicking a German province picks Germany")
	main.map_view.select(fra)
	_check(picker.chosen() == "FRA", "clicking a French one picks France")
	main.map_view.select(0)
	_check(picker.chosen() == "FRA", "clicking nothing keeps the choice")
	_check(picker._play.text == "Play as France", "the button names the nation (%s)" % picker._play.text)

	var got := []
	picker.nation_chosen.connect(func(tag: String) -> void: got.append(tag))
	picker._start()
	_check(got == ["FRA"], "Play chooses France")
	await process_frame
	await process_frame
	_check(gs.player_tag == "FRA" and get_first_node_in_group("nation_picker") == null, "the game goes on as France and the picker is gone")
	# A new game watched as a spectator: no nation, the AI runs all, the country panel and the world pages still open.
	main.queue_free()
	await process_frame
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	picker = get_first_node_in_group("nation_picker")
	picker._watch.pressed.emit()
	await process_frame
	await process_frame
	_check(gs.player_tag == "" and get_first_node_in_group("nation_picker") == null, "Watch starts the game with no nation")
	bar = get_first_node_in_group("top_bar")
	_check(bar != null and bar._nation.text == "Spectator", "the top bar says Spectator")
	_check(load("res://scripts/ai/ai.gd").is_ai(gs, "GER") and load("res://scripts/ai/ai.gd").is_ai(gs, "FRA"), "the AI runs every nation")
	get_first_node_in_group("nation_stats").show_nation("FRA")
	await process_frame
	_check(get_first_node_in_group("nation_stats").visible and not get_first_node_in_group("nation_stats")._actions_box.visible, "a right click shows a nation's panel, with no actions to take")
	var screen: Node = get_first_node_in_group("nation_screen")
	screen.open_page("Economy")
	_check(screen.current_page() == screen.page_named("Rankings"), "the Nation screen opens on the world's pages only")
	screen.open_page("History")
	_check(screen.current_page() == screen.page_named("History"), "History opens")
	var clock: Node = root.get_node("Clock")
	for d in 40:
		clock.advance_day()
	await process_frame
	_check(not gs.has_pending(), "time runs with nothing waiting for an answer")
	_check(Fmt.ordinal(1) == "1st" and Fmt.ordinal(12) == "12th" and Fmt.ordinal(23) == "23rd", "ordinals read right")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
