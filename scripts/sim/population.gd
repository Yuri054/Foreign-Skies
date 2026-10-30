class_name Population
extends RefCounted
## People: a province's population does not grow (manpower comes from mobilization, not births); it loses the soldiers
## killed (Nation.deaths_month), spread over the nation's provinces by their people. Run once a month before the economy
## is worked out. A province is never left under MIN_PROVINCE.

const MIN_PROVINCE := 1000


static func step_month(gs: Node) -> void:
	if gs.province_pop_frac.size() != gs.province_population.size():
		gs.province_pop_frac.resize(gs.province_population.size())
	for tag in gs.nations:
		var n: Nation = gs.nations[tag]
		if n.provinces.is_empty():
			continue
		var dead := n.deaths_month
		var before := float(n.population)
		if dead > 0.0 and before > 0.0:
			for id: int in n.provinces:
				_add(gs, id, -dead * gs.province_population[id] / before)
		n.war_dead += n.deaths_month
		n.deaths_month = 0.0
		var total := 0
		for id: int in n.provinces:
			total += gs.province_population[id]
		n.population = total


## Adds `delta` people (can be negative) to a province, keeping the fraction left over by rounding.
static func _add(gs: Node, id: int, delta: float) -> void:
	var total: float = gs.province_pop_frac[id] + delta
	var whole := int(total)
	var now: int = gs.province_population[id]
	if now + whole < MIN_PROVINCE:
		whole = MIN_PROVINCE - now
	gs.province_population[id] = now + whole
	gs.province_pop_frac[id] = total - whole if now + whole > MIN_PROVINCE else 0.0
