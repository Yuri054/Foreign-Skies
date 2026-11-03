class_name AIBudget
extends RefCounted
## A light budget for AI nations, once a month: buildings while the gold and construction points allow (civilian
## factories for income, a construction sector when gold piles up faster than CP, works and railways behind the fronts
## at war), a standing army that grows in peace while the surplus pays for it, ships, and diplomacy points bought when
## a crisis finds the stock low.
## Everything goes through the commands the player uses. Weights are in ai.json ("budget").


static func cfg() -> Dictionary:
	return AI.cfg.budget


static func step(gs: Node, tag: String) -> void:
	var stamp: int = Clock.year * 12 + Clock.month
	if gs.ai_budget_stamp.get(tag, 0) == stamp or not cfg().enabled:
		return
	gs.ai_budget_stamp[tag] = stamp
	_buildings(gs, tag)
	_army(gs, tag)
	AINavy.build(gs, tag)
	_points(gs, tag)


## The gold the nation keeps in hand: build_floor, plus cushion_months of a deficit, twice that at war.
static func reserve(gs: Node, tag: String) -> float:
	var c := cfg()
	var n: Nation = gs.nations[tag]
	var floor_gold := float(c.build_floor) + maxf(0.0, -float(n.budget.get("net", 0.0))) * float(c.cushion_months)
	return floor_gold * (2.0 if not gs.wars_of(tag).is_empty() else 1.0)


# --- Buildings ---------------------------------------------------------------------------------------

## How much the nation wants a building now, against a civilian factory (1): a construction sector when its gold runs
## ahead of its CP, works and railways near a front at war (where `id` is), a port for its income.
static func want(gs: Node, tag: String, id: int, type: String) -> float:
	var c := cfg()
	var n: Nation = gs.nations[tag]
	var at_war: bool = not gs.wars_of(tag).is_empty()
	match type:
		"civilian_factory":
			return float(c.factory_war) if at_war else 1.0
		"construction_sector":
			# Gold in hand that CP cannot keep up with: months of gold over months of CP for a factory.
			var factory: Dictionary = Economy.build_plan(gs, id, "civilian_factory")
			var cp_month := maxf(float(n.budget.get("cp", 0.0)) * 30.0, 0.01)
			var gold_month := maxf(float(n.budget.get("net", 0.0)), 0.01)
			var ratio: float = (factory.cp / cp_month) / maxf(factory.gold / gold_month, 0.01)
			return clampf(ratio - 1.0, 0.0, 1.5)
		"port":
			return float(c.port_want)
		"railway":
			return float(c.front_railway) if at_war and _near_front(gs, tag, id) else 0.0
		"trench", "fortification":
			return float(c.front_works) if at_war and _near_front(gs, tag, id) else 0.0
	return 0.0


## Whether a province lies on or just behind one of the nation's fronts.
static func _near_front(gs: Node, tag: String, id: int) -> bool:
	for f: Front in gs.fronts.values():
		if f.tag != tag:
			continue
		for p in f.provinces:
			if p == id or Military.neighbors(p).has(id):
				return true
	return false


## The provinces worth looking at: the best for income, the capital and the ground behind the fronts.
static func _places(gs: Node, tag: String) -> Array[int]:
	var n: Nation = gs.nations[tag]
	var owned: Array = Array(n.provinces)
	owned.sort_custom(func(x: int, y: int) -> bool:
		return gs.province_base_income[x] > gs.province_base_income[y] or (gs.province_base_income[x] == gs.province_base_income[y] and x < y))
	var places: Array[int] = []
	for id: int in owned.slice(0, int(cfg().candidates)):
		places.append(id)
	if n.capital > 0 and n.capital in n.provinces and n.capital not in places:
		places.append(n.capital)
	for f: Front in gs.fronts.values():
		if f.tag == tag:
			for p in f.provinces:
				for q: int in Military.neighbors(p):
					if gs.province_owner[q] == tag and q not in places:
						places.append(q)
	return places


## Starts buildings, the most wanted per gold first, while the gold (above the reserve) and the CP last, at most
## max_starts a month and max_construction under way.
static func _buildings(gs: Node, tag: String) -> void:
	var c := cfg()
	var n: Nation = gs.nations[tag]
	var places := _places(gs, tag)
	for i in int(c.max_starts):
		if n.construction.size() >= int(c.max_construction):
			return
		var best_id := 0
		var best_type := ""
		var best_value := 0.0
		for id in places:
			if Economy.province_busy(n, id):
				continue
			for type in Economy.building_ids():
				if not Economy.build_problem(gs, tag, id, type, true).is_empty():
					continue
				var plan := Economy.build_plan(gs, id, type)
				if n.treasury - plan.gold < reserve(gs, tag):
					continue
				var value := want(gs, tag, id, type) / maxf(plan.gold, 1.0)
				if value > best_value + 0.000001:
					best_id = id
					best_type = type
					best_value = value
		if best_id == 0:
			return
		gs.issue_quiet(ConstructBuilding.new(tag, best_id, best_type))


# --- The standing army ---------------------------------------------------------------------------

## In peace, with a surplus, the standing army grows by army_growth_per_year (a twelfth a month), as long as the upkeep
## of the men added takes at most army_surplus_share of the surplus, up to the standing cap.
static func _army(gs: Node, tag: String) -> void:
	var c := cfg()
	var n: Nation = gs.nations[tag]
	var net := float(n.budget.get("net", 0.0))
	if not gs.wars_of(tag).is_empty() or net <= 0.0:
		return
	var per_man := Economy.division_upkeep(gs, n) / float(Military.cfg.unit_types.infantry.size)
	var affordable := int(net * float(c.army_surplus_share) / maxf(per_man, 0.000001))
	var grown := int(n.peacetime_army * float(c.army_growth_per_year) / 12.0)
	var target := mini(n.peacetime_army + mini(grown, affordable), Economy.standing_cap(gs, n))
	if target > n.peacetime_army:
		gs.issue_quiet(SetEconomyPolicy.new(tag, "standing_army", float(target)))


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
