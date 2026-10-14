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
	_check(Fmt.ordinal(1) == "1st" and Fmt.ordinal(12) == "12th" and Fmt.ordinal(23) == "23rd", "ordinals read right")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
