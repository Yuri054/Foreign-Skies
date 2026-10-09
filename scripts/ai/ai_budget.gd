class_name AIBudget
extends RefCounted
## A light budget for AI nations, once a month, so they do not drift into ruin: the tax rate
## against deficit and debt, the programs that pay for themselves (or that diplomacy needs),
## one building at a time where it earns the most (the capital, the richest provinces, the
## railways behind the front), and diplomacy points bought when a crisis finds the stock low.
## Everything goes through the commands the player uses. Weights are in ai.json ("budget").


static func cfg() -> Dictionary:
	return AI.cfg.budget


static func step(gs: Node, tag: String) -> void:
	var stamp: int = Clock.year * 12 + Clock.month
	if gs.ai_budget_stamp.get(tag, 0) == stamp or not cfg().enabled:
		return
	gs.ai_budget_stamp[tag] = stamp
	_taxes(gs, tag)
	_programs(gs, tag)
	_buildings(gs, tag)
	_points(gs, tag)


## Monthly expenses of the nation (a twelfth of the annual figure).
static func _monthly_expenses(n: Nation) -> float:
	return maxf(float(n.budget.get("expenses", 0.0)) / 12.0, 0.1)


# --- Taxes -------------------------------------------------------------------------------------------

## The tax rate goes up a step while the nation is running short (in debt, or a deficit its
## treasury cannot carry for cushion_months) and comes down when it is rich and in surplus.
static func wanted_tax(gs: Node, tag: String) -> float:
	var c := cfg()
	var n: Nation = gs.nations[tag]
	var net_m := float(n.budget.get("net", 0.0)) / 12.0
	var at_war: bool = not gs.wars_of(tag).is_empty()
	var top: float = float(c.tax_max_war) if at_war else float(c.tax_max)
	var rate := n.tax_rate
	var short: bool = n.treasury < 0.0 and net_m * float(c.repay_months) < -n.treasury
	short = short or (net_m < 0.0 and n.treasury < -net_m * float(c.cushion_months))
	if short:
		return minf(rate + float(c.tax_step), top)
	var rich: bool = net_m > 0.0 and n.treasury > _monthly_expenses(n) * float(c.rich_months)
	if rich and rate > float(Economy.cfg.default_tax_rate) + 0.0001:
		return maxf(rate - float(c.tax_step), float(Economy.cfg.default_tax_rate))
	return minf(rate, top)


static func _taxes(gs: Node, tag: String) -> void:
	var rate := wanted_tax(gs, tag)
	if not is_equal_approx(rate, gs.nations[tag].tax_rate):
		gs.issue_quiet(SetEconomyPolicy.new(tag, "tax_rate", rate))


# --- Programs ----------------------------------------------------------------------------------------

## What a program costs the nation each year.
static func program_cost(gs: Node, tag: String, program: String) -> float:
	var raw_gdp := float(gs.nations[tag].budget.get("gdp", 0.0))
	return float(Economy.cfg.programs[program].cost_gdp_share) * raw_gdp


## Switches programs: all are dropped when the nation is broke, the diplomatic service is kept
## when it needs points and can afford them, and the others are taken up only when the
## nation is in surplus and rich enough to carry them.
static func _programs(gs: Node, tag: String) -> void:
	var c := cfg()
	var n: Nation = gs.nations[tag]
	var net: float = float(n.budget.get("net", 0.0))
	var broke: bool = n.treasury < float(c.program_floor) and net < 0.0
	if broke:
		for program: String in n.programs.keys():
			gs.issue_quiet(SetProgram.new(tag, program, false))
			return
		return
	for program: String in c.program_order:
		if n.programs.has(program):
			continue
		var cost := program_cost(gs, tag, program)
		if net - cost < float(c.program_margin) or n.treasury < float(c.program_floor) * 2.0:
			continue
		gs.issue_quiet(SetProgram.new(tag, program, true))
		return


# --- Buildings ---------------------------------------------------------------------------------------

## What a building would earn a year in a province, per pound it costs, with a bonus for the
## capital and for railways behind a front.
static func build_return(gs: Node, tag: String, id: int, type: String, plan: Dictionary) -> float:
	var c := cfg()
	var def: Dictionary = Economy.cfg.buildings[type]
	var effects: Dictionary = def.effects
	var output: float = gs.province_gdp[id] + gs.province_industry[id]
	var gain: float = float(effects.get("gdp", 0.0)) * gs.province_gdp[id] + float(effects.get("industry", 0.0)) * gs.province_industry[id]
	gain += float(effects.get("trade", 0.0)) * output * 0.5
	gain += float(effects.get("food", 0.0)) * output * float(c.food_value)
	if effects.has("diplomacy"):
		gain += float(effects.diplomacy) * float(c.diplomacy_value) if Diplomacy.points(gs, tag) < float(c.buy_below) * 2.0 else 0.0
	if type == "railway" and _near_front(gs, tag, id):
		gain += output * float(c.front_railway_bonus)
	if id == gs.nations[tag].capital:
		gain *= float(c.capital_multiplier)
	return gain / maxf(plan.total, 0.01)


## Whether a province lies on or just behind one of the nation's fronts.
static func _near_front(gs: Node, tag: String, id: int) -> bool:
	for f: Front in gs.fronts.values():
		if f.tag != tag:
			continue
		for p in f.provinces:
			if p == id or Military.neighbors(p).has(id):
				return true
	return false


## One building a month, where it earns most, if the treasury stays above the floor and few
## jobs are already under way.
static func _buildings(gs: Node, tag: String) -> void:
	var c := cfg()
	var n: Nation = gs.nations[tag]
	if n.construction.size() >= int(c.max_construction) or float(n.budget.get("net", 0.0)) < float(c.build_min_net):
		return
	var floor_ := float(c.build_floor) * (2.0 if not gs.wars_of(tag).is_empty() else 1.0)
	var places: Array[int] = []
	var owned: Array = Array(n.provinces)
	owned.sort_custom(func(x: int, y: int) -> bool:
		var ox: float = gs.province_gdp[x] + gs.province_industry[x]
		var oy: float = gs.province_gdp[y] + gs.province_industry[y]
		return ox > oy or (ox == oy and x < y))
	for id: int in owned.slice(0, int(c.candidates)):
		places.append(id)
	if n.capital > 0 and n.capital not in places:
		places.append(n.capital)
	for f: Front in gs.fronts.values():
		if f.tag == tag:
			for p in f.provinces:
				for q: int in Military.neighbors(p):
					if gs.province_owner[q] == tag and q not in places:
						places.append(q)
	var best_id := 0
	var best_type := ""
	var best_value := float(c.min_return)
	for id in places:
		for type in Economy.building_ids():
			if not Economy.build_problem(gs, tag, id, type, false).is_empty():
				continue
			var plan := Economy.build_plan(gs, id, type)
			if plan.blocked != "" or n.treasury - plan.total < floor_:
				continue
			var value := build_return(gs, tag, id, type, plan)
			if value > best_value + 0.000001:
				best_id = id
				best_type = type
				best_value = value
	if best_id > 0:
		gs.issue_quiet(ConstructBuilding.new(tag, best_id, best_type))


# --- Diplomacy points ----------------------------------------------------------------------------------

## In a crisis (mobilized, or at war) a nation that is short of points buys a batch if it can
## spare the money.
static func _points(gs: Node, tag: String) -> void:
	var c := cfg()
	var n: Nation = gs.nations[tag]
	var crisis: bool = n.mobilization >= float(Diplomacy.cfg.crisis.min_mobilization) or not gs.wars_of(tag).is_empty()
	if not crisis or Diplomacy.points(gs, tag) >= float(c.buy_below):
		return
	if n.treasury - Diplomacy.purchase_price(gs, tag) < float(c.buy_floor):
		return
	gs.issue_quiet(BuyPoints.new(tag))
