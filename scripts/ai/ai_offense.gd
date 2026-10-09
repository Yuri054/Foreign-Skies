class_name AIOffense
extends RefCounted
## The AI on the attack. A nation runs one campaign at a time: it picks the enemy province
## that is worth most among those it can take (next to ground it supplies, within the share
## of its army its aggression allows), gathers the armies in a staging province next to it,
## advances when the combined power beats the defenders by the odds its temperament asks for,
## and carries on to the next province for as long as the odds hold and supply reaches. It
## falls back (and the armies go back to the defence) when a battle turns bad.
##
## State lives in GameState.ai_campaign: tag -> {enemy, target, staging, armies, phase,
## started}. phase is "gather" or "advance".


static func in_campaign(gs: Node, tag: String, army_id: int) -> bool:
	var c: Variant = gs.ai_campaign.get(tag)
	return (c != null and army_id in c.armies) or AILanding.involves(gs, tag, army_id)


static func step(gs: Node, tag: String) -> void:
	var c: Variant = gs.ai_campaign.get(tag)
	if c != null and not _alive(gs, tag, c):
		gs.ai_campaign.erase(tag)
		c = null
	if c == null:
		if Clock.days_elapsed < gs.ai_campaign_wait.get(tag, 0):
			return
		c = _start(gs, tag)
		if c == null:
			gs.ai_campaign_wait[tag] = Clock.days_elapsed + int(AI.cfg.offense.retry_days)
			return
	_run(gs, tag, c)


## Drops dead armies; false if the campaign is over (no armies, or the war is).
static func _alive(gs: Node, tag: String, c: Dictionary) -> bool:
	var live: Array[int] = []
	for id in c.armies:
		if gs.armies.has(id):
			live.append(id)
	c.armies = live
	return not live.is_empty() and gs.at_war(tag, c.enemy)


# --- Choosing a target ---------------------------------------------------------------------------

## Enemy-held provinces next to ground the nation holds (and supplies), in id order.
static func _frontier(gs: Node, tag: String, enemy: String) -> Array[int]:
	var seen := {}
	for p in Military.border_provinces(gs, tag, enemy):
		for n: int in Military.neighbors(p):
			if gs.province_controller[n] == enemy:
				seen[n] = true
	var out: Array[int] = []
	for n: int in seen:
		out.append(n)
	out.sort()
	return out


## Enemy-held provinces next to where a stack stands.
static func _beyond(gs: Node, enemy: String, from: int) -> Array[int]:
	var out: Array[int] = []
	for n: int in Military.neighbors(from):
		if gs.province_controller[n] == enemy:
			out.append(n)
	out.sort()
	return out


static func _km(a: int, b: int) -> float:
	return (MapData.provinces[a].center as Vector2).distance_to(MapData.provinces[b].center) * Military.KM_PER_PX


## What stands against an attack on a province: the defenders there and the enemy power
## around it (see AIDefense._defence_at), plus a share of every enemy army within reach, which
## can march to its help. An enemy far stronger than the attacker overall is not provoked
## just because the ground in front of it is empty.
static func _resistance(gs: Node, tag: String, target: int) -> float:
	var reach := AI.hops_from(target, int(AI.cfg.offense.support_hops))
	var at := AI.armies_by_province(gs)
	var around := 0.0
	for id: int in reach:
		for a: Army in at.get(id, []):
			if a.tag != tag and gs.at_war(tag, a.tag):
				around += a.power()
	return AIDefense._defence_at(gs, tag, target) + float(AI.cfg.offense.reinforce_weight) * around


## What a plan wants: the heaviest objective against this enemy, less the nearer it is the more.
static func _plan_weight(gs: Node, tag: String, enemy: String, target: int) -> float:
	var best := 0.0
	for plan: Dictionary in gs.ai_plans:
		if plan.nation != tag or plan.enemy != enemy:
			continue
		for o: Dictionary in plan.objectives:
			var hops := AI.hops_from(o.province, int(AI.cfg.offense.plan_hops))
			if hops.has(target):
				best = maxf(best, o.weight / (1.0 + hops[target]))
	return best


## Whether a plan against this enemy says to stay on the defensive.
static func _defensive(gs: Node, tag: String, enemy: String) -> bool:
	for plan: Dictionary in gs.ai_plans:
		if plan.nation == tag and plan.enemy == enemy and plan.posture == "defensive":
			return true
	return false


## How much taking a province is worth, before the odds and the cost.
static func _worth(gs: Node, tag: String, enemy: String, target: int) -> float:
	var w: Dictionary = AI.cfg.offense
	var owner: String = gs.province_owner[target]
	var points := Peace.province_share(gs, target, owner) * float(Diplomacy.cfg.peace.score.occupation_points)
	if target == gs.nations[owner].capital:
		points += float(Diplomacy.cfg.peace.score.capital_points)
	points /= float(Diplomacy.cfg.peace.score.max)
	return float(w.w_plan) * _plan_weight(gs, tag, enemy, target) + float(w.w_value) * AI.value(gs, target) + float(w.w_score) * points


## The best target for a force, as {target, staging, utility, power} or {} if none is worth
## the attempt. `armies` is the force on offer (best first within its budget), `candidates`
## the provinces to consider.
static func _best_target(gs: Node, tag: String, enemy: String, candidates: Array[int], armies: Array[Army], budget: float, exact: bool) -> Dictionary:
	var w: Dictionary = AI.cfg.offense
	var odds := AI.required_odds(gs, tag)
	var best := {}
	for target in candidates:
		if not AI.supplied(gs, tag, target):
			continue
		var required := odds * _resistance(gs, tag, target)
		var picked := _pick_force(gs, tag, target, armies, required, budget, exact)
		if picked.is_empty():
			continue
		var staging := _staging(gs, tag, target, picked.armies)
		if staging == 0:
			continue
		var days := 0.0
		for a: Army in picked.armies:
			days = maxf(days, (_km(a.province, staging) + _km(staging, target)) / a.speed())
		var margin := clampf(picked.power / required - 1.0, 0.0, 2.0)
		var cost: float = float(w.w_days) * days + float(w.w_supply) * Military.supply_cost(gs, tag, target)
		var utility := _worth(gs, tag, enemy, target) + float(w.w_margin) * margin - cost
		if best.is_empty() or utility > best.utility + 0.000001:
			best = {"target": target, "staging": staging, "utility": utility, "armies": picked.armies}
	return best


## The armies, nearest first, that reach `required` together without going over the budget.
## With `exact` the whole force on offer is used (a campaign under way) and only the odds are
## tested.
static func _pick_force(gs: Node, tag: String, target: int, armies: Array[Army], required: float, budget: float, exact: bool) -> Dictionary:
	var reach := AI.hops_from(target, int(AI.cfg.offense.reach_hops))
	var near: Array[Army] = []
	for a in armies:
		if reach.has(a.province):
			near.append(a)
	near.sort_custom(func(x: Army, y: Army) -> bool:
		var dx := _km(x.province, target)
		var dy := _km(y.province, target)
		return dx < dy or (dx == dy and x.id < y.id))
	var out: Array[Army] = []
	var power := 0.0
	for a in near:
		if not exact and power + a.power() > budget and not out.is_empty():
			break
		out.append(a)
		power += a.power()
		if not exact and power >= required:
			break
	# A single army may always go, however small the budget.
	if out.is_empty() or power < required or (not exact and power > budget and out.size() > 1):
		return {}
	return {"armies": out, "power": power}


## A province we hold next to the target, nearest to the force.
static func _staging(gs: Node, tag: String, target: int, force: Array[Army]) -> int:
	var best := 0
	var best_km := INF
	for n: int in Military.neighbors(target):
		if gs.province_controller[n] != tag:
			continue
		var km := 0.0
		for a in force:
			km += _km(a.province, n)
		if km < best_km - 0.000001:
			best = n
			best_km = km
	return best


## The armies the nation could send: not the reserve, not busy, and not the last one on a
## front. Strongest first.
static func _available(gs: Node, tag: String) -> Array[Army]:
	var reserve: int = gs.ai_reserve.get(tag, 0)
	var left := {}
	for f: Front in gs.fronts.values():
		if f.tag == tag:
			left[f.id] = f.army_ids.size()
	var out: Array[Army] = []
	var all := Military.armies_of(gs, tag)
	all.sort_custom(func(x: Army, y: Army) -> bool: return x.power() > y.power() or (x.power() == y.power() and x.id < y.id))
	for a in all:
		if a.id == reserve or not a.path.is_empty() or a.fighting or a.embarked() or gs.province_controller[a.province] != tag or AILanding.involves(gs, tag, a.id):
			continue
		if a.front_id != 0:
			if left.get(a.front_id, 0) < 2:
				continue
			left[a.front_id] -= 1
		out.append(a)
	return out


static func _start(gs: Node, tag: String) -> Variant:
	var armies := _available(gs, tag)
	if armies.is_empty():
		return null
	var total := 0.0
	for a in Military.armies_of(gs, tag):
		total += a.power()
	var budget := total * float(AI.temperament(gs, tag).aggression) * float(AI.cfg.offense.max_share)
	if budget <= 0.0:
		return null
	var best := {}
	var best_enemy := ""
	for enemy in AI.enemies(gs, tag):
		if _defensive(gs, tag, enemy):
			continue
		var pick := _best_target(gs, tag, enemy, _frontier(gs, tag, enemy), armies, budget, false)
		if not pick.is_empty() and (best.is_empty() or pick.utility > best.utility + 0.000001):
			best = pick
			best_enemy = enemy
	if best.is_empty() or best.utility < float(AI.cfg.offense.min_utility):
		return null
	var ids: Array[int] = []
	for a: Army in best.armies:
		ids.append(a.id)
	var c := {"enemy": best_enemy, "target": best.target, "staging": best.staging, "armies": ids,
			"phase": "gather", "started": Clock.days_elapsed}
	gs.ai_campaign[tag] = c
	return c


# --- Running a campaign -------------------------------------------------------------------------

static func _end(gs: Node, tag: String) -> void:
	gs.ai_campaign.erase(tag)
	gs.ai_campaign_wait[tag] = Clock.days_elapsed + int(AI.cfg.offense.retry_days)


static func _order(gs: Node, tag: String, a: Army, province: int) -> void:
	if a.province == province and a.path.is_empty():
		return
	if not a.path.is_empty() and a.path[a.path.size() - 1] == province:
		return
	gs.issue_quiet(MoveArmy.new(tag, a.id, province))


static func _army_list(gs: Node, c: Dictionary) -> Array[Army]:
	var out: Array[Army] = []
	for id in c.armies:
		out.append(gs.armies[id])
	return out


static func _power(armies: Array[Army]) -> float:
	var total := 0.0
	for a in armies:
		total += a.power()
	return total


static func _run(gs: Node, tag: String, c: Dictionary) -> void:
	var odds := AI.required_odds(gs, tag)
	var armies := _army_list(gs, c)
	if gs.province_controller[c.target] == tag:
		_next(gs, tag, c, armies)
		return
	if c.phase == "gather":
		var all_there := true
		for a in armies:
			if a.province != c.staging:
				all_there = false
				_order(gs, tag, a, c.staging)
			elif not a.path.is_empty() or a.fighting:
				all_there = false
		if not all_there:
			if Clock.days_elapsed - c.started > int(AI.cfg.offense.gather_days):
				_end(gs, tag)
			return
		if armies.size() > 1:
			var ids: Array[int] = []
			for a in armies:
				ids.append(a.id)
			gs.issue_quiet(MergeArmies.new(tag, ids))
			c.armies = [ids[0]] as Array[int]
			armies = _army_list(gs, c)
		if _power(armies) < odds * _resistance(gs, tag, c.target) or not AI.supplied(gs, tag, c.target):
			if Clock.days_elapsed - c.started > int(AI.cfg.offense.gather_days):
				_end(gs, tag)
			return
		c.phase = "advance"
		for a in armies:
			_order(gs, tag, a, c.target)
		return
	# Advancing.
	var at_target := true
	for a in armies:
		at_target = at_target and a.province == c.target
	if at_target:
		if _going_badly(gs, tag, c, armies):
			_fall_back(gs, tag, c, armies)
		return
	for a in armies:
		if not a.path.is_empty() or a.fighting:
			continue
		# Stopped short (a battle at the staging point, a routed stack): try again if the odds hold.
		if _power(armies) >= odds * _resistance(gs, tag, c.target):
			_order(gs, tag, a, c.target)
		else:
			_end(gs, tag)
			return


## Whether the stack at the target is losing: worn down, or outnumbered by what is around.
static func _going_badly(gs: Node, tag: String, c: Dictionary, armies: Array[Army]) -> bool:
	var morale := 0.0
	var men := 0.0
	for a in armies:
		morale += a.morale() * a.men()
		men += a.men()
	if men <= 0.0:
		return true
	var caution := float(AI.temperament(gs, tag).caution)
	var floor_morale: float = float(AI.cfg.offense.fall_back_morale) * (0.5 + caution)
	if morale / men < floor_morale:
		return true
	return _power(armies) < float(AI.cfg.offense.fall_back_ratio) * AI.enemy_power(gs, tag, c.target)


static func _fall_back(gs: Node, tag: String, c: Dictionary, armies: Array[Army]) -> void:
	var to: int = c.staging
	if gs.province_controller[to] != tag:
		to = gs.nations[tag].capital
	for a in armies:
		gs.issue_quiet(MoveArmy.new(tag, a.id, to))
	_end(gs, tag)


## The target is ours: go on to the next province if one is worth it and within supply.
static func _next(gs: Node, tag: String, c: Dictionary, armies: Array[Army]) -> void:
	if armies.is_empty() or gs.province_controller[armies[0].province] != tag:
		_end(gs, tag)
		return
	var here: int = armies[0].province
	for a in armies:
		if a.province != here or not a.path.is_empty():
			return
	var pick := _best_target(gs, tag, c.enemy, _beyond(gs, c.enemy, here), armies, INF, true)
	if pick.is_empty() or pick.utility < float(AI.cfg.offense.min_utility):
		_end(gs, tag)
		return
	c.target = pick.target
	c.staging = here
	c.phase = "advance"
	c.started = Clock.days_elapsed
	for a in armies:
		_order(gs, tag, a, c.target)
