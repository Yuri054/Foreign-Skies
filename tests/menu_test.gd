extends SceneTree
## Headless test of the main menu and the pause menu: the menu lists the scenarios, a game
## started from it is the game a direct launch gives, Continue and Load put a save back and a
## refused save says why, and Esc opens and closes the pause menu with the clock as it was.
## Run: godot --headless --path . -s res://tests/menu_test.gd

const DIR := "user://test_menu_saves/"

var _failures := 0
var gs: Node
var Clock: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	Clock = root.get_node("Clock")
	var Scenarios = load("res://scripts/sim/scenarios.gd")
	var SaveGame = load("res://scripts/sim/save_game.gd")
	SaveGame.dir = DIR

	var list: Array = Scenarios.list()
	var names: Array = list.map(func(s: Dictionary) -> String: return s.name)
	_check("July 1914" in names, "the scenario list has July 1914")
	_check(list[0].playable and list[0].start_date == "28 July 1914", "it is playable and starts on 28 July 1914")

	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	menu.opens_map = false
	root.add_child(menu)
	await process_frame
	_check(menu.page() == "main", "the menu opens on its main page")
	_check(menu._continue.disabled, "Continue is off while there are no saves")
	menu.show_page("new")
	_check(menu.selected_scenario().get("name", "") == "July 1914", "the new game page offers July 1914, selected")

	gs.load_scenario(gs.DEFAULT_SCENARIO)
	var direct := _fingerprint()
	for i in 30:
		Clock.advance_day()
	menu.start_new()
	_check(_fingerprint() == direct, "a game started from the menu equals a direct launch")
	_check(not Scenarios.resume, "a new game asks for a nation")

	# Continue and Load.
	for i in 20:
		Clock.advance_day()
	var played := _fingerprint()
	_check(gs.save_game(DIR + "one.sav") == "", "a game is saved")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	menu.show_page("main")
	_check(not menu._continue.disabled, "Continue is on once there is a save")
	menu.continue_game()
	_check(_fingerprint() == played and Scenarios.resume, "Continue loads the newest save and resumes it")
	Scenarios.resume = false
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	menu.show_page("load")
	_check(menu.load_save(DIR + "one.sav") and _fingerprint() == played, "Load puts a save back")

	var f := FileAccess.open(DIR + "junk.sav", FileAccess.WRITE)
	f.store_string("not a save")
	f.close()
	Scenarios.resume = false
	_check(not menu.load_save(DIR + "junk.sav") and menu._status.text != "" and not Scenarios.resume, "a refused save says why and does not resume")
	menu.queue_free()

	# The pause menu.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var pause: Node = get_first_node_in_group("pause_menu")
	_check(pause != null, "the map has a pause menu")
	gs.pending_joins.clear()
	gs.pending_offers.clear()
	Clock.paused = false
	_esc()
	# The nation picker is up on a new game, so Esc is not the pause menu's yet.
	_check(not pause.is_open(), "Esc does nothing while the nation picker is up")
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	await process_frame
	_esc()
	_check(pause.is_open() and Clock.paused, "Esc opens the pause menu and stops the clock")
	_esc()
	_check(not pause.is_open() and not Clock.paused, "Esc closes it and the clock runs as before")
	Clock.paused = true
	_esc()
	_esc()
	_check(Clock.paused, "a clock that was paused stays paused")

	DirAccess.remove_absolute(DIR + "one.sav")
	DirAccess.remove_absolute(DIR + "junk.sav")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _esc() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _fingerprint() -> String:
	var parts: PackedStringArray = [Clock.date_string(), str(gs.province_owner), str(gs.scenario.get("name", "")), str(gs.player_tag)]
	for tag in gs.nations:
		var n = gs.nations[tag]
		parts.append("%s %.4f %d" % [tag, n.treasury, n.manpower])
	parts.append("%d armies %d fleets %d wars" % [gs.armies.size(), gs.fleets.size(), gs.wars.size()])
	return "\n".join(parts)
