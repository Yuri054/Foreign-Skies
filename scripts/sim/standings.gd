class_name Standings
extends RefCounted
## How the nations compare: the figures that can be ranked, their current order, and a history
## of them kept month by month for charts. Read-only: nothing in the simulation depends on it.

const MAX_MONTHS := 240

## The rankable figures. `kind` says how to show them: people, money (gold, a month or a stock), men, count, points.
const METRICS := [
	{"id": "population", "label": "Population", "kind": "people", "tip": "People living in the nation's provinces."},
	{"id": "income", "label": "Income", "kind": "money", "tip": "Gold the nation takes in each month."},
	{"id": "factories", "label": "Civilian factories", "kind": "count", "tip": "Civilian factories in the provinces it holds."},
	{"id": "treasury", "label": "Treasury", "kind": "money", "tip": "Gold in the treasury; a debt is negative."},
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
		"income":
			return b.get("income", 0.0)
		"factories":
			return float(b.get("levels", {}).get("civilian_factory", 0.0))
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


## The player's year in a line, from the records of a year ago and now: how much the output grew, where it ranks and
## which nations it passed or fell behind ("" without a player or a year of records). Posted each 1 January
## (VISION.md, rule 2: you can see it).
static func year_report(gs: Node) -> String:
	var me: String = gs.player_tag
	var h: Array = gs.standings_history
	if not gs.nations.has(me) or h.size() < 13:
		return ""
	var then: Dictionary = h[h.size() - 13].values
	var now: Dictionary = h[h.size() - 1].values
	if not then.has(me) or not now.has(me) or float(then[me].get("income", 0.0)) <= 0.0:
		return ""
	var growth: float = float(now[me].income) / float(then[me].income) - 1.0
	var rank_then := _rank_in(then, me, "income")
	var rank_now := _rank_in(now, me, "income")
	var passed: PackedStringArray = []
	var lost: PackedStringArray = []
	for tag: String in now:
		if tag == me or not then.has(tag) or not gs.nations.has(tag):
			continue
		var was_ahead: bool = float(then[tag].get("income", 0.0)) > float(then[me].income)
		var is_ahead: bool = float(now[tag].income) > float(now[me].income)
		if was_ahead and not is_ahead:
			passed.append(gs.nations[tag].display_name)
		elif is_ahead and not was_ahead:
			lost.append(gs.nations[tag].display_name)
	var line := "The year %d: income %+.1f%%, %s largest economy" % [Clock.year - 1, growth * 100.0, Fmt.ordinal(rank_now)]
	if rank_now != rank_then:
		line += " (%s last year)" % Fmt.ordinal(rank_then)
	if not passed.is_empty():
		line += "; passed %s" % ", ".join(passed)
	if not lost.is_empty():
		line += "; passed by %s" % ", ".join(lost)
	return line + "."


static func _rank_in(values: Dictionary, tag: String, id: String) -> int:
	var mine: float = float(values[tag][id])
	var rank := 1
	for other: String in values:
		if other != tag and float(values[other][id]) > mine:
			rank += 1
	return rank
