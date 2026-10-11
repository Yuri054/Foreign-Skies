extends SceneTree
## Headless test for the economy.
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

	# Starting budgets are sane and roughly match 1914 revenue.
	var targets := {"GBR": 198.0, "FRA": 200.0, "GER": 280.0, "ITA": 100.0, "AUH": 150.0}
	for tag in gs.nations:
		var b: Dictionary = gs.nations[tag].budget
		_check(b.gdp > 0.0 and b.revenue > 0.0 and b.manpower_max > 0.0, "%s: positive GDP, revenue and manpower" % tag)
	for tag in targets:
		var rev: float = gs.nations[tag].budget.revenue
		_check(absf(rev - targets[tag]) / targets[tag] < 0.05, "%s revenue %.0f is within 5%% of %.0f" % [tag, rev, targets[tag]])
	for tag in gs.nations:
		_check(gs.nations[tag].budget.net > -0.05, "%s starts balanced or in surplus (net %.1f a year)" % [tag, gs.nations[tag].budget.net])
	_check(gs.nations["GBR"].budget.food_shortage == 0.0, "no famine at the start (imports cover the gap)")
	_check(gs.nations["GBR"].budget.food_imported > 0.0, "Britain imports food")

	# Policy commands: clamping, rejection and the log.
	var fra = gs.nations["FRA"]
	var base_rev: float = fra.budget.revenue
	_check(gs.issue(Policy.new("FRA", "tax_rate", 0.2)), "tax command accepted")
	_check(fra.budget.revenue > base_rev, "higher tax raises revenue")
	gs.issue(Policy.new("FRA", "tax_rate", 5.0))
	_check(is_equal_approx(fra.tax_rate, Eco.cfg.max_tax_rate), "tax rate clamps to its maximum")
	_check(not gs.issue(Policy.new("XXX", "tax_rate", 0.1)), "unknown nation rejected")
	_check(not gs.issue(Policy.new("FRA", "bogus", 0.1)), "unknown policy rejected")
	_check(gs.command_log.size() == 2, "only accepted commands are logged")
	gs.issue(Policy.new("FRA", "tax_rate", Eco.cfg.default_tax_rate))

	# Mobilization trades output for manpower.
	var gdp0: float = fra.budget.gdp
	var max0: float = fra.budget.manpower_max
	var army0: float = fra.budget.army
	gs.issue(Policy.new("FRA", "mobilization", 1.0))
	_check(fra.budget.gdp < gdp0, "mobilization lowers GDP")
	_check(fra.budget.manpower_max > max0 * 3.0, "mobilization raises the manpower cap")
	_check(fra.total_men() == fra.peacetime_army, "manpower fills over time, not instantly")
	_advance_month(clock)
	_check(fra.total_men() > fra.peacetime_army, "manpower grows after a month of mobilization")
	_check(fra.budget.army > army0, "a bigger army costs more upkeep")
	gs.issue(Policy.new("FRA", "mobilization", 0.0))
	_check(fra.budget.manpower_max == float(fra.peacetime_army), "demobilizing returns the cap to the peacetime army")
	_advance_month(clock)
	_check(fra.total_men() == fra.peacetime_army, "manpower above the cap is released")

	# Monthly step pays out the budget.
	var ger = gs.nations["GER"]
	var treasury0 = ger.treasury
	var spent0 = ger.equipment_spent
	var net: float = ger.budget.net
	var equipment: float = ger.budget.equipment
	var dev0 = ger.development
	_advance_month(clock)
	_check(is_equal_approx(ger.treasury, treasury0 + (net + equipment) / 12.0 - (ger.equipment_spent - spent0)), "treasury changes by one twelfth of the net budget, less what the production lines paid")
	_check(ger.development > dev0, "economy grows each month")

	# Buildings: paid up front, built over time, then boost the province.
	var Build = load("res://scripts/sim/construct_building.gd")
	var SetProg = load("res://scripts/sim/set_program.gd")
	var home: int = ger.provinces[0]
	var gdp_before: float = ger.budget.gdp
	var cash = ger.treasury
	var cost: float = Eco.build_plan(gs, home, "factory").total
	var f0: int = gs.province_buildings[home].get("factory", 0)
	_check(gs.issue(Build.new("GER", home, "factory")), "construction accepted")
	_check(is_equal_approx(ger.treasury, cash - cost), "construction is paid up front")
	_check(ger.construction.size() == 1 and gs.province_buildings[home].get("factory", 0) == f0, "building is queued, not built")
	var slots: int = gs.province_slots[home]
	gs.province_slots[home] = Eco.slots_used(gs, home)
	_check(not gs.issue(Build.new("GER", home, "factory")) and Eco.build_problem(gs, "GER", home, "factory") == "No free slot", "a province with no free slot takes no more factories")
	gs.province_slots[home] = slots
	_check(not gs.issue(Build.new("GER", gs.nations["FRA"].provinces[0], "factory")), "cannot build in a foreign province")
	_check(not gs.issue(Build.new("GER", home, "bogus")), "unknown building rejected")
	var completed = [0]
	gs.building_completed.connect(func(_t, _p, _ty) -> void: completed[0] += 1)
	for i in Eco.cfg.buildings.factory.build_days - 1:
		clock.advance_day()
	_check(ger.construction.size() == 1, "still building one day early")
	clock.advance_day()
	_check(ger.construction.is_empty() and gs.province_buildings[home].get("factory", 0) == f0 + 1 and completed[0] == 1, "factory completes on schedule")
	_check(ger.budget.gdp > gdp_before, "factory raises GDP")
	_check(is_equal_approx(Eco.build_plan(gs, home, "factory").total, cost), "a factory costs the same each time")
	_check(Eco.build_plan(gs, home, "railway").total < (Eco.build_plan(gs, home, "railway").gold + 1.0) * 5.0, "other buildings still cost more for each level")
	var poor = ger.treasury
	ger.treasury = 0.0
	_check(not gs.issue(Build.new("GER", home, "factory")), "cannot build without money")
	ger.treasury = poor

	# Ports need a coast; trade buildings add tariff income that a blockade removes.
	var map: Node = root.get_node("MapData")
	var inland := -1
	var coast := -1
	for id in ger.provinces:
		if map.provinces[id].coastal and coast < 0 and id != home:
			coast = id
		elif not map.provinces[id].coastal and inland < 0:
			inland = id
	_check(coast > 0 and inland > 0, "Germany has coastal and inland provinces")
	ger.treasury = 1000.0
	_check(not gs.issue(Build.new("GER", inland, "port")), "ports cannot be built inland")
	_check(Eco.build_problem(gs, "GER", inland, "port") == "Needs a coastal province", "inland port gives a reason")
	var stats0 = Eco.building_stats(gs, "GER")
	_check(stats0.port.levels >= 1, "Germany starts with a port, as every nation that starts with a navy does")
	var trade0: float = ger.budget.trade
	var rev0: float = ger.budget.revenue
	_check(gs.issue(Build.new("GER", coast, "port")) and gs.issue(Build.new("GER", inland, "railway")), "port and railway accepted")
	for i in Eco.cfg.buildings.railway.build_days:
		clock.advance_day()
	_check(ger.budget.trade > trade0 and ger.budget.revenue > rev0, "a port and a railway add trade income and revenue")
	var stats = Eco.building_stats(gs, "GER")
	_check(stats.port.levels == stats0.port.levels + 1 and stats.port.trade > stats0.port.trade, "port stats report its trade")
	_check(stats.railway.levels == 1 and stats.railway.income > 0.0, "railway stats report income")
	_check(stats.factory.levels > 1 and stats.factory.industry > 0.0 and stats.factory.gdp > 0.0, "factory stats report industry and output")
	_check(stats.military_factory.gdp == 0.0 and stats.military_factory.income == 0.0, "a military factory earns nothing itself")
	_check(not stats.has("farmland") and not stats.has("market") and not stats.has("coal_mine"), "the removed buildings are gone")
	var from_buildings: float = stats.port.income + stats.railway.income + stats.factory.income
	_check(from_buildings > 0.0 and from_buildings < ger.budget.revenue, "building income is part of total revenue")
	ger.blockade = 1.0
	Eco.recompute(gs)
	_check(is_zero_approx(ger.budget.trade), "blockade removes trade income")
	ger.blockade = 0.0
	Eco.recompute(gs)
	ger.treasury = poor

	# Programs cost upkeep and boost output.
	var food0: float = ger.budget.food_production
	var prog0: float = ger.budget.programs
	_check(gs.issue(SetProg.new("GER", "agri_subsidies", true)), "program enabled")
	_check(ger.budget.food_production > food0 and ger.budget.programs > prog0, "agricultural subsidies add food and cost money")
	_check(not gs.issue(SetProg.new("GER", "bogus", true)) and not gs.issue(SetProg.new("GER", "_note", true)), "unknown program rejected")
	var dev_a = ger.development
	_advance_month(clock)
	var slow = ger.development / dev_a
	gs.issue(SetProg.new("GER", "education", true))
	var dev_b = ger.development
	_advance_month(clock)
	_check(ger.development / dev_b > slow, "education speeds up growth")
	gs.issue(SetProg.new("GER", "agri_subsidies", false))
	_check(is_equal_approx(ger.budget.food_production, food0), "program can be switched off")

	# Blockade hurts an importer far more than a self-sufficient nation.
	var gbr = gs.nations["GBR"]
	var gbr_gdp: float = gbr.budget.gdp
	gbr.blockade = 1.0
	Eco.recompute(gs)
	_check(gbr.budget.food_shortage > 0.1, "blockaded Britain starves (shortage %.2f)" % gbr.budget.food_shortage)
	_check(gbr.budget.gdp < gbr_gdp * 0.8, "blockade cuts GDP")
	gbr.blockade = 0.0
	Eco.recompute(gs)

	# Ownership changes move the tax base.
	var ger_rev: float = ger.budget.revenue
	var fra_rev: float = fra.budget.revenue
	var prov: int = ger.provinces[0]
	gs.transfer_province(prov, "FRA")
	_check(ger.budget.revenue < ger_rev and fra.budget.revenue > fra_rev, "transferring a province moves its revenue")

	# Construction in a transferred province is lost.
	var other: int = gs.nations["ITA"].provinces[0]
	gs.nations["ITA"].treasury = 5000.0
	gs.nations["ITA"].stock.iron = 1e6
	gs.nations["ITA"].stock.coal = 1e6
	gs.issue(Build.new("ITA", other, "factory"))
	gs.transfer_province(other, "FRA")
	_check(gs.nations["ITA"].construction.is_empty(), "construction is dropped when the province changes hands")

	# ---- Resources ----
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()  # the scenario starts a crisis; these tests want a quiet world
	gs.wars.clear()
	var map2: Node = root.get_node("MapData")
	var res_names := ["coal", "iron", "wood"]
	var coal_real := {"GBR": 292000.0, "GER": 225000.0, "FRA": 40000.0}
	for tag in coal_real:
		var made: float = gs.nations[tag].budget.resources.coal.production
		_check(absf(made - coal_real[tag]) / coal_real[tag] < 0.02, "%s mines %.0f kt coal (target %.0f)" % [tag, made, coal_real[tag]])
	var ruhr: int = map2.provinces.find_custom(func(p: Dictionary) -> bool: return p.get("name", "") == "Nordrhein-Westfalen 2")
	_check(gs.province_deposit[ruhr].coal > 50000, "the Ruhr has a huge coal deposit")
	_check(gs.nations["GBR"].budget.resources.coal.balance > 50000, "Britain exports coal")
	_check(gs.nations["ITA"].budget.resources.coal.balance < 0 and gs.nations["FRA"].budget.resources.coal.balance < 0, "Italy and France import coal")
	_check(gs.nations["ESP"].budget.resources.iron.balance > 5000, "Spain exports iron ore")
	_check(gs.nations["GER"].budget.resources.iron.balance < 0, "Germany imports iron ore")
	for tag in gs.nations:
		for r in res_names:
			_check(gs.nations[tag].budget.resources[r].shortage == 0.0, "%s has no %s shortage at the start" % [tag, r])
	for tag in targets:
		var rev2: float = gs.nations[tag].budget.revenue
		_check(absf(rev2 - targets[tag]) / targets[tag] < 0.05, "%s revenue %.0f still matches with resource trade" % [tag, rev2])

	# Extraction: a province yields its whole deposit, with no mines to build.
	var ger2 = gs.nations["GER"]
	ger2.treasury = 5000.0
	var no_coal := -1
	var deposit_coal := 0.0
	for id in ger2.provinces:
		if gs.province_deposit[id].coal < 50 and no_coal < 0:
			no_coal = id
		if gs.province_deposit[id].coal >= Eco.cfg.min_deposit:
			deposit_coal += gs.province_deposit[id].coal
	_check(is_equal_approx(ger2.budget.resources.coal.production, deposit_coal), "Germany extracts the whole of its coal deposits (%.0f kt)" % deposit_coal)
	_check(Eco.build_problem(gs, "GER", ruhr, "coal_mine") == "Unknown nation or building", "there are no mines to build")

	# Consumption: factories burn coal and iron, and their cost leans on the stockpile.
	var demand0: float = ger2.budget.resources.coal.demand
	var iron_stock: float = ger2.stock.iron
	var plan = Eco.build_plan(gs, no_coal, "factory")
	_check(plan.materials.iron == 1500.0 and plan.materials.coal == 800.0, "factory materials: 1500 kt iron, 800 kt coal")
	_check(gs.issue(Build.new("GER", no_coal, "factory")), "factory accepted")
	_check(is_equal_approx(ger2.stock.iron, iron_stock - plan.from_stock.iron), "materials come out of the stockpile")
	for i in Eco.cfg.buildings.factory.build_days:
		clock.advance_day()
	_check(ger2.budget.resources.coal.demand - demand0 >= 600.0, "a new factory raises coal demand through its industry")

	# Empty stockpile: materials are bought at a markup; a blockade stops that.
	var ita = gs.nations["ITA"]
	ita.treasury = 5000.0
	var ita_home: int = ita.provinces[0]
	ita.stock.iron = 0.0
	ita.stock.coal = 0.0
	var dry = Eco.build_plan(gs, ita_home, "factory")
	_check(dry.buy.iron == 1500.0 and dry.purchase > 0.0 and dry.total > dry.gold, "an empty stockpile means buying materials (+£%.2fM)" % dry.purchase)
	ita.stock.iron = 1e6
	ita.stock.coal = 1e6
	var full = Eco.build_plan(gs, ita_home, "factory")
	_check(full.purchase == 0.0 and is_equal_approx(full.total, full.gold), "a full stockpile means no purchase")
	ita.stock.iron = 0.0
	ita.blockade = 0.6
	_check(Eco.build_problem(gs, "ITA", ita_home, "factory") != "", "blockade stops imported materials")
	ita.blockade = 0.0

	# Blockade: stocks run down, then shortages bite.
	var gbr2 = gs.nations["GBR"]
	var ind0: float = gbr2.budget.industry
	var exp0: float = gbr2.budget.resource_exports
	gbr2.blockade_pinned = 1.0
	gbr2.blockade = 1.0
	Eco.recompute(gs)
	_check(gbr2.budget.resource_exports == 0.0 and exp0 > 0.0, "blockade ends coal exports")
	_check(gbr2.budget.resources.wood.shortage == 0.0, "stockpile covers the first month of blockaded timber")
	var wood_stock: float = gbr2.stock.wood
	for i in 8:
		_advance_month(clock)
	_check(gbr2.stock.wood < wood_stock, "stockpile is drawn down by the blockade")
	_check(gbr2.budget.resources.wood.shortage > 0.0, "timber shortage appears once the stockpile is gone")
	_check(gbr2.budget.industry < ind0 * 0.99, "shortages cut industry")
	gbr2.blockade_pinned = -1.0
	gbr2.blockade = 0.0
	Eco.recompute(gs)
	_check(gbr2.budget.resources.wood.shortage == 0.0, "lifting the blockade ends the shortage")

	# Building stats include resources.
	var cstats = Eco.building_stats(gs, "GER")
	_check(cstats.factory.uses.is_empty(), "factories burn nothing of their own: their industry sets the demand")

	# ---- Mass building ----
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()  # the scenario starts a crisis; these tests want a quiet world
	gs.wars.clear()
	var Mass = load("res://scripts/sim/mass_construct_building.gd")
	var fra3 = gs.nations["FRA"]
	fra3.treasury = 500.0
	var cands = Eco.mass_candidates(gs, "FRA", "factory")
	_check(cands.size() > 50, "many French provinces have a slot for a factory (%d)" % cands.size())
	var pri_ok := true
	for i in cands.size() - 1:
		pri_ok = pri_ok and Eco.build_priority(gs, cands[i], "factory") >= Eco.build_priority(gs, cands[i + 1], "factory")
	_check(pri_ok, "candidates are ordered best first")
	var ports = Eco.mass_candidates(gs, "FRA", "port")
	var coastal_only := true
	for id in ports:
		coastal_only = coastal_only and map2.provinces[id].coastal
	_check(ports.size() > 5 and coastal_only, "port candidates are all coastal (%d)" % ports.size())

	# preview changes nothing and matches the real run
	var cmd = Mass.new("FRA", "railway", 10, 0.0)
	var cash2 = fra3.treasury
	var stock2 = fra3.stock.duplicate()
	var q0: int = fra3.construction.size()
	var pv = cmd.preview(gs)
	_check(fra3.treasury == cash2 and fra3.stock == stock2 and fra3.construction.size() == q0, "preview leaves the state untouched")
	_check(pv.count == 10 and pv.spent > 0.0, "preview: 10 railways for £%.1fM" % pv.spent)
	_check(gs.issue(cmd), "mass build accepted")
	_check(cmd.built.size() == 10 and fra3.construction.size() == q0 + 10, "built in exactly the previewed number of provinces")
	_check(is_equal_approx(cash2 - fra3.treasury, pv.spent) and is_equal_approx(pv.spent, cmd.spent), "preview cost matches the real cost")
	_check(gs.command_log.back().type == "MassConstructBuilding" and gs.command_log.back().provinces.size() == 10, "logged as one command")

	# a spending cap and running out of money both stop it
	var capped = Mass.new("FRA", "factory", 1000, 20.0)
	gs.issue(capped)
	_check(capped.stopped_by == "spend" and capped.built.size() >= 1 and capped.spent <= 20.0, "spend cap respected (£%.1fM of 20)" % capped.spent)
	fra3.treasury = 25.0
	var broke = Mass.new("FRA", "port", 1000, 0.0)
	_check(gs.issue(broke) and broke.spent <= 25.0 and broke.built.size() < 20, "stops when the money runs out (%d built)" % broke.built.size())
	fra3.treasury = 0.0
	_check(not gs.issue(Mass.new("FRA", "factory", 5, 0.0)), "nothing built with no money is rejected")
	_check(Mass.new("FRA", "factory", 5, 0.0).preview(gs).stopped_by == "money", "preview says money is the limit")
	_check(not gs.issue(Mass.new("FRA", "bogus", 5, 0.0)) and not gs.issue(Mass.new("XXX", "factory", 5, 0.0)), "unknown building or nation rejected")

	# Recruits.
	var m = ger.manpower
	_check(not ger.spend_manpower(m + 1) and ger.manpower == m, "cannot spend more manpower than available")
	_check(ger.spend_manpower(1000) and ger.manpower == m - 1000, "spending manpower deducts it")

	print("FAILURES: ", _failures)
	quit(1 if _failures else 0)


func _advance_month(clock: Node) -> void:
	var month: int = clock.month
	while clock.month == month:
		clock.advance_day()
