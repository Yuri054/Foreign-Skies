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
	var c := cfg()
	var enemy := war.other(tag)
	var n: Nation = gs.nations[tag]
	var score := Peace.war_score(gs, war, tag)
	var u := -score * float(c.k_score)
	u += maxf(0.0, float(c.support_ref) - n.war_support) * float(c.k_support)
	var monthly_revenue := maxf(float(n.budget.get("revenue", 0.0)), 1.0) / 12.0
	u += float(c.k_debt) * minf(float(c.debt_cap_months), maxf(0.0, -n.treasury) / monthly_revenue)
	u += float(c.k_days_per_month) * war.days_lasted(Clock.days_elapsed) / 30.0
	# A war nobody fights (the two cannot reach each other, or sit behind others) wears on both with no end in sight.
	var quiet_months := float(Clock.days_elapsed - maxi(war.last_fight_day, war.start_day)) / 30.0
	if n.blockade > 0.05 or gs.nations[enemy].blockade > 0.05:
		quiet_months = 0.0   # a blockade is fighting too
	u += float(c.k_quiet) * maxf(0.0, quiet_months - float(c.quiet_grace_months))
	if Peace.capital_taken_by(gs, tag) == enemy:
		u += float(c.capital_lost)
	var t: Dictionary = AI.base_temperament(gs, tag)
	var boldness := clampf((float(t.aggression) + 1.0 - float(t.caution)) / 2.0, 0.0, 1.0)
	u -= float(c.k_ally) * allies_fighting(gs, tag, enemy) * (1.0 - float(c.ally_boldness_discount) * boldness)
	return u


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
			var result := Peace.propose(gs, tag, war.other(tag), p.mode, p.demands)
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
	for id: int in held:
		var price := Peace.province_price(gs, id, taker, giver)
		if spent + price <= budget:
			ids.append(id)
			spent += price
	var terms: Array = []
	if not ids.is_empty():
		terms.append({"kind": "province", "ids": ids})
	var ind := indemnity_for(gs, taker, giver, budget - spent)
	if not ind.is_empty() and not ids.is_empty():
		terms.append(ind)
	return terms


## An indemnity worth up to `left` of war score that the giver can carry, as a demand ({} if none fits).
static func indemnity_for(gs: Node, taker: String, giver: String, left: float) -> Dictionary:
	var c := cfg()
	var per_year: float = Diplomacy.cfg.peace.price.indemnity_points_per_year
	var months := int(c.indemnity_months)
	var share := minf(float(c.indemnity_max_share), left / (per_year * months / 12.0))
	if share < 0.01:
		return {}
	var ind := {"kind": "indemnity", "share": snappedf(share, 0.01), "months": months}
	if Peace.demand_cost(gs, taker, giver, ind) >= 0.0 and _affordable(gs, giver, [ind]):
		return ind
	return {}
