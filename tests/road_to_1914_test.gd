extends SceneTree
## Headless test for the road to 1914: the war gate a scenario sets and how it falls with the years, the 1900 nations'
## temperaments, old rivalries as a floor under grievance that fades, the cost of a war with no reason on a nation that
## stands apart, and crises opened only on the odds of the two sides.
## Run: godot --headless --path . -s res://tests/road_to_1914_test.gd

var _failures := 0
var gs: Node
var clock: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _fresh(dir := "res://data/scenarios/jan_1900/") -> void:
	gs.load_scenario(dir)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.set_player("ESP")
	gs.ai_enabled = false


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	var Pr = load("res://scripts/sim/pressure.gd")
	var D = load("res://scripts/sim/diplomacy.gd")
	var C = load("res://scripts/sim/crisis.gd")
	var A = load("res://scripts/ai/ai.gd")

	# --- The war gate ----------------------------------------------------------------------------
	_fresh()
	var g: Dictionary = gs.scenario.ai_war_gate
	_check(is_equal_approx(Pr.war_gate(gs), float(g.start)), "in 1900 the AI needs tension %d to start a war of its own" % int(Pr.war_gate(gs)))
	clock.year = int(g.to)
	_check(is_equal_approx(Pr.war_gate(gs), float(g.end)), "by %d it needs %d" % [int(g.to), int(g.end)])
	clock.year = int((float(g.from) + float(g.to)) / 2.0)
	_check(Pr.war_gate(gs) < float(g.start) and Pr.war_gate(gs) > float(g.end), "and in between something between (%.1f)" % Pr.war_gate(gs))
	clock.year = 1900
	gs.tension = float(g.start) - 1.0
	_check(not Pr.ai_may_declare(gs), "a 1900 Europe at tension %d is too calm for the AI to choose war" % int(gs.tension))
	gs.tension = float(g.start) + 1.0
	_check(Pr.ai_may_declare(gs), "and at %d it may" % int(gs.tension))
	_fresh("res://data/scenarios/july_1914/")
	_check(is_equal_approx(Pr.war_gate(gs), float(Pr.cfg.ai_war_gate)), "the July 1914 start keeps the general gate (%d)" % int(Pr.war_gate(gs)))

	# --- Temperaments and old quarrels -------------------------------------------------------------
	_fresh()
	_check(float(A.base_temperament(gs, "SRB").aggression) > float(A.base_temperament(gs, "SUI").aggression) + 0.3, "1900 Serbia is far bolder than Switzerland")
	_check(float(A.base_temperament(gs, "NED").aggression) < float(A.cfg.ambition.min_aggression), "a neutral like the Netherlands forms no ambitions")
	_check(gs.relations.has(D.pair_key("FRA", "GER")) and D.relation(gs, "FRA", "GER") < -20.0, "France and Germany start hostile in 1900 (%.0f)" % D.relation(gs, "FRA", "GER"))
	var floor: float = gs.rivalries.get("FRA>GER", 0.0)
	_check(floor > 0.0 and is_equal_approx(D.grievance(gs, "FRA", "GER"), floor), "France resents Germany from the start (%.0f)" % floor)
	gs.grievance["FRA>GER"] = floor + 20.0
	_check(is_equal_approx(D.grievance(gs, "FRA", "GER"), floor + 20.0), "a fresh grievance on top counts in full")
	for i in 24:
		D._step_grievance(gs)
	_check(D.grievance(gs, "FRA", "GER") >= gs.rivalries.get("FRA>GER", 0.0) - 0.001 and gs.rivalries.get("FRA>GER", 0.0) < floor, "it cools to the rivalry, and the rivalry itself fades (%.1f after two years)" % gs.rivalries.get("FRA>GER", 0.0))

	gs.relations[D.pair_key("RUS", "AUH")] = 90.0
	_check(not D.treaty_acceptable(gs, "RUS", "AUH", "nap") and not D.treaty_acceptable(gs, "AUH", "RUS", "nap"), "old rivals sign no pact, however friendly they grow")
	_check(not D.treaty_acceptable(gs, "RUS", "AUH", "alliance"), "and no alliance")
	gs.relations[D.pair_key("RUS", "GBR")] = 90.0
	_check(D.treaty_acceptable(gs, "RUS", "GBR", "nap"), "while nations with no old quarrel may")

	# --- Nations that stand apart -------------------------------------------------------------------
	_fresh()
	_check(D.is_neutral(gs, "SUI") and D.is_neutral(gs, "NED"), "Switzerland and the Netherlands stand apart")
	_check(not D.is_neutral(gs, "GER") and not D.is_neutral(gs, "POR"), "Germany (a bloc) and Portugal (Britain's ally) do not")
	gs.nations["NED"].mobilization = 0.5
	_check(not D.is_neutral(gs, "NED"), "nor does a nation that mobilizes")
	gs.nations["NED"].mobilization = 0.0
	gs.nations["GER"].mobilization = 1.0
	gs.nations["GER"].diplomacy_points = 200.0
	var prestige: float = gs.nations["GER"].prestige
	var british: float = D.relation(gs, "GBR", "GER")
	var impulse: float = gs.tension_impulse
	_check(D.declare_war(gs, "GER", "NED", "none"), "Germany attacks the Netherlands with no reason")
	var none_rules: Dictionary = D.cfg.war.casus_belli.none
	var v: Dictionary = D.cfg.war.neutral_violation
	_check(gs.nations["GER"].prestige < prestige + float(none_rules.prestige) - 1.0, "it loses more standing than any war with no reason costs (%.1f)" % (gs.nations["GER"].prestige - prestige))
	_check(D.relation(gs, "GBR", "GER") <= british + float(none_rules.world_relations) + float(v.world_relations) + 0.5, "the world thinks still less of it (Britain %.0f to %.0f)" % [british, D.relation(gs, "GBR", "GER")])
	_check(gs.tension_impulse >= impulse + float(v.tension) - 0.001, "and Europe grows tenser")

	# --- Crises on the odds of the sides ------------------------------------------------------------
	_fresh()
	gs.tension = 60.0
	var draft := {"a": "SRB", "b": "AUH", "backers_a": [], "backers_b": []}
	var odds: float = C.odds_a(gs, draft)
	_check(odds < float(C.cfg.gate.min_odds) and not C.may_quarrel(gs, "SRB", "AUH"), "Serbia, weaker than Austria-Hungary and its allies, cannot open a crisis against it (%.2f)" % odds)
	var back := {"a": "AUH", "b": "SRB", "backers_a": [], "backers_b": []}
	_check(C.odds_a(gs, back) >= float(C.cfg.gate.min_odds) == C.may_quarrel(gs, "AUH", "SRB") or gs.crisis_cooldown.has(D.pair_key("AUH", "SRB")), "while the stronger side may, by the same measure")

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
