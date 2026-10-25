extends SceneTree
## Headless test for the 1914 war plans and the AI running inside the real day tick: the plans
## are well formed, no code names a nation, the AI plays in the tick, and the crisis produces
## fighting on both fronts.
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


func _plan(nation: String, enemy: String):
	for p in gs.ai_plans:
		if p.nation == nation and p.enemy == enemy:
			return p
	return null


func _names(plan) -> Array:
	return plan.objectives.map(func(o) -> String: return map.provinces[o.province].name)


func _test_plans() -> void:
	_check(gs.ai_plans.size() >= 6, "the scenario has its 1914 plans (%d)" % gs.ai_plans.size())
	for p in gs.ai_plans:
		var label := "%s against %s" % [p.nation, p.enemy]
		_check(gs.nations.has(p.nation) and gs.nations.has(p.enemy), "%s names real nations" % label)
		_check(not p.objectives.is_empty(), "%s has objectives" % label)
		for o in p.objectives:
			_check(gs.province_owner[o.province] == p.enemy, "%s: %s belongs to the enemy at the start" % [label, map.provinces[o.province].name])
			_check(o.weight > 0.0, "%s: %s has a positive weight" % [label, map.provinces[o.province].name])
	_check(_names(_plan("GER", "BEL")).has("Brussels") and _names(_plan("GER", "FRA")).has("Paris"), "Germany aims at Brussels and Paris")
	_check(_names(_plan("FRA", "GER")).has("Moselle") and _names(_plan("FRA", "GER")).has("Bas-Rhin") and _names(_plan("FRA", "GER")).has("Saarland"), "France aims at Alsace-Lorraine")
	_check(_names(_plan("RUS", "AUH")).has("Lemberg") and _names(_plan("RUS", "AUH")).has("Krakow"), "Russia aims at Lemberg and Cracow")
	_check(_names(_plan("AUH", "SRB")) == ["Belgrade"], "Austria-Hungary aims at Belgrade")
	_check(_plan("RUS", "GER") != null, "Russia has a plan against Germany")
	# Serbia, Montenegro, Belgium and Britain need no entry: they fall back on the general rule.
	for tag in ["SRB", "MNE", "BEL", "GBR"]:
		var none := true
		for p in gs.ai_plans:
			none = none and p.nation != tag
		_check(none, "%s has no plan of its own" % tag)


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
	_check(battles.get("RUS", 0) > 0 and battles.get("GER", 0) > 0, "there is fighting on the Eastern front")
	_check(battles.get("FRA", 0) > 0, "there is fighting on the Western front")
	_check(gs.command_log.any(func(c) -> bool: return c.type == "RaiseUnits"), "nations at war recruit")
	var west := 0
	for id in range(1, gs.province_owner.size()):
		var o: String = gs.province_owner[id]
		var c: String = gs.province_controller[id]
		if o != c and o in ["FRA", "GER", "BEL"] and c in ["FRA", "GER", "BEL"]:
			west += 1
	_check(west <= 15, "the Western front has not collapsed after four months (%d provinces held across it)" % west)
