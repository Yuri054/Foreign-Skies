extends SceneTree
## Headless test of construction capacity: a nation's daily points come from its industry, a
## project takes at most its rate (so min_days with ample points), a small nation's queue is
## served in order and slowly, the queue can be re-ordered, industry in enemy hands stops
## counting, and the queue survives a save.
## Run: godot --headless --path . -s res://tests/construction_points_test.gd

var _failures := 0
var gs: Node
var Clock: Node
var Eco
var Build
var Prioritize


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
	Eco = load("res://scripts/sim/economy.gd")
	Build = load("res://scripts/sim/construct_building.gd")
	Prioritize = load("res://scripts/sim/prioritize_construction.gd")
	_fresh()
	_test_pool()
	_test_single_project()
	_test_scarce_points()
	_test_priority()
	_test_occupation()
	_test_save()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.ai_enabled = false
	for tag in ["GER", "SRB", "BEL"]:
		gs.nations[tag].treasury = 100000.0
		# The queue alone: no IC set aside for munitions (munitions_test covers the arms share).
		gs.nations[tag].arms_share = 0.0


func _free_province(tag: String, skip := [], type := "factory") -> int:
	for id in gs.nations[tag].provinces:
		# One with none of the type yet, whatever works the big cities begin with.
		if id not in skip and gs.province_buildings[id].get(type, 0) == 0 and Eco.build_problem(gs, tag, id, type).is_empty():
			return id
	return 0


func _test_pool() -> void:
	var cfg: Dictionary = Eco.cfg.construction
	var ger = gs.nations["GER"]
	var expected: float = Eco.construction_points(ger, ger.budget.industry)
	_check(is_equal_approx(ger.budget.construction_points, expected), "Germany's %.1f IC a day come from its industry (£%.0fM a year)" % [expected, ger.budget.industry])
	_check(ger.budget.construction_points > cfg.base_ic * 4.0, "a great industry gives far more than the base")
	_check(gs.nations["BEL"].budget.construction_points < ger.budget.construction_points / 3.0, "Belgium has far fewer")
	_check(gs.nations["SRB"].budget.construction_points >= cfg.base_ic, "even a tiny nation has the base points")


func _test_single_project() -> void:
	var ger = gs.nations["GER"]
	var id := _free_province("GER")
	var days: int = Eco.cfg.buildings.factory.min_days
	var rate: float = Eco.cfg.buildings.factory.ic / float(days)
	var f0: int = gs.province_buildings[id].get("factory", 0)
	_check(gs.issue(Build.new("GER", id, "factory")), "a factory is queued")
	var job: Dictionary = ger.construction[0]
	_check(is_equal_approx(job.points_total, Eco.cfg.buildings.factory.ic), "it needs the building's IC")
	Clock.advance_day()
	_check(is_equal_approx(job.given, rate) and job.days_left == days - 1, "with ample points it gets its full rate: %d days left" % job.days_left)
	_check(is_equal_approx(ger.construction_used, rate), "and the day's use is counted")
	for i in days - 2:
		Clock.advance_day()
	_check(ger.construction.size() == 1, "it is not done a day early")
	Clock.advance_day()
	_check(ger.construction.is_empty() and gs.province_buildings[id].get("factory", 0) == f0 + 1, "it stands after exactly min_days")


func _test_scarce_points() -> void:
	var srb = gs.nations["SRB"]
	var pool: float = srb.budget.construction_points
	var rate: float = Eco.cfg.buildings.fortification.ic / float(Eco.cfg.buildings.fortification.min_days)
	var a := _free_province("SRB", [], "fortification")
	var b := _free_province("SRB", [a], "fortification")
	_check(a > 0 and b > 0, "Serbia has two places for a fortification")
	_check(gs.issue(Build.new("SRB", a, "fortification")) and gs.issue(Build.new("SRB", b, "fortification")), "two fortifications are queued")
	for i in 10:
		Clock.advance_day()
	var first: Dictionary = srb.construction[0]
	var second: Dictionary = srb.construction[1]
	_check(pool < rate, "Serbia's %.1f IC are under one fortification's rate (%.0f)" % [pool, rate])
	_check(absf(first.given - pool) < 1.0 and second.given == 0.0, "the first in the queue takes them all, the next waits")
	_check(first.days_left > Eco.cfg.buildings.fortification.min_days and second.days_left >= 9999, "so it takes longer than build_days and the next has no estimate")
	_check(absf(srb.construction_used - pool) < 1.0, "every point is used")
	# The second starts once the first is done.
	var guard := 0
	while srb.construction.size() == 2 and guard < 2000:
		Clock.advance_day()
		guard += 1
	_check(srb.construction.size() == 1 and srb.construction[0].given > 0.0 or srb.construction.size() == 1, "the first finishes (%d days) and the second takes over" % guard)
	Clock.advance_day()
	_check(srb.construction[0].given > 0.0, "and now it is served")


func _test_priority() -> void:
	_fresh()
	var srb = gs.nations["SRB"]
	var a := _free_province("SRB")
	var b := _free_province("SRB", [a])
	gs.issue(Build.new("SRB", a, "factory"))
	gs.issue(Build.new("SRB", b, "factory"))
	_check(srb.construction[0].province == a, "the queue is in the order built")
	_check(gs.issue(Prioritize.new("SRB", b, "factory")) and srb.construction[0].province == b, "a project can be moved to the front")
	_check(not gs.issue(Prioritize.new("SRB", b, "factory")), "it is not moved if it is first already")
	_check(not gs.issue(Prioritize.new("SRB", a, "railway")) and not gs.issue(Prioritize.new("GER", a, "factory")), "nothing happens for a project that is not queued")
	Clock.advance_day()
	_check(srb.construction[0].given > 0.0 and srb.construction[1].given == 0.0, "the first in the queue is served first")


func _test_occupation() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	var before: float = ger.budget.construction_points
	var held := 0
	var best := 0.0
	for id in ger.provinces:
		if gs.province_industry[id] > best:
			best = gs.province_industry[id]
			held = id
	gs.set_controller(held, "FRA")
	Eco.recompute(gs)
	var drop: float = before - ger.budget.construction_points
	_check(drop > 0.0, "enemy hands: its industry stops adding points (-%.1f)" % drop)


func _test_save() -> void:
	var SaveGame = load("res://scripts/sim/save_game.gd")
	SaveGame.dir = "user://test_points_saves/"
	_fresh()
	var srb = gs.nations["SRB"]
	var a := _free_province("SRB")
	gs.issue(Build.new("SRB", a, "factory"))
	for i in 5:
		Clock.advance_day()
	var left: float = srb.construction[0].points_left
	var path: String = SaveGame.dir + "points.sav"
	_check(gs.save_game(path) == "", "a game with a queue saves")
	_fresh()
	_check(gs.load_game(path) == "" and gs.nations["SRB"].construction.size() == 1, "and loads")
	_check(is_equal_approx(gs.nations["SRB"].construction[0].points_left, left), "the project's progress is as saved")
	DirAccess.remove_absolute(path)
