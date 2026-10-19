class_name Production
extends RefCounted
## Equipment production lines. A line makes one category of equipment with some of the
## nation's military factories (and the arsenals every army has, `base_factories`). Output a day
## is factories x the category's output x efficiency over the cap x the economy law's military figure.
## Efficiency climbs from `efficiency_start` to `efficiency_cap` over `efficiency_days` days of running
## and a line that changes product keeps a share of it. Each item costs money and raw materials (data/military.json,
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


## A line's efficiency now: it starts at efficiency_start and climbs to efficiency_cap.
static func efficiency(line: Dictionary) -> float:
	return lerpf(float(cfg().efficiency_start), float(cfg().efficiency_cap), minf(1.0, float(line.days) / float(cfg().efficiency_days)))


## Days of running that give a line the efficiency `eff` (the inverse of efficiency()).
static func days_for(eff: float) -> float:
	var start: float = cfg().efficiency_start
	var cap: float = cfg().efficiency_cap
	return clampf((eff - start) / (cap - start), 0.0, 1.0) * float(cfg().efficiency_days)


## What a line keeps of its efficiency when it changes product: a different kind of equipment
## keeps efficiency_keep_kind of it, a newer version of the same kind efficiency_keep_version.
static func retained_days(line: Dictionary, same_kind := false) -> float:
	var keep: float = cfg().efficiency_keep_version if same_kind else cfg().efficiency_keep_kind
	return days_for(efficiency(line) * keep)


## GBP millions a year the nation's lines would cost at full tilt (what the budget counts).
static func planned_spend(n: Nation) -> float:
	var total := 0.0
	for line in n.production_lines:
		total += capacity(n, line) * float(item_cost(line.category).get("money", 0.0)) * 365.0
	return total * paid_share(n)


## Thousand tonnes a year of each resource the nation's lines use at full tilt: {resource: kt}.
static func planned_materials(n: Nation) -> Dictionary:
	var out := {}
	for line in n.production_lines:
		var cost := item_cost(line.category)
		var yearly := capacity(n, line) * 365.0
		for key in cost:
			if key != "money" and key != "ic":
				out[key] = float(out.get(key, 0.0)) + yearly * float(cost[key])
	return out


## Items a day the line could make with all it needs at hand.
static func capacity(n: Nation, line: Dictionary) -> float:
	return line.factories * float(cfg().categories[line.category].output) * efficiency(line) / float(cfg().efficiency_cap) * float(Economy.law_of(n).military) * Economy.worker_share(n)


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
	# Materials are flows (see Flows): what the nation lacks of one slows every line that needs it.
	var ratio := 1.0
	var limit := ""
	var flows: Dictionary = n.budget.get("resources", {})
	for key in cost:
		if key == "money" or float(cost[key]) <= 0.0:
			continue
		var m: float = float(flows.get(key, {}).get("mult", 1.0))
		if m < ratio:
			ratio = m
			limit = key
	var bill := want * ratio * float(cost.get("money", 0.0)) * paid
	if bill > maxf(0.0, n.treasury):
		ratio *= maxf(0.0, n.treasury) / bill
		limit = "money"
	if ratio < 1.0:
		line.limit = limit
	var made := want * ratio
	var pay := made * float(cost.get("money", 0.0)) * paid
	n.treasury -= pay
	n.equipment_spent += pay
	line.made = made
	line.days += ratio
	n.equipment[line.category] = float(n.equipment.get(line.category, 0.0)) + made


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
	# Shells are not part of a unit's kit but a store the guns burn: the lack is how far the
	# stock falls short of shell_reserve_days of the guns firing (shell_firing_share of them at a time).
	var burn := 0.0
	for a: Army in gs.armies.values():
		if a.tag == tag:
			for u in a.units:
				burn += float(Military.cfg.unit_types[u.type].get("shells", 0.0)) * u.strength
	if burn > 0.0:
		var reserve := burn * float(cfg().shell_reserve_days) * float(cfg().shell_firing_share)
		out["shells"] = clampf((reserve - float(n.equipment.get("shells", 0.0))) / reserve, 0.0, 1.0)
	return out
