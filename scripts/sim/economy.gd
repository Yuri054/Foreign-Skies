class_name Economy
extends RefCounted
## The economy (data/economy.json): one currency, gold, and construction points (CP). Every flow is a month.
##   INCOME: each province's base income (from its people at the start, fixed), plus its civilian factories and ports,
##   times mobilization, blockade and war support. An occupied province pays its owner nothing and its occupier a share
##   of its base income.
##   EXPENSES: the army (each unit's upkeep, military.json), the navy, the buildings' upkeep and interest on debt.
##   CP: a stockpile. Construction sectors (and a little from the capital) add to it every day; starting a building
##   spends its gold and CP at once, and the building is finished after a fixed number of days. One project at a time in
##   a province, at most construction.max_level of each building in a province; the queue starts each project as soon as
##   its province is free and the gold and CP are there, in the order queued.
##   MANPOWER: a pool from the people, drawn on by raising units, refilled monthly toward what mobilization allows.
## The old resource economy (deposits, IC, materials, munitions, food, taxes, investment, growth) is described in
## docs/archive/RESOURCE_ECONOMY.md and kept on the branch archive/resource-economy.

const CONFIG_PATH := "res://data/economy.json"

static var cfg: Dictionary = {}


static func load_config() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	assert(cfg is Dictionary, "economy.json is invalid")


## Ids of the building types, in file order.
static func building_ids() -> Array:
	return cfg.buildings.keys().filter(func(k: String) -> bool: return not k.begins_with("_"))


static func max_level() -> int:
	return int(cfg.construction.max_level)


# ------------------------------------------------------------------ the scenario

## A scenario's start: every nation gets at least one civilian factory and one construction sector (in its capital, or
## its most populous province), so even the smallest can earn and build from the first day.
static func load_scenario(gs: Node) -> void:
	var s: Dictionary = cfg.start
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		if n.provinces.is_empty():
			continue
		var home := n.capital if n.capital > 0 and n.capital in n.provinces else n.provinces[0]
		for pair: Array in [["civilian_factory", int(s.min_civilian_factories)], ["construction_sector", int(s.min_construction_sectors)]]:
			var have := 0
			for id in n.provinces:
				have += int(gs.province_buildings[id].get(pair[0], 0))
			if have < pair[1]:
				gs.province_buildings[home][pair[0]] = int(gs.province_buildings[home].get(pair[0], 0)) + pair[1] - have


# ------------------------------------------------------------------ building

## Everything needed to start a level of a building: its gold, its CP and the days it takes (the same everywhere).
static func build_plan(_gs: Node, _id: int, type: String) -> Dictionary:
	var def: Dictionary = cfg.buildings[type]
	return {"gold": float(def.gold), "cp": float(def.cp), "days": int(def.days)}


## Levels of a building a province has, built and queued.
static func levels_planned(gs: Node, tag: String, id: int, type: String) -> int:
	var level: int = gs.province_buildings[id].get(type, 0)
	for job in gs.nations[tag].construction:
		if job.province == id and job.type == type:
			level += 1
	return level


## Why a building cannot be queued, or "" if it can. With `check_money`, also whether the gold and CP are there now (the
## AI asks before it queues; the player may queue what it cannot yet pay for, and it starts when it can).
static func build_problem(gs: Node, tag: String, id: int, type: String, check_money := false) -> String:
	var n: Nation = gs.nations.get(tag)
	if n == null or not cfg.buildings.has(type) or type.begins_with("_"):
		return "Unknown nation or building"
	var def: Dictionary = cfg.buildings[type]
	if id < 1 or id >= gs.province_owner.size() or gs.province_owner[id] != tag:
		return "Not your province"
	if gs.province_controller[id] != tag:
		return "Province is occupied"
	if def.get("requires", "") == "coastal" and not MapData.provinces[id].coastal:
		return "Needs a coastal province"
	if levels_planned(gs, tag, id, type) >= max_level():
		return "Fully built (%d)" % max_level()
	if check_money:
		var plan := build_plan(gs, id, type)
		if n.treasury < plan.gold:
			return "Not enough gold (%s)" % Fmt.gold(plan.gold)
		if n.cp < plan.cp:
			return "Not enough construction points (%d)" % roundi(plan.cp)
	return ""


## Whether a province already has a project under way (not one waiting in the queue).
static func province_busy(n: Nation, id: int) -> bool:
	for job in n.construction:
		if job.province == id and job.started:
			return true
	return false


## A project in the queue: waiting until it can be paid for and its province is free, then `days` long.
static func new_job(province: int, type: String, days: int) -> Dictionary:
	return {"province": province, "type": type, "started": false, "days_total": days, "days_left": days}


## How much a province gains from a building, for ranking where to build first: its people and what it already has.
static func build_priority(gs: Node, id: int, type: String) -> float:
	var b: Dictionary = gs.province_buildings[id]
	return float(gs.province_base_income[id]) + 0.1 * float(b.get(type, 0)) + 0.01 * float(b.get("civilian_factory", 0))


## Provinces of a nation where the next level of a building could be queued, best first.
static func mass_candidates(gs: Node, tag: String, type: String) -> Array[int]:
	var ids: Array[int] = []
	for id in gs.nations[tag].provinces:
		if build_problem(gs, tag, id, type).is_empty():
			ids.append(id)
	ids.sort_custom(func(a: int, b: int) -> bool: return build_priority(gs, a, type) > build_priority(gs, b, type))
	return ids


# ------------------------------------------------------------------ income and the budget

## A province's base income, gold a month: from its people at the start of the scenario, so it does not change.
static func base_income(population: float) -> float:
	var c: Dictionary = cfg.income
	return float(c.per_million) * pow(maxf(population, 0.0) / 1e6, float(c.exponent))


## What a province earns its owner a month before the nation's modifiers: its base income and its buildings' income.
static func province_income(gs: Node, id: int) -> float:
	var total: float = gs.province_base_income[id] if id < gs.province_base_income.size() else 0.0
	var built: Dictionary = gs.province_buildings[id]
	for type: String in built:
		total += float(cfg.buildings.get(type, {}).get("income", 0.0)) * float(built[type])
	return total


## Works the economy out again: each province's base income, and every nation's sums and budget.
static func recompute(gs: Node) -> void:
	var count: int = gs.province_owner.size()
	if gs.province_base_income.size() != count:
		gs.province_base_income.resize(count)
	for id in range(1, count):
		var pop: float = gs.province_pop_base[id] if id < gs.province_pop_base.size() else gs.province_population[id]
		gs.province_base_income[id] = base_income(pop)
	var sums := {}
	for tag in gs.nations:
		sums[tag] = {"base": 0.0, "occupied": 0.0, "factories": 0.0, "ports": 0.0, "upkeep": 0.0, "cp": 0.0, "pool": 0.0,
				"levels": {}}
	var b: Dictionary = cfg.buildings
	for id in range(1, count):
		var tag: String = gs.province_owner[id]
		if not sums.has(tag):
			continue
		var holder: String = gs.province_controller[id]
		var s: Dictionary = sums[tag]
		s.pool += float(gs.province_population[id]) * float(cfg.manpower_share)
		if holder != tag:
			if sums.has(holder):
				sums[holder].occupied += gs.province_base_income[id] * float(cfg.income.occupied_share)
			continue
		s.base += gs.province_base_income[id]
		var built: Dictionary = gs.province_buildings[id]
		for type: String in built:
			if not b.has(type):
				continue
			var level := float(built[type])
			s.levels[type] = float(s.levels.get(type, 0.0)) + level
			s.upkeep += float(b[type].get("upkeep", 0.0)) * level
			s.cp += float(b[type].get("cp_per_day", 0.0)) * level
			if type == "port":
				s.ports += float(b[type].income) * level
			elif b[type].has("income"):
				s.factories += float(b[type].income) * level
	gs.economy_sums = sums
	_budgets(gs)


static func _budgets(gs: Node) -> void:
	Navy.refresh_upkeep(gs)
	var army := army_upkeep(gs)
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		n.budget = nation_budget(gs, n, gs.economy_sums.get(tag, {}), WarSupport.economy_mult(gs, tag), float(army.get(tag, 0.0)))


## What each nation's army costs a month: every unit's upkeep (military.json unit_types), in armies and in training, and
## more for those on exercise (training cost_share).
static func army_upkeep(gs: Node) -> Dictionary:
	var types: Dictionary = Military.cfg.unit_types
	var drill := float(Military.cfg.get("training", {}).get("cost_share", 0.0))
	var out := {}
	for a: Army in gs.armies.values():
		var sum := 0.0
		for u in a.units:
			sum += float(types[u.type].get("upkeep", 0.0))
		if FrontSolver.root_of(gs, a).training:
			sum *= 1.0 + drill
		out[a.tag] = float(out.get(a.tag, 0.0)) + sum
	for tag in gs.nations:
		for job in gs.nations[tag].recruiting:
			out[tag] = float(out.get(tag, 0.0)) + float(types[job.type].get("upkeep", 0.0))
	return out


## A nation's budget for a month from its summed provinces: income by source, expenses by kind, net, CP a day, manpower.
static func nation_budget(gs: Node, n: Nation, raw: Dictionary, war_mult: float, army := 0.0) -> Dictionary:
	var c: Dictionary = cfg.income
	var base := float(raw.get("base", 0.0)) * (1.0 - float(c.mobilization_loss) * n.mobilization) * (1.0 + float(n.focus_fx.get("income", 0.0)))
	var factories := float(raw.get("factories", 0.0)) * (1.0 - float(c.blockade_factory_loss) * n.blockade)
	var ports := float(raw.get("ports", 0.0)) * (1.0 - n.blockade)
	var occupied := float(raw.get("occupied", 0.0))
	var income := (base + factories + ports + occupied) * war_mult
	var navy := n.naval_budget / 12.0
	var buildings := float(raw.get("upkeep", 0.0))
	var interest := maxf(0.0, -n.treasury) * float(cfg.debt.interest) / 12.0
	var expenses := army + navy + buildings + interest
	var cp := float(raw.get("cp", 0.0)) + float(n.focus_fx.get("cp", 0.0))
	if n.capital > 0 and n.capital < gs.province_controller.size() and gs.province_controller[n.capital] == n.tag:
		cp += float(cfg.construction.capital_cp)
	var pool := float(raw.get("pool", 0.0))
	var peace := minf(n.peacetime_army, pool)
	return {
		"base": base * war_mult,
		"factories": factories * war_mult,
		"ports": ports * war_mult,
		"occupied": occupied * war_mult,
		"income": income,
		"army": army,
		"navy": navy,
		"buildings": buildings,
		"interest": interest,
		"expenses": expenses,
		"net": income - expenses,
		"cp": cp,
		"levels": raw.get("levels", {}),
		"manpower_pool": pool,
		"manpower_max": peace + (pool - peace) * n.mobilization,
	}


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


static func refresh(gs: Node) -> void:
	refresh_now(gs)


# ------------------------------------------------------------------ mobilization and the standing army

## The lowest and highest mobilization a nation may have now, as Vector2(min, max): in peace 0 to
## peace_max, at war up to 1 and no lower than the war floor.
static func mobilization_range(gs: Node, n: Nation) -> Vector2:
	if gs.wars_of(n.tag).is_empty():
		return Vector2(0.0, float(cfg.mobilization.peace_max))
	return Vector2(float(Diplomacy.cfg.crisis.war_floor), 1.0)


## What mobilizing to `level` costs a month in gold, against none: the base income the men called up no longer earn.
static func mobilization_cost(gs: Node, n: Nation, level: float) -> float:
	var raw: Dictionary = gs.economy_sums.get(n.tag, {})
	return float(raw.get("base", 0.0)) * float(cfg.income.mobilization_loss) * level * WarSupport.economy_mult(gs, n.tag)


static func mobilization_cap(gs: Node, n: Nation) -> float:
	return mobilization_range(gs, n).y


## Brings mobilization inside the range now allowed (after a war ends).
static func clamp_mobilization(gs: Node, n: Nation) -> void:
	var r := mobilization_range(gs, n)
	n.mobilization = clampf(n.mobilization, r.x, r.y)


## The most men a nation may keep under arms in peace: economy.json standing_share of its manpower pool. The standing
## army (Nation.peacetime_army) is set below it, by the player (SetEconomyPolicy "standing_army").
static func standing_cap(gs: Node, n: Nation) -> int:
	var raw: Dictionary = gs.economy_sums.get(n.tag, {})
	return int(float(raw.get("pool", 0.0)) * float(cfg.standing_share))


## What an infantry division costs a month to keep, gold.
static func division_upkeep(_gs: Node, _n: Nation) -> float:
	return float(Military.cfg.unit_types.infantry.get("upkeep", 0.0))


## Infrastructure of a province: its railway level plus half the best railway level of the neighbours its nation owns
## (read by Military for supply and movement).
static func infrastructure(gs: Node, id: int) -> float:
	var own: int = gs.province_buildings[id].get("railway", 0)
	var best := 0
	var tag: String = gs.province_owner[id]
	for n: int in Military.neighbors(id):
		if gs.province_owner[n] == tag:
			best = maxi(best, gs.province_buildings[n].get("railway", 0))
	return own + 0.5 * best


## What each building type does for a nation now: {type: {levels, provinces, income, upkeep, cp}} (a month; cp a day).
static func building_stats(gs: Node, tag: String) -> Dictionary:
	var n: Nation = gs.nations[tag]
	var stats := {}
	for type in building_ids():
		stats[type] = {"levels": 0, "provinces": 0, "income": 0.0, "upkeep": 0.0, "cp": 0.0}
	for id in n.provinces:
		if gs.province_controller[id] != tag:
			continue
		var owned: Dictionary = gs.province_buildings[id]
		for type: String in owned:
			if not stats.has(type) or int(owned[type]) <= 0:
				continue
			var def: Dictionary = cfg.buildings[type]
			var st: Dictionary = stats[type]
			st.levels += int(owned[type])
			st.provinces += 1
			st.income += float(def.get("income", 0.0)) * owned[type]
			st.upkeep += float(def.get("upkeep", 0.0)) * owned[type]
			st.cp += float(def.get("cp_per_day", 0.0)) * owned[type]
	return stats


# ------------------------------------------------------------------ the day and the month

## Daily: CP from the construction sectors, the projects under way count down (and are finished), and the queue starts
## what it can.
static func step_day(gs: Node) -> void:
	refresh(gs)
	var finished := false
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		n.cp += float(n.budget.get("cp", 0.0))
		for i in range(n.construction.size() - 1, -1, -1):
			var job := n.construction[i]
			if gs.province_owner[job.province] != tag:
				n.construction.remove_at(i)   # ceded: the project is lost
				continue
			if not job.started:
				continue
			job.days_left -= 1
			if job.days_left <= 0:
				n.construction.remove_at(i)
				var owned: Dictionary = gs.province_buildings[job.province]
				owned[job.type] = owned.get(job.type, 0) + 1
				gs.building_completed.emit(tag, job.province, job.type)
				finished = true
		start_queued(gs, tag)
		for job in n.shipbuilding:
			job.days_left = maxi(0, int(job.days_left) - 1)
	if finished:
		recompute(gs)
		gs.economy_updated.emit()


## Starts the projects waiting in a nation's queue, in order: each whose province is free and held, paying its gold and
## CP. The first that cannot be paid for stops the rest, so the queue keeps its order.
static func start_queued(gs: Node, tag: String) -> void:
	var n: Nation = gs.nations[tag]
	for job in n.construction:
		if job.started or gs.province_controller[job.province] != tag or province_busy(n, job.province):
			continue
		var plan := build_plan(gs, job.province, job.type)
		if n.treasury < plan.gold or n.cp < plan.cp:
			return
		n.treasury -= plan.gold
		n.cp -= plan.cp
		job.started = true


## Monthly: pays the budget and refills manpower toward its cap.
static func step_month(gs: Node) -> void:
	Population.step_month(gs)
	for tag in gs.nations:
		clamp_mobilization(gs, gs.nations[tag])
	Military.refresh_men(gs)
	recompute(gs)
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		var b := n.budget
		n.treasury += float(b.net)
		# The cap covers everyone in service; what is not under arms is the reserve.
		var cap := maxi(0, int(b.manpower_max) - n.men_in_units)
		if n.manpower < cap:
			n.manpower = mini(cap, n.manpower + int(b.manpower_pool * cfg.mobilization_rate * WarSupport.economy_mult(gs, tag)))
		else:
			n.manpower = cap
	recompute(gs)
