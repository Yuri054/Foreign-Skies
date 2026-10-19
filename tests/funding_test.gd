extends SceneTree
## Headless test of army and navy funding: the economy law caps it, the budget pays for it,
## readiness follows it a little each day and sets fighting power, and a law coming down brings it
## down too.
## Run: godot --headless --path . -s res://tests/funding_test.gd

var _failures := 0
var gs: Node
var Eco
var Mil
var Policy
var SetLaw


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
	Mil = load("res://scripts/sim/military.gd")
	Policy = load("res://scripts/sim/set_economy_policy.gd")
	SetLaw = load("res://scripts/sim/set_economy_law.gd")
	_fresh()
	_test_caps()
	_test_cost()
	_test_readiness()
	_test_law_down()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.ai_enabled = false


func _test_caps() -> void:
	var gbr = gs.nations["GBR"]
	_check(gbr.army_funding == 1.0 and gbr.navy_funding == 1.0 and gbr.army_ready == 1.0, "everyone starts at the usual funding")
	gs.issue(Policy.new("GBR", "army_funding", 1.5))
	_check(is_equal_approx(gbr.army_funding, 1.0), "the civilian economy funds no more than the usual (%.2f)" % gbr.army_funding)
	gs.issue(Policy.new("GBR", "army_funding", 0.1))
	_check(is_equal_approx(gbr.army_funding, 0.5), "and no less than half (%.2f)" % gbr.army_funding)
	gbr.economy_law = "war_economy"
	gs.issue(Policy.new("GBR", "navy_funding", 2.0))
	_check(is_equal_approx(gbr.navy_funding, 1.3), "a war economy allows 130%% (%.2f)" % gbr.navy_funding)
	_check(not gs.issue(Policy.new("GBR", "air_funding", 1.0)), "there is no other kind")


func _test_cost() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	var army0: float = ger.budget.army
	var naval0: float = ger.budget.naval
	_check(naval0 > 0.0, "Germany has a navy to pay for")
	ger.economy_law = "war_economy"
	gs.issue(Policy.new("GER", "army_funding", 1.2))
	gs.issue(Policy.new("GER", "navy_funding", 0.5))
	_check(is_equal_approx(ger.budget.army, army0 * 1.2), "the army costs in proportion to its funding (%.1f)" % ger.budget.army)
	_check(is_equal_approx(ger.budget.naval, naval0 * 0.5), "and so does the navy (%.1f)" % ger.budget.naval)


func _test_readiness() -> void:
	_fresh()
	var fra = gs.nations["FRA"]
	var army = null
	for a in gs.armies.values():
		if a.tag == "FRA":
			army = a
			break
	var full: float = army.power()
	gs.issue(Policy.new("FRA", "army_funding", 0.5))
	_check(is_equal_approx(army.power(), full), "readiness has not moved yet, so neither has power")
	for i in 5:
		Mil.step_readiness(gs)
	_check(fra.army_ready < 1.0 and fra.army_ready > 0.5 and army.power() < full, "it drifts down a step a day (%.2f)" % fra.army_ready)
	for i in 40:
		Mil.step_readiness(gs)
	_check(is_equal_approx(fra.army_ready, 0.5) and is_equal_approx(army.power(), full * Mil.cfg.funding.power_floor), "and settles at the floor (%.2f of full power)" % (army.power() / full))
	fra.economy_law = "total_mobilization"
	gs.issue(Policy.new("FRA", "army_funding", 1.5))
	for i in 60:
		Mil.step_readiness(gs)
	_check(army.power() > full and is_equal_approx(Mil.readiness_power(1.5), 1.0 + 0.5 * Mil.cfg.funding.power_bonus), "overfunding adds a little (%.3f of full power)" % (army.power() / full))
	var gbr = gs.nations["GBR"]
	var fleet = null
	for f in gs.fleets.values():
		if f.tag == "GBR":
			fleet = f
			break
	var fleet_full: float = fleet.power()
	gbr.navy_ready = 0.5
	_check(fleet.power() < fleet_full, "an underfunded navy is weaker too")


func _test_law_down() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	gs.set_war("GER", "FRA", true)
	ger.law_changed_day = -1000
	gs.issue(SetLaw.new("GER", "early_mobilization"))
	gs.issue(Policy.new("GER", "army_funding", 1.15))
	_check(is_equal_approx(ger.army_funding, 1.15), "early mobilization allows 115%")
	gs.wars.clear()
	Eco.enforce_laws(gs)
	_check(ger.economy_law == "civilian" and is_equal_approx(ger.army_funding, 1.0), "when the law comes down the funding does too (%.2f)" % ger.army_funding)
