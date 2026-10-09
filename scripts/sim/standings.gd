class_name Standings
extends RefCounted
## How the nations compare: the figures that can be ranked, their current order, and a history
## of them kept month by month for charts. Read-only: nothing in the simulation depends on it.

const MAX_MONTHS := 240

## The rankable figures. `kind` says how to show them: people, money (GBP millions, a month or
## a stock), men, count, points.
const METRICS := [
	{"id": "population", "label": "Population", "kind": "people", "tip": "People living in the nation's provinces."},
	{"id": "gdp", "label": "Output", "kind": "money", "tip": "What the economy produces each month (GBP millions)."},
	{"id": "industry", "label": "Industry", "kind": "money", "tip": "Industrial output each month (GBP millions)."},
	{"id": "income", "label": "Income", "kind": "money", "tip": "What the state takes in each month (GBP millions)."},
	{"id": "treasury", "label": "Treasury", "kind": "money", "tip": "Money in the treasury (GBP millions); a debt is negative."},
	{"id": "army", "label": "Army", "kind": "men", "tip": "Men under arms and in training."},
	{"id": "navy", "label": "Navy", "kind": "count", "tip": "Squadrons of warships and transports afloat."},
	{"id": "manpower", "label": "Manpower", "kind": "men", "tip": "The pool of men that could be called up."},
	{"id": "provinces", "label": "Provinces", "kind": "count", "tip": "Provinces owned."},
	{"id": "diplomacy_points", "label": "Diplomacy points", "kind": "points", "tip": "The stock of diplomatic effort, spent on declarations, treaties and gifts."},
	{"id": "prestige", "label": "Prestige", "kind": "points", "tip": "Standing among the powers."},
	{"id": "war_support", "label": "War support", "kind": "points", "tip": "How far the people stand behind the war."},
]


static func metric(id: String) -> Dictionary:
	for m: Dictionary in METRICS:
		if m.id == id:
			return m
	return {}


## One figure for one nation.
static func value(gs: Node, tag: String, id: String) -> float:
	var n: Nation = gs.nations[tag]
	var b: Dictionary = n.budget
	match id:
		"population":
			return float(n.population)
		"gdp":
			return b.get("gdp", 0.0) / 12.0
		"industry":
			return b.get("industry", 0.0) / 12.0
		"income":
			return b.get("revenue", 0.0) / 12.0
		"treasury":
			return n.treasury
		"army":
			return Military.men_in_service(gs, tag)
		"navy":
			var ships := 0
			for f in Navy.fleets_of(gs, tag):
				ships += f.ships.size()
			return float(ships)
		"manpower":
			return b.get("manpower_pool", 0.0)
		"provinces":
			return float(n.provinces.size())
		"diplomacy_points":
			return n.diplomacy_points
		"prestige":
			return n.prestige
		"war_support":
			return n.war_support
	return 0.0


## The nations that hold land, best first, as {tag, value}. Ties keep tag order.
static func ranking(gs: Node, id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tag: String in gs.nations:
		if not gs.nations[tag].provinces.is_empty():
			out.append({"tag": tag, "value": value(gs, tag, id)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(a.value, b.value):
			return a.value > b.value
		return a.tag < b.tag
	)
	return out


## 1 for the best, or 0 if the nation holds no land.
static func rank_of(gs: Node, tag: String, id: String) -> int:
	var list := ranking(gs, id)
	for i in list.size():
		if list[i].tag == tag:
			return i + 1
	return 0


# --- History -------------------------------------------------------------------------------

## Writes down every figure for every nation: called at the start and each month.
static func record(gs: Node) -> void:
	var values := {}
	for tag: String in gs.nations:
		if gs.nations[tag].provinces.is_empty():
			continue
		var row := {}
		for m: Dictionary in METRICS:
			row[m.id] = value(gs, tag, m.id)
		values[tag] = row
	gs.standings_history.append({"day": Clock.days_elapsed, "date": Clock.date_string(), "values": values})
	while gs.standings_history.size() > MAX_MONTHS:
		gs.standings_history.pop_front()


## One nation's figure over time as points (months since the first record, value).
static func series(gs: Node, tag: String, id: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in gs.standings_history.size():
		var row: Dictionary = gs.standings_history[i].values.get(tag, {})
		if row.has(id):
			out.append(Vector2(i, row[id]))
	return out
