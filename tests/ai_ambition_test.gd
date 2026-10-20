extends SceneTree
## Headless test for the late-game AI: ambitions (target, plan, mobilization, dropping), peacetime
## rebuilding, repeatable foci, and a long run that keeps going after the opening war.
## Run: godot --headless --path . -s res://tests/ai_ambition_test.gd

var _failures := 0
var gs: Node
var clock: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("ESP")
	gs.ai_enabled = false
	gs.wars.clear()


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	var Amb = load("res://scripts/ai/ai_ambition.gd")
	var Forces = load("res://scripts/ai/ai_forces.gd")
	var D = load("res://scripts/sim/diplomacy.gd")
	var Mil = load("res://scripts/sim/military.gd")
	var UnitC = load("res://scripts/sim/unit.gd")
	var ai_cfg: Dictionary = load("res://scripts/ai/ai.gd").cfg

	# Nothing before the start delay.
	_fresh()
	gs.armies.clear()
	var a = Mil.new_army(gs, "FRA", "Big", gs.nations["FRA"].provinces[0])
	for i in 80:
		a.units.append(UnitC.new("infantry"))
	gs.ai_traits["FRA"] = {"aggression": 0.8, "caution": 0.3}
	for t in ["BEL", "NED", "LUX", "SUI", "GBR", "ITA", "ESP", "GER"]:
		var b = Mil.new_army(gs, t, "Small", gs.nations[t].provinces[0])
		b.units.append(UnitC.new("infantry"))
	Amb.step(gs, "FRA")
	_check(gs.ai_ambition.is_empty(), "no ambition in the first year")

	# After it: a strong, aggressive nation picks a weak neighbour.
	clock.days_elapsed = int(ai_cfg.ambition.start_delay_days) + 5
	for tr in gs.treaties.duplicate():
		if tr.kind == "nap":
			tr.end_day = 0
	var best: Dictionary = Amb.best_target(gs, "FRA")
	_check(not best.is_empty() and best.score >= float(ai_cfg.ambition.threshold), "France finds a neighbour worth fighting (%s, score %.2f)" % [best.get("target", "-"), best.get("score", 0.0)])
	for d in 95:
		clock.days_elapsed += 1
		Amb.step(gs, "FRA")
		if gs.ai_ambition.has("FRA"):
			break
	_check(gs.ai_ambition.has("FRA"), "and takes it up as an ambition")
	var target: String = gs.ai_ambition.get("FRA", {}).get("target", "")
	var planned := false
	for plan in gs.ai_plans:
		planned = planned or (plan.nation == "FRA" and plan.enemy == target and plan.get("dynamic", false) and not plan.objectives.is_empty())
	_check(planned, "with a plan whose objectives lie in %s" % target)
	_check(D.mobilization_target(gs, "FRA") >= float(ai_cfg.ambition.mobilization), "and a mobilization target of %.2f" % D.mobilization_target(gs, "FRA"))
	# It ends when the war comes, and the plan goes with it.
	gs.set_war("FRA", target, true)
	Amb.step(gs, "FRA")
	_check(not gs.ai_ambition.has("FRA") and gs.ai_ambition_wait.has("FRA"), "a war ends the ambition and starts the wait")
	var left := 0
	for plan in gs.ai_plans:
		if plan.nation == "FRA" and plan.get("dynamic", false):
			left += 1
	_check(left == 0, "and the plan is removed")

	# A weak, timid nation has none.
	_fresh()
	clock.days_elapsed = int(ai_cfg.ambition.start_delay_days) + 5
	gs.ai_traits["BEL"] = {"aggression": 0.1, "caution": 0.9}
	_check(Amb.best_target(gs, "BEL").is_empty(), "a timid nation wants nothing")

	# Peacetime rebuilding.
	_fresh()
	gs.armies.clear()
	var n = gs.nations["GER"]
	n.treasury = 500.0
	n.manpower = 500000
	var before: int = Mil.men_in_service(gs, "GER")
	Forces.rebuild(gs, "GER")
	_check(Mil.men_in_service(gs, "GER") > before, "a nation far under its peacetime army raises troops (%d to %d)" % [before, Mil.men_in_service(gs, "GER")])
	_fresh()
	var full: int = Mil.men_in_service(gs, "FRA")
	Forces.rebuild(gs, "FRA")
	_check(Mil.men_in_service(gs, "FRA") == full, "one at its strength does not")

	# Repeatable foci come back until their limit.
	_fresh()
	var F = load("res://scripts/sim/focus.gd")
	var Set = load("res://scripts/sim/set_focus.gd")
	var nn = gs.nations["DEN"]
	var gdp: float = nn.focus_fx.get("gdp", 0.0)
	for i in 3:
		gs.issue(Set.new("DEN", "local_investment"))
		nn.focus.days_left = 1
		clock.advance_day()
	_check(nn.focus_count.get("local_investment", 0) == 3 and F.block(gs, "DEN", "local_investment") == "", "a repeatable focus can be taken again (%d times)" % nn.focus_count.get("local_investment", 0))
	_check(absf(nn.focus_fx.gdp - 0.03) < 0.0001, "and its effect adds up (+%.0f%%)" % (nn.focus_fx.gdp * 100.0))
	for i in 3:
		gs.issue(Set.new("DEN", "local_investment"))
		nn.focus.days_left = 1
		clock.advance_day()
	_check(F.block(gs, "DEN", "local_investment") == "done", "until its limit")

	# A long run: wars, treaties and foci go on past the opening.
	_fresh()
	clock.days_elapsed = 0
	gs.ai_enabled = true
	var late := {"wars": 0, "treaties": 0}
	gs.war_changed.connect(func(_a: String, _b: String, on: bool) -> void:
		if on and clock.days_elapsed > 400:
			late.wars += 1
	)
	gs.treaty_changed.connect(func(_t: Treaty, added: bool) -> void:
		if added and clock.days_elapsed > 400:
			late.treaties += 1
	)
	for i in 365 * 3:
		clock.advance_day()
	_check(late.wars > 0, "wars go on after the first year (%d begun)" % late.wars)
	_check(late.treaties > 0, "so do treaties (%d signed)" % late.treaties)
	var empty := 0
	for tag in gs.nations:
		empty += 1 if gs.nations[tag].provinces.is_empty() else 0
	_check(empty <= 1, "no wave of nations wiped out (%d gone)" % empty)
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
