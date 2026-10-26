class_name AIPeace
extends RefCounted
## How the AI makes and takes peace. Everything is worked out from one number per nation and
## war, the urge for peace, in the same points as war score:
##
##   urge = -score + weariness (war support below support_ref) + debt (months of revenue owed)
##          + time at war + the capital being lost - allies still fighting the same enemy
##
## A positive urge means the nation would sooner be out of the war. What follows from it:
##  - a nation made to give accepts terms that cost no more than its urge (so never worse than
##    fighting on), and only when it is really losing or worn out; it refuses what it cannot
##    afford (indemnities beyond afford_share of its revenue);
##  - a white peace is taken unless the nation is clearly winning (urge below -white_tolerance);
##  - a nation that has taken enough (score and war aims met) names its price in the ground it
##    holds; one with urge past seek_threshold offers what it can pay, or a white peace;
##  - allies still fighting the enemy count against a separate peace, less for the bold.
## Weights are in ai.json ("peace").


static func cfg() -> Dictionary:
	return AI.cfg.peace


## The war aims of `tag` against `enemy` that it has met, 0 to 1 by plan weight (1 if it has
## no plan: the general rule has no aims beyond the score).
static func aims_met(gs: Node, tag: String, enemy: String) -> float:
	var war: War = gs.war_between(tag, enemy)
	# A stated war goal is the aim of the war for the nation that declared it.
	if war != null and war.a == tag and not war.goal.is_empty():
		return WarGoal.progress(gs, war)
	var total := 0.0
	var met := 0.0
	for plan: Dictionary in gs.ai_plans:
		if plan.nation != tag or plan.enemy != enemy:
			continue
		for o: Dictionary in plan.objectives:
			total += o.weight
			if gs.province_controller[o.province] == tag:
				met += o.weight
	return met / total if total > 0.0 else 1.0


## Allies of `tag` on its side of the conflict still at war with `enemy`.
static func allies_fighting(gs: Node, tag: String, enemy: String) -> int:
	var war: War = gs.war_between(tag, enemy)
	var g: Dictionary = gs.war_groups.get(war.war_group, {}) if war != null else {}
	if g.is_empty():
		return 0
	var n := 0
	for ally in Diplomacy.group_side(gs, g.id, g.members.get(tag, "")):
		if ally != tag and gs.at_war(ally, enemy):
			n += 1
	return n


## How much `tag` wants out of the war (negative: it wants to go on).
static func urge(gs: Node, tag: String, war: War) -> float:
	return urge_parts(gs, tag, war).total


## What the urge is made of, each part with its sign (positive pushes toward peace): {score, support, debt,
## duration, quiet, capital, allies, total}.
static func urge_parts(gs: Node, tag: String, war: War) -> Dictionary:
	var c := cfg()
	var enemy := war.other(tag)
	var n: Nation = gs.nations[tag]
	var score := Peace.war_score(gs, war, tag)
	var parts := {}
	var u := -score * float(c.k_score)
	parts.score = u
	parts.support = maxf(0.0, float(c.support_ref) - n.war_support) * float(c.k_support)
	u += parts.support
	var monthly_revenue := maxf(float(n.budget.get("revenue", 0.0)), 1.0) / 12.0
	parts.debt = float(c.k_debt) * minf(float(c.debt_cap_months), maxf(0.0, -n.treasury) / monthly_revenue)
	u += parts.debt
	parts.duration = float(c.k_days_per_month) * war.days_lasted(Clock.days_elapsed) / 30.0
	u += parts.duration
	# A war nobody fights (the two cannot reach each other, or sit behind others) wears on both with no end in sight.
	var quiet_months := float(Clock.days_elapsed - maxi(war.last_fight_day, war.start_day)) / 30.0
	if n.blockade > 0.05 or gs.nations[enemy].blockade > 0.05:
		quiet_months = 0.0   # a blockade is fighting too
	parts.quiet = float(c.k_quiet) * maxf(0.0, quiet_months - float(c.quiet_grace_months))
	u += parts.quiet
	parts.capital = float(c.capital_lost) if Peace.capital_taken_by(gs, tag) == enemy else 0.0
	u += parts.capital
	var t: Dictionary = AI.base_temperament(gs, tag)
	var boldness := clampf((float(t.aggression) + 1.0 - float(t.caution)) / 2.0, 0.0, 1.0)
	parts.allies = -float(c.k_ally) * allies_fighting(gs, tag, enemy) * (1.0 - float(c.ally_boldness_discount) * boldness)
	u += parts.allies
	parts.total = u
	return parts


## In words, how `tag` stands on ending `war`: its urge against the level it seeks peace at, and what
## weighs most each way. Read-only: the same numbers urge() uses.
static func explain(gs: Node, tag: String, war: War) -> String:
	var who: String = gs.nations[tag].display_name
	var c := cfg()
	var p := urge_parts(gs, tag, war)
	var seek := float(c.seek_threshold)
	var names := {"score": "the war is going badly", "support": "war support is low at home", "debt": "it is in debt",
			"duration": "the war has dragged on", "quiet": "the fighting has gone quiet", "capital": "its capital is lost",
			"allies": "its allies are still fighting"}
	var push: Array = []
	var hold: Array = []
	for key: String in names:
		if p[key] >= 3.0:
			push.append([p[key], names[key]])
		elif p[key] <= -3.0:
			hold.append([p[key], "the war is going well" if key == "score" else "its allies are still fighting"])
	push.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	hold.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var line := ""
	if p.total >= seek:
		line = "%s wants peace now (%+d against %d needed)" % [who, roundi(p.total), roundi(seek)]
	else:
		line = "%s will fight on (%+d against %d needed for peace)" % [who, roundi(p.total), roundi(seek)]
	if not push.is_empty():
		line += "; pushing it to peace: %s" % ", ".join(push.slice(0, 2).map(func(x: Array) -> String: return x[1]))
	if not hold.is_empty():
		line += "; holding it back: %s" % ", ".join(hold.slice(0, 2).map(func(x: Array) -> String: return x[1]))
	return line + "."


# --- Answering ---------------------------------------------------------------------------------

## Whether an AI nation (the offer's target) takes the deal.
static func accepts(gs: Node, offer: Dictionary) -> bool:
	var previous := AI.enter(offer.to)
	var answer := _accepts(gs, offer)
	AI.leave(previous)
	return answer


static func _accepts(gs: Node, offer: Dictionary) -> bool:
	var war: War = gs.war_between(offer.from, offer.to)
	if war == null:
		return false
	var c := cfg()
	var me: String = offer.to
	var u := urge(gs, me, war)
	var score := Peace.war_score(gs, war, me)
	var white: bool = offer.demands.is_empty()
	if offer.mode == "demand":
		# I am the one asked to give.
		if white:
			return u >= -float(c.white_tolerance)
		# A nation that has lost its capital (or the will to fight) can be made to give anything.
		if offer.forced:
			return true
		if not _affordable(gs, me, offer.demands):
			return false
		return offer.cost <= u and (score <= -float(c.loss_floor) or u >= float(c.seek_threshold))
	# I am offered terms by the one who gives.
	if white:
		return u >= -float(c.white_tolerance)
	# The ground a loser can hand over is all it can give: battles won add to the score but not to what is on the table.
	# (A little slack: an offer built to be exactly the share of the score must not fail on rounding.)
	var parts := Peace.score_parts(gs, war, me)
	var ground := maxf(0.0, float(parts.occupation) + float(parts.capital))
	return offer.cost >= float(c.accept_share) * minf(maxf(0.0, score), ground) - 0.000001 or u >= float(c.seek_threshold)


## Whether a nation can carry the indemnities in a set of demands on top of those it pays.
## Whether `giver` can carry the indemnities in `demands` on top of those it already pays.
static func affordable(gs: Node, giver: String, demands: Array) -> bool:
	return _affordable(gs, giver, demands)


static func _affordable(gs: Node, giver: String, demands: Array) -> bool:
	var revenue := maxf(float(gs.nations[giver].budget.get("revenue", 0.0)), 0.001)
	var committed := 0.0
	for ind: Dictionary in gs.indemnities:
		if ind.payer == giver:
			committed += ind.monthly / (revenue / 12.0)
	for d: Dictionary in demands:
		if d.get("kind", "") == "indemnity":
			committed += float(d.share)
	return committed <= float(cfg().afford_share) + 0.000001


# --- Proposing ---------------------------------------------------------------------------------

## Monthly: every AI nation at war decides whether to put a proposal on the table. Offers to
## the player wait for an answer.
static func overtures(gs: Node) -> void:
	for war: War in gs.wars.values().duplicate():
		if gs.war_between(war.a, war.b) != war:
			continue
		for tag in [war.a, war.b]:
			if tag == gs.player_tag:
				continue
			var p := proposal(gs, tag, war)
			if p.is_empty():
				continue
			var enemy := war.other(tag)
			# Allies fighting on: a nation that wants to win terms takes them to the table together, if they all want peace
			# too; otherwise it stays in the war with them unless it is strained.
			var group := AICoalition.joint_partners(gs, tag, war)
			if not group.is_empty() and p.mode == "demand" and enemy != gs.player_tag:
				var joint := Conference.propose(gs, tag, enemy, p.demands, group)
				if joint.ok and joint.accepted != false:
					break
				if joint.ok:
					continue
				# The table could not be set (a partner's terms cannot be made now): the nation goes on alone.
			if AICoalition.hold(gs, tag, war):
				continue
			var result := Peace.propose(gs, tag, enemy, p.mode, p.demands)
			if result.ok and result.accepted != false:
				break


## What `tag` would propose in this war: {mode, demands}, or {} for nothing.
static func proposal(gs: Node, tag: String, war: War) -> Dictionary:
	var previous := AI.enter(tag)
	var out := _proposal(gs, tag, war)
	AI.leave(previous)
	return out


static func _proposal(gs: Node, tag: String, war: War) -> Dictionary:
	var c := cfg()
	var enemy := war.other(tag)
	var score := Peace.war_score(gs, war, tag)
	if score >= float(c.demand_score) and aims_met(gs, tag, enemy) >= float(c.aims_enough):
		var terms := price_terms(gs, tag, enemy, war)
		if not terms.is_empty():
			return {"mode": "demand", "demands": terms}
	if urge(gs, tag, war) >= float(c.seek_threshold):
		if score < 0.0:
			return {"mode": "offer", "demands": Peace.surrender_terms(gs, war, tag, enemy)}
		return {"mode": "demand", "demands": []}
	return {}


## The ground `taker` holds that is the enemy's, chosen to fit the war score it has: war aims
## first, then the dearest, up to demand_budget_share of the score; leftover score buys an
## indemnity the enemy can carry.
static func price_terms(gs: Node, taker: String, giver: String, war: War) -> Array:
	var c := cfg()
	var budget := Peace.war_score(gs, war, taker) * float(c.demand_budget_share)
	var aims := {}
	for plan: Dictionary in gs.ai_plans:
		if plan.nation == taker and plan.enemy == giver:
			for o: Dictionary in plan.objectives:
				aims[o.province] = o.weight
	# The goal of the war comes first, ahead of every plan.
	var goal: Dictionary = war.goal if war.a == taker else {}
	if not goal.is_empty() and goal.has("ids"):
		for id: int in goal.ids:
			aims[id] = 1000.0
	var held: Array = []
	for id: int in gs.nations[giver].provinces:
		if gs.province_controller[id] == taker:
			held.append(id)
	held.sort_custom(func(x: int, y: int) -> bool:
		var ax: float = aims.get(x, 0.0)
		var ay: float = aims.get(y, 0.0)
		if ax != ay:
			return ax > ay
		var px := Peace.province_price(gs, x, taker, giver)
		var py := Peace.province_price(gs, y, taker, giver)
		return px > py or (px == py and x < y))
	var ids: Array = []
	var spent := 0.0
	var terms: Array = []
	# A concession goal is the first term asked.
	if not goal.is_empty() and goal.kind == "concession":
		var cost := Peace.demand_cost(gs, taker, giver, goal.demand)
		if cost >= 0.0 and cost <= budget and (goal.demand.kind != "indemnity" or _affordable(gs, giver, [goal.demand])):
			terms.append(goal.demand.duplicate(true))
			spent += cost
	var picked := Peace.pick_takeable(gs, taker, giver, held,
			func(id: int) -> float: return Peace.province_price(gs, id, taker, giver) * WarGoal.price_factor(war, taker, {"kind": "province"}, id),
			budget - spent)
	ids = picked.ids
	spent += picked.spent
	if not ids.is_empty():
		terms.append({"kind": "province", "ids": ids})
	var ind := indemnity_for(gs, taker, giver, budget - spent)
	var has_indemnity := false
	for t: Dictionary in terms:
		has_indemnity = has_indemnity or t.kind == "indemnity"
	if not ind.is_empty() and not has_indemnity and (not ids.is_empty() or not terms.is_empty()):
		terms.append(ind)
	return terms


## An indemnity worth up to `left` of war score that the giver can carry, as a demand ({} if none fits).
static func indemnity_for(gs: Node, taker: String, giver: String, left: float) -> Dictionary:
	var c := cfg()
	var per_year: float = Diplomacy.cfg.peace.price.indemnity_points_per_year
	var months := int(c.indemnity_months)
	var factor := WarGoal.price_factor(gs.war_between(taker, giver), taker, {"kind": "indemnity"})
	var share := minf(float(c.indemnity_max_share), left / (per_year * months / 12.0 * factor))
	if share < 0.01:
		return {}
	var ind := {"kind": "indemnity", "share": snappedf(share, 0.01), "months": months}
	# An indemnity too small to notice is no term at all.
	if ind.share * float(gs.nations[giver].budget.get("revenue", 0.0)) / 12.0 < float(Diplomacy.cfg.peace.price.indemnity_min_monthly):
		return {}
	if Peace.demand_cost(gs, taker, giver, ind) >= 0.0 and _affordable(gs, giver, [ind]):
		return ind
	return {}
