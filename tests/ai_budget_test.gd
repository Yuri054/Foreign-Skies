extends SceneTree
## Headless test for the AI's budget: buildings (factories in peace, a construction sector when gold runs ahead of
## the points, works on a front at war), buying diplomacy points, and that nations stay out of ruin over two years.
## Run: godot --headless --path . -s res://tests/ai_budget_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var clock: Node
var B
var A


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
	B = load("res://scripts/ai/ai_budget.gd")
	A = load("res://scripts/ai/ai.gd")

	_test_buildings()
	_test_points()
	_test_recovery()

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.set_player("ESP")
	gs.ai_enabled = false
	A.cfg.budget.enabled = true


func _log_count(kind: String) -> int:
	return gs.command_log.filter(func(c: Dictionary) -> bool: return c.type == kind).size()


func _started(n: Object, type: String) -> int:
	return n.construction.filter(func(j: Dictionary) -> bool: return j.type == type).size()


func _test_buildings() -> void:
	# In peace with gold and points to spare, a nation builds civilian factories, several a month, keeping its reserve.
	_fresh()
	var n = gs.nations["ITA"]
	n.treasury = 200.0
	n.cp = 2000.0
	B.step(gs, "ITA")
	var factories := _started(n, "civilian_factory")
	_check(factories >= 2, "a rich nation in peace starts civilian factories (%d)" % factories)
	_check(n.treasury >= B.reserve(gs, "ITA") - 0.001, "and keeps its reserve (%.1f)" % n.treasury)
	_check(n.construction.size() <= int(A.cfg.budget.max_starts), "at most max_starts a month")
	var places := {}
	for job in n.construction:
		places[job.province] = places.get(job.province, 0) + 1
	_check(places.values().all(func(v: int) -> bool: return v == 1), "one project a province")
	B.step(gs, "ITA")
	_check(n.construction.size() == factories, "and once a month")

	# Without the gold, nothing.
	_fresh()
	n = gs.nations["ITA"]
	n.treasury = 5.0
	n.cp = 2000.0
	B.step(gs, "ITA")
	_check(n.construction.is_empty(), "a nation without gold to spare builds nothing")

	# Gold piling up faster than the points: a construction sector.
	_fresh()
	n = gs.nations["ITA"]
	n.treasury = 1000.0
	n.cp = 300.0
	n.budget.net = 40.0
	B.step(gs, "ITA")
	_check(_started(n, "construction_sector") >= 1, "with gold to spare and few points it builds a construction sector")

	# At war, works on the front come first.
	_fresh()
	gs.set_war("FRA", "GER", true)
	n = gs.nations["FRA"]
	var front = load("res://scripts/sim/designate_front.gd").new("FRA", "Eastern Front", [] as Array[int], "GER")
	gs.issue(front)
	n.treasury = 300.0
	n.cp = 2000.0
	B.step(gs, "FRA")
	var works := _started(n, "trench") + _started(n, "fortification")
	_check(works >= 1, "at war, with a front, it digs in (%d works started)" % works)


func _test_points() -> void:
	_fresh()
	var n = gs.nations["FRA"]
	n.diplomacy_points = 5.0
	n.treasury = 100.0
	n.mobilization = 0.0
	B.step(gs, "FRA")
	_check(_log_count("BuyPoints") == 0, "at peace it does not buy points")
	_fresh()
	n = gs.nations["FRA"]
	n.diplomacy_points = 5.0
	n.treasury = 100.0
	n.mobilization = 0.5
	B.step(gs, "FRA")
	_check(_log_count("BuyPoints") == 1 and n.diplomacy_points > 5.0, "in a crisis, short of points, it buys a batch")
	_fresh()
	n = gs.nations["FRA"]
	n.diplomacy_points = 90.0
	n.treasury = 100.0
	n.mobilization = 0.5
	B.step(gs, "FRA")
	_check(_log_count("BuyPoints") == 0, "not when it has plenty")
	_fresh()
	n = gs.nations["FRA"]
	n.diplomacy_points = 5.0
	n.treasury = 3.0
	n.mobilization = 0.5
	B.step(gs, "FRA")
	_check(_log_count("BuyPoints") == 0, "nor when it cannot spare the money")


## Two years of the crisis: debts shrink, and no nation is left in ruin.
func _test_recovery() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("ESP")
	gs.ai_enabled = true
	var debt := func() -> float:
		var total := 0.0
		for t in gs.nations:
			total += minf(0.0, gs.nations[t].treasury)
		return total
	for i in 300:
		clock.advance_day()
	var mid: float = debt.call()
	for i in 400:
		clock.advance_day()
	var late: float = debt.call()
	_check(late > mid - 10.0 and late > -50.0, "the world's debts stay small between month ten and month twenty-three (%.0f to %.0f)" % [mid, late])
	var worst := 0.0
	for t in gs.nations:
		worst = minf(worst, gs.nations[t].treasury)
	_check(worst > -300.0, "no nation is in deep debt after two years, even with the new wars of the second year (worst %.0f)" % worst)
