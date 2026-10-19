extends SceneTree
## Headless test for gifts: size scaling, diminishing returns, memory and the price.
## Run: godot --headless --path . -s res://tests/gift_test.gd

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
	var D = load("res://scripts/sim/diplomacy.gd")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("ESP")
	_check(D.cost_of("gift") == 10.0, "a gift costs 10 points")
	var big: float = D.gift_effect(gs, "FRA", "GER", 5.0)
	var small: float = D.gift_effect(gs, "FRA", "SRB", 5.0)
	_check(small > big, "the same money moves a small nation more (%.1f against %.1f)" % [small, big])
	var one: float = D.gift_effect(gs, "FRA", "SRB", 2.0)
	var two: float = D.gift_effect(gs, "FRA", "SRB", 4.0)
	_check(two < 2.0 * one and two > one, "bigger gifts have diminishing returns (%.1f for 2, %.1f for 4)" % [one, two])
	_check(D.gift_effect(gs, "FRA", "SRB", 10000.0) <= float(D.cfg.actions.gift_max_relation) + 0.001, "and never pass the cap")
	gs.nations["FRA"].treasury = 100.0
	var before: float = D.relation(gs, "SRB", "FRA")
	D.gift(gs, "FRA", "SRB", 4.0)
	var first: float = D.relation(gs, "SRB", "FRA") - before
	_check(first > 0.0, "a gift raises opinion (+%.1f)" % first)
	var again: float = D.gift_effect(gs, "FRA", "SRB", 4.0)
	_check(again < first * 0.5, "a second gift at once does far less (%.1f)" % again)
	for i in 12:
		D.step_month(gs)
	_check(D.gift_effect(gs, "FRA", "SRB", 4.0) > again * 2.0, "and the memory fades over a year (%.1f)" % D.gift_effect(gs, "FRA", "SRB", 4.0))
	# Prestige: cheaper justifications, a pull on treaty offers.
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	var n = gs.nations["GER"]
	n.prestige = 0.0
	var base: float = D.justify_cost(gs, "GER")
	n.prestige = 20.0
	var high: float = D.justify_cost(gs, "GER")
	n.prestige = 1000.0
	_check(high < base and D.justify_cost(gs, "GER") >= base * 0.6 - 0.001, "prestige cuts the price of a justification (%.0f to %.0f), up to 40%%" % [base, high])
	n.prestige = -20.0
	_check(D.justify_cost(gs, "GER") > base, "and a bad name raises it")
	n.prestige = 0.0
	var need: float = D.cfg.actions.treaty_accept.nap
	D.set_relation(gs, "NED", "GER", need - 5.0)
	var refused: bool = not D.treaty_acceptable(gs, "GER", "NED", "nap")
	n.prestige = 20.0
	_check(refused and D.treaty_acceptable(gs, "GER", "NED", "nap"), "prestige adds pull to a treaty offer")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
