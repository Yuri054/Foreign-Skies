class_name Production
extends RefCounted
## Equipment production lines. A line makes one category of equipment with some of the
## nation's military factories (and the arsenals every army has, `base_factories`). Output a day
## is factories x the category's output x efficiency x the economy law's military figure.
## Efficiency climbs from `efficiency_start` to 1 over `efficiency_days` days of running and starts
## over if the line changes product. Each item costs money and raw materials (data/military.json,
## "equipment"); a line short of either makes only what it can pay for. While `lines_auto` is
## set (everyone at the start, and the AI for now) the factories are shared between the
## categories by `auto_split` and re-shared as their number changes.


static func cfg() -> Dictionary:
	return Military.cfg.equipment


## Military factories a nation holds, plus its arsenals.
static func total_factories(n: Nation) -> int:
	var f: int = n.budget.get("military_factories", 0)
	if n.peacetime_army > 0:
		f += int(cfg().base_factories)
	return f


## Share of the money cost the treasury pays: the first `free_factories` factories' worth (the
## arsenals every army has) is kept in army upkeep, so only the rest is charged.
static func paid_share(n: Nation) -> float:
	var total := total_factories(n)
	if total <= 0 or n.peacetime_army <= 0:
		return 1.0
	return clampf(1.0 - float(cfg().free_factories) / float(total), 0.0, 1.0)


static func assigned(n: Nation) -> int:
	var total := 0
	for line in n.production_lines:
		total += line.factories
	return total


static func free_factories(n: Nation) -> int:
	return maxi(0, total_factories(n) - assigned(n))


## Share of its best output a line makes now, 0..1 (the efficiency).
static func efficiency(line: Dictionary) -> float:
	var start: float = cfg().efficiency_start
	return lerpf(start, 1.0, minf(1.0, float(line.days) / float(cfg().efficiency_days)))


## GBP millions a year the nation's lines would cost at full tilt (what the budget counts).
static func planned_spend(n: Nation) -> float:
	var total := 0.0
	for line in n.production_lines:
		total += capacity(n, line) * float(item_cost(line.category).get("money", 0.0)) * 365.0
	return total * paid_share(n)


## Items a day the line could make with all it needs at hand.
static func capacity(n: Nation, line: Dictionary) -> float:
	return line.factories * float(cfg().categories[line.category].output) * efficiency(line) * float(Economy.law_of(n).military)


## What one item of a category costs: {"money": GBP millions, resource id: thousand tonnes ...}.
static func item_cost(category: String) -> Dictionary:
	return cfg().categories[category].cost


static func new_line(n: Nation, category: String, factories: int, days := 0) -> Dictionary:
	var line := {"id": n.next_line_id, "category": category, "factories": factories, "days": days, "made": 0.0, "limit": ""}
	n.next_line_id += 1
	n.production_lines.append(line)
	return line


## Shares the factories out by auto_split, keeping each category's efficiency.
static func auto_assign(n: Nation) -> void:
	var total := total_factories(n)
	var split: Dictionary = cfg().auto_split
	var kept := {}
	for line in n.production_lines:
		if split.has(line.category) and not kept.has(line.category):
			kept[line.category] = line
	n.production_lines.clear()
	var left := total
	for cat in split:
		var line: Dictionary = kept.get(cat, {})
		if line.is_empty():
			line = {"id": n.next_line_id, "category": cat, "factories": 0, "days": cfg().efficiency_days, "made": 0.0, "limit": ""}
			n.next_line_id += 1
		var share := int(floor(total * float(split[cat])))
		line.factories = mini(share, left)
		left -= line.factories
		n.production_lines.append(line)
	# What the shares left over goes to the first line.
	if left > 0 and not n.production_lines.is_empty():
		n.production_lines[0].factories += left


## Trims lines from the last when the nation holds fewer factories than are assigned.
static func _fit(n: Nation) -> void:
	var excess := assigned(n) - total_factories(n)
	for i in range(n.production_lines.size() - 1, -1, -1):
		if excess <= 0:
			break
		var cut := mini(excess, n.production_lines[i].factories)
		n.production_lines[i].factories -= cut
		excess -= cut


static func step_day(gs: Node) -> void:
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		if n.peacetime_army <= 0 and n.budget.get("military_factories", 0) <= 0:
			continue
		if n.lines_auto:
			auto_assign(n)
		else:
			_fit(n)
		for line in n.production_lines:
			_run(n, line)


static func _run(n: Nation, line: Dictionary) -> void:
	line.made = 0.0
	line.limit = ""
	var want := capacity(n, line)
	if want <= 0.0:
		return
	var cost := item_cost(line.category)
	var paid := paid_share(n)
	var markup: float = Economy.cfg.import_markup
	# Materials come from the stockpile first; what is short is bought at a markup, but not past
	# a blockade.
	var ratio := 1.0
	var limit := ""
	for key in cost:
		if key == "money":
			continue
		var need: float = want * float(cost[key])
		if need <= 0.0:
			continue
		var stock: float = n.stock.get(key, 0.0)
		var reach := (stock + (1.0 - n.blockade) * maxf(0.0, need - stock)) / need
		if reach < ratio:
			ratio = reach
			limit = key
	var bill := _bill(n, cost, want * ratio, paid, markup)
	if bill > maxf(0.0, n.treasury):
		ratio *= maxf(0.0, n.treasury) / bill
		limit = "money"
	if ratio < 1.0:
		line.limit = limit
	var made := want * ratio
	var pay := _bill(n, cost, made, paid, markup)
	n.treasury -= pay
	n.equipment_spent += pay
	for key in cost:
		if key != "money":
			n.stock[key] = maxf(0.0, float(n.stock.get(key, 0.0)) - made * float(cost[key]))
	line.made = made
	line.days += ratio
	n.equipment[line.category] = float(n.equipment.get(line.category, 0.0)) + made


## Money for `items` of a category: the item's money cost (after the arsenals' share) and the
## materials the stockpile cannot cover, bought at a markup.
static func _bill(n: Nation, cost: Dictionary, items: float, paid: float, markup: float) -> float:
	var total: float = items * float(cost.get("money", 0.0)) * paid
	for key in cost:
		if key == "money":
			continue
		var short: float = maxf(0.0, items * float(cost[key]) - float(n.stock.get(key, 0.0)))
		total += short * float(Economy.cfg.resources[key].price) / 1000.0 * markup
	return total


## Share of what a nation's units and training units need that it does not have, by category
## (0..1): need less what the units hold, what is set aside for units in training and what is in
## store. A category nothing uses is left out.
static func deficit(gs: Node, tag: String) -> Dictionary:
	var n: Nation = gs.nations[tag]
	var need := {}
	var held := {}
	for a: Army in gs.armies.values():
		if a.tag != tag:
			continue
		for u in a.units:
			for cat in u.needs():
				need[cat] = float(need.get(cat, 0.0)) + u.need(cat)
				held[cat] = float(held.get(cat, 0.0)) + minf(float(u.equip.get(cat, 0.0)), u.need(cat))
	for job in n.recruiting:
		var needs: Dictionary = Military.cfg.unit_types[job.type].get("needs", {})
		for cat in needs:
			need[cat] = float(need.get(cat, 0.0)) + float(needs[cat])
			held[cat] = float(held.get(cat, 0.0)) + minf(float(job.get("equip", {}).get(cat, 0.0)), float(needs[cat]))
	var out := {}
	for cat in need:
		out[cat] = clampf((float(need[cat]) - float(held.get(cat, 0.0)) - float(n.equipment.get(cat, 0.0))) / float(need[cat]), 0.0, 1.0)
	return out
