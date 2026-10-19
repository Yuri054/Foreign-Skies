extends SceneTree
## Headless test of the AI's economy planner: it leaves the automatic equipment lines alone while
## nothing is lacking, bends the factories toward the category the army lacks, keeps the
## factory total, takes an economy law by the state of the war and drops it in peace, and
## values a military factory only when equipment is short.
## Run: godot --headless --path . -s res://tests/ai_production_test.gd

var _failures := 0
var gs: Node
var Clock: Node
var Plan
var Prod
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
	Clock = root.get_node("Clock")
	Plan = load("res://scripts/ai/ai_production.gd")
	Prod = load("res://scripts/sim/production.gd")
	Eco = load("res://scripts/sim/economy.gd")
	_fresh()
	_test_quiet()
	_test_lines()
	_test_law()
	_test_value()
	_test_funding()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	Plan._lacking_day = -1
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.ai_enabled = false


func _line(n, cat: String) -> Dictionary:
	for line in n.production_lines:
		if line.category == cat:
			return line
	return {}


## Strips the arms (or the guns) from every unit of a nation.
func _strip(tag: String, cat: String) -> void:
	Plan._lacking_day = -1
	for a in gs.armies.values():
		if a.tag == tag:
			for u in a.units:
				u.equip[cat] = 0.0
				u.refresh_factor()
	gs.nations[tag].equipment[cat] = 0.0


func _test_quiet() -> void:
	var fra = gs.nations["FRA"]
	var before := [_line(fra, "arms").factories, _line(fra, "artillery").factories]
	Plan.step(gs, "FRA")
	_check(fra.lines_auto and _line(fra, "arms").factories == before[0], "with nothing lacking the lines stay automatic")
	_check(fra.economy_law == "civilian", "and the law stays civilian in peace")
	_check(Plan.factory_value(gs, "FRA") == 0.0, "a military factory is worth nothing to a well-equipped army")


func _test_lines() -> void:
	_fresh()
	var fra = gs.nations["FRA"]
	Clock.advance_day()
	var total: int = Prod.total_factories(fra)
	var arms_before: int = _line(fra, "arms").factories
	var days: float = _line(fra, "arms").days
	_strip("FRA", "arms")
	Plan.step(gs, "FRA")
	_check(not fra.lines_auto, "an army short of arms ends automatic production")
	_check(_line(fra, "arms").factories > arms_before, "and moves factories to arms (%d to %d)" % [arms_before, _line(fra, "arms").factories])
	_check(Prod.assigned(fra) == total, "using all the factories (%d)" % total)
	_check(is_equal_approx(_line(fra, "arms").days, days), "without resetting the line's efficiency")
	Clock.advance_day()
	_check(Prod.assigned(fra) == total, "and the assignment holds")


func _test_law() -> void:
	_fresh()
	var fra = gs.nations["FRA"]
	var lacking := {}
	_check(Plan.wanted_law(gs, "FRA", lacking) == "civilian", "at peace the wanted law is civilian")
	Diplomacy_war("FRA", "GER")
	Plan.step(gs, "FRA")
	_check(fra.economy_law == "early_mobilization", "a nation at war takes early mobilization (%s)" % fra.economy_law)
	fra.mobilization = 0.6
	_strip("FRA", "arms")
	_strip("FRA", "artillery")
	Plan.step(gs, "FRA")
	_check(fra.economy_law == "early_mobilization", "but a law cannot be changed again at once (%s)" % fra.economy_law)
	fra.law_changed_day = -1000
	Plan.step(gs, "FRA")
	_check(fra.economy_law in ["war_economy", "total_mobilization"], "an army short of equipment calls for more (%s)" % fra.economy_law)
	fra.law_changed_day = -1000
	fra.war_support = 80.0
	Plan.step(gs, "FRA")
	_check(fra.economy_law == "total_mobilization", "with the people behind it, total mobilization (%s)" % fra.economy_law)
	gs.wars.clear()
	Plan.step(gs, "FRA")
	_check(fra.economy_law != "total_mobilization", "and in peace the law comes down (%s)" % fra.economy_law)


func Diplomacy_war(a: String, b: String) -> void:
	var D = load("res://scripts/sim/diplomacy.gd")
	D.start_war(gs, a, b, false)


func _test_value() -> void:
	_fresh()
	_strip("GER", "arms")
	var peace: float = Plan.factory_value(gs, "GER")
	_check(peace > 0.0, "a military factory is worth something to an army short of arms (%.1f)" % peace)
	Diplomacy_war("GER", "FRA")
	_check(Plan.factory_value(gs, "GER") > peace, "and more at war (%.1f)" % Plan.factory_value(gs, "GER"))


func _test_funding() -> void:
	_fresh()
	var fra = gs.nations["FRA"]
	_check(Plan.wanted_funding(gs, "FRA") == 1.0, "in peace the AI funds its forces at the usual")
	Diplomacy_war("FRA", "GER")
	fra.treasury = 10000.0
	fra.economy_law = "war_economy"
	_check(is_equal_approx(Plan.wanted_funding(gs, "FRA"), 1.2), "at war, rich, under a war economy it funds above the usual")
	fra.economy_law = "civilian"
	_check(Plan.wanted_funding(gs, "FRA") == 1.0, "but not past what its law allows")
	fra.economy_law = "war_economy"
	fra.treasury = -50.0
	_check(Plan.wanted_funding(gs, "FRA") == 1.0, "nor when the treasury cannot carry it")
	fra.treasury = 10000.0
	Plan._funding(gs, "FRA")
	_check(is_equal_approx(fra.army_funding, 1.2) and is_equal_approx(fra.navy_funding, 1.2), "and it sets both through the policy command")
