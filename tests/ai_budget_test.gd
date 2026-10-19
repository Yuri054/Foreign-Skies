extends SceneTree
## Headless test for the AI's budget: taxes, programs, buildings and buying diplomacy points,
## and that nations climb out of debt over two years of the crisis.
## Run: godot --headless --path . -s res://tests/ai_budget_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var clock: Node
var B
var A
var Eco


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
	Eco = load("res://scripts/sim/economy.gd")

	_test_taxes()
	_test_programs()
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


func _test_taxes() -> void:
	_fresh()
	var n = gs.nations["FRA"]
	n.tax_rate = 0.1
	n.treasury = -50.0
	n.budget["net"] = -24.0
	_check(is_equal_approx(B.wanted_tax(gs, "FRA"), 0.1 + A.cfg.budget.tax_step), "a nation in debt and in deficit raises its tax")
	n.treasury = 5.0
	_check(B.wanted_tax(gs, "FRA") > 0.1, "so does one whose treasury cannot carry the deficit for six months")
	n.treasury = 500.0
	_check(is_equal_approx(B.wanted_tax(gs, "FRA"), 0.1), "but a deficit it can easily carry changes nothing")
	n.tax_rate = A.cfg.budget.tax_max
	n.treasury = -50.0
	_check(is_equal_approx(B.wanted_tax(gs, "FRA"), A.cfg.budget.tax_max), "at peace it never goes past the ceiling")
	gs.set_war("FRA", "GER", true)
	_check(B.wanted_tax(gs, "FRA") > A.cfg.budget.tax_max, "at war the ceiling is higher")
	gs.set_war("FRA", "GER", false)
	n.tax_rate = 0.2
	n.treasury = 1000.0
	n.budget["net"] = 12.0
	_check(is_equal_approx(B.wanted_tax(gs, "FRA"), 0.2 - A.cfg.budget.tax_step), "a rich nation in surplus lowers its tax")
	n.tax_rate = 0.1
	_check(is_equal_approx(B.wanted_tax(gs, "FRA"), 0.1), "but never below the default")
	n.tax_rate = 0.1
	n.treasury = -50.0
	n.budget["net"] = -24.0
	B.step(gs, "FRA")
	_check(is_equal_approx(n.tax_rate, 0.1 + A.cfg.budget.tax_step) and _log_count("SetEconomyPolicy") == 1, "the monthly step makes the change by command")
	B.step(gs, "FRA")
	_check(_log_count("SetEconomyPolicy") == 1, "once a month")


func _test_programs() -> void:
	_fresh()
	var n = gs.nations["GER"]
	n.budget["net"] = 30.0
	n.treasury = 100.0
	B.step(gs, "GER")
	_check(n.programs.has("diplomatic_service"), "a nation in surplus takes up the diplomatic service")
	gs.ai_budget_stamp.clear()
	B.step(gs, "GER")
	_check(n.programs.has("education"), "then a growth program, one a month")
	_fresh()
	n = gs.nations["GER"]
	n.budget["net"] = 0.2
	n.treasury = 100.0
	B.step(gs, "GER")
	_check(n.programs.is_empty(), "but not when the budget cannot carry the cost")
	_fresh()
	n = gs.nations["GER"]
	n.programs["education"] = true
	n.programs["diplomatic_service"] = true
	n.budget["net"] = -10.0
	n.treasury = 2.0
	B.step(gs, "GER")
	_check(n.programs.size() == 1, "a broke nation drops its programs, one a month")
	gs.ai_budget_stamp.clear()
	B.step(gs, "GER")
	_check(n.programs.is_empty(), "until none are left")


func _test_buildings() -> void:
	_fresh()
	var n = gs.nations["FRA"]
	n.budget["net"] = 20.0
	n.treasury = 200.0
	n.programs.clear()
	B.step(gs, "FRA")
	_check(n.construction.size() == 1 and _log_count("ConstructBuilding") == 1, "a nation in surplus starts a building")
	var job = n.construction[0]
	_check(gs.province_owner[job.province] == "FRA", "in its own province (%s)" % job.type)
	gs.ai_budget_stamp.clear()
	B.step(gs, "FRA")
	gs.ai_budget_stamp.clear()
	B.step(gs, "FRA")
	_check(n.construction.size() <= int(A.cfg.budget.max_construction), "never more than max_construction jobs at once")
	_fresh()
	n = gs.nations["FRA"]
	n.budget["net"] = -2.0
	n.treasury = 200.0
	B.step(gs, "FRA")
	_check(n.construction.is_empty(), "no building while the budget is in deficit")
	_fresh()
	n = gs.nations["FRA"]
	n.budget["net"] = 20.0
	n.treasury = 11.0
	B.step(gs, "FRA")
	_check(n.construction.size() == 1, "buildings cost IC, not money, so a low treasury does not stop it")
	# Railways behind a front score higher than elsewhere.
	_fresh()
	gs.set_war("GER", "BEL", true)
	var line: Array = load("res://scripts/sim/military.gd").border_provinces(gs, "BEL", "GER")
	var plan: Dictionary = Eco.build_plan(gs, line[0], "railway")
	var near: float = B.build_return(gs, "BEL", line[0], "railway", plan)
	gs.set_war("GER", "BEL", false)
	var d = load("res://scripts/sim/designate_front.gd")
	gs.set_war("GER", "BEL", true)
	var none: Array[int] = []
	gs.issue(d.new("BEL", "", none, "GER"))
	var with_front: float = B.build_return(gs, "BEL", line[0], "railway", plan)
	_check(with_front > near, "a railway on a front is worth more than the same one in peace (%.3f against %.3f)" % [with_front, near])


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
	_check(late > mid, "the world's debts shrink between month ten and month twenty-three (%.0f to %.0f)" % [mid, late])
	var worst := 0.0
	for t in gs.nations:
		worst = minf(worst, gs.nations[t].treasury)
	_check(worst > -200.0, "no nation is in deep debt after two years (worst %.0f)" % worst)
