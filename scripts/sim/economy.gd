class_name Economy
extends RefCounted
## Economy rules. Province output comes from population, density, deposits, the owner's
## development and what is built there; each nation's budget is derived from the province
## totals plus its policy (tax, mobilization) and its national programs. Money is GBP
## millions per year; GameState applies a twelfth of it each month. Raw resources (coal, iron,
## timber) are in thousand tonnes per year and are balanced nationally: shortfalls are
## imported (unless blockaded), surpluses are exported, and a stockpile buffers both.
## All constants live in data/economy.json.

const CONFIG_PATH := "res://data/economy.json"

static var cfg: Dictionary = {}


static func load_config() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	assert(cfg is Dictionary, "economy.json is invalid")


## Ids of the raw resources (coal, iron, wood), in file order.
static func resource_ids() -> Array:
	return cfg.resources.keys().filter(func(k: String) -> bool: return not k.begins_with("_"))


## Ids of the building types, in file order.
static func building_ids() -> Array:
	return cfg.buildings.keys().filter(func(k: String) -> bool: return not k.begins_with("_"))


## Ids of the national programs, in file order.
static func program_ids() -> Array:
	return cfg.programs.keys().filter(func(k: String) -> bool: return not k.begins_with("_"))


## Summed fractional bonuses from a province's buildings and the owner's programs:
## gdp, industry, food, trade, growth and diplomacy.
static func modifiers(buildings: Dictionary, programs: Dictionary) -> Dictionary:
	var m := {"gdp": 0.0, "industry": 0.0, "food": 0.0, "trade": 0.0, "growth": 0.0, "diplomacy": 0.0}
	for type in buildings:
		for k in cfg.buildings[type].effects:
			m[k] += cfg.buildings[type].effects[k] * buildings[type]
	for id in programs:
		for k in cfg.programs[id].effects:
			m[k] += cfg.programs[id].effects[k]
	return m


## Output of one province before nation-wide modifiers (mobilization, famine, blockade).
## gdp, industry and trade are GBP millions/yr; food is people it can feed; pool is recruitable
## men; coal, iron and wood are extracted kt/yr; use_<resource> is what its buildings consume.
## `civ_base` is how many civilian factories the province held when the game began: the output
## the economy was calibrated with, so only factories beyond (or short of) it change the figures.
static func province_output(population: int, area_km2: float, nation: Nation, buildings := {}, deposit := {}, civ_base := 0) -> Dictionary:
	var density := population / maxf(area_km2, 1.0)
	var mod := clampf(pow(density / cfg.reference_density, cfg.density_exponent), cfg.density_min, cfg.density_max)
	var urban := inverse_lerp(cfg.density_min, cfg.density_max, mod)
	var fx := modifiers(buildings, nation.programs)
	var gdp: float = population * cfg.gdp_per_capita * nation.development * mod / 1e6 * (1.0 + fx.gdp)
	var industry: float = gdp * lerpf(cfg.industry_share_min, cfg.industry_share_max, urban) * (1.0 + fx.industry)
	# Factories beyond the calibrated base add their output; civilian ones turned military take it away.
	var factory_delta := float(buildings.get("factory", 0) - civ_base)
	var factory_gain: float = factory_delta * factory_output(nation)
	gdp += factory_gain
	industry += factory_gain
	var out := {
		"gdp": gdp,
		"industry": industry,
		"food": area_km2 * cfg.food_per_km2 * nation.agri_yield * (1.0 + fx.food),
		"trade": gdp * fx.trade,
		"pool": population * cfg.manpower_share,
		"factory_delta": factory_delta,
	}
	for r in resource_ids():
		out[r] = deposit.get(r, 0.0) * cfg.extraction_base if deposit.get(r, 0.0) >= cfg.min_deposit else 0.0
		out["use_" + r] = 0.0
	for type in buildings:
		for r in cfg.buildings[type].get("consumes", {}):
			out["use_" + r] += cfg.buildings[type].consumes[r] * buildings[type]
	return out


## A building (or retooling) in the queue: `rate` points a day at most, `build_days` times that
## in all. days_left is the estimate shown to the player: it is worked out each day from what the
## project is getting.
static func new_job(province: int, type: String, days: int, convert := false) -> Dictionary:
	var rate: float = cfg.buildings[type].get("rate", 10.0)
	var job := {"province": province, "type": type, "points_total": days * rate, "points_left": days * rate,
			"rate": rate, "given": 0.0, "days_total": days, "days_left": days}
	if convert:
		job["convert"] = true
	return job


## Ids of the economy laws, from peace to total war.
static func law_ids() -> Array:
	return cfg.laws.keys().filter(func(k: String) -> bool: return not k.begins_with("_") and k != "cooldown_days")


## The economy law a nation has (see data/economy.json, "laws").
static func law_of(n: Nation) -> Dictionary:
	return cfg.laws[n.economy_law] if cfg.laws.has(n.economy_law) else cfg.laws.civilian


## How heavy the taxes are, 0 to 1: the rate's distance above the default toward the maximum,
## squared, so a little above the default costs almost nothing and the top rate costs a lot.
static func tax_strain(n: Nation) -> float:
	var span: float = cfg.max_tax_rate - cfg.default_tax_rate
	return pow(clampf((n.tax_rate - cfg.default_tax_rate) / span, 0.0, 1.0), 2.0)


## The lowest and highest mobilization the law in force allows, as Vector2(min, max).
static func mobilization_range(n: Nation) -> Vector2:
	var r: Array = law_of(n).mobilization
	return Vector2(float(r[0]), float(r[1]))


## The highest mobilization a nation may have now: its law's, or the war floor if it is at war
## (a nation at war is held at a war footing whatever its law).
static func mobilization_cap(gs: Node, n: Nation) -> float:
	var cap := mobilization_range(n).y
	if not gs.wars_of(n.tag).is_empty():
		cap = maxf(cap, float(Diplomacy.cfg.crisis.war_floor))
	return cap


## The most the army and the navy may be funded under the law in force.
static func funding_cap(n: Nation) -> float:
	return float(law_of(n).funding)


## Brings both fundings under the law's ceiling (after the law came down).
static func clamp_funding(n: Nation) -> void:
	n.army_funding = clampf(n.army_funding, float(cfg.funding_min), funding_cap(n))
	n.navy_funding = clampf(n.navy_funding, float(cfg.funding_min), funding_cap(n))


## Share of the factories' work left after the workers called up (1 when nobody is).
static func worker_share(n: Nation) -> float:
	return 1.0 - float(cfg.mobilization_factory_penalty) * n.mobilization


## Share of the civilian factories' work that goes to the people's goods, not to building.
static func consumer_share(n: Nation) -> float:
	return law_of(n).consumer


## What stops a nation from having a law now, ignoring the wait between changes: "" if nothing.
static func law_requirement(gs: Node, tag: String, law: String) -> String:
	var n: Nation = gs.nations.get(tag)
	if n == null or not cfg.laws.has(law) or law == "cooldown_days" or law.begins_with("_"):
		return "Unknown law."
	var req: Dictionary = cfg.laws[law].requires
	var at_war: bool = not gs.wars_of(tag).is_empty()
	if req.get("war", false) and not at_war:
		return "Needs a war."
	if req.has("war_or_mobilization") and not at_war and n.mobilization < float(req.war_or_mobilization):
		return "Needs a war or %d%% mobilization." % roundi(float(req.war_or_mobilization) * 100.0)
	if req.has("mobilization") and n.mobilization < float(req.mobilization):
		return "Needs %d%% mobilization." % roundi(float(req.mobilization) * 100.0)
	return ""


## Why a nation cannot take a law now, or "" if it can: its requirements, and the wait before
## going to a higher law than the one in force.
static func law_problem(gs: Node, tag: String, law: String) -> String:
	var reason := law_requirement(gs, tag, law)
	if not reason.is_empty():
		return reason
	var n: Nation = gs.nations[tag]
	var ids := law_ids()
	if law == n.economy_law:
		return "Already in force."
	if ids.find(law) > ids.find(n.economy_law):
		var wait: int = int(cfg.laws.cooldown_days) - (Clock.days_elapsed - n.law_changed_day)
		if wait > 0:
			return "Wait %d more days." % wait
	return ""


## Monthly: a law whose requirements no longer hold (a war economy after the war) is dropped
## a step.
static func enforce_laws(gs: Node) -> void:
	var ids := law_ids()
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		var i := ids.find(n.economy_law)
		while i > 0 and not law_requirement(gs, tag, ids[i]).is_empty():
			i -= 1
		if ids[i] != n.economy_law:
			n.economy_law = ids[i]
			n.law_changed_day = Clock.days_elapsed
		clamp_funding(n)


## Construction points a nation can spend in a day, given the civilian factories it holds.
static func construction_points(n: Nation, factories: float) -> float:
	return cfg.construction.base_points + factories * cfg.construction.points_per_factory * (1.0 - consumer_share(n)) * worker_share(n)


## GBP millions a year one civilian factory pays the treasury (beyond the calibrated start).
static func factory_income(nation: Nation) -> float:
	return cfg.factories.income * nation.development * float(law_of(nation).gdp) * worker_share(nation)


## GBP millions a year of industrial output one civilian factory of this nation is worth.
static func factory_output(nation: Nation) -> float:
	return cfg.factories.output * nation.development


## Infrastructure of a province (see data/economy.json, "infrastructure"): its railway level plus
## a share of the best railway level of the neighbours its nation owns.
static func infrastructure(gs: Node, id: int) -> float:
	var own: int = gs.province_buildings[id].get("railway", 0)
	var best := 0
	var tag: String = gs.province_owner[id]
	for n: int in Military.neighbors(id):
		if gs.province_owner[n] == tag:
			best = maxi(best, gs.province_buildings[n].get("railway", 0))
	return own + float(cfg.infrastructure.network_share) * best


## Building slots of a province: its own (set when the game starts and raised as its people
## grow, see Population) and the ones its infrastructure adds (data/economy.json, "factories" and
## "infrastructure").
static func slots_of(gs: Node, id: int) -> int:
	if id >= gs.province_slots.size():
		return 0
	return gs.province_slots[id] + int(infrastructure(gs, id) * float(cfg.infrastructure.slots_per_level))


## Slots taken by factories already built and by those under construction.
static func slots_used(gs: Node, id: int) -> int:
	var used := 0
	for type in building_ids():
		if cfg.buildings[type].get("slot", false):
			used += gs.province_buildings[id].get(type, 0)
	for job in gs.nations[gs.province_owner[id]].construction:
		if job.province == id and cfg.buildings[job.type].get("slot", false):
			used += 1
	return used


## Gives every province its slots and its starting factories, from the industry it was
## calibrated with. Military factories go to a nation's most industrial provinces first.
static func deploy_factories(gs: Node) -> void:
	var count: int = gs.province_owner.size()
	gs.province_slots.resize(count)
	gs.province_civ_base.resize(count)
	var f: Dictionary = cfg.factories
	var by_nation := {}
	var exact := {}
	for id in range(1, count):
		var tag: String = gs.province_owner[id]
		var n: Nation = gs.nations[tag]
		var o := province_output(gs.province_population[id], MapData.provinces[id].area * MapData.KM2_PER_PX, n,
				gs.province_buildings[id], gs.province_deposit[id])
		gs.province_buildings[id].erase("factory")
		gs.province_buildings[id].erase("military_factory")
		exact[id] = o.industry / factory_output(n)
		if not by_nation.has(tag):
			by_nation[tag] = []
		by_nation[tag].append(id)
	# A nation's industry is shared out in whole factories, the biggest remainders getting the last ones.
	for tag in by_nation:
		var ids: Array = by_nation[tag]
		var total := 0.0
		for id: int in ids:
			total += exact[id]
		var left := roundi(total)
		for id: int in ids:
			var whole := int(exact[id])
			if whole > 0:
				gs.province_buildings[id]["factory"] = whole
			left -= whole
		var order := ids.duplicate()
		order.sort_custom(func(a: int, b: int) -> bool:
			var ra: float = exact[a] - int(exact[a])
			var rb: float = exact[b] - int(exact[b])
			return ra > rb or (ra == rb and a < b))
		for id: int in order:
			if left <= 0:
				break
			gs.province_buildings[id]["factory"] = gs.province_buildings[id].get("factory", 0) + 1
			left -= 1
	for id in range(1, count):
		var have: int = gs.province_buildings[id].get("factory", 0)
		gs.province_slots[id] = maxi(maxi(int(f.slot_min), ceili(float(gs.province_population[id]) / float(f.slot_pop))),
				have + ceili(have * float(f.slot_growth)))
	for tag in by_nation:
		var n: Nation = gs.nations[tag]
		var ids: Array = by_nation[tag]
		ids.sort_custom(func(a: int, b: int) -> bool:
			var fa: int = gs.province_buildings[a].get("factory", 0)
			var fb: int = gs.province_buildings[b].get("factory", 0)
			return fa > fb or (fa == fb and a < b))
		var wanted: int = int(gs.scenario.nations.get(tag, {}).get("military_factories", roundi(float(n.peacetime_army) / float(f.army_per_military_factory))))
		for id: int in ids:
			if wanted <= 0:
				break
			var civ: int = gs.province_buildings[id].get("factory", 0)
			# Never more than half of a province's factories, so no province is all arsenal.
			var take := mini(wanted, ceili(civ / 2.0))
			if take <= 0:
				continue
			gs.province_buildings[id]["factory"] = civ - take
			if civ - take == 0:
				gs.province_buildings[id].erase("factory")
			gs.province_buildings[id]["military_factory"] = take
			wanted -= take
	for id in range(1, count):
		gs.province_civ_base[id] = gs.province_buildings[id].get("factory", 0)


## Everything needed to start the next level of a building: gold, materials (thousand tonnes,
## drawn from stock first, the rest bought at a markup), the total gold bill and any blocker.
static func build_plan(gs: Node, id: int, type: String) -> Dictionary:
	var def: Dictionary = cfg.buildings[type]
	var levels: int = 1 if def.get("slot", false) else gs.province_buildings[id].get(type, 0) + 1
	var n: Nation = gs.nations[gs.province_owner[id]]
	var plan := {"gold": def.cost * levels, "materials": {}, "from_stock": {}, "buy": {}, "purchase": 0.0, "total": 0.0, "blocked": ""}
	for r in def.get("materials", {}):
		var need: float = def.materials[r] * levels
		var use := minf(need, n.stock.get(r, 0.0))
		plan.materials[r] = need
		plan.from_stock[r] = use
		plan.buy[r] = need - use
		if need - use > 0.0:
			if n.blockade >= 0.5:
				plan.blocked = "Blockade stops %s imports" % cfg.resources[r].name.to_lower()
			plan.purchase += (need - use) * cfg.resources[r].price / 1000.0 * cfg.import_markup
	plan.total = plan.gold + plan.purchase
	return plan


## Why a building cannot be started now, or "" if it can. With check_money false the
## treasury is ignored (used to list where something could be built).
static func build_problem(gs: Node, tag: String, id: int, type: String, check_money := true) -> String:
	var n: Nation = gs.nations.get(tag)
	if n == null or not cfg.buildings.has(type) or type.begins_with("_"):
		return "Unknown nation or building"
	if id < 1 or id >= gs.province_owner.size() or gs.province_owner[id] != tag:
		return "Not your province"
	if gs.province_controller[id] != tag:
		return "Province is occupied"
	var requires: String = cfg.buildings[type].get("requires", "")
	if requires == "coastal" and not MapData.provinces[id].coastal:
		return "Needs a coastal province"
	if requires == "capital" and id != n.capital:
		return "Only in the capital"
	if requires.begins_with("deposit:"):
		var r := requires.trim_prefix("deposit:")
		if gs.province_deposit[id].get(r, 0.0) < cfg.min_deposit:
			return "No %s deposit here" % cfg.resources[r].name.to_lower()
	var level: int = gs.province_buildings[id].get(type, 0)
	if cfg.buildings[type].get("slot", false):
		if slots_used(gs, id) >= slots_of(gs, id):
			return "No free slot"
	else:
		for job in n.construction:
			if job.province == id and job.type == type:
				return "Already under construction"
		if level >= cfg.buildings[type].max_level:
			return "Fully built"
	var plan := build_plan(gs, id, type)
	if not plan.blocked.is_empty():
		return plan.blocked
	if check_money and n.treasury < plan.total:
		return "Not enough money (£%.1fM)" % plan.total
	return ""


## How much a province gains from a building, for ranking where to build first: its economic
## output.
static func build_priority(gs: Node, id: int, type: String) -> float:
	return gs.province_gdp[id]


## Provinces of a nation where the next level of a building could be started (money aside),
## best first.
static func mass_candidates(gs: Node, tag: String, type: String) -> Array[int]:
	var ids: Array[int] = []
	for id in gs.nations[tag].provinces:
		if build_problem(gs, tag, id, type, false).is_empty():
			ids.append(id)
	ids.sort_custom(func(a: int, b: int) -> bool: return build_priority(gs, a, type) > build_priority(gs, b, type))
	return ids


## Gold cost of the next level of a building, not counting materials.
static func build_cost(gs: Node, id: int, type: String) -> float:
	if cfg.buildings[type].get("slot", false):
		return cfg.buildings[type].cost
	return cfg.buildings[type].cost * (gs.province_buildings[id].get(type, 0) + 1)


## Rebuilds per-province output and every nation's budget from the current state.
static func recompute(gs: Node) -> void:
	var count: int = gs.province_owner.size()
	for arr: PackedFloat32Array in [gs.province_gdp, gs.province_industry, gs.province_food, gs.province_pool]:
		arr.resize(count)

	var keys: Array = ["gdp", "industry", "food", "trade", "pool", "factories", "military_factories", "factory_delta"]
	for r in resource_ids():
		keys.append(r)
		keys.append("use_" + r)
	var sums := {}
	for tag in gs.nations:
		sums[tag] = {}
		for k in keys:
			sums[tag][k] = 0.0
	for id in range(1, count):
		var tag: String = gs.province_owner[id]
		var o := province_output(gs.province_population[id], MapData.provinces[id].area * MapData.KM2_PER_PX,
				gs.nations[tag], gs.province_buildings[id], gs.province_deposit[id], gs.province_civ_base[id])
		gs.province_gdp[id] = o.gdp
		gs.province_industry[id] = o.industry
		gs.province_food[id] = o.food
		gs.province_pool[id] = o.pool
		var holder: String = gs.province_controller[id]
		if holder == tag:
			for k in keys:
				if o.has(k):
					sums[tag][k] += o[k]
			sums[tag].factories += gs.province_buildings[id].get("factory", 0)
			sums[tag].military_factories += gs.province_buildings[id].get("military_factory", 0)
		else:
			# Occupied: the owner loses the output (its people still need feeding) and the
			# occupier collects a share of the tax.
			sums[holder].gdp += o.gdp * Military.cfg.occupation.income_share

	Navy.refresh_upkeep(gs)
	for tag in gs.nations:
		gs.nations[tag].budget = nation_budget(gs.nations[tag], sums[tag], WarSupport.economy_mult(gs, tag))


## Budget of one nation given its summed province output.
static func nation_budget(n: Nation, raw: Dictionary, tax_mult := 1.0) -> Dictionary:
	var mob_mult: float = 1.0 - cfg.mobilization_output_penalty * n.mobilization

	var food_production: float = raw.food * mob_mult
	var food_need := float(n.population)
	var food_deficit := maxf(0.0, food_need - food_production)
	var food_imported := food_deficit * (1.0 - n.blockade)
	var food_shortage := (food_deficit - food_imported) / maxf(food_need, 1.0)

	# Raw resources: produce, consume, then import the gap or export the surplus.
	var res := {}
	var export_income := 0.0
	var import_cost := 0.0
	var industry_penalty := 0.0
	var gdp_penalty := 0.0
	for r in resource_ids():
		var def: Dictionary = cfg.resources[r]
		var production: float = raw[r] * mob_mult
		var demand: float = (raw.industry * def.industry_demand + n.population * def.pop_demand) 				* n.intensity.get(r, 1.0) + raw["use_" + r]
		var balance := production - demand
		var cap: float = demand * cfg.stockpile_months / 12.0
		var stock: float = n.stock.get(r, 0.0)
		var info := {"production": production, "demand": demand, "balance": balance, "stock": stock, "cap": cap,
				"exported": 0.0, "imported": 0.0, "fill": 0.0, "draw": 0.0, "shortage": 0.0}
		if balance >= 0.0:
			if stock < cap:
				info.fill = minf((cap - stock) * 12.0, balance * cfg.stockpile_share)
			info.exported = (balance - info.fill) * (1.0 - n.blockade)
		else:
			var deficit := -balance
			info.imported = deficit * (1.0 - n.blockade)
			var unmet: float = (deficit - info.imported) / 12.0  # per month
			info.draw = minf(unmet, stock)
			info.shortage = (unmet - info.draw) / maxf(demand / 12.0, 1.0)
		export_income += info.exported * def.price / 1000.0 * cfg.trade_state_share
		import_cost += info.imported * def.price / 1000.0 * cfg.trade_state_share
		industry_penalty += info.shortage * def.shortage.industry
		gdp_penalty += info.shortage * def.shortage.gdp
		res[r] = info
	var resource_industry_mult := maxf(0.2, 1.0 - industry_penalty)
	var resource_gdp_mult := maxf(0.5, 1.0 - gdp_penalty)

	var output_mult: float = mob_mult * (1.0 - cfg.famine_output_penalty * food_shortage)
	var gdp_scale: float = output_mult * resource_gdp_mult * (1.0 - cfg.blockade_trade_loss * n.blockade) * float(law_of(n).gdp)
	var industry_scale: float = output_mult * resource_industry_mult
	var gdp: float = raw.gdp * gdp_scale
	var trade_scale := output_mult * (1.0 - n.blockade)
	var trade: float = raw.trade * trade_scale

	var tax_drag: float = 1.0 - cfg.tax_drag * maxf(0.0, n.tax_rate - cfg.default_tax_rate)
	var revenue_per_gdp := n.tax_rate * tax_drag
	var factory_money: float = raw.factory_delta * factory_income(n)
	var revenue := gdp * revenue_per_gdp * tax_mult + trade + export_income + factory_money

	var civil: float = raw.gdp * cfg.default_tax_rate * cfg.civil_share
	var army: float = n.total_men() * cfg.soldier_upkeep / 1e6 * n.army_funding
	var naval: float = n.naval_budget * n.navy_funding
	# The whole economy buys the food; the treasury only carries its share (subsidies, duties).
	var food_imports: float = food_imported * cfg.food_import_cost * cfg.food_state_share / 1e6
	var programs := 0.0
	for id in n.programs:
		programs += cfg.programs[id].cost_gdp_share * raw.gdp
	var equipment := Production.planned_spend(n)
	var expenses := civil + army + naval + food_imports + import_cost + programs + equipment

	var pool: float = raw.pool
	var peace := minf(n.peacetime_army, pool)
	return {
		"gdp": gdp,
		"industry": raw.industry * industry_scale,
		"revenue": revenue,
		"trade": trade,
		"resource_exports": export_income,
		"factory_income": factory_money,
		"resource_imports": import_cost,
		"resources": res,
		"gdp_scale": gdp_scale,
		"trade_scale": trade_scale,
		"industry_scale": industry_scale,
		"food_scale": mob_mult,
		"output_scale": output_mult,
		"revenue_per_gdp": revenue_per_gdp,
		"civil": civil,
		"army": army,
		"naval": naval,
		"food_imports": food_imports,
		"programs": programs,
		"tax_strain": tax_strain(n),
		"equipment": equipment,
		"expenses": expenses,
		"net": revenue - expenses,
		"food_production": food_production,
		"food_need": food_need,
		"food_imported": food_imported,
		"food_shortage": food_shortage,
		"factories": raw.factories,
		"military_factories": raw.military_factories,
		"construction_points": construction_points(n, raw.factories),
		"law": n.economy_law,
		"consumer_share": consumer_share(n),
		"manpower_pool": pool,
		"manpower_max": peace + (pool - peace) * n.mobilization,
	}


## Yearly money value of an amount of a resource to the state (its share of the trade).
static func resource_value(r: String, kt: float) -> float:
	return kt * cfg.resources[r].price / 1000.0 * cfg.trade_state_share


## What each building type currently contributes to a nation, per year: levels, provinces,
## gdp, industry, trade (GBP millions), food (people fed), extracted kt per resource, kt of
## each resource it consumes (uses), and income (tax on its output, trade, and the value of
## the resources it extracts). Each figure is the difference the building makes, with the
## nation's modifiers applied.
static func building_stats(gs: Node, tag: String) -> Dictionary:
	var n: Nation = gs.nations[tag]
	var b := n.budget
	var stats := {}
	for type in building_ids():
		var st := {"levels": 0, "provinces": 0, "gdp": 0.0, "industry": 0.0, "trade": 0.0, "food": 0.0, "income": 0.0, "uses": {}}
		for r in resource_ids():
			st[r] = 0.0
		stats[type] = st
	for id in n.provinces:
		var owned: Dictionary = gs.province_buildings[id]
		if owned.is_empty():
			continue
		var pop: int = gs.province_population[id]
		var area: float = MapData.provinces[id].area * MapData.KM2_PER_PX
		var deposit: Dictionary = gs.province_deposit[id]
		var base: int = gs.province_civ_base[id]
		var with := province_output(pop, area, n, owned, deposit, base)
		for type in owned:
			var without_set := owned.duplicate()
			without_set.erase(type)
			var without := province_output(pop, area, n, without_set, deposit, base)
			var st: Dictionary = stats[type]
			st.levels += owned[type]
			st.provinces += 1
			st.gdp += (with.gdp - without.gdp) * b.gdp_scale
			st.industry += (with.industry - without.industry) * b.industry_scale
			st.trade += (with.trade - without.trade) * b.trade_scale
			st.food += (with.food - without.food) * b.food_scale
			for r in resource_ids():
				st[r] += (with[r] - without[r]) * b.food_scale
				var used: float = with["use_" + r] - without["use_" + r]
				if used > 0.0:
					st.uses[r] = st.uses.get(r, 0.0) + used
	for type in stats:
		var st: Dictionary = stats[type]
		st.income = st.gdp * b.revenue_per_gdp + st.trade
		for r in resource_ids():
			st.income += resource_value(r, st[r])
	return stats


## Daily update: advances construction and completes finished buildings.
static func step_day(gs: Node) -> void:
	var finished := false
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		if n.construction.is_empty():
			n.construction_used = 0.0
			continue
		# The queue is served in order: each project takes what it can use of the day's points.
		var pool: float = n.budget.get("construction_points", cfg.construction.base_points)
		var left := pool
		for job in n.construction:
			var give := minf(minf(job.rate, left), job.points_left)
			left -= give
			job.points_left -= give
			job.given = give
		n.construction_used = pool - left
		for i in range(n.construction.size() - 1, -1, -1):
			var job := n.construction[i]
			if job.points_left <= 0.0001:
				n.construction.remove_at(i)
				var owned: Dictionary = gs.province_buildings[job.province]
				owned[job.type] = owned.get(job.type, 0) + 1
				gs.building_completed.emit(tag, job.province, job.type)
				finished = true
			else:
				var rate_now: float = job.given if job.given > 0.0 else 0.0
				job.days_left = ceili(job.points_left / rate_now) if rate_now > 0.0 else 9999
	if finished:
		recompute(gs)
		gs.economy_updated.emit()


## Monthly update: pays the budget, moves the stockpiles, grows the economy and refills
## manpower toward its cap.
static func step_month(gs: Node) -> void:
	Population.step_month(gs)
	enforce_laws(gs)
	Military.refresh_men(gs)
	recompute(gs)
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		var b := n.budget
		# The lines pay for equipment out of the treasury each day (Production), so the month
		# does not take it again.
		n.treasury += (b.net + b.equipment) / 12.0

		for r in b.resources:
			var info: Dictionary = b.resources[r]
			n.stock[r] = maxf(0.0, n.stock.get(r, 0.0) + info.fill / 12.0 - info.draw)

		var growth: float = (cfg.baseline_growth + modifiers({}, n.programs).growth - cfg.tax_strain.growth_penalty * tax_strain(n)) / 12.0
		n.development *= 1.0 + growth

		# The cap covers everyone in service; what is not under arms is the reserve.
		var cap := maxi(0, int(b.manpower_max) - n.men_in_units)
		if n.manpower < cap:
			n.manpower = mini(cap, n.manpower + int(b.manpower_pool * cfg.mobilization_rate * WarSupport.economy_mult(gs, tag)))
		else:
			n.manpower = cap
	recompute(gs)
