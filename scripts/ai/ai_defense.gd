class_name AIDefense
extends RefCounted
## The AI at war on the defensive. For each enemy it shares a border with it keeps a border
## front (the ordinary kind, drawn on the map), assigns its armies to the fronts by how
## threatened each line is, holds one army back as a reserve in the most threatened province,
## merges stacks that stand together and retakes home ground the enemy holds when the odds
## are good. Armies on a front hold their slot and dig in. Everything goes through commands.


static func step(gs: Node, tag: String) -> void:
	_sync_fronts(gs, tag)
	_merge(gs, tag)
	var fronts := _fronts(gs, tag)
	if not fronts.is_empty():
		_anchor(gs, tag, fronts)
		_reserve(gs, tag, fronts)
		_assign(gs, tag, fronts)
		_rebalance(gs, tag, fronts)
	_retake(gs, tag)


# --- Fronts ----------------------------------------------------------------------------------

## One border front per enemy the nation touches; fronts against nations it no longer fights
## (or no longer touches) are dropped.
static func _sync_fronts(gs: Node, tag: String) -> void:
	var enemies := AI.enemies(gs, tag)
	for f: Front in _fronts(gs, tag):
		if f.against.is_empty() or f.against not in enemies or f.provinces.is_empty():
			gs.issue_quiet(DeleteFront.new(tag, f.id))
	var have := {}
	for f: Front in _fronts(gs, tag):
		have[f.against] = true
	for enemy in enemies:
		if have.has(enemy) or Military.border_provinces(gs, tag, enemy).is_empty():
			continue
		var none: Array[int] = []
		gs.issue_quiet(DesignateFront.new(tag, "", none, enemy))


## The nation's fronts, in id order.
static func _fronts(gs: Node, tag: String) -> Array[Front]:
	var out: Array[Front] = []
	for f: Front in gs.fronts.values():
		if f.tag == tag:
			out.append(f)
	out.sort_custom(func(x: Front, y: Front) -> bool: return x.id < y.id)
	return out


## Picks the few provinces of each line its armies mass on, so they stand as stacks that can fight a stack:
## the most threatened (and most valuable) ones, one anchor for every `anchor_armies` armies on the front.
## It is looked at again every `anchor_days`, or at once when an anchor is no longer on the line.
static func _anchor(gs: Node, tag: String, fronts: Array[Front]) -> void:
	var d: Dictionary = AI.cfg.defense
	for f in fronts:
		var stale := Clock.days_elapsed - int(gs.ai_anchor_stamp.get(f.id, -1000)) >= int(d.anchor_days)
		for p in f.anchors:
			if not f.provinces.has(p):
				stale = true
		if not stale or f.provinces.is_empty():
			continue
		gs.ai_anchor_stamp[f.id] = Clock.days_elapsed
		var scored: Array = []
		for p in f.provinces:
			scored.append([AI.threat(gs, tag, p) + float(d.anchor_value_weight) * AI.value(gs, p), p])
		scored.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0] + 0.000001 or (absf(x[0] - y[0]) <= 0.000001 and x[1] < y[1]))
		var count := clampi(f.army_ids.size() / int(d.anchor_armies), 1, int(d.anchor_max))
		var picks: Array[int] = []
		for i in mini(count, scored.size()):
			picks.append(scored[i][1])
		picks.sort()
		gs.issue_quiet(SetFrontAnchors.new(tag, f.id, picks))


## What a front must stand against: the threat on the provinces of its line.
static func _need(gs: Node, f: Front) -> float:
	var total := 0.0
	for p in f.provinces:
		total += AI.threat(gs, f.tag, p)
	# The theatre an offensive plan aims at is the main effort: it gets a larger share of the army.
	for plan: Dictionary in gs.ai_plans:
		if plan.nation == f.tag and plan.enemy == f.against and plan.posture == "offensive":
			total *= float(AI.cfg.defense.plan_need)
			break
	return maxf(total, float(AI.cfg.defense.min_need))


static func _power_on(gs: Node, f: Front) -> float:
	var total := 0.0
	for id in f.army_ids:
		if gs.armies.has(id):
			total += gs.armies[id].power()
	return total


## Front with the least cover (power over need); ties go to the lower id.
static func _weakest(gs: Node, fronts: Array[Front], needs: Dictionary, powers: Dictionary) -> Front:
	var best: Front = null
	var best_cover := INF
	for f in fronts:
		var cover: float = powers[f.id] / needs[f.id]
		if cover < best_cover - 0.000001:
			best = f
			best_cover = cover
	return best


static func _tables(gs: Node, fronts: Array[Front]) -> Array:
	var needs := {}
	var powers := {}
	for f in fronts:
		needs[f.id] = _need(gs, f)
		powers[f.id] = _power_on(gs, f)
	return [needs, powers]


# --- Armies ----------------------------------------------------------------------------------

## Armies standing still and out of battle, in id order, except those on a campaign.
static func _idle(gs: Node, tag: String) -> Array[Army]:
	var out: Array[Army] = []
	for a in Military.armies_of(gs, tag):
		if a.path.is_empty() and not a.fighting and not a.embarked() and not AIOffense.in_campaign(gs, tag, a.id):
			out.append(a)
	return out


## Joins stacks that stand in one province on the same front (or on none), leaving the reserve.
static func _merge(gs: Node, tag: String) -> void:
	var reserve: int = gs.ai_reserve.get(tag, 0)
	var groups := {}
	for a in _idle(gs, tag):
		if a.id == reserve:
			continue
		var key := Vector2i(a.province, a.front_id)
		if not groups.has(key):
			groups[key] = [] as Array[int]
		groups[key].append(a.id)
	var keys: Array = groups.keys()
	keys.sort_custom(func(x: Vector2i, y: Vector2i) -> bool: return x.x < y.x or (x.x == y.x and x.y < y.y))
	for key: Vector2i in keys:
		# Stacks are joined up to merge_max_units, so a front keeps several armies to spare.
		var chunk: Array[int] = []
		var units := 0
		for id: int in groups[key]:
			var n: int = gs.armies[id].units.size()
			if chunk.size() > 0 and units + n > int(AI.cfg.defense.merge_max_units):
				if chunk.size() > 1:
					gs.issue_quiet(MergeArmies.new(tag, chunk))
				chunk = [] as Array[int]
				units = 0
			chunk.append(id)
			units += n
		if chunk.size() > 1:
			gs.issue_quiet(MergeArmies.new(tag, chunk))


## Keeps one army back, in the most threatened province of any line. It is the biggest idle
## army that does not exceed the reserve share of the nation's power.
static func _reserve(gs: Node, tag: String, fronts: Array[Front]) -> void:
	var armies := Military.armies_of(gs, tag)
	if armies.size() < int(AI.cfg.defense.reserve_min_armies):
		gs.ai_reserve.erase(tag)
		return
	var reserve: Army = gs.armies.get(gs.ai_reserve.get(tag, 0))
	if reserve == null or reserve.tag != tag:
		gs.ai_reserve.erase(tag)
		reserve = null
		var total := 0.0
		for a in armies:
			total += a.power()
		var share: float = float(AI.cfg.defense.reserve_share) * (0.5 + float(AI.temperament(gs, tag).caution))
		for a in _idle(gs, tag):
			if a.power() <= share * total and (reserve == null or a.power() > reserve.power()):
				reserve = a
		if reserve == null:
			return
		gs.issue_quiet(AssignToFront.new(tag, 0, [reserve.id] as Array[int]))
		gs.ai_reserve[tag] = reserve.id
	if not reserve.path.is_empty() or reserve.fighting:
		return
	# The most threatened province of any line.
	var best := 0
	var best_threat := -1.0
	for f in fronts:
		for p in f.provinces:
			var t := AI.threat(gs, tag, p)
			if t > best_threat + 0.000001 or (absf(t - best_threat) <= 0.000001 and p < best):
				best = p
				best_threat = t
	if best == 0 or best == reserve.province:
		return
	if AI.threat(gs, tag, reserve.province) * float(AI.cfg.defense.reserve_stay) >= best_threat:
		return
	gs.issue_quiet(MoveArmy.new(tag, reserve.id, best))


## Puts armies that belong to no front (and are not the reserve, nor busy taking ground) on the front
## with the least cover.
static func _assign(gs: Node, tag: String, fronts: Array[Front]) -> void:
	var reserve: int = gs.ai_reserve.get(tag, 0)
	var pool: Array[Army] = []
	for a in _idle(gs, tag):
		# An army standing on ground the enemy holds is taking it: let it finish.
		if a.front_id == 0 and a.id != reserve and gs.occupation.get(a.province, {}).get("tag", "") != tag:
			pool.append(a)
	if pool.is_empty():
		return
	pool.sort_custom(func(x: Army, y: Army) -> bool: return x.power() > y.power() or (x.power() == y.power() and x.id < y.id))
	var t := _tables(gs, fronts)
	var batches := {}
	# Armies far from every line wait a few days after a new war starts: the other fronts may not be drawn yet, and
	# an army sent to the first one would march across the country just as the war on the other side begins.
	var newest := INF
	for w: War in gs.wars_of(tag):
		newest = minf(newest, float(w.days_lasted(Clock.days_elapsed)))
	var settled: bool = newest >= float(AI.cfg.defense.settle_days)
	for a in pool:
		var f := _front_for(gs, a, fronts, t[0], t[1])
		if not settled and _km_to_line(a, f) > float(AI.cfg.defense.rebalance_max_km):
			continue
		t[1][f.id] += a.power()
		if not batches.has(f.id):
			batches[f.id] = [] as Array[int]
		batches[f.id].append(a.id)
	var ids: Array = batches.keys()
	ids.sort()
	for fid: int in ids:
		gs.issue_quiet(AssignToFront.new(tag, fid, batches[fid]))


## The front an unassigned army should join: the least covered, but an army does not march across the country
## to a line that is only a little worse covered than one beside it (`near_km` of distance count as one cover).
static func _front_for(gs: Node, a: Army, fronts: Array[Front], needs: Dictionary, powers: Dictionary) -> Front:
	var best: Front = null
	var best_score := INF
	for f in fronts:
		var score: float = powers[f.id] / needs[f.id] + _km_to_line(a, f) / float(AI.cfg.defense.near_km)
		if score < best_score - 0.000001:
			best = f
			best_score = score
	return best


## Moves the smallest army of the best-covered front to the worst-covered one when the cover
## differs by more than rebalance_ratio, so none stays idle behind a quiet line while another
## is overrun. One move per turn.
static func _rebalance(gs: Node, tag: String, fronts: Array[Front]) -> void:
	if fronts.size() < 2:
		return
	var t := _tables(gs, fronts)
	var best: Front = null
	var best_cover := -1.0
	for f in fronts:
		var cover: float = t[1][f.id] / t[0][f.id]
		if cover > best_cover + 0.000001:
			best = f
			best_cover = cover
	var worst := _weakest(gs, fronts, t[0], t[1])
	if best == worst or best.army_ids.size() < 2:
		return
	var worst_cover: float = t[1][worst.id] / t[0][worst.id]
	if best_cover < worst_cover * float(AI.cfg.defense.rebalance_ratio):
		return
	# The donor is the army nearest the line that needs it, if that is not too far to march.
	var smallest: Army = null
	var best_km := INF
	for id in best.army_ids:
		var a: Army = gs.armies.get(id)
		if a == null or not a.path.is_empty() or a.fighting:
			continue
		var km := _km_to_line(a, worst)
		if km < best_km - 0.000001 or (absf(km - best_km) <= 0.000001 and smallest != null and a.id < smallest.id):
			smallest = a
			best_km = km
	if smallest == null or best_km > float(AI.cfg.defense.rebalance_max_km):
		return
	# Only if the donor stays better covered than the receiver will be.
	if (t[1][best.id] - smallest.power()) / t[0][best.id] < (t[1][worst.id] + smallest.power()) / t[0][worst.id]:
		return
	gs.issue_quiet(AssignToFront.new(tag, worst.id, [smallest.id] as Array[int]))


## How far an army stands from the provinces a front masses on.
static func _km_to_line(a: Army, f: Front) -> float:
	var km := INF
	for p in (f.anchors if not f.anchors.is_empty() else f.provinces):
		km = minf(km, (MapData.provinces[a.province].center as Vector2).distance_to(MapData.provinces[p].center) * Military.KM_PER_PX)
	return km


# --- Retaking home ground ------------------------------------------------------------------------

## Sends armies to take back home provinces an enemy holds, when the force that can reach
## them in step beats the defenders by the odds the nation's temperament asks for. At most
## one province a turn.
static func _retake(gs: Node, tag: String) -> void:
	var odds := AI.required_odds(gs, tag)
	var targets: Array[int] = []
	for p: int in gs.nations[tag].provinces:
		var holder: String = gs.province_controller[p]
		if holder != tag and gs.at_war(tag, holder):
			targets.append(p)
	targets.sort_custom(func(x: int, y: int) -> bool:
		var vx := AI.value(gs, x)
		var vy := AI.value(gs, y)
		return vx > vy or (vx == vy and x < y))
	var armies := _idle(gs, tag)
	for target in targets:
		if _under_way(gs, tag, target):
			continue
		var required := odds * _defence_at(gs, tag, target)
		# Cheap test first: is there enough idle power within reach at all?
		var near := AI.hops_from(target, int(AI.cfg.defense.retake_hops))
		var reachable := 0.0
		for a in armies:
			if near.has(a.province):
				reachable += a.power()
		if reachable < required or not AI.supplied(gs, tag, target):
			continue
		var force := _force_for(gs, tag, target, armies, required)
		if force.is_empty():
			continue
		for a in force:
			gs.issue_quiet(MoveArmy.new(tag, a.id, target))
		return


## Whether one of the nation's armies is already marching on the province.
static func _under_way(gs: Node, tag: String, target: int) -> bool:
	for a in Military.armies_of(gs, tag):
		if not a.path.is_empty() and a.path[a.path.size() - 1] == target:
			return true
	return false


## What stands in the way of taking a province: the defenders there, with terrain and
## entrenchment, plus the enemy power around it.
static func _defence_at(gs: Node, tag: String, target: int) -> float:
	var inside := 0.0
	var inside_dug := 0.0
	for a in Military.armies_at(gs, target):
		if gs.at_war(tag, a.tag):
			inside += a.power()
			inside_dug += a.power() * Military.defense_multiplier(a)
	return maxf(AI.enemy_power(gs, tag, target) - inside + inside_dug, 0.01)


## The idle armies, nearest first, that together reach the required power and arrive within
## retake_eta_spread days of each other. Empty if there are not enough.
static func _force_for(gs: Node, tag: String, target: int, armies: Array[Army], required: float) -> Array[Army]:
	var near := AI.hops_from(target, int(AI.cfg.defense.retake_hops))
	var options: Array[Dictionary] = []
	for a in armies:
		if not near.has(a.province) or a.province == target:
			continue
		var route := Military.find_path(gs, tag, a.speed(), a.province, target)
		if route.is_empty():
			continue
		var etas := Military.path_etas(gs, tag, a.speed(), a.province, route, 0.0)
		options.append({"army": a, "eta": etas[etas.size() - 1]})
	options.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.eta < y.eta or (x.eta == y.eta and x.army.id < y.army.id))
	var force: Array[Army] = []
	var power := 0.0
	for o in options:
		if o.eta - options[0].eta > float(AI.cfg.defense.retake_eta_spread):
			break
		force.append(o.army)
		power += o.army.power()
		if power >= required:
			return force
	return []
