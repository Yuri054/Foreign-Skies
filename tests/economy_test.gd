extends SceneTree
## Headless test for the economy: money, industry and manpower (see Economy).
## Run: godot --headless --path . -s res://tests/economy_test.gd
## Class names (Economy, SetEconomyPolicy) are loaded at runtime because this script
## compiles before the autoloads exist.

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
	gs.ai_enabled = false  # these tests are about other systems; the AI has its own
	var clock: Node = root.get_node("Clock")
	var Eco = load("res://scripts/sim/economy.gd")
	var Policy = load("res://scripts/sim/set_economy_policy.gd")

	# ---- Starting budgets: sane, balanced, near the 1914 revenues ----
	var targets := {"GBR": 198.0, "FRA": 200.0, "GER": 280.0, "ITA": 100.0, "AUH": 150.0}
	for tag in gs.nations:
		var b: Dictionary = gs.nations[tag].budget
		_check(b.gdp > 0.0 and b.revenue > 0.0 and b.manpower_max > 0.0 and b.construction_points > 0.0, "%s: positive output, revenue, manpower and construction points" % tag)
		var surplus: float = float(b.revenue) * float(Eco.cfg.start_surplus)
		_check(absf(b.net - surplus) < 0.05 + surplus * 0.02, "%s starts with a small surplus to spend (net %.2f a year, %d%% of revenue)" % [tag, b.net, roundi(b.net / b.revenue * 100.0)])
		_check(b.materials.ratio >= 0.999, "%s starts with the raw materials its industry needs" % tag)
	for tag in targets:
		var rev: float = gs.nations[tag].budget.revenue
		_check(absf(rev - targets[tag]) / targets[tag] < 0.06, "%s revenue %.0f is within 6%% of %.0f" % [tag, rev, targets[tag]])
	_check(gs.nations["GBR"].budget.food_shortage == 0.0 and gs.nations["GBR"].budget.food_imported > 0.0, "Britain imports its food and does not starve")

	# ---- Policy commands: clamping, rejection and the log ----
	var fra = gs.nations["FRA"]
	var base_rev: float = fra.budget.revenue
	_check(gs.issue(Policy.new("FRA", "tax_rate", 0.2)), "tax command accepted")
	_check(fra.budget.revenue > base_rev, "higher tax raises revenue")
	gs.issue(Policy.new("FRA", "tax_rate", 5.0))
	_check(is_equal_approx(fra.tax_rate, Eco.cfg.max_tax_rate), "tax rate clamps to its maximum")
	_check(not gs.issue(Policy.new("XXX", "tax_rate", 0.1)), "unknown nation rejected")
	_check(not gs.issue(Policy.new("FRA", "bogus", 0.1)), "unknown policy rejected")
	_check(not gs.issue(Policy.new("FRA", "army_funding", 1.0)) and not gs.issue(Policy.new("FRA", "navy_funding", 1.0)), "the funding policies are gone")
	_check(gs.command_log.size() == 2, "only accepted commands are logged")
	gs.issue(Policy.new("FRA", "tax_rate", Eco.cfg.default_tax_rate))

	# ---- Mobilization: one lever, held in peace, free in war ----
	var peace_max: float = Eco.cfg.mobilization.peace_max
	gs.issue(Policy.new("FRA", "mobilization", 1.0))
	_check(is_equal_approx(fra.mobilization, peace_max), "in peace mobilization stops at %d%%" % roundi(peace_max * 100.0))
	gs.issue(Policy.new("FRA", "mobilization", 0.0))
	var gdp0: float = fra.budget.gdp
	var max0: float = fra.budget.manpower_max
	var army0: float = fra.budget.army
	var ind0: float = fra.budget.industry
	gs.issue(Policy.new("FRA", "mobilization", peace_max))
	_check(fra.budget.gdp < gdp0 and fra.budget.industry < ind0, "mobilization lowers output and industry")
	_check(fra.budget.manpower_max > max0, "mobilization raises the manpower cap")
	_check(fra.total_men() == fra.peacetime_army, "manpower fills over time, not instantly")
	_advance_month(clock)
	_check(fra.total_men() > fra.peacetime_army, "manpower grows after a month of mobilization")
	_check(fra.budget.army > army0, "a bigger army costs more upkeep")
	gs.issue(Policy.new("FRA", "mobilization", 0.0))
	_check(fra.budget.manpower_max == float(fra.peacetime_army), "demobilizing returns the cap to the peacetime army")
	_advance_month(clock)
	_check(fra.total_men() == fra.peacetime_army, "manpower above the cap is released")
	gs.set_war("FRA", "GER", true)
	_check(Eco.mobilization_range(gs, fra).y == 1.0 and Eco.mobilization_range(gs, fra).x > 0.0, "at war the range runs up to 1 and no lower than the war floor")
	gs.set_war("FRA", "GER", false)

	# ---- The monthly step pays out the budget ----
	var ger = gs.nations["GER"]
	gs.issue(Policy.new("GER", "tax_rate", 0.14))
	var treasury0: float = ger.treasury
	var net: float = ger.budget.net
	var dev0: float = ger.development
	_advance_month(clock)
	# The month's growth of the people moves the budget a little before it is paid.
	var expected: float = treasury0 + net / 12.0
	_check(absf(ger.treasury - expected) < 0.3 + 0.02 * absf(net / 12.0), "treasury changes by one twelfth of the net budget (%.2f against %.2f)" % [ger.treasury, expected])
	_check(ger.development > dev0, "economy grows each month")
	gs.issue(Policy.new("GER", "tax_rate", Eco.cfg.default_tax_rate))

	# ---- Debt costs interest ----
	var ita = gs.nations["ITA"]
	var interest0: float = ita.budget.interest
	ita.treasury = -100.0
	Eco.recompute(gs)
	_check(interest0 == 0.0 and is_equal_approx(ita.budget.interest, 100.0 * Eco.cfg.debt.interest), "a nation in debt pays %d%% a year on it" % roundi(Eco.cfg.debt.interest * 100.0))
	ita.treasury = 50.0
	Eco.recompute(gs)

	# ---- Buildings: IC only, queued, built over time, then boost the province ----
	var Build = load("res://scripts/sim/construct_building.gd")
	var home: int = ger.provinces[0]
	var gdp_before: float = ger.budget.gdp
	var ind_before: float = ger.budget.industry
	var cash: float = ger.treasury
	var cost: float = Eco.build_plan(gs, home, "factory").ic
	var f0: int = gs.province_buildings[home].get("factory", 0)
	var gold: float = Eco.build_plan(gs, home, "factory").gold
	_check(gs.issue(Build.new("GER", home, "factory")), "construction accepted")
	_check(is_equal_approx(ger.treasury, cash - gold) and cost > 0.0 and gold > 0.0, "construction costs money when begun (£%.2fM), then IC" % gold)
	_check(ger.construction.size() == 1 and gs.province_buildings[home].get("factory", 0) == f0, "building is queued, not built")
	_check(not gs.issue(Build.new("GER", home, "factory")) and Eco.build_problem(gs, "GER", home, "factory") == "Already under construction", "the same building is not queued twice")
	_check(not gs.issue(Build.new("GER", gs.nations["FRA"].provinces[0], "factory")), "cannot build in a foreign province")
	_check(not gs.issue(Build.new("GER", home, "bogus")), "unknown building rejected")
	var completed := [0]
	gs.building_completed.connect(func(_t, _p, _ty) -> void: completed[0] += 1)
	var days_needed: int = Eco.cfg.buildings.factory.min_days
	var built_days := 0
	while ger.construction.size() > 0 and built_days < 1500:
		clock.advance_day()
		built_days += 1
	_check(built_days >= days_needed, "it takes at least min_days (%d)" % built_days)
	_check(ger.construction.is_empty() and gs.province_buildings[home].get("factory", 0) == f0 + 1 and completed[0] == 1, "the factory completes on schedule")
	_check(ger.budget.gdp > gdp_before and ger.budget.industry > ind_before, "a factory raises output and industry")
	_check(Eco.build_plan(gs, home, "factory").ic > cost, "the next level of a factory costs more")
	var max_level: int = Eco.cfg.buildings.factory.max_level
	gs.province_buildings[home]["factory"] = max_level
	_check(Eco.build_problem(gs, "GER", home, "factory") == "Fully built", "a building stops at its top level")
	gs.province_buildings[home]["factory"] = f0 + 1
	var poor: float = ger.treasury
	ger.treasury = 0.0
	_check(not gs.issue(Build.new("GER", home, "railway")) and Eco.build_problem(gs, "GER", home, "railway").contains("money"), "building needs money: " + Eco.build_problem(gs, "GER", home, "railway"))
	ger.construction.clear()
	ger.treasury = poor

	# ---- Ports need a coast; trade buildings add tariff income that a blockade removes ----
	var map: Node = root.get_node("MapData")
	var inland := -1
	var coast := -1
	for id in ger.provinces:
		if map.provinces[id].coastal and coast < 0 and id != home:
			coast = id
		elif not map.provinces[id].coastal and inland < 0:
			inland = id
	_check(coast > 0 and inland > 0, "Germany has coastal and inland provinces")
	_check(not gs.issue(Build.new("GER", inland, "port")) and Eco.build_problem(gs, "GER", inland, "port") == "Needs a coastal province", "ports cannot be built inland, and it says why")
	var stats0: Dictionary = Eco.building_stats(gs, "GER")
	_check(stats0.port.levels >= 1, "Germany starts with a port, as every nation that starts with a navy does")
	var trade0: float = ger.budget.trade
	var rev0: float = ger.budget.revenue
	_check(gs.issue(Build.new("GER", coast, "port")) and gs.issue(Build.new("GER", inland, "railway")), "a port and a railway accepted")
	var guard := 0
	while ger.construction.size() > 0 and guard < 3000:
		clock.advance_day()
		guard += 1
	_check(ger.budget.trade > trade0 and ger.budget.revenue > rev0, "a port and a railway add trade income and revenue")
	var stats: Dictionary = Eco.building_stats(gs, "GER")
	_check(stats.port.levels == stats0.port.levels + 1 and stats.port.trade > stats0.port.trade, "port stats report its trade")
	_check(stats.railway.levels >= 1 and stats.railway.income > 0.0, "railway stats report income")
	_check(stats.factory.levels >= 1 and stats.factory.industry > 0.0 and stats.factory.gdp > 0.0, "factory stats report industry and output")
	_check(not stats.has("military_factory") and not stats.has("haber_bosch") and not stats.has("naval_dockyard"), "the removed buildings are gone")
	ger.blockade = 1.0
	Eco.recompute(gs)
	_check(is_zero_approx(ger.budget.trade), "blockade removes trade income")
	ger.blockade = 0.0
	Eco.recompute(gs)

	# ---- A blockade hurts an importer far more than a self-sufficient nation ----
	var gbr = gs.nations["GBR"]
	var gbr_gdp: float = gbr.budget.gdp
	gbr.blockade = 1.0
	Eco.recompute(gs)
	_check(gbr.budget.food_shortage > 0.1, "blockaded Britain starves (shortage %.2f)" % gbr.budget.food_shortage)
	_check(gbr.budget.gdp < gbr_gdp * 0.8, "blockade cuts GDP")
	gbr.blockade = 0.0
	Eco.recompute(gs)

	# ---- Ownership changes move the tax base; construction in a transferred province is lost ----
	var ger_rev: float = ger.budget.revenue
	var fra_rev: float = fra.budget.revenue
	var prov: int = ger.provinces[0]
	gs.transfer_province(prov, "FRA")
	_check(ger.budget.revenue < ger_rev and fra.budget.revenue > fra_rev, "transferring a province moves its revenue")
	var other: int = gs.nations["ITA"].provinces[0]
	gs.issue(Build.new("ITA", other, "factory"))
	gs.transfer_province(other, "FRA")
	_check(gs.nations["ITA"].construction.is_empty(), "construction is dropped when the province changes hands")

	# ---- Raw materials ----
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()  # the scenario starts a crisis; these tests want a quiet world
	gs.wars.clear()
	var ruhr: int = map.provinces.find_custom(func(p: Dictionary) -> bool: return p.get("name", "") == "Nordrhein-Westfalen 2")
	_check(gs.province_deposit[ruhr].coal > 50000, "the Ruhr has a huge coal deposit")
	var ger2 = gs.nations["GER"]
	var gbr2 = gs.nations["GBR"]
	var ita2 = gs.nations["ITA"]
	_check(gbr2.budget.materials.exported > 0.0 and gbr2.budget.materials.income > 0.0, "Britain's coal sells abroad, and earns")
	_check(ita2.budget.materials.imported > 0.0 and ita2.budget.materials_cost > 0.0, "Italy has few deposits and buys what its industry needs, at a cost")
	var deposits := 0.0
	for id in ger2.provinces:
		for r in Eco.resource_ids():
			var d: float = gs.province_deposit[id].get(r, 0.0)
			if d >= Eco.cfg.materials.min_deposit:
				deposits += d
	_check(is_equal_approx(ger2.budget.materials.own, deposits * Eco.cfg.materials.extraction_base), "Germany extracts the whole of its deposits (%.0f kt)" % deposits)
	# A blockade cuts the imports, and what is short slows industry.
	var ind_ita: float = ita2.budget.industry
	var gdp_ita: float = ita2.budget.gdp
	ita2.blockade_pinned = 1.0
	ita2.blockade = 1.0
	Eco.recompute(gs)
	_check(ita2.budget.materials.imported == 0.0 and ita2.budget.materials.ratio < 0.2, "a full blockade stops Italy's imports (%d%% of the need left)" % roundi(ita2.budget.materials.ratio * 100.0))
	_check(ita2.budget.industry < ind_ita * 0.5 and ita2.budget.gdp < gdp_ita, "and industry and output fall")
	_check(ita2.budget.industry > 0.0 and Eco.construction_points(ita2, ita2.budget.industry) >= Eco.cfg.construction.base_ic, "though never to nothing: the small works go on")
	ita2.blockade_pinned = -1.0
	ita2.blockade = 0.0
	Eco.recompute(gs)
	_check(ita2.budget.materials.ratio >= 0.999 and is_equal_approx(ita2.budget.industry, ind_ita), "lifting the blockade restores it")
	# Building needs money, not materials.
	var cash2: float = ita2.treasury
	ita2.treasury = 0.0
	ita2.blockade = 0.6
	_check(Eco.build_problem(gs, "ITA", ita2.provinces[0], "factory").contains("money"), "an empty treasury stops a factory")
	ita2.treasury = 1000.0
	_check(Eco.build_problem(gs, "ITA", ita2.provinces[0], "factory") == "", "a blockade does not")
	ita2.blockade = 0.0
	ita2.treasury = cash2

	# ---- Mass building ----
	var Mass = load("res://scripts/sim/mass_construct_building.gd")
	var fra3 = gs.nations["FRA"]
	var cands: Array = Eco.mass_candidates(gs, "FRA", "factory")
	_check(cands.size() > 50, "many French provinces can take a factory (%d)" % cands.size())
	var pri_ok := true
	for i in cands.size() - 1:
		pri_ok = pri_ok and Eco.build_priority(gs, cands[i], "factory") >= Eco.build_priority(gs, cands[i + 1], "factory")
	_check(pri_ok, "candidates are ordered best first")
	var ports: Array = Eco.mass_candidates(gs, "FRA", "port")
	var coastal_only := true
	for id in ports:
		coastal_only = coastal_only and map.provinces[id].coastal
	_check(ports.size() > 5 and coastal_only, "port candidates are all coastal (%d)" % ports.size())
	var cmd = Mass.new("FRA", "railway", 10, 0.0)
	var cash3: float = fra3.treasury
	var q0: int = fra3.construction.size()
	var pv: Dictionary = cmd.preview(gs)
	_check(fra3.treasury == cash3 and fra3.construction.size() == q0, "preview leaves the state untouched")
	_check(pv.count == 10 and pv.spent > 0.0, "preview: 10 railways for %.0f IC" % pv.spent)
	_check(gs.issue(cmd), "mass build accepted")
	_check(cmd.built.size() == 10 and fra3.construction.size() == q0 + 10, "built in exactly the previewed number of provinces")
	_check(is_equal_approx(pv.spent, cmd.spent) and pv.gold > 0.0 and is_equal_approx(fra3.treasury, cash3 - pv.gold), "preview cost matches the real cost, money included (£%.1fM)" % pv.gold)
	_check(gs.command_log.back().type == "MassConstructBuilding" and gs.command_log.back().provinces.size() == 10, "logged as one command")
	var broke = Mass.new("FRA", "railway", 1000, 0.0)
	fra3.treasury = float(Eco.build_plan(gs, Eco.mass_candidates(gs, "FRA", "railway")[0], "railway").gold) * 2.5
	gs.issue(broke)
	_check(broke.stopped_by == "money" and broke.built.size() == 2 and fra3.treasury >= 0.0, "a mass build stops when the money runs out (%d built)" % broke.built.size())
	fra3.treasury = cash3
	# Room for the two best candidates (the big cities, whose works are already built up) and not a third.
	var cap_ic: float = Eco.level_cost(gs, cands[0], "factory") + Eco.level_cost(gs, cands[1], "factory") + 0.5 * Eco.level_cost(gs, cands[2], "factory")
	var capped = Mass.new("FRA", "factory", 1000, cap_ic)
	gs.issue(capped)
	_check(capped.stopped_by == "spend" and capped.built.size() == 2 and capped.spent <= cap_ic, "spend cap respected (%.0f IC of %.0f)" % [capped.spent, cap_ic])
	_check(not gs.issue(Mass.new("FRA", "bogus", 5, 0.0)) and not gs.issue(Mass.new("XXX", "factory", 5, 0.0)), "unknown building or nation rejected")

	# ---- What money is for (economy round 2) ----
	gs.load_scenario("res://data/scenarios/jan_1900/")
	var srb = gs.nations["SRB"]
	var gbr5 = gs.nations["GBR"]
	_check(Eco.wage_factor(srb, gs.economy_sums["SRB"]) < Eco.wage_factor(gbr5, gs.economy_sums["GBR"]), "a Serbian soldier costs less to keep than a British one (%.2f to %.2f)" % [Eco.wage_factor(srb, gs.economy_sums["SRB"]), Eco.wage_factor(gbr5, gs.economy_sums["GBR"])])
	for tag in gs.nations:
		var bb: Dictionary = gs.nations[tag].budget
		if gs.nations[tag].provinces.is_empty():
			continue
		_check(bb.army < bb.revenue * 0.7, "%s can pay for its army (%.2f of %.2f a year)" % [tag, bb.army, bb.revenue])
	# Building pays: the state's civil spending does not grow with the buildings, so most of what they add is kept.
	var ger4 = gs.nations["GER"]
	ger4.treasury = 5000.0
	var net0: float = ger4.budget.net
	var rev0_5: float = ger4.budget.revenue
	var site: int = Eco.mass_candidates(gs, "GER", "factory")[0]
	var gain: Dictionary = Eco.level_gain(gs, "GER", site, "factory")
	var plan4: Dictionary = Eco.build_plan(gs, site, "factory")
	var cash4: float = ger4.treasury
	_check(gs.issue(load("res://scripts/sim/construct_building.gd").new("GER", site, "factory")) and is_equal_approx(ger4.treasury, cash4 - float(plan4.gold)) and float(plan4.gold) > 0.0, "a factory is paid for when begun (£%.2fM)" % plan4.gold)
	gs.province_buildings[site]["factory"] = int(gs.province_buildings[site].get("factory", 0)) + 1
	ger4.construction.clear()
	Eco.recompute(gs)
	var added: float = ger4.budget.revenue - rev0_5
	var kept: float = ger4.budget.net - net0
	_check(added > 0.0 and kept >= added * 0.5, "and of the £%.2fM a year it adds, the budget keeps £%.2fM (the rest buys its raw materials)" % [added, kept])
	_check(absf(gain.revenue - added) < 0.001 and absf(gain.net - kept) < 0.001, "level_gain foresees both (£%.2fM, £%.2fM)" % [gain.revenue, gain.net])
	ger4.treasury = 0.0
	_check(Eco.build_problem(gs, "GER", Eco.mass_candidates(gs, "GER", "railway")[0] if not Eco.mass_candidates(gs, "GER", "railway").is_empty() else site, "railway").contains("money"), "with no money nothing can be begun")
	# The standing army: set by the player up to a ceiling, paid every month.
	gs.set_player("ITA")
	var ita_5 = gs.nations["ITA"]
	var cap: int = Eco.standing_cap(gs, ita_5)
	gs.issue(Policy.new("ITA", "standing_army", float(cap * 2)))
	_check(ita_5.peacetime_army == cap and cap > 0, "the standing army stops at its ceiling (%d)" % cap)
	gs.issue(Policy.new("ITA", "standing_army", 100000.0))
	_check(ita_5.peacetime_army == 100000, "and may be set below it")
	var army_low: float = ita_5.budget.army
	gs.issue(Policy.new("ITA", "standing_army", float(cap)))
	_advance_month(clock)
	_check(ita_5.budget.army > army_low and ita_5.manpower > 0, "a larger standing army calls more recruits and costs more (%.1f to %.1f a year)" % [army_low, ita_5.budget.army])
	var pta: int = ita_5.peacetime_army
	for i in 12:
		_advance_month(clock)
	_check(ita_5.peacetime_army == pta, "the player's standing army does not grow on its own")

	# ---- Recruits ----
	var ger3 = gs.nations["GER"]
	var m: int = ger3.manpower
	_check(not ger3.spend_manpower(m + 1) and ger3.manpower == m, "cannot spend more manpower than available")
	_check(ger3.spend_manpower(1000) and ger3.manpower == m - 1000, "spending manpower deducts it")

	print("FAILURES: ", _failures)
	quit(1 if _failures else 0)


func _advance_month(clock: Node) -> void:
	var month: int = clock.month
	while clock.month == month:
		clock.advance_day()
