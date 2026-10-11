class_name Population
extends RefCounted
## People: each province's population grows by its nation's yearly rate (data/scenarios, "pop_growth"),
## shrinks in a famine and in provinces an enemy holds, and loses the soldiers killed (Nation.deaths).
## Run once a month before the economy is worked out. Constants: data/economy.json, "population".


static func cfg() -> Dictionary:
	return Economy.cfg.population


## Yearly growth of a nation's people now, as a fraction: its own rate, less what a food shortage
## takes. Occupation and war deaths are worked out per province and are not in it.
static func growth_rate(n: Nation) -> float:
	return n.pop_growth - float(cfg().famine_decline) * float(n.budget.get("food_shortage", 0.0))


## Adds `delta` people (can be negative) to a province, keeping the fraction left over by rounding.
static func _add(gs: Node, id: int, delta: float) -> float:
	var total: float = gs.province_pop_frac[id] + delta
	var floor_pop: float = float(cfg().min_province)
	var whole := int(total)
	var now: int = gs.province_population[id]
	if now + whole < floor_pop:
		whole = int(floor_pop) - now
	gs.province_population[id] = now + whole
	# A province with more people has room for more factories, and does not lose it again.
	if id < gs.province_slots.size():
		gs.province_slots[id] = maxi(gs.province_slots[id], ceili(float(now + whole) / float(Economy.cfg.factories.slot_pop)))
	gs.province_pop_frac[id] = total - whole if now + whole > floor_pop else 0.0
	return float(whole)


static func step_month(gs: Node) -> void:
	if gs.province_pop_frac.size() != gs.province_population.size():
		gs.province_pop_frac.resize(gs.province_population.size())
	var c: Dictionary = cfg()
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		if n.provinces.is_empty():
			continue
		var rate := growth_rate(n)
		var dead := n.deaths_month * float(c.death_share)
		var before := float(n.population)
		for id: int in n.provinces:
			var pop: float = gs.province_population[id]
			var yearly := rate
			if gs.province_controller[id] != tag and gs.at_war(tag, gs.province_controller[id]):
				yearly -= float(c.occupation_decline)
			var delta := pop * yearly / 12.0
			if dead > 0.0 and before > 0.0:
				delta -= dead * pop / before
			_add(gs, id, delta)
		n.war_dead += n.deaths_month
		n.deaths_month = 0.0
		var total := 0
		for id: int in n.provinces:
			total += gs.province_population[id]
		n.population = total
