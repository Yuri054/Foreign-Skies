class_name Economy
extends RefCounted
## The economy has three pillars (data/economy.json says how each is worked out):
##   MONEY, GBP millions a year: tax on the nation's output pays the army, the navy, the state's other
##   costs, food and raw-material imports and interest on debt. GameState applies a twelfth a month.
##   INDUSTRY, construction points (IC) a day: the industrial output of the nation's provinces, after its
##   supply of raw materials and the workers left, one queue of buildings and ships.
##   MANPOWER: a pool from the people, drawn on by raising units, refilled monthly toward what
##   mobilization allows.
## Province output comes from people, density, deposits, the owner's development, the buildings
## and the national focus. Raw materials are one number: a nation's own deposits against what its
## industry needs, the shortfall imported (unless blockaded). Food is a separate check on famine.

const CONFIG_PATH := "res://data/economy.json"

static var cfg: Dictionary = {}


static func load_config() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	assert(cfg is Dictionary, "economy.json is invalid")


## Ids of the deposit tables of a province (coal, iron, timber), in file order.
static func resource_ids() -> Array:
	return cfg.resources.keys().filter(func(k: String) -> bool: return not k.begins_with("_"))


static func deposit_ids() -> Array:
	return resource_ids()


## Ids of the building types, in file order.
static func building_ids() -> Array:
	return cfg.buildings.keys().filter(func(k: String) -> bool: return not k.begins_with("_"))


## Summed fractional bonuses from a province's buildings and the owner's national focus:
## gdp, industry, food, trade, growth.
static func modifiers(buildings: Dictionary, focus_fx := {}) -> Dictionary:
	var m := {"gdp": 0.0, "industry": 0.0, "food": 0.0, "trade": 0.0, "growth": 0.0}
	for type in buildings:
		for k in cfg.buildings[type].effects:
			m[k] += cfg.buildings[type].effects[k] * buildings[type]
	for k in m:
		m[k] += focus_fx.get(k, 0.0)
	return m


## Output of one province before nation-wide modifiers (mobilization, famine, blockade): gdp,
## industry and trade are GBP millions a year; food is the people it can feed; pool is recruitable
## men; materials is the kt a year its deposits give.
static func province_output(population: int, area_km2: float, nation: Nation, buildings := {}, deposit := {}) -> Dictionary:
	var density := population / maxf(area_km2, 1.0)
	var mod := clampf(pow(density / cfg.reference_density, cfg.density_exponent), cfg.density_min, cfg.density_max)
	var urban := inverse_lerp(cfg.density_min, cfg.density_max, mod)
	var fx := modifiers(buildings, nation.focus_fx)
	var gdp: float = population * cfg.gdp_per_capita * nation.development * mod / 1e6 * (1.0 + fx.gdp)
	var industry: float = gdp * lerpf(cfg.industry_share_min, cfg.industry_share_max, urban) * (1.0 + fx.industry)
	var materials := 0.0
	for r in resource_ids():
		var have: float = deposit.get(r, 0.0)
		if have >= cfg.materials.min_deposit:
			materials += have * cfg.materials.extraction_base
	return {
		"gdp": gdp,
		"industry": industry,
		"food": area_km2 * cfg.food_per_km2 * nation.agri_yield * (1.0 + fx.food),
		"trade": gdp * fx.trade,
		"pool": population * cfg.manpower_share,
		"materials": materials,
	}


## A project in the queue: it costs `ic` and takes in at most ic / min_days a day. days_left is
## the estimate shown to the player: it is worked out each day from what the project is getting.
static func new_job(province: int, type: String, ic: float, min_days: int) -> Dictionary:
	var rate := ic / maxf(float(min_days), 1.0)
	return {"province": province, "type": type, "points_total": ic, "points_left": ic,
			"rate": rate, "given": 0.0, "days_total": min_days, "days_left": min_days}


## How heavy the taxes are, 0 to 1: the rate's distance above the default toward the maximum,
## squared, so a little above the default costs almost nothing and the top rate costs a lot.
static func tax_strain(n: Nation) -> float:
	var span: float = cfg.max_tax_rate - cfg.default_tax_rate
	return pow(clampf((n.tax_rate - cfg.default_tax_rate) / span, 0.0, 1.0), 2.0)


## The lowest and highest mobilization a nation may have now, as Vector2(min, max): in peace 0 to
## peace_max, at war up to 1 and no lower than the war floor.
static func mobilization_range(gs: Node, n: Nation) -> Vector2:
	if gs.wars_of(n.tag).is_empty():
		return Vector2(0.0, float(cfg.mobilization.peace_max))
	return Vector2(float(Diplomacy.cfg.crisis.war_floor), 1.0)


## The highest mobilization a nation may have now.
static func mobilization_cap(gs: Node, n: Nation) -> float:
	return mobilization_range(gs, n).y


## Brings mobilization inside the range now allowed (after a war ends).
static func clamp_mobilization(gs: Node, n: Nation) -> void:
	var r := mobilization_range(gs, n)
	n.mobilization = clampf(n.mobilization, r.x, r.y)


## Share of the industry's work left after the people called up, in a famine the hunger, and in a long
## war the weariness.
static func worker_share(n: Nation) -> float:
	var armed := float(n.men_in_units) / maxf(float(n.population), 1.0)
	var share := maxf(float(cfg.labor.floor), 1.0 - float(cfg.labor.penalty) * armed - n.weariness)
	if n.starving:
		share *= 1.0 - float(cfg.starvation.output)
	return share


## Infrastructure of a province: its railway level plus network_share of the best railway level of
## the neighbours its nation owns (read by Military for supply and movement).
static func infrastructure(gs: Node, id: int) -> float:
	var own: int = gs.province_buildings[id].get("railway", 0)
	var best := 0
	var tag: String = gs.province_owner[id]
	for n: int in Military.neighbors(id):
		if gs.province_owner[n] == tag:
			best = maxi(best, gs.province_buildings[n].get("railway", 0))
	return own + 0.5 * best


## The cost of the next level of a building in IC: the first level costs `ic` and each further level
## `ic_growth` more than the one before it.
static func level_cost(gs: Node, id: int, type: String) -> float:
	var def: Dictionary = cfg.buildings[type]
	var level: int = gs.province_buildings[id].get(type, 0)
	return float(def.ic) * pow(1.0 + float(def.get("ic_growth", 0.0)), level)


## Everything needed to start the next level of a building: its cost in IC, the fewest days it takes,
## and a money-equivalent `total` (the IC at `ic_value`, so the AI can weigh buildings against each
## other). Nothing is paid in money.
static func build_plan(gs: Node, id: int, type: String) -> Dictionary:
	var ic := level_cost(gs, id, type)
	return {"ic": ic, "days": int(cfg.buildings[type].min_days), "gold": 0.0, "total": ic * float(cfg.ic_value), "blocked": ""}


## Why a building cannot be started now, or "" if it can. `_check_money` is kept for the callers
## that pass it: buildings cost no money.
static func build_problem(gs: Node, tag: String, id: int, type: String, _check_money := true) -> String:
	var n: Nation = gs.nations.get(tag)
	if n == null or not cfg.buildings.has(type) or type.begins_with("_"):
		return "Unknown nation or building"
	var def: Dictionary = cfg.buildings[type]
	if not def.get("enabled", true):
		return "Not available yet"
	if id < 1 or id >= gs.province_owner.size() or gs.province_owner[id] != tag:
		return "Not your province"
	if gs.province_controller[id] != tag:
		return "Province is occupied"
	if def.get("requires", "") == "coastal" and not MapData.provinces[id].coastal:
		return "Needs a coastal province"
	for job in n.construction:
		if job.province == id and job.type == type:
			return "Already under construction"
	if gs.province_buildings[id].get(type, 0) >= def.max_level:
		return "Fully built"
	return ""


## How much a province gains from a building, for ranking where to build first: its output.
static func build_priority(gs: Node, id: int, type: String) -> float:
	if type == "factory":
		return gs.province_industry[id]
	return gs.province_gdp[id]


## Provinces of a nation where the next level of a building could be started, best first.
static func mass_candidates(gs: Node, tag: String, type: String) -> Array[int]:
	var ids: Array[int] = []
	for id in gs.nations[tag].provinces:
		if build_problem(gs, tag, id, type, false).is_empty():
			ids.append(id)
	ids.sort_custom(func(a: int, b: int) -> bool: return build_priority(gs, a, type) > build_priority(gs, b, type))
	return ids


## IC cost of the next level of a building.
static func build_cost(gs: Node, id: int, type: String) -> float:
	return level_cost(gs, id, type)


# ------------------------------------------------------------------ province output and budgets

static var _output_cache: Dictionary = {}
static var _output_owner := 0


## Rebuilds per-province output and every nation's budget from the current state.
static func recompute(gs: Node) -> void:
	var count: int = gs.province_owner.size()
	for arr: PackedFloat32Array in [gs.province_gdp, gs.province_industry, gs.province_food, gs.province_pool]:
		arr.resize(count)
	var keys := ["gdp", "industry", "food", "trade", "pool", "materials"]
	var sums := {}
	for tag in gs.nations:
		sums[tag] = {"coast": 0.0}
		for k in keys:
			sums[tag][k] = 0.0
	# A province's output follows from its people, buildings, deposits and its owner's modifiers, and those
	# change seldom (people monthly, buildings now and then): what was worked out for the same inputs
	# last time is used again, so a recompute costs the provinces that changed.
	if _output_owner != gs.get_instance_id():
		_output_cache.clear()
		_output_owner = gs.get_instance_id()
	var nation_inputs := {}
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		nation_inputs[tag] = [n.development, n.agri_yield, n.focus_fx]
	for id in range(1, count):
		var tag: String = gs.province_owner[id]
		var inputs := [gs.province_population[id], gs.province_buildings[id], gs.province_deposit[id], nation_inputs[tag]]
		var cached: Variant = _output_cache.get(id)
		var o: Dictionary
		if cached != null and cached.inputs == inputs:
			o = cached.out
		else:
			o = province_output(gs.province_population[id], MapData.provinces[id].area * MapData.KM2_PER_PX,
					gs.nations[tag], gs.province_buildings[id], gs.province_deposit[id])
			_output_cache[id] = {"inputs": inputs.duplicate(true), "out": o}
		gs.province_gdp[id] = o.gdp
		gs.province_industry[id] = o.industry
		gs.province_food[id] = o.food
		gs.province_pool[id] = o.pool
		var holder: String = gs.province_controller[id]
		if holder == tag:
			for k in keys:
				sums[tag][k] += o[k]
			if MapData.provinces[id].coastal:
				sums[tag].coast += 1.0
		else:
			# Occupied: the owner loses the output (its people still need feeding) and the
			# occupier collects a share of the tax.
			sums[holder].gdp += o.gdp * Military.cfg.occupation.income_share
	gs.economy_sums = sums
	if gs.materials_k <= 0.0:
		calibrate(gs)
	_budgets(gs)


## Calibrates a scenario at its start: the kt of raw materials a year one GBP million of industrial
## output needs, so that the world just balances (all deposits against all industry), and each nation's
## civil spending, so that its budget just balances. Read again on every load.
static func calibrate(gs: Node) -> void:
	_calibrate_materials(gs)
	for tag in gs.nations:
		gs.nations[tag].civil_mult = 1.0
	_budgets(gs)
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		var civil: float = n.budget.civil
		if civil > 0.0:
			n.civil_mult = clampf((n.budget.net + civil) / civil, 0.1, 4.0)


static func _calibrate_materials(gs: Node) -> void:
	var own := 0.0
	var industry := 0.0
	for id in range(1, gs.province_owner.size()):
		own += gs.province_deposit[id].values().filter(func(v: float) -> bool: return v >= cfg.materials.min_deposit).reduce(func(a: float, b: float) -> float: return a + b, 0.0) * float(cfg.materials.extraction_base)
		industry += gs.province_industry[id]
	gs.materials_k = own / industry if industry > 0.0 else float(cfg.materials.need_per_industry)


static func _budgets(gs: Node) -> void:
	Navy.refresh_upkeep(gs)
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		n.budget = nation_budget(gs, n, gs.economy_sums[tag], WarSupport.economy_mult(gs, tag))


## The economy has changed: recompute now, or, in the middle of the daily step, once at its end (see GameState.in_day_step).
static func request(gs: Node) -> void:
	if gs.in_day_step:
		gs.economy_dirty = true
	else:
		recompute(gs)
		gs.economy_updated.emit()


## Works out the budgets again now, from the last province sums.
static func refresh_now(gs: Node) -> void:
	if not gs.economy_sums.is_empty():
		_budgets(gs)


## The daily refresh of the budgets, without going through the provinces again.
static func refresh(gs: Node) -> void:
	if not gs.economy_sums.is_empty():
		_budgets(gs)


## A nation's raw materials: its own supply, what it needs, what it imports (the shortfall up to
## import_cap of the need, cut by the blockade), what it sells, and the share of its need it has.
static func materials_of(gs: Node, n: Nation, raw: Dictionary) -> Dictionary:
	var c: Dictionary = cfg.materials
	var own: float = raw.materials
	var need: float = raw.industry * gs.materials_k * n.materials_need_mult
	var short := maxf(0.0, need - own)
	var imported := minf(short, need * float(c.import_cap)) * (1.0 - n.blockade)
	var supply := own + imported
	var ratio := 1.0 if need <= 0.0 else minf(1.0, supply / need)
	var exported := maxf(0.0, own - need)
	return {"own": own, "need": need, "imported": imported, "exported": exported, "ratio": ratio,
			"cost": imported * float(c.import_price) * float(c.import_markup) / 1000.0,
			"income": exported * float(c.import_price) * float(c.export_share) / 1000.0}


## Budget of one nation given its summed province output.
static func nation_budget(gs: Node, n: Nation, raw: Dictionary, tax_mult: float) -> Dictionary:
	var mob_mult: float = 1.0 - cfg.mobilization_output_penalty * n.mobilization

	var food_production: float = raw.food * mob_mult
	var food_need := float(n.population)
	var food_deficit := maxf(0.0, food_need - food_production)
	var food_imported := food_deficit * (1.0 - n.blockade)
	var food_shortage := (food_deficit - food_imported) / maxf(food_need, 1.0)

	var mats := materials_of(gs, n, raw)
	var materials_mult := maxf(float(cfg.materials.floor), float(mats.ratio))

	var output_mult: float = mob_mult * (1.0 - cfg.famine_output_penalty * food_shortage)
	var gdp_scale: float = output_mult * (1.0 - cfg.blockade_trade_loss * n.blockade) * lerpf(1.0, materials_mult, 0.4)
	var industry_scale: float = output_mult * materials_mult * worker_share(n)
	var gdp: float = raw.gdp * gdp_scale
	var industry: float = raw.industry * industry_scale
	var trade_scale := output_mult * (1.0 - n.blockade)
	var trade: float = raw.trade * trade_scale

	var tax_drag: float = 1.0 - cfg.tax_drag * maxf(0.0, n.tax_rate - cfg.default_tax_rate)
	var revenue_per_gdp := n.tax_rate * tax_drag
	var revenue: float = gdp * revenue_per_gdp * tax_mult + trade + float(mats.income)

	var civil: float = raw.gdp * cfg.default_tax_rate * cfg.civil_share * n.civil_mult
	var army: float = (n.men_in_units + n.manpower * float(cfg.reserve_upkeep)) * cfg.soldier_upkeep / 1e6
	var naval: float = n.naval_budget
	# The whole economy buys the food; the treasury only carries its share (subsidies, duties).
	var food_imports: float = food_imported * cfg.food_import_cost * cfg.food_state_share / 1e6
	var interest: float = maxf(0.0, -n.treasury) * float(cfg.debt.interest)
	var expenses: float = civil + army + naval + food_imports + float(mats.cost) + interest

	var pool: float = raw.pool
	var peace := minf(n.peacetime_army, pool)
	return {
		"gdp": gdp,
		"industry": industry,
		"revenue": revenue,
		"trade": trade,
		"materials": mats,
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
		"materials_cost": mats.cost,
		"interest": interest,
		"tax_strain": tax_strain(n),
		"expenses": expenses,
		"net": revenue - expenses,
		"food_production": food_production,
		"food_need": food_need,
		"food_imported": food_imported,
		"food_shortage": food_shortage,
		"construction_points": construction_points(n, industry),
		"manpower_pool": pool,
		"manpower_max": peace + (pool - peace) * n.mobilization,
	}


## Construction points (IC) a nation can spend in a day: the works everywhere, the focus's addition and
## the industrial output (after materials and workers) times ic_per_industry.
static func construction_points(n: Nation, industry: float) -> float:
	return float(cfg.construction.base_ic) + float(n.focus_fx.get("construction", 0.0)) + industry * float(cfg.construction.ic_per_industry)


## What each building type currently contributes to a nation, per year: levels, provinces, gdp, industry,
## trade (GBP millions), food (people fed) and income (tax on its output plus trade). Each figure is the
## difference the building makes, with the nation's modifiers applied.
static func building_stats(gs: Node, tag: String) -> Dictionary:
	var n: Nation = gs.nations[tag]
	var b := n.budget
	var stats := {}
	for type in building_ids():
		stats[type] = {"levels": 0, "provinces": 0, "gdp": 0.0, "industry": 0.0, "trade": 0.0, "food": 0.0, "income": 0.0}
	for id in n.provinces:
		var owned: Dictionary = gs.province_buildings[id]
		if owned.is_empty():
			continue
		var pop: int = gs.province_population[id]
		var area: float = MapData.provinces[id].area * MapData.KM2_PER_PX
		var deposit: Dictionary = gs.province_deposit[id]
		var with := province_output(pop, area, n, owned, deposit)
		for type in owned:
			var without_set := owned.duplicate()
			without_set.erase(type)
			var without := province_output(pop, area, n, without_set, deposit)
			var st: Dictionary = stats[type]
			st.levels += owned[type]
			st.provinces += 1
			st.gdp += (with.gdp - without.gdp) * b.gdp_scale
			st.industry += (with.industry - without.industry) * b.industry_scale
			st.trade += (with.trade - without.trade) * b.trade_scale
			st.food += (with.food - without.food) * b.food_scale
	for type in stats:
		var st: Dictionary = stats[type]
		st.income = st.gdp * b.revenue_per_gdp + st.trade
	return stats


# ------------------------------------------------------------------ the day and the month

## Daily update: refreshes the budgets, advances construction and completes finished buildings.
static func step_day(gs: Node) -> void:
	_pressures(gs)
	refresh(gs)
	var finished := false
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		if n.construction.is_empty() and n.shipbuilding.is_empty():
			n.construction_used = 0.0
			continue
		# The queue is served in order: each project takes what it can use of the day's capacity.
		# Hulls on the slips come first, then the buildings.
		var pool: float = n.budget.get("construction_points", cfg.construction.base_ic)
		var left := pool
		for job in n.shipbuilding:
			var give := minf(minf(job.rate, left), job.points_left)
			left -= give
			job.points_left -= give
			job.given = give
			job.days_left = ceili(job.points_left / give) if give > 0.0 and job.points_left > 0.0 else (0 if job.points_left <= 0.0 else 9999)
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


## The daily macro pressures: war weariness (the share of the workers lost for every 100,000 men
## lost, easing in peace) and starvation (a nation that needs imports and gets under 30% of them
## through the blockade loses output and war support).
static func _pressures(gs: Node) -> void:
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		var w: Dictionary = cfg.weariness
		var target := minf(float(w.max), (n.war_dead + n.deaths_month) / 100000.0 * float(w.per_100k))
		if gs.wars_of(tag).is_empty():
			n.weariness = maxf(0.0, n.weariness - float(w.ease_per_day))
		else:
			n.weariness = maxf(n.weariness, target)
		var b: Dictionary = n.budget
		var needs_imports: bool = b.get("food_need", 0.0) > b.get("food_production", 0.0)
		if not needs_imports and b.has("materials") and b.materials.need > b.materials.own:
			needs_imports = true
		var s: Dictionary = cfg.starvation
		n.starving = needs_imports and (1.0 - n.blockade) < float(s.below)
		if n.starving:
			WarSupport.change(gs, tag, -float(s.support_per_day))


## Monthly update: pays the budget, grows the economy and refills manpower toward its cap.
static func step_month(gs: Node) -> void:
	Population.step_month(gs)
	for tag in gs.nations:
		clamp_mobilization(gs, gs.nations[tag])
	Military.refresh_men(gs)
	recompute(gs)
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		var b := n.budget
		n.treasury += b.net / 12.0

		var growth: float = (cfg.baseline_growth + modifiers({}, n.focus_fx).growth - cfg.tax_strain.growth_penalty * tax_strain(n)) / 12.0
		n.development *= 1.0 + growth
		# The peacetime army of an AI nation grows with its people and its output (the player sets their own).
		if tag != gs.player_tag and gs.wars_of(tag).is_empty():
			n.peacetime_army = int(n.peacetime_army * (1.0 + (growth + n.pop_growth / 12.0) * float(cfg.army_growth_share)))

		# The cap covers everyone in service; what is not under arms is the reserve.
		var cap := maxi(0, int(b.manpower_max) - n.men_in_units)
		if n.manpower < cap:
			n.manpower = mini(cap, n.manpower + int(b.manpower_pool * cfg.mobilization_rate * WarSupport.economy_mult(gs, tag)))
		else:
			n.manpower = cap
	recompute(gs)
