extends SceneTree
## Headless test of the AI running inside the real day tick: nothing is scripted for any nation (no authored plans),
## no code names a nation, the AI plays in the tick, and the crisis produces fighting.
## Run: godot --headless --path . -s res://tests/ai_plans_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var clock: Node
var map: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	map = root.get_node("MapData")

	_test_plans()
	_test_no_special_cases()
	_test_tick_and_crisis()

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _test_plans() -> void:
	# The AI's plans are its own (AIAmbition makes them): a scenario brings none, and none are there at the start.
	_check(gs.ai_plans.is_empty(), "a scenario starts with no plans for anyone (%d)" % gs.ai_plans.size())
	for dir in ["res://data/scenarios/july_1914/", "res://data/scenarios/jan_1900/"]:
		var sc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "scenario.json"))
		_check(not sc.has("ai_plans"), "%s does not script what any nation wants" % dir)


## The AI treats every nation by the same rules: no script under scripts/ai names one.
func _test_no_special_cases() -> void:
	var re := RegEx.new()
	re.compile("\"([A-Z]{3})\"")
	var hits: Array[String] = []
	for file in DirAccess.get_files_at("res://scripts/ai"):
		if not file.ends_with(".gd"):
			continue
		for line in FileAccess.get_file_as_string("res://scripts/ai/" + file).split("\n"):
			if line.strip_edges().begins_with("#") or line.strip_edges().begins_with("##"):
				continue
			for m in re.search_all(line):
				if gs.nations.has(m.get_string(1)):
					hits.append("%s: %s" % [file, line.strip_edges()])
	_check(hits.is_empty(), "no AI script names a nation %s" % str(hits))


func _test_tick_and_crisis() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("ESP")
	var battles := {}
	gs.battle_fought.connect(func(_p: int, tags: Array) -> void:
		for t: String in tags:
			battles[t] = battles.get(t, 0) + 1)
	for i in 12:
		clock.advance_day()
	var ai_fronts := 0
	for f in gs.fronts.values():
		ai_fronts += 1
	_check(ai_fronts > 0, "the AI draws fronts in the real day tick (%d)" % ai_fronts)
	for i in 240:
		clock.advance_day()
	var fought := 0
	for t in battles:
		fought += battles[t]
	_check(battles.size() >= 4 and fought >= 20, "the powers fight (%d nations in %d battle sides)" % [battles.size(), fought])
	_check(gs.command_log.any(func(c) -> bool: return c.type == "RaiseUnits"), "nations at war recruit")
