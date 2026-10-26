extends SceneTree
## Headless test for step 3b: sending men home (the command and the AI), taxes that cost evenly above the default and help
## below it, civil spending that follows the output, state investment, and the mobilization slider's cost line.
## Run: godot --headless --path . -s res://tests/demobilize_test.gd

var _failures := 0
var gs: Node
var clock: Node
var E
var Mil
var UnitC


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _fresh() -> void:
	gs.load_scenario("res://data/scenarios/jan_1900/")
	gs.join_calls.clear()
	gs.wars.clear()
	gs.set_player("ESP")
	gs.ai_enabled = false


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	E = load("res://scripts/sim/economy.gd")
	Mil = load("res://scripts/sim/military.gd")
	UnitC = load("res://scripts/sim/unit.gd")
	var Demob = load("res://scripts/sim/demobilize_units.gd")
	var Policy = load("res://scripts/sim/set_economy_policy.gd")
	var AF = load("res://scripts/ai/ai_forces.gd")
	var AB = load("res://scripts/ai/ai_budget.gd")
	var A = load("res://scripts/ai/ai.gd")

	# --- Sending men home -----------------------------------------------------------------------
	_fresh()
	var fra = gs.nations["FRA"]
	var army = Mil.new_army(gs, "FRA", "Big army", fra.capital)
	for i in 20:
		army.units.append(UnitC.new("infantry"))
	for i in 5:
		army.units.append(UnitC.new("artillery"))
	Mil.refresh_men(gs)
	E.recompute(gs)
	var men0: int = fra.men_in_units
	var upkeep0: float = fra.budget.army
	var reserve0: int = fra.manpower
	var cmd = Demob.new("FRA", army.id, 3)
	_check(gs.issue(cmd) and cmd.sent == 3, "France sends three units home")
	_check(fra.men_in_units == men0 - 36000 and fra.manpower == reserve0 + 36000, "their men leave the army for the reserve (%d)" % (men0 - fra.men_in_units))
	E.recompute(gs)
	_check(fra.budget.army < upkeep0, "and the army costs less at once (£%.2fM to £%.2fM a year)" % [upkeep0, fra.budget.army])
	_check(army.units.filter(func(u) -> bool: return u.type == "artillery").size() == 5, "the guns go last")
	cmd = Demob.new("FRA", 0, -1)
	_check(gs.issue(cmd) and fra.men_in_units <= fra.peacetime_army + 12000, "'to peacetime' sends home all above the peacetime army (%dk left, %dk peacetime)" % [fra.men_in_units / 1000, fra.peacetime_army / 1000])
	E.step_month(gs)
	_check(fra.manpower <= int(fra.budget.manpower_max) - fra.men_in_units + 1, "and the reserve past what mobilization keeps goes back to the people at the month's end")
	gs.set_war("FRA", "GER", true)
	_check(not gs.issue(Demob.new("FRA", 0, 1)), "no one is sent home in a war")

	# The AI sends men home some time after a war, when at ease.
	_fresh()
	var ger = gs.nations["GER"]
	army = Mil.new_army(gs, "GER", "War army", ger.capital)
	for i in 60:
		army.units.append(UnitC.new("infantry"))
	Mil.refresh_men(gs)
	gs.set_war("GER", "DEN", true)
	gs.set_war("GER", "DEN", false)
	var big: int = ger.men_in_units
	AF.demobilize(gs, "GER")
	_check(ger.men_in_units == big, "not straight after a peace")
	clock.days_elapsed += int(A.cfg.forces.demob_after_days) + 1
	AF.demobilize(gs, "GER")
	_check(ger.men_in_units < big, "but some months on it sends a share of the excess home (%dk to %dk)" % [big / 1000, ger.men_in_units / 1000])
	for i in 30:
		AF.demobilize(gs, "GER")
	_check(ger.men_in_units <= ger.peacetime_army * float(A.cfg.forces.demob_margin) + 12000, "down to about its peacetime army")
	ger.mobilization = 0.5
	var before: int = ger.men_in_units
	army.units.append(UnitC.new("infantry"))
	army.units.append(UnitC.new("infantry"))
	Mil.refresh_men(gs)
	before = ger.men_in_units
	AF.demobilize(gs, "GER")
	_check(ger.men_in_units == before, "and keeps its men while mobilized")

	# A nation gone from the map stands down, and so do the neighbours its mobilization held up.
	_fresh()
	var D = load("res://scripts/sim/diplomacy.gd")
	var mne = gs.nations["MNE"]
	mne.mobilization = 0.4
	D.step_day(gs)
	_check(not gs.alarms.keys().filter(func(k: String) -> bool: return k.begins_with("MNE>")).is_empty(), "Montenegro mobilized alarms its neighbours")
	for id: int in mne.provinces.duplicate():
		gs.transfer_province(id, "AUH")
	D.step_day(gs)
	_check(mne.mobilization == 0.0 and gs.alarms.keys().filter(func(k: String) -> bool: return k.begins_with("MNE>")).is_empty(), "gone from the map, it stands down and its alarms lapse")
	_check(gs.mobilization_calls.values().filter(func(c: Dictionary) -> bool: return c.against == "MNE").is_empty(), "and nobody is called up against it")

	# --- Taxes ------------------------------------------------------------------------------------
	_fresh()
	var ita = gs.nations["ITA"]
	var g10: float = E.growth_rate(ita)
	gs.issue(Policy.new("ITA", "tax_rate", 0.05))
	_check(E.growth_rate(ita) > g10 + 0.004, "a tax under the default spurs growth (%.2f%% to %.2f%% a year)" % [g10 * 100.0, E.growth_rate(ita) * 100.0])
	gs.issue(Policy.new("ITA", "tax_rate", 0.15))
	var g15: float = E.growth_rate(ita)
	gs.issue(Policy.new("ITA", "tax_rate", 0.2))
	var g20: float = E.growth_rate(ita)
	_check(g15 < g10 and absf((g10 - g20) - 2.0 * (g10 - g15)) < 0.0001, "above it the cost rises evenly: 15%% costs %.2f points, 20%% twice that" % [(g10 - g15) * 100.0])
	_check((g10 - g20) * 100.0 >= 0.9, "and a 20%% tax costs a real point of growth (%.2f)" % ((g10 - g20) * 100.0))

	# --- Civil spending follows the output ----------------------------------------------------------
	_fresh()
	ger = gs.nations["GER"]
	E.recompute(gs)
	var civil0: float = ger.budget.civil
	ger.mobilization = 0.4
	E.recompute(gs)
	_check(ger.budget.civil < civil0 * 0.9, "a mobilized state spends less on itself, as its output falls (£%.1fM to £%.1fM)" % [civil0, ger.budget.civil])
	ger.mobilization = 0.0

	# --- Investment --------------------------------------------------------------------------------
	_fresh()
	ita = gs.nations["ITA"]
	E.recompute(gs)
	var net0: float = ita.budget.net
	_check(gs.issue(Policy.new("ITA", "investment", 1.0)) and is_equal_approx(ita.investment, 1.0), "Italy invests £1M a month")
	E.recompute(gs)
	_check(absf((net0 - ita.budget.net) - 12.0) < 0.01, "which is spent like any cost")
	var g1: float = E.investment_growth(ita)
	gs.issue(Policy.new("ITA", "investment", 2.0))
	var g2: float = E.investment_growth(ita)
	_check(g1 > 0.0 and g2 > g1 and g2 < 2.0 * g1, "and adds growth, each further pound a little less (%.2f, %.2f points)" % [g1 * 100.0, g2 * 100.0])
	gs.issue(Policy.new("ITA", "investment", 1.0e6))
	_check(ita.investment <= ita.budget.gdp / 12.0 * 0.1 + 0.001, "at most a tenth of the month's output")
	var rich = gs.nations["GBR"]
	rich.treasury = 500.0
	rich.budget["net"] = 60.0
	_check(AB.wanted_investment(gs, "GBR") > 0.0, "a rich AI nation in surplus invests")
	rich.tax_rate = 0.1
	_check(AB.wanted_tax(gs, "GBR") < 0.1, "and eases its taxes under the default")

	# --- The cost of mobilizing, said before it is paid -------------------------------------------
	_fresh()
	ger = gs.nations["GER"]
	E.recompute(gs)
	var predicted: float = E.mobilization_cost(gs, ger, 0.4)
	var before_net: float = ger.budget.net / 12.0
	gs.issue(Policy.new("GER", "mobilization", 0.4))
	for i in 12:
		E.step_month(gs)
	E.recompute(gs)
	var paid: float = before_net - ger.budget.net / 12.0
	_check(predicted > 0.0 and absf(paid - predicted) <= 0.05 * predicted + 0.05, "mobilizing to 40%% costs what the slider says once the reserve is in (£%.2fM said, £%.2fM paid a month)" % [predicted, paid])

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
