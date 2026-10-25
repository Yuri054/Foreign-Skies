extends SceneTree
## Headless test for AI peace: the urge for peace, who asks for what, what is accepted and
## refused, and that no AI peace is worse than fighting on.
## Run: godot --headless --path . -s res://tests/ai_peace_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var clock: Node
var P
var AP
var A
var D


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
	gs.ai_enabled = false
	P = load("res://scripts/sim/peace.gd")
	AP = load("res://scripts/ai/ai_peace.gd")
	A = load("res://scripts/ai/ai.gd")
	D = load("res://scripts/sim/diplomacy.gd")

	_test_urge()
	_test_winner_names_price()
	_test_loser_concedes()
	_test_exhausted_asks()
	_test_affordability()
	_test_never_worse()
	_test_allies()

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _war() -> Object:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.scenario["war_plans"] = []
	gs.wars.clear()
	gs.armies.clear()
	gs.ai_plans.clear()
	gs.set_player("ESP")
	gs.set_war("FRA", "GER", true)
	return gs.war_between("FRA", "GER")


func _occupy(owner: String, by: String, count: int) -> Array:
	var ids: Array = []
	for id: int in gs.nations[owner].provinces:
		if ids.size() >= count:
			break
		if id != gs.nations[owner].capital:
			gs.set_controller(id, by)
			ids.append(id)
	return ids


func _offer(from: String, to: String, mode: String, demands: Array, cost := 0.0, forced := false) -> Dictionary:
	return {"from": from, "to": to, "mode": mode, "demands": demands, "cost": cost, "forced": forced}


func _test_urge() -> void:
	var war = _war()
	var level: float = AP.urge(gs, "GER", war)
	_check(absf(level) < 5.0, "in a level young war the urge for peace is about nothing (%.1f)" % level)
	_occupy("GER", "FRA", 60)
	_check(AP.urge(gs, "GER", war) > level + 10.0 and AP.urge(gs, "FRA", war) < level - 10.0, "the loser wants peace more, the winner less")
	war = _war()
	var base: float = AP.urge(gs, "FRA", war)
	gs.nations["FRA"].war_support = 20.0
	_check(AP.urge(gs, "FRA", war) > base + 50.0, "a nation whose war support has collapsed wants peace")
	gs.nations["FRA"].war_support = 65.0
	gs.nations["FRA"].treasury = -200.0
	_check(AP.urge(gs, "FRA", war) > base + 10.0, "so does one deep in debt")
	gs.nations["FRA"].treasury = 20.0
	var before: float = AP.urge(gs, "FRA", war)
	clock.days_elapsed += 960
	_check(AP.urge(gs, "FRA", war) > before + 25.0, "and one worn down by months of war")
	war = _war()
	gs.set_controller(gs.nations["FRA"].capital, "GER")
	_check(AP.urge(gs, "FRA", war) > 35.0, "losing the capital adds to it")


func _test_winner_names_price() -> void:
	var war = _war()
	var ids := _occupy("GER", "FRA", 60)
	var p: Dictionary = AP.proposal(gs, "FRA", war)
	_check(p.get("mode", "") == "demand" and not p.demands.is_empty() and p.demands[0].kind == "province", "a winning AI asks for provinces")
	var check: Dictionary = P.check(gs, "FRA", "GER", "demand", p.demands)
	_check(check.ok, "that it can price: the terms fit its war score (%.1f of %.1f)" % [check.cost, P.war_score(gs, war, "FRA")])
	var all_held := true
	for id: int in p.demands[0].ids:
		all_held = all_held and gs.province_controller[id] == "FRA" and gs.province_owner[id] == "GER"
	_check(all_held, "it asks only for ground it holds")
	# War aims come first.
	var aim: int = ids[ids.size() - 1]
	gs.ai_plans.append({"nation": "FRA", "enemy": "GER", "posture": "offensive", "objectives": [{"province": aim, "weight": 5.0}]})
	var terms: Array = AP.price_terms(gs, "FRA", "GER", war)
	_check(terms[0].ids[0] == aim, "the provinces it set out to take come first")
	_check(AP.aims_met(gs, "FRA", "GER") == 1.0, "and its war aims are met")
	# Aims not met: it keeps fighting although it is ahead.
	gs.ai_plans.clear()
	var far := 0
	for id: int in gs.nations["GER"].provinces:
		if gs.province_controller[id] == "GER":
			far = id
			break
	gs.ai_plans.append({"nation": "FRA", "enemy": "GER", "posture": "offensive", "objectives": [{"province": far, "weight": 5.0}]})
	_check(AP.aims_met(gs, "FRA", "GER") == 0.0 and AP.proposal(gs, "FRA", war).is_empty(), "with its aims unmet it does not ask for peace while it is ahead")
	# The proposal goes through the real month step.
	gs.ai_plans.clear()
	P.step_month(gs)
	_check(not gs.at_war("FRA", "GER") and war.peace.taker == "FRA" and not war.peace.white, "and the loser accepts it")


func _test_loser_concedes() -> void:
	var war = _war()
	var held := _occupy("GER", "FRA", 200)
	var p: Dictionary = AP.proposal(gs, "GER", war)
	_check(p.get("mode", "") == "offer" and not p.demands.is_empty() and p.demands[0].kind == "province", "a badly losing AI offers ground")
	var cost := 0.0
	for d in p.demands:
		cost += P.demand_cost(gs, "FRA", "GER", d)
	_check(cost <= P.war_score(gs, war, "FRA"), "within what the winner's score pays for (%.1f)" % cost)
	var all_held := true
	for id: int in p.demands[0].ids:
		all_held = all_held and id in held
	_check(all_held, "all of it ground the enemy already holds")
	_check(AP.accepts(gs, _offer("GER", "FRA", "offer", p.demands, cost)), "and the winner takes it")
	var token := _offer("GER", "FRA", "offer", [{"kind": "province", "ids": [p.demands[0].ids[0]]}], 0.5)
	_check(not AP.accepts(gs, token), "but not a token of it")


func _test_exhausted_asks() -> void:
	var war = _war()
	_check(AP.proposal(gs, "GER", war).is_empty(), "a fresh level war brings no proposal")
	gs.nations["GER"].war_support = 15.0
	var p: Dictionary = AP.proposal(gs, "GER", war)
	_check(not p.is_empty() and p.demands.is_empty(), "an exhausted nation asks for a white peace")
	_check(AP.accepts(gs, _offer("GER", "FRA", "demand", [])), "which the other side takes while it is not clearly winning")
	war = _war()
	_occupy("GER", "FRA", 80)
	_check(not AP.accepts(gs, _offer("GER", "FRA", "demand", [])), "but a clear winner refuses it")


func _test_affordability() -> void:
	var war = _war()
	_occupy("GER", "FRA", 200)
	var heavy: Array = [{"kind": "indemnity", "share": 0.45, "months": 12}]
	_check(not AP.accepts(gs, _offer("FRA", "GER", "demand", heavy, 5.0)), "a nation refuses an indemnity it cannot carry")
	var light: Array = [{"kind": "indemnity", "share": 0.1, "months": 12}]
	_check(AP.accepts(gs, _offer("FRA", "GER", "demand", light, 2.0)), "but takes a lighter one when it is losing")
	gs.indemnities.append({"payer": "GER", "receiver": "FRA", "monthly": gs.nations["GER"].budget.revenue / 12.0 * 0.35, "months_left": 10})
	_check(not AP.accepts(gs, _offer("FRA", "GER", "demand", light, 2.0)), "and refuses it on top of what it already pays")


## No AI peace is worse than fighting on: whatever it accepts costs no more than its urge for
## peace, and a white peace is not taken by a nation clearly winning.
func _test_never_worse() -> void:
	var accepted := 0
	var refused := 0
	var bad := 0
	for count in [-120, -30, 0, 10, 30, 60, 120]:
		for support in [70.0, 40.0, 20.0]:
			for days in [0, 200, 400]:
				var war = _war()
				if count >= 0:
					_occupy("GER", "FRA", count)
				else:
					_occupy("FRA", "GER", -count)
				gs.nations["GER"].war_support = support
				clock.days_elapsed += days
				var u: float = AP.urge(gs, "GER", war)
				var demands: Array = AP.price_terms(gs, "FRA", "GER", war)
				var everything: Array = []
				var held: Array = []
				for id: int in gs.nations["GER"].provinces:
					if gs.province_controller[id] == "FRA":
						held.append(id)
				if not held.is_empty():
					everything.append({"kind": "province", "ids": held})
				for d in [[], demands, everything]:
					var cost := 0.0
					for t in d:
						cost += maxf(0.0, P.demand_cost(gs, "FRA", "GER", t))
					if AP.accepts(gs, _offer("FRA", "GER", "demand", d, cost)):
						accepted += 1
						if d.is_empty():
							if u < -20.0:
								bad += 1
						elif cost > u + 0.0001:
							bad += 1
					else:
						refused += 1
	_check(accepted > 0 and refused > 0, "the sweep covers both answers (%d taken, %d refused)" % [accepted, refused])
	_check(bad == 0, "no accepted deal costs more than the nation's urge for peace (%d bad)" % bad)


func _test_allies() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.set_player("ESP")
	gs.nations["GER"].mobilization = 0.5
	gs.issue(load("res://scripts/sim/declare_war.gd").new("GER", "BEL", "none"))
	for i in 80:
		if gs.join_calls.is_empty():
			break
		clock.advance_day()
	var war = gs.war_between("RUS", "GER")
	_check(war != null and AP.allies_fighting(gs, "RUS", "GER") >= 1, "Russia has allies still fighting Germany")
	var with_allies: float = AP.urge(gs, "RUS", war)
	var saved: float = A.cfg.peace.k_ally
	A.cfg.peace.k_ally = 0.0
	var without: float = AP.urge(gs, "RUS", war)
	A.cfg.peace.k_ally = saved
	_check(with_allies < without, "allies still fighting weigh against a separate peace (%.1f against %.1f)" % [with_allies, without])
	gs.ai_traits["RUS"] = {"aggression": 1.0, "caution": 0.0}
	var bold: float = AP.urge(gs, "RUS", war)
	gs.ai_traits["RUS"] = {"aggression": 0.0, "caution": 1.0}
	var careful: float = AP.urge(gs, "RUS", war)
	gs.ai_traits.clear()
	_check(bold > careful, "a bold nation is less held back by it than a cautious one (%.1f against %.1f)" % [bold, careful])
	var fra_rus: float = D.relation(gs, "RUS", "FRA")
	P.propose(gs, "RUS", "GER", "demand", [])
	_check(D.relation(gs, "RUS", "FRA") < fra_rus, "and a separate peace does cost that trust")
