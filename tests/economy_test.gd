extends SceneTree
## Headless test for the gold economy (docs/REWORK.md, R3; see Economy): starting buildings and incomes, where income
## comes from and what cuts it, the upkeep of the army and the buildings, construction points, the construction queue
## (paid when a project starts, fixed days, one project a province, ten of a kind, in order), policies, and saves.
## Run: godot --headless --path . -s res://tests/economy_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var clock: Node
var Eco
var Build
var Mass
var Prioritize
var Policy


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
	Eco = load("res://scripts/sim/economy.gd")
	Build = load("res://scripts/sim/construct_building.gd")
	Mass = load("res://scripts/sim/mass_construct_building.gd")
	Prioritize = load("res://scripts/sim/prioritize_construction.gd")
	Policy = load("res://scripts/sim/set_economy_policy.gd")

	_test_start()
	_test_income()
	_test_upkeep()
	_test_points()
	_test_queue()
	_test_mass()
	_test_policies()
	_test_month()
	_test_save()

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


## A quiet Europe: no wars, the AI off, the player in Spain.
func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.ai_enabled = false
	gs.join_calls.clear()
	gs.scenario["war_plans"] = []
	for w in gs.wars.values().duplicate():
		gs.set_war(w.a, w.b, false)
	gs.set_player("ESP")


## A province of `tag` with nothing under way and room for `type`, not the capital unless asked.
func _free(tag: String, type := "civilian_factory", capital := false) -> int:
	var n = gs.nations[tag]
	for id: int in n.provinces:
		var queued: bool = n.construction.any(func(j: Dictionary) -> bool: return j.province == id)
		if (capital or id != n.capital) and not queued and Eco.build_problem(gs, tag, id, type).is_empty() and not Eco.province_busy(n, id):
			return id
	return 0


func _test_start() -> void:
	_fresh()
	var targets := {"GER": 25.0, "GBR": 28.0, "FRA": 20.0, "RUS": 18.0, "AUH": 14.0, "ITA": 10.0}
	for tag: String in targets:
		var income: float = gs.nations[tag].budget.income
		_check(absf(income - targets[tag]) / targets[tag] < 0.1, "%s earns about %.0f gold a month (%.1f)" % [tag, targets[tag], income])
	var all_ok := true
	for tag: String in gs.nations:
		var n = gs.nations[tag]
		if n.provinces.is_empty():
			continue
		var lv: Dictionary = n.budget.levels
		all_ok = all_ok and int(lv.get("civilian_factory", 0)) >= 1 and int(lv.get("construction_sector", 0)) >= 1 and n.budget.income > 0.0
	_check(all_ok, "every nation starts with a civilian factory, a construction sector and an income")
	_check(gs.nations["GER"].budget.net > 0.0 and gs.nations["SRB"].budget.net > 0.0, "great and small start in surplus")
	var ger_cp: float = gs.nations["GER"].budget.cp
	_check(ger_cp >= 2.0 and ger_cp <= 4.5, "Germany makes a few construction points a day (%.2f)" % ger_cp)


func _test_income() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	var b: Dictionary = ger.budget
	var id: int = ger.provinces[0]
	_check(is_equal_approx(gs.province_base_income[id], 0.1 * pow(gs.province_pop_base[id] / 1e6, 0.8)), "a province's base income comes from its people")
	_check(is_equal_approx(b.factories, 1.5 * float(b.levels.civilian_factory)), "each civilian factory earns 1.5 gold")
	_check(is_equal_approx(b.income, b.base + b.factories + b.ports + b.occupied), "income is the sum of its parts")

	# Mobilization takes base income; blockade takes ports and a share of factories.
	ger.mobilization = 0.4
	Eco.recompute(gs)
	_check(is_equal_approx(ger.budget.base, b.base * (1.0 - 0.35 * 0.4)), "mobilization costs base income")
	_check(is_equal_approx(Eco.mobilization_cost(gs, ger, 0.4), b.base * 0.35 * 0.4), "and the slider says how much")
	ger.mobilization = 0.0
	ger.blockade = 1.0
	Eco.recompute(gs)
	_check(ger.budget.ports == 0.0 and is_equal_approx(ger.budget.factories, b.factories * 0.7), "a full blockade takes the ports and 30% of the factories")
	ger.blockade = 0.0

	# Occupation: the owner loses the province, the occupier gets half its base income.
	gs.set_war("FRA", "GER", true)
	var best := 0
	for p: int in ger.provinces:
		if p != ger.capital and int(gs.province_buildings[p].get("civilian_factory", 0)) > 0:
			best = p
			break
	var ger_raw: float = gs.economy_sums["GER"].base + gs.economy_sums["GER"].factories
	gs.set_controller(best, "FRA")
	Eco.recompute(gs)
	var ger_now: float = gs.economy_sums["GER"].base + gs.economy_sums["GER"].factories
	_check(is_equal_approx(ger_raw - ger_now, Eco.province_income(gs, best)), "Germany loses the income of a province France holds")
	_check(is_equal_approx(gs.economy_sums["FRA"].occupied, gs.province_base_income[best] * 0.5), "France takes half its base income")
	gs.set_war("FRA", "GER", false)


func _test_upkeep() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	var expected := 0.0
	for a in gs.armies.values():
		if a.tag == "GER":
			for u in a.units:
				expected += float(load("res://scripts/sim/military.gd").cfg.unit_types[u.type].upkeep)
	_check(expected > 0.0 and is_equal_approx(ger.budget.army, expected), "the army costs each unit's upkeep (%.2f)" % expected)
	var upkeep := 0.0
	for id: int in ger.provinces:
		for type: String in gs.province_buildings[id]:
			upkeep += float(Eco.cfg.buildings[type].get("upkeep", 0.0)) * gs.province_buildings[id][type]
	_check(is_equal_approx(ger.budget.buildings, upkeep), "the buildings cost their upkeep (%.2f)" % upkeep)
	_check(is_equal_approx(ger.budget.navy, ger.naval_budget / 12.0), "the navy a twelfth of its yearly cost")
	_check(is_equal_approx(ger.budget.expenses, ger.budget.army + ger.budget.navy + ger.budget.buildings + ger.budget.interest), "spending is the sum of its parts")
	ger.treasury = -120.0
	Eco.recompute(gs)
	_check(is_equal_approx(ger.budget.interest, 120.0 * 0.05 / 12.0), "a debt costs interest")


func _test_points() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	var sectors: float = float(ger.budget.levels.construction_sector)
	_check(is_equal_approx(ger.budget.cp, sectors + 0.25), "points a day: a point for each sector and a quarter from the capital")
	var cp0: float = ger.cp
	clock.advance_day()
	_check(is_equal_approx(ger.cp, cp0 + ger.budget.cp), "and they pile up day by day")
	# Without its sectors a nation still builds, slowly, from its capital.
	gs.set_war("FRA", "GER", true)
	for id: int in ger.provinces:
		if id != ger.capital and int(gs.province_buildings[id].get("construction_sector", 0)) > 0:
			gs.set_controller(id, "FRA")
	if int(gs.province_buildings[ger.capital].get("construction_sector", 0)) > 0:
		gs.province_buildings[ger.capital].erase("construction_sector")
	Eco.recompute(gs)
	_check(is_equal_approx(ger.budget.cp, 0.25), "a nation that has lost every sector still makes a quarter of a point a day")
	gs.set_war("FRA", "GER", false)


func _test_queue() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	var id := _free("GER")
	ger.treasury = 1000.0
	ger.cp = 1000.0
	var plan: Dictionary = Eco.build_plan(gs, id, "civilian_factory")
	_check(plan.gold == 60.0 and plan.cp == 240.0 and plan.days == 60, "a civilian factory costs 60 gold and 240 points and takes 60 days")
	var f0: int = gs.province_buildings[id].get("civilian_factory", 0)
	_check(gs.issue(Build.new("GER", id, "civilian_factory")), "a factory is queued")
	_check(ger.construction.size() == 1 and ger.construction[0].started and is_equal_approx(ger.treasury, 940.0) and is_equal_approx(ger.cp, 760.0), "and started at once, its gold and points paid")
	_check(gs.issue(Build.new("GER", id, "railway")) and not ger.construction[1].started, "a second project in the province waits")
	_check(Eco.province_busy(ger, id), "while the first is under way")
	for d in 59:
		clock.advance_day()
	_check(gs.province_buildings[id].get("civilian_factory", 0) == f0, "not finished after 59 days")
	clock.advance_day()
	_check(gs.province_buildings[id].get("civilian_factory", 0) == f0 + 1, "finished on the 60th day")
	_check(ger.construction.size() == 1 and ger.construction[0].started and ger.construction[0].type == "railway", "and the waiting railway starts")

	# At most ten of a kind in a province, the queued ones counted.
	var other := _free("GER")
	gs.province_buildings[other]["trench"] = 9
	_check(gs.issue(Build.new("GER", other, "trench")), "a tenth trench can be queued")
	_check(not gs.issue(Build.new("GER", other, "trench")) and Eco.build_problem(gs, "GER", other, "trench").begins_with("Fully built"), "an eleventh cannot")
	_check(not gs.issue(Build.new("GER", gs.nations["FRA"].provinces[0], "civilian_factory")), "nor can anything abroad")

	# The queue keeps its order: the first that cannot be paid for holds the rest.
	_fresh()
	ger = gs.nations["GER"]
	ger.treasury = 50.0
	ger.cp = 1000.0
	var a := _free("GER")
	gs.issue(Build.new("GER", a, "civilian_factory"))
	var c := _free("GER", "trench")
	gs.issue(Build.new("GER", c, "trench"))
	_check(not ger.construction[0].started and not ger.construction[1].started, "a factory it cannot pay for holds a cheap trench behind it")
	_check(gs.issue(Prioritize.new("GER", c, "trench")) and ger.construction[0].province == c, "until the trench is put first")
	clock.advance_day()
	_check(ger.construction[0].started and not ger.construction[1].started, "then it starts, and the factory waits for the gold")
	ger.treasury = 200.0
	clock.advance_day()
	_check(ger.construction[1].started, "and starts when the gold is there")

	# Ground lost: an occupied province waits, a ceded one is struck off.
	_fresh()
	ger = gs.nations["GER"]
	ger.treasury = 0.0
	var lost := _free("GER")
	gs.issue(Build.new("GER", lost, "civilian_factory"))
	gs.set_war("FRA", "GER", true)
	gs.set_controller(lost, "FRA")
	_check(Eco.build_problem(gs, "GER", lost, "trench") == "Province is occupied", "nothing new is queued in an occupied province")
	gs.set_war("FRA", "GER", false)
	gs.transfer_province(lost, "FRA")
	clock.advance_day()
	_check(ger.construction.is_empty(), "a project in a province ceded is lost")


func _test_mass() -> void:
	_fresh()
	var fra = gs.nations["FRA"]
	fra.treasury = 10000.0
	fra.cp = 100000.0
	var cands: Array = Eco.mass_candidates(gs, "FRA", "civilian_factory")
	_check(cands.size() > 5, "France has many places for a factory")
	var ok := true
	for i in cands.size() - 1:
		ok = ok and Eco.build_priority(gs, cands[i], "civilian_factory") >= Eco.build_priority(gs, cands[i + 1], "civilian_factory")
	_check(ok, "best first")
	var preview: Dictionary = Mass.new("FRA", "civilian_factory", 3, 0.0).preview(gs)
	_check(preview.count == 3 and fra.construction.is_empty() and is_equal_approx(fra.treasury, 10000.0), "a preview changes nothing")
	var capped = Mass.new("FRA", "civilian_factory", 1000, 150.0)
	_check(gs.issue(capped) and capped.built.size() == 2 and capped.stopped_by == "spend", "a gold limit stops it (two factories for 150 gold)")
	_check(not gs.issue(Mass.new("FRA", "bogus", 5, 0.0)) and not gs.issue(Mass.new("XXX", "civilian_factory", 5, 0.0)), "unknown building or nation rejected")


func _test_policies() -> void:
	_fresh()
	var fra = gs.nations["FRA"]
	_check(not gs.issue(Policy.new("FRA", "tax_rate", 0.2)) and not gs.issue(Policy.new("FRA", "investment", 1.0)) and not gs.issue(Policy.new("FRA", "arms_share", 0.2)), "taxes, investment and arms are gone")
	gs.issue(Policy.new("FRA", "mobilization", 1.0))
	_check(is_equal_approx(fra.mobilization, float(Eco.cfg.mobilization.peace_max)), "in peace mobilization stops at its ceiling")
	gs.issue(Policy.new("FRA", "standing_army", 1.0e9))
	_check(fra.peacetime_army == Eco.standing_cap(gs, fra), "the standing army stops at its cap")


func _test_month() -> void:
	_fresh()
	var ita = gs.nations["ITA"]
	var t0: float = ita.treasury
	var net: float = ita.budget.net
	while clock.day != 1:
		clock.advance_day()
	var t1: float = ita.treasury
	_check(absf(t1 - t0 - net) < 0.5, "a month pays the net into the treasury (%.2f, expected %.2f)" % [t1 - t0, net])
	var pop: int = ita.population
	for d in 40:
		clock.advance_day()
	_check(ita.population == pop, "the people do not grow")


func _test_save() -> void:
	_fresh()
	var SaveGame = load("res://scripts/sim/save_game.gd")
	SaveGame.dir = "user://test_economy_saves/"
	var srb = gs.nations["SRB"]
	srb.treasury = 0.0
	srb.cp = 123.0
	var id := _free("SRB", "civilian_factory", true)
	gs.issue(Build.new("SRB", id, "civilian_factory"))
	var path: String = SaveGame.dir + "economy.sav"
	_check(gs.save_game(path) == "", "a game with a queue saves")
	_fresh()
	_check(gs.load_game(path) == "" and gs.nations["SRB"].construction.size() == 1 and is_equal_approx(gs.nations["SRB"].cp, 123.0), "and loads with its queue and its points")
	_check(gs.nations["SRB"].budget.income > 0.0 and gs.province_base_income[id] > 0.0, "and its incomes worked out again")
	DirAccess.remove_absolute(path)
