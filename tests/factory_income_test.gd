extends SceneTree
## Headless test of what a civilian factory gives: construction points and money. A factory built
## since the start pays into the treasury, a retooled one stops paying, the start itself is
## unchanged, and the AI counts the income when it weighs a factory.
## Run: godot --headless --path . -s res://tests/factory_income_test.gd

var _failures := 0
var gs: Node
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
	Eco = load("res://scripts/sim/economy.gd")
	_fresh()
	_test_income()
	_test_construction()
	_test_ai()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.ai_enabled = false
	gs.set_player("FRA")


func _test_income() -> void:
	var fra = gs.nations["FRA"]
	_check(is_zero_approx(fra.budget.factory_income), "at the start the factories pay nothing extra (the start is calibrated)")
	var id: int = fra.provinces[0]
	var revenue0: float = fra.budget.revenue
	var gdp0: float = fra.budget.gdp
	gs.province_buildings[id]["factory"] = gs.province_buildings[id].get("factory", 0) + 1
	Eco.recompute(gs)
	var gain: float = fra.budget.revenue - revenue0
	var income: float = Eco.factory_income(fra)
	_check(is_equal_approx(fra.budget.factory_income, income), "a new factory pays into the treasury (%.2fM a year)" % income)
	_check(gain > income and gain < income + Eco.factory_output(fra), "on top of the tax on the output it adds (%.2f in all)" % gain)
	_check(fra.budget.gdp > gdp0, "and output rises")
	# Higher taxes do not change what it pays directly.
	fra.tax_rate = 0.3
	Eco.recompute(gs)
	_check(is_equal_approx(fra.budget.factory_income, income), "whatever the tax rate")
	# A retooled factory takes it away.
	fra.tax_rate = 0.1
	gs.province_buildings[id]["factory"] -= 2
	Eco.recompute(gs)
	_check(fra.budget.factory_income < 0.0, "one retooled to military costs it (%.2f)" % fra.budget.factory_income)


func _test_construction() -> void:
	_fresh()
	var fra = gs.nations["FRA"]
	var points0: float = fra.budget.construction_points
	var id: int = fra.provinces[0]
	gs.province_buildings[id]["factory"] = gs.province_buildings[id].get("factory", 0) + 5
	Eco.recompute(gs)
	var gained: float = fra.budget.construction_points - points0
	var full: float = 5.0 * Eco.cfg.construction.ic_per_factory * (1.0 - Eco.consumer_share(fra)) * Eco.worker_share(fra)
	_check(gained > 0.8 * full and gained <= full + 0.001, "each factory also gives construction points (%.2f for five)" % gained)


func _test_ai() -> void:
	_fresh()
	var AIB = load("res://scripts/ai/ai_budget.gd")
	var fra = gs.nations["FRA"]
	var id: int = fra.provinces[0]
	var plan: Dictionary = Eco.build_plan(gs, id, "factory")
	var value: float = AIB.build_return(gs, "FRA", id, "factory", plan)
	var worth: float = (Eco.factory_income(fra) + Eco.factory_output(fra) * fra.tax_rate) / plan.total
	_check(value >= worth, "the AI counts the income when it weighs a factory (%.2f a pound)" % value)
	_check(plan.total / Eco.factory_income(fra) < 6.0, "and a factory pays back in a few years (%.1f)" % (plan.total / Eco.factory_income(fra)))
