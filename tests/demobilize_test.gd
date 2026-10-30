extends SceneTree
## Headless test for step 3b: sending men home (the command and the AI), and the mobilization slider's cost line.
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
	_check(fra.budget.army < upkeep0, "and the army costs less at once (%.2f to %.2f gold a month)" % [upkeep0, fra.budget.army])
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

	# --- The cost of mobilizing, said before it is paid -------------------------------------------
	_fresh()
	ger = gs.nations["GER"]
	E.recompute(gs)
	var predicted: float = E.mobilization_cost(gs, ger, 0.4)
	var before_net: float = ger.budget.income
	gs.issue(Policy.new("GER", "mobilization", 0.4))
	for i in 12:
		E.step_month(gs)
	E.recompute(gs)
	var paid: float = before_net - ger.budget.income
	_check(predicted > 0.0 and absf(paid - predicted) <= 0.05 * predicted + 0.05, "mobilizing to 40%% costs the base income the slider says (%.2f said, %.2f lost a month)" % [predicted, paid])

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
