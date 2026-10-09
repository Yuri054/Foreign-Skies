class_name AIForces
extends RefCounted
## The AI's recruiting. A nation at war with a front to hold (or home ground to retake) raises
## units behind its most threatened line, a couple per turn, until it reaches its war strength
## or hits a limit: recruits, the treasury floor (with a cushion against deficit), a share of
## its income for units in training, or the cap on units in training. The mix of unit types
## follows ai.json. Rebuilding a destroyed stack falls out of the war strength: when men are
## lost the nation is below it again. Demobilizing is left to the mobilization rules.


static func step(gs: Node, tag: String) -> void:
	if not _needs_forces(gs, tag):
		return
	var f: Dictionary = AI.cfg.forces
	var n: Nation = gs.nations[tag]
	var target := float(n.peacetime_army) * float(f.war_multiplier)
	var province := _where(gs, tag)
	if province == 0:
		return
	for i in int(f.per_turn):
		if n.recruiting.size() >= int(f.max_training) or Military.men_in_service(gs, tag) >= target:
			return
		var type := _next_type(gs, tag)
		var def: Dictionary = Military.cfg.unit_types[type]
		if not _affordable(gs, tag, def):
			return
		if not gs.issue_quiet(RaiseUnits.new(tag, province, type, 1)):
			return


## Whether there is a war to raise troops for: a front to hold, or home ground in enemy hands.
static func _needs_forces(gs: Node, tag: String) -> bool:
	if gs.wars_of(tag).is_empty():
		return false
	for fr: Front in gs.fronts.values():
		if fr.tag == tag:
			return true
	for p: int in gs.nations[tag].provinces:
		if gs.province_controller[p] != tag:
			return true
	return false


## Whether the nation can pay for a unit and stay within its limits.
static func _affordable(gs: Node, tag: String, def: Dictionary) -> bool:
	var f: Dictionary = AI.cfg.forces
	var n: Nation = gs.nations[tag]
	if n.manpower < def.size:
		return false
	var cost := float(def.cost)
	var deficit_cushion := maxf(0.0, -float(n.budget.get("net", 0.0)) / 12.0) * float(f.deficit_months)
	if n.treasury - cost < float(f.treasury_floor) + deficit_cushion:
		return false
	var in_training := cost
	for job in n.recruiting:
		in_training += float(Military.cfg.unit_types[job.type].cost)
	var monthly_revenue := maxf(0.0, float(n.budget.get("revenue", 0.0))) / 12.0
	return in_training <= float(f.income_share) * monthly_revenue * float(f.horizon_months)


## The unit type furthest below its share of the force (men in armies and in training).
static func _next_type(gs: Node, tag: String) -> String:
	var have := {}
	var total := 0.0
	for a in Military.armies_of(gs, tag):
		for u in a.units:
			have[u.type] = have.get(u.type, 0.0) + u.men()
			total += u.men()
	for job in gs.nations[tag].recruiting:
		var size: float = Military.cfg.unit_types[job.type].size
		have[job.type] = have.get(job.type, 0.0) + size
		total += size
	var mix: Dictionary = AI.cfg.forces.mix
	var best := ""
	var best_gap := -INF
	var types: Array = mix.keys()
	types.sort()
	for type: String in types:
		var gap: float = float(mix[type]) - (have.get(type, 0.0) / total if total > 0.0 else 0.0)
		if gap > best_gap + 0.000001:
			best = type
			best_gap = gap
	return best


## Where to raise: the safest province the nation owns and holds within train_hops of its most
## threatened line province (the capital if there is no line).
static func _where(gs: Node, tag: String) -> int:
	var hot := 0
	var hot_threat := -1.0
	for fr: Front in gs.fronts.values():
		if fr.tag != tag:
			continue
		for p in fr.provinces:
			var t := AI.threat(gs, tag, p)
			if t > hot_threat + 0.000001 or (absf(t - hot_threat) <= 0.000001 and p < hot):
				hot = p
				hot_threat = t
	var n: Nation = gs.nations[tag]
	if hot == 0:
		return n.capital if gs.province_controller[n.capital] == tag else 0
	var near := AI.hops_from(hot, int(AI.cfg.forces.train_hops))
	var ids: Array = near.keys()
	ids.sort()
	var best := 0
	var best_threat := INF
	for id: int in ids:
		if gs.province_owner[id] != tag or gs.province_controller[id] != tag:
			continue
		var t := AI.threat(gs, tag, id)
		if t < best_threat - 0.000001:
			best = id
			best_threat = t
	return best
