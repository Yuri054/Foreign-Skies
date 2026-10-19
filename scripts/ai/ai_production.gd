class_name AIProduction
extends RefCounted
## The AI's economy planner, once a month, by the same commands the player uses. It shares the
## military factories between the equipment lines by what the army lacks (leaving the automatic
## split alone while nothing is lacking), and takes an economy law by the state of the war. It
## also tells AIBudget what a military factory is worth (see factory_value). Weights are in
## ai.json ("production").


static var _lacking_day := -1
static var _lacking_cache := {}


static func cfg() -> Dictionary:
	return AI.cfg.production


## Production.deficit, worked out once a day for each nation however often it is asked.
static func lacking(gs: Node, tag: String) -> Dictionary:
	if _lacking_day != Clock.days_elapsed:
		_lacking_day = Clock.days_elapsed
		_lacking_cache.clear()
	if not _lacking_cache.has(tag):
		_lacking_cache[tag] = Production.deficit(gs, tag)
	return _lacking_cache[tag]


static func step(gs: Node, tag: String) -> void:
	if not cfg().enabled:
		return
	var short := lacking(gs, tag)
	_lines(gs, tag, short)
	_law(gs, tag, short)
	_funding(gs, tag)


static func worst(lacking: Dictionary) -> float:
	var w := 0.0
	for cat in lacking:
		w = maxf(w, float(lacking[cat]))
	return w


## What one more military factory is worth a year to a nation, in the units of AIBudget's
## returns: more the worse the army is equipped, and more at war.
static func factory_value(gs: Node, tag: String) -> float:
	var at_war: bool = not gs.wars_of(tag).is_empty()
	return float(cfg().factory_value) * worst(lacking(gs, tag)) * (float(cfg().war_factor) if at_war else 1.0)


## What a Haber-Bosch plant is worth a year: the nation's shells and industry lean on nitrates it
## buys abroad (each purchase locks civilian factories), so the more of its need it imports, and the
## less the plants it has already built cover, the more another one is worth; more at war.
static func nitrate_value(gs: Node, tag: String) -> float:
	var n: Nation = gs.nations[tag]
	var info: Dictionary = n.budget.get("resources", {}).get("nitrates", {})
	if info.is_empty():
		return 0.0
	var need: float = float(info.get("need", 0.0))
	var demand: float = float(info.get("demand", 0.0))
	if demand <= 0.0 or need <= 0.0:
		return 0.0
	var at_war: bool = not gs.wars_of(tag).is_empty()
	return float(cfg().nitrate_value) * minf(1.0, need / demand) * (float(cfg().war_factor) if at_war else 1.0)


# --- Lines -------------------------------------------------------------------------------------------

## The factories each category should have: the automatic split, bent toward the categories the
## army lacks most by deficit_weight.
static func wanted_lines(n: Nation, lacking: Dictionary) -> Dictionary:
	var split: Dictionary = Military.cfg.equipment.auto_split
	var total := Production.total_factories(n)
	var sum := 0.0
	for cat in split:
		sum += float(lacking.get(cat, 0.0))
	var w := float(cfg().deficit_weight) if sum > 0.0 else 0.0
	var shares := {}
	for cat in split:
		shares[cat] = float(split[cat]) * (1.0 - w) + (w * float(lacking.get(cat, 0.0)) / sum if sum > 0.0 else 0.0)
	var out := {}
	var left := total
	var biggest := ""
	for cat in shares:
		out[cat] = int(floor(total * float(shares[cat])))
		left -= out[cat]
		if biggest == "" or shares[cat] > shares[biggest]:
			biggest = cat
	out[biggest] += left
	return out


static func _lines(gs: Node, tag: String, lacking: Dictionary) -> void:
	var n: Nation = gs.nations[tag]
	if n.production_lines.is_empty():
		return
	var wanted := wanted_lines(n, lacking)
	var have := {}
	for line in n.production_lines:
		have[line.category] = have.get(line.category, 0) + line.factories
	var same := true
	for cat in wanted:
		same = same and have.get(cat, 0) == wanted[cat]
	if same and n.lines_auto:
		return
	if n.lines_auto:
		gs.issue_quiet(SetProductionAuto.new(tag, false))
	for pass_up in [false, true]:
		for line in n.production_lines.duplicate():
			var target: int = wanted.get(line.category, 0)
			if line.factories == target or (line.factories < target) != pass_up:
				continue
			gs.issue_quiet(SetProductionLine.new(tag, line.id, line.category, mini(target, line.factories + Production.free_factories(n)) if pass_up else target))


# --- Funding ------------------------------------------------------------------------------------------

## At war a nation under a heavier law funds its forces above the usual, if its treasury holds
## funding_months of its expenses; otherwise, and in peace, at the usual.
static func wanted_funding(gs: Node, tag: String) -> float:
	var n: Nation = gs.nations[tag]
	if gs.wars_of(tag).is_empty():
		return 1.0
	var months := float(n.budget.get("expenses", 0.0)) / 12.0 * float(cfg().funding_months)
	if n.treasury < months:
		return 1.0
	return clampf(float(cfg().war_funding), 1.0, Economy.funding_cap(n))


static func _funding(gs: Node, tag: String) -> void:
	var n: Nation = gs.nations[tag]
	var want := wanted_funding(gs, tag)
	for policy in ["army_funding", "navy_funding"]:
		var now: float = n.army_funding if policy == "army_funding" else n.navy_funding
		if not is_equal_approx(now, want):
			gs.issue_quiet(SetEconomyPolicy.new(tag, policy, want))


# --- Law ----------------------------------------------------------------------------------------------

## The law the nation wants: civilian in peace, early mobilization at war or when called up,
## a war economy when the war leaves the army short, total mobilization when it leaves it very
## short and the people can bear it.
static func wanted_law(gs: Node, tag: String, lacking: Dictionary) -> String:
	var c := cfg()
	var n: Nation = gs.nations[tag]
	var short := worst(lacking)
	var at_war: bool = not gs.wars_of(tag).is_empty()
	if at_war and short >= float(c.total_deficit) and n.war_support >= float(c.total_min_support):
		return "total_mobilization"
	if at_war and short >= float(c.war_deficit):
		return "war_economy"
	if at_war or n.mobilization >= float(c.early_mobilization):
		return "early_mobilization"
	return "civilian"


static func _law(gs: Node, tag: String, lacking: Dictionary) -> void:
	var n: Nation = gs.nations[tag]
	var want := wanted_law(gs, tag, lacking)
	var ids := Economy.law_ids()
	var now := ids.find(n.economy_law)
	# Down at once; up as far as the requirements and the wait allow.
	for i in range(ids.find(want), -1, -1):
		if i == now:
			return
		if i > now and not Economy.law_problem(gs, tag, ids[i]).is_empty():
			continue
		gs.issue_quiet(SetEconomyLaw.new(tag, ids[i]))
		return
