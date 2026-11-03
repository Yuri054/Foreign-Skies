class_name AIDiplomacy
extends RefCounted
## The AI's diplomacy: whether to join a war it is called to, whether to declare one, which
## treaties to propose and whom to befriend. Everything is a utility over the same inputs the
## player sees (relations, grievance, power of each side, blocs, treaties, war support,
## debt), with weights in ai.json ("diplomacy"). No nation is special-cased; nations act on
## their own plans (ai_plans) and the same temperament.
##
## Wars. An AI declares only when mobilized (or provoked past the retaliation threshold). A
## war with a casus belli needs enough desire and the odds its temperament asks for. A war
## with none ("unjustified") also needs a plan against the target, high aggression, odds
## far above the usual, and must keep the unjustified wars at ai.unjustified_share_max or
## less of every war the AI has opened so far (GameState.ai_declarations; joining a war
## counts as one justified declaration). Declarations by the player do not count.


static func cfg() -> Dictionary:
	return AI.cfg.diplomacy


## The fighting power of the armies of a set of nations.
static func side_power(gs: Node, tags: Array) -> float:
	if _powers_open:
		var sum := 0.0
		for tag: String in tags:
			sum += _powers.get(tag, 0.0)
		return sum
	var total := 0.0
	for a: Army in gs.armies.values():
		if a.tag in tags:
			total += a.power()
	return total


## While a batch of evaluations runs (the monthly treaty search), each nation's power is
## added up once.
static var _powers_open := false
static var _powers: Dictionary = {}


static func _open_powers(gs: Node) -> void:
	_powers.clear()
	for a: Army in gs.armies.values():
		_powers[a.tag] = _powers.get(a.tag, 0.0) + a.power()
	_powers_open = true


static func _close_powers() -> void:
	_powers_open = false
	_powers.clear()


# --- Joining a war -----------------------------------------------------------------------------

## How much a nation wants to join the war it has been asked into (a join decision from
## Diplomacy._make_decision): the weight of the tie, how it feels about the ally and the
## enemies, which side is stronger, war support and debt, what declining would cost, and
## whether the enemy is at its border. Positive and past join.threshold means it joins.
static func join_value(gs: Node, d: Dictionary) -> float:
	var j: Dictionary = cfg().join
	var tag: String = d.tag
	var n: Nation = gs.nations[tag]
	var v: float = j.kind.get(d.kind, 0.0)
	v += float(j.w_ally_relation) * Diplomacy.relation(gs, tag, d.ally) / 100.0
	var enemies: Array = d.enemies
	if not enemies.is_empty():
		var hostility := 0.0
		var bordering := 0.0
		var neighbors := Diplomacy.neighbor_nations(gs, tag)
		for e: String in enemies:
			hostility += -Diplomacy.relation(gs, tag, e) / 100.0
			if e in neighbors:
				bordering += 1.0
		v += float(j.w_enemy_relation) * hostility / enemies.size()
		v += float(j.w_border) * bordering / enemies.size()
	var ours: Array = Diplomacy.group_side(gs, d.group, d.side)
	if tag not in ours:
		ours.append(tag)
	var mine := side_power(gs, ours)
	var theirs := side_power(gs, enemies)
	if mine + theirs > 0.0:
		v += float(j.w_odds) * ((mine / (mine + theirs)) - 0.5) * 2.0
	v += float(j.w_support) * (n.war_support - 50.0) / 50.0
	var monthly_revenue := maxf(float(n.budget.get("income", 0.0)), 1.0 / 12.0)
	v -= float(j.w_debt) * minf(1.0, maxf(0.0, -n.treasury) / monthly_revenue)
	var cost: Dictionary = d.decline_cost
	v += float(j.w_decline) * (absf(float(cost.ally_relations)) / 40.0 + absf(float(cost.prestige)) / 10.0) / 2.0
	return v


static func joins(gs: Node, d: Dictionary) -> bool:
	var previous := AI.enter(d.tag)
	var yes := join_value(gs, d) >= float(cfg().join.threshold)
	AI.leave(previous)
	return yes


# --- Declaring war ---------------------------------------------------------------------------

## Records a war the AI opened (by declaration or by joining). Called by Diplomacy.
static func note_declaration(gs: Node, tag: String, cb: String) -> void:
	if tag == gs.player_tag:
		return
	gs.ai_declarations.total += 1
	if cb == "none":
		gs.ai_declarations.unjustified += 1


## Whether one more unjustified war would keep their share of the AI's declarations at or
## under the cap.
static func unjustified_allowed(gs: Node) -> bool:
	var total: int = gs.ai_declarations.total + 1
	var unjustified: int = gs.ai_declarations.unjustified + 1
	return float(unjustified) / total <= float(AI.cfg.unjustified_share_max) + 0.000001


## Whether the two nations made peace less than war.truce_days ago.
static func in_truce(gs: Node, a: String, b: String) -> bool:
	for i in range(gs.war_history.size() - 1, -1, -1):
		var war: War = gs.war_history[i]
		if Clock.days_elapsed - war.end_day > int(cfg().war.truce_days):
			break
		if (war.a == a and war.b == b) or (war.a == b and war.b == a):
			return true
	return false


## Whether a nation has a plan to attack another.
static func has_plan(gs: Node, tag: String, target: String) -> bool:
	for plan: Dictionary in gs.ai_plans:
		if plan.nation == tag and plan.enemy == target and plan.posture == "offensive":
			return true
	return false


static func _side(gs: Node, tag: String) -> Array:
	var out: Array = [tag]
	for ally in Diplomacy.allies_of(gs, tag):
		out.append(ally)
	return out


## The target and its allies, apart from nations on our own side.
static func _their_side(gs: Node, tag: String, target: String) -> Array:
	var ours := _side(gs, tag)
	var out: Array = [target]
	for t in Diplomacy.allies_of(gs, target):
		if t not in ours and t not in out:
			out.append(t)
	return out


## The odds against a target: our side's power (with our allies) over the target's and its
## allies'. Guarantors are not counted: they are a risk, not an army in the field.
static func odds_against(gs: Node, tag: String, target: String) -> float:
	return side_power(gs, _side(gs, tag)) / maxf(side_power(gs, _their_side(gs, tag, target)), 0.01)


## How much `tag` wants a war with `target`, before odds, gates and the cap.
static func war_desire(gs: Node, tag: String, target: String, justified: bool) -> float:
	var w: Dictionary = cfg().war
	var hostile := clampf(-Diplomacy.relation(gs, tag, target) / 100.0, 0.0, 1.0)
	var grievance := Diplomacy.grievance(gs, tag, target) / 100.0
	var desire: float = float(w.w_hostile) * hostile + float(w.w_grievance) * grievance + float(w.get("w_tension", 0.0)) * gs.tension / 100.0 * hostile
	if has_plan(gs, tag, target):
		desire += float(w.w_plan)
	if justified:
		desire += float(w.w_cb)
	# Ground the target took from it at a peace, or a demand it refused lately.
	if not Diplomacy.revanche_ids(gs, tag, target).is_empty():
		desire += float(w.get("w_revanche", 0.0))
	if Diplomacy.refused_lately(gs, tag, target):
		desire += float(w.get("w_refused", 0.0))
	# A nation that stands apart from the quarrels, or that a third power guarantees, is not a target to reach for lightly.
	if Diplomacy.is_neutral(gs, target):
		desire -= float(w.get("neutral_penalty", 0.0))
	for g in Diplomacy.guarantors_of(gs, target):
		if g != tag:
			desire -= float(w.get("guaranteed_penalty", 0.0))
			break
	return desire


## What a declaration against `target` would be, or {} if the nation should not: {target, cb,
## desire, odds}.
static func war_option(gs: Node, tag: String, target: String) -> Dictionary:
	var check := war_check(gs, tag, target)
	if check.reason != "":
		return {}
	return {"target": target, "cb": check.cb, "desire": check.desire, "odds": check.odds}


## The same weighing as war_option, with the reason it stops: {reason, cb, desire, odds, threshold,
## need} where `reason` is "" for a war the nation would declare, else one of blocked, truce, calm,
## unmobilized, cannot, desire, motive, odds, plan, temper, cap. war_option and the explanations
## (explain_declare) read the same answer.
static func war_check(gs: Node, tag: String, target: String) -> Dictionary:
	var w: Dictionary = cfg().war
	var out := {"reason": "", "cb": "none", "desire": 0.0, "odds": 0.0, "threshold": float(w.declare_threshold), "need": 0.0}
	if Diplomacy.declare_block(gs, tag, target) != "":
		out.reason = "blocked"
		return out
	if in_truce(gs, tag, target):
		out.reason = "truce"
		return out
	var n: Nation = gs.nations[tag]
	var options := Diplomacy.casus_belli_options(gs, tag, target)
	var cb: String = options[0]
	out.cb = cb
	var justified := cb != "none"
	var provoked := Diplomacy.grievance(gs, tag, target) >= float(Diplomacy.cfg.war.provocation.retaliation_threshold) and justified
	# Ground the target took at the peace after a war is provocation enough to fight in a calm Europe.
	provoked = provoked or not Diplomacy.revanche_ids(gs, tag, target, true).is_empty()
	# In a calm Europe the AI starts no wars of its own choosing (see Pressure).
	if not provoked and not Pressure.ai_may_declare(gs):
		out.reason = "calm"
		return out
	# An AI goes to war only when its country is mobilized, or it has been provoked past bearing.
	if n.mobilization < float(Diplomacy.cfg.crisis.min_mobilization) and not provoked:
		out.reason = "unmobilized"
		return out
	if not Diplomacy.can_declare(gs, tag, target, cb) or not Diplomacy.can_afford(gs, tag, Diplomacy.cost_of("declare_war", cb)):
		out.reason = "cannot"
		return out
	var temperament: Dictionary = AI.temperament(gs, tag)
	var desire := war_desire(gs, tag, target, justified)
	out.desire = desire
	if desire * (0.5 + float(temperament.aggression)) < float(w.declare_threshold):
		out.reason = "desire"
		return out
	# A casus belli alone is no reason: a defensive tie to someone else's war does not make a nation fight.
	if war_desire(gs, tag, target, false) < float(w.min_motive):
		out.reason = "motive"
		return out
	var odds := odds_against(gs, tag, target)
	out.odds = odds
	if justified:
		out.need = AI.required_odds(gs, tag) * float(w.odds_margin)
		if odds < out.need:
			out.reason = "odds"
			return out
	else:
		out.need = float(w.unjustified_odds)
		if not has_plan(gs, tag, target):
			out.reason = "plan"
			return out
		if float(temperament.aggression) < float(w.unjustified_min_aggression):
			out.reason = "temper"
			return out
		if odds < float(w.unjustified_odds) or not unjustified_allowed(gs):
			out.reason = "odds" if odds < float(w.unjustified_odds) else "cap"
			return out
	return out


## In words, whether `tag` would go to war with `target` now and why not: the weighing of war_check.
static func explain_declare(gs: Node, tag: String, target: String) -> String:
	var who: String = gs.nations[tag].display_name
	var them: String = gs.nations[target].display_name
	var c := war_check(gs, tag, target)
	match c.reason:
		"":
			return "%s is ready to attack %s (desire %.1f against %.1f needed, odds %.1f to 1%s)." % [who, them, c.desire, c.threshold, c.odds, "" if c.cb != "none" else ", with no casus belli"]
		"blocked":
			return "%s cannot attack %s: they are allied, bound by a pact or already at war." % [who, them]
		"truce":
			return "%s will not attack %s: a peace between them is too recent." % [who, them]
		"calm":
			return "%s will not attack %s: Europe is too calm for the AI to start a war." % [who, them]
		"unmobilized":
			return "%s will not attack %s: its country is not mobilized for war." % [who, them]
		"cannot":
			return "%s cannot afford to declare war on %s (diplomacy points)." % [who, them]
		"desire":
			return "%s does not want war with %s enough (desire %.1f, it needs %.1f): they are not hostile or aggrieved enough." % [who, them, c.desire, c.threshold]
		"motive":
			return "%s has no reason of its own to attack %s." % [who, them]
		"odds":
			return "%s would not win: odds %.1f to 1, it wants %.1f." % [who, c.odds, c.need]
		"plan":
			return "%s has no plan against %s, and would need a casus belli." % [who, them]
		"temper":
			return "%s is too cautious to start a war with no casus belli." % who
		"cap":
			return "%s would be starting too many wars with no casus belli." % who
	return ""


## Whether a nation is mobilized, or resents someone past the retaliation threshold: the only
## ways an AI goes to war, so anyone else is spared the weighing.
static func _may_strike(gs: Node, tag: String) -> bool:
	if gs.nations[tag].mobilization >= float(Diplomacy.cfg.crisis.min_mobilization):
		return true
	var prefix := tag + ">"
	var threshold: float = Diplomacy.cfg.war.provocation.retaliation_threshold
	for key: String in gs.grievance:
		if key.begins_with(prefix) and gs.grievance[key] >= threshold:
			return true
	return false


## The best war a nation could declare now, or {}.
static func best_war(gs: Node, tag: String) -> Dictionary:
	var best := {}
	if not _may_strike(gs, tag):
		return best
	for target in Diplomacy.neighbor_nations(gs, tag):
		var option := war_option(gs, tag, target)
		if option.is_empty():
			continue
		if best.is_empty() or option.desire > best.desire + 0.000001:
			best = option
	return best


static func consider_war(gs: Node, tag: String) -> void:
	var option := best_war(gs, tag)
	if not option.is_empty():
		gs.issue_quiet(DeclareWar.new(tag, option.target, option.cb))
	else:
		consider_press(gs, tag)


## A nation that has a plan against a neighbour, the temper for it and the odds, but no casus belli, makes a demand of
## it instead of striking with no cause: if refused, it holds a casus belli with the demand as its goal.
static func consider_press(gs: Node, tag: String) -> void:
	var w: Dictionary = cfg().war
	for c: Dictionary in gs.crises:
		if c.a == tag:
			return
	var temperament: Dictionary = AI.temperament(gs, tag)
	if float(temperament.aggression) < float(w.unjustified_min_aggression):
		return
	var best := ""
	var best_goal := {}
	var best_desire := -INF
	for target in Diplomacy.neighbor_nations(gs, tag):
		if Crisis.press_block(gs, tag, target, true) != "" or in_truce(gs, tag, target) or not has_plan(gs, tag, target):
			continue
		var options := Diplomacy.casus_belli_options(gs, tag, target)
		if options[0] != "none":
			continue
		var desire := war_desire(gs, tag, target, false)
		if desire < float(w.min_motive) or odds_against(gs, tag, target) < AI.required_odds(gs, tag) * float(w.odds_margin):
			continue
		var goal := choose_goal(gs, tag, target)
		if goal.is_empty() or Crisis.custom_problem(gs, tag, target, {"demand": Crisis.demand_for(goal), "goal": goal}) != "":
			continue
		var cost := Crisis.press_cost(gs, tag, goal) + Diplomacy.cost_of("declare_war", "fabricated_claim")
		if not Diplomacy.can_afford(gs, tag, cost):
			continue
		if desire > best_desire:
			best = target
			best_goal = goal
			best_desire = desire
	if best != "":
		gs.issue_quiet(PressDemand.new(tag, best, "", {"demand": Crisis.demand_for(best_goal), "goal": best_goal}))


## What `tag` would fight `target` for: the provinces its campaign plans aim at, else the
## richest of the target's provinces on its border, else (with no border to take) an indemnity.
static func choose_goal(gs: Node, tag: String, target: String) -> Dictionary:
	var limit: int = mini(int(WarGoal.cfg().max_provinces), 3)
	var wanted := {}
	for plan: Dictionary in gs.ai_plans:
		if plan.nation == tag and plan.enemy == target:
			for o: Dictionary in plan.objectives:
				if gs.province_owner[o.province] == target:
					wanted[o.province] = o.weight
	if wanted.is_empty():
		for id: int in gs.nations[target].provinces:
			for n: int in Military.neighbors(id):
				if gs.province_owner[n] == tag:
					wanted[id] = Peace.province_share(gs, id, target)
					break
	if not wanted.is_empty():
		var ids: Array = wanted.keys()
		ids.sort_custom(func(x: int, y: int) -> bool: return wanted[x] > wanted[y] or (wanted[x] == wanted[y] and x < y))
		# Only ground that could be handed over at peace: touching its own, and never the capital alone.
		var takeable: Array = Peace.pick_takeable(gs, tag, target, ids, func(_id: int) -> float: return 1.0, float(limit)).ids
		if not takeable.is_empty():
			return WarGoal.provinces_goal(takeable)
	var c: Dictionary = WarGoal.cfg().concession
	return WarGoal.concession_goal({"kind": "indemnity", "share": c.indemnity_share, "months": c.indemnity_months})


# --- Treaties and relations ----------------------------------------------------------------------

## The strongest land neighbour that does not like `tag`, as a ratio of its power to ours (0 if
## none): how much `tag` needs friends.
static func neediness(gs: Node, tag: String) -> float:
	var mine := maxf(side_power(gs, _side(gs, tag)), 0.01)
	var worst := 0.0
	for other in Diplomacy.neighbor_nations(gs, tag):
		if Diplomacy.relation(gs, other, tag) < float(cfg().treaties.rival_relation):
			worst = maxf(worst, side_power(gs, _side(gs, other)) / mine)
	var need := clampf(worst, 0.0, 2.0) / 2.0
	# A demand made of it makes a nation look for friends, whatever its neighbours' strength.
	for c: Dictionary in gs.crises:
		if c.b == tag:
			need = maxf(need, 0.8)
			break
	return need


## The land neighbour that does not like `tag` and outweighs it most: {tag, ratio}, or {} if none.
static func strongest_rival(gs: Node, tag: String) -> Dictionary:
	var mine := maxf(side_power(gs, _side(gs, tag)), 0.01)
	var best := {}
	for other in Diplomacy.neighbor_nations(gs, tag):
		if Diplomacy.relation(gs, other, tag) < float(cfg().treaties.rival_relation):
			var ratio := side_power(gs, _side(gs, other)) / mine
			if best.is_empty() or ratio > best.ratio:
				best = {"tag": other, "ratio": ratio}
	return best


static func _same_bloc(gs: Node, a: String, b: String) -> bool:
	var ba := Diplomacy.bloc_of(gs, a)
	return ba != "" and ba == Diplomacy.bloc_of(gs, b)


## Utility of proposing a treaty of this kind (`from` proposes to `to`), or -1 if it should not.
static func treaty_value(gs: Node, from: String, to: String, kind: String) -> float:
	var t: Dictionary = cfg().treaties
	if Diplomacy.proposal_block(gs, from, to, kind) != "" or not Diplomacy.treaty_acceptable(gs, from, to, kind):
		return -1.0
	var bloc := 1.0 if _same_bloc(gs, from, to) else 0.0
	var friendly := clampf(Diplomacy.relation(gs, to, from) / 100.0, 0.0, 1.0)
	match kind:
		"alliance":
			if has_plan(gs, from, to) or has_plan(gs, to, from):
				return -1.0
			return float(t.w_need) * neediness(gs, from) + float(t.w_bloc) * bloc + float(t.w_relation) * friendly
		"guarantee":
			# Guarantee a weaker friend whose neighbour is no friend of ours.
			var menace := 0.0
			for n in Diplomacy.neighbor_nations(gs, to):
				if n != from and Diplomacy.relation(gs, from, n) < float(t.rival_relation):
					menace = maxf(menace, side_power(gs, [n]) / maxf(side_power(gs, [to]), 0.01))
			if side_power(gs, [from]) < side_power(gs, [to]):
				return -1.0
			return float(t.w_menace) * clampf(menace, 0.0, 2.0) / 2.0 + float(t.w_bloc) * bloc + float(t.w_relation) * friendly
		"nap":
			if has_plan(gs, from, to) or not (to in Diplomacy.neighbor_nations(gs, from)):
				return -1.0
			var stronger := clampf(side_power(gs, [to]) / maxf(side_power(gs, [from]), 0.01), 0.0, 2.0) / 2.0
			return float(t.w_need) * stronger + float(t.w_relation) * friendly
		"passage":
			var value := 0.0
			for e: String in AI.enemies(gs, from):
				if e in Diplomacy.neighbor_nations(gs, to) and not (e in Diplomacy.neighbor_nations(gs, from)):
					value = float(t.w_passage)
			return value if value > 0.0 else -1.0
	return -1.0


## The best treaty to propose this month, as {to, kind, value}, within the nation's points.
static func best_treaty(gs: Node, tag: String) -> Dictionary:
	var t: Dictionary = cfg().treaties
	var best := {}
	var tags: Array = gs.nations.keys()
	tags.sort()
	for other: String in tags:
		if other == tag or gs.nations[other].provinces.is_empty():
			continue
		for kind: String in Diplomacy.PROPOSABLE:
			var cost := Diplomacy.cost_of("propose", kind)
			if Diplomacy.points(gs, tag) - cost < float(t.points_reserve):
				continue
			var value := treaty_value(gs, tag, other, kind)
			if value >= float(t.propose_threshold) and (best.is_empty() or value > best.value + 0.000001):
				best = {"to": other, "kind": kind, "value": value}
	return best


## The nation worth befriending: opinion short of the bar for an alliance with a friend of its
## bloc, or a strong neighbour it needs to calm. {} if none.
static func best_friend(gs: Node, tag: String) -> Dictionary:
	var t: Dictionary = cfg().treaties
	var best := {}
	var tags: Array = gs.nations.keys()
	tags.sort()
	var bar: float = Diplomacy.cfg.actions.treaty_accept.alliance
	for other: String in tags:
		if other == tag or gs.nations[other].provinces.is_empty() or Diplomacy.improve_block(gs, tag, other) != "":
			continue
		var rel := Diplomacy.relation(gs, other, tag)
		var value := 0.0
		if _same_bloc(gs, tag, other) and rel < bar and rel >= bar - float(t.improve_window):
			value = float(t.w_bloc) + float(t.w_need) * neediness(gs, tag)
		elif other in Diplomacy.neighbor_nations(gs, tag) and rel < 0.0 and neediness(gs, tag) > 0.0 and not has_plan(gs, tag, other):
			value = float(t.w_need) * neediness(gs, tag)
		if value >= float(t.improve_threshold) and (best.is_empty() or value > best.value + 0.000001):
			best = {"to": other, "value": value}
	return best


## Once a month: one treaty proposal and one effort to improve relations, within the points the
## nation can spare.
static func consider_treaties(gs: Node, tag: String) -> void:
	var stamp: int = Clock.year * 12 + Clock.month
	if gs.ai_diplo_stamp.get(tag, 0) == stamp:
		return
	gs.ai_diplo_stamp[tag] = stamp
	var reserve := float(cfg().treaties.points_reserve)
	_open_powers(gs)
	var proposal := best_treaty(gs, tag)
	var friend := best_friend(gs, tag)
	_close_powers()
	if not proposal.is_empty():
		gs.issue_quiet(ProposeTreaty.new(tag, proposal.to, proposal.kind))
	if not friend.is_empty() and Diplomacy.points(gs, tag) - Diplomacy.cost_of("improve_relations") >= reserve:
		gs.issue_quiet(ImproveRelations.new(tag, friend.to))


static func step(gs: Node, tag: String) -> void:
	consider_war(gs, tag)
	consider_treaties(gs, tag)
