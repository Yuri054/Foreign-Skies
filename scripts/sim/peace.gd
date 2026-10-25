class_name Peace
extends RefCounted
## War score, peace offers and peace terms (phase 5, step 5). Static, like Diplomacy; the data
## lives in GameState (pending_offers, indemnities, restrictions) and in each War. Constants
## are in data/diplomacy.json under "peace".
##
## War score is one number per pairwise war, from a nation's side: positive means it is
## winning. It is the ground each holds of the other (by population and GDP share), the
## enemy capital, and the battles won, which fade with time.
##
## A peace offer is a set of demands. In "demand" mode the proposer takes them from the
## target; in "offer" mode the proposer gives them to the target. The side that takes can
## only ask for what its war score pays for, unless the other side has lost its capital to it.
## Demands: {kind: "province", ids}, {kind: "indemnity", share, months},
## {kind: "release_ally", nation}, {kind: "disarm_border", years}. No demands is a white peace.


static func cfg() -> Dictionary:
	return Diplomacy.cfg.peace


# --- War score -----------------------------------------------------------------------------

static func nation_gdp(gs: Node, tag: String) -> float:
	var total := 0.0
	for id: int in gs.nations[tag].provinces:
		total += gs.province_gdp[id]
	return total


## Share of a nation's weight (population and GDP) that one province carries, 0..1.
static func province_share(gs: Node, id: int, tag: String) -> float:
	var c: Dictionary = cfg().score
	var pop_total := maxf(float(gs.nations[tag].population), 1.0)
	var gdp_total := maxf(nation_gdp(gs, tag), 0.001)
	return c.pop_weight * gs.province_population[id] / pop_total + c.gdp_weight * gs.province_gdp[id] / gdp_total


## Score `holder` earns for the share of `owner`'s land it holds.
static func occupation_points(gs: Node, holder: String, owner: String) -> float:
	var c: Dictionary = cfg().score
	var n: Nation = gs.nations[owner]
	var pop_total := maxf(float(n.population), 1.0)
	var gdp_total := maxf(nation_gdp(gs, owner), 0.001)
	var share := 0.0
	for id: int in n.provinces:
		if gs.province_controller[id] == holder:
			share += c.pop_weight * gs.province_population[id] / pop_total + c.gdp_weight * gs.province_gdp[id] / gdp_total
	return share * c.occupation_points


## Who holds a nation's capital if it is not the nation itself, else "".
static func capital_taken_by(gs: Node, tag: String) -> String:
	var n: Nation = gs.nations[tag]
	if n.capital <= 0:
		return ""
	var holder: String = gs.province_controller[n.capital]
	return "" if holder == tag else holder


## The parts of `tag`'s war score in a war, and their sum (clamped): occupation, capital,
## battles and total.
static func score_parts(gs: Node, war: War, tag: String) -> Dictionary:
	var c: Dictionary = cfg().score
	var other := war.other(tag)
	var occupation := occupation_points(gs, tag, other) - occupation_points(gs, other, tag)
	var capital := 0.0
	if capital_taken_by(gs, other) == tag:
		capital += c.capital_points
	if capital_taken_by(gs, tag) == other:
		capital -= c.capital_points
	var battles: float = war.battle_points.get(tag, 0.0) - war.battle_points.get(other, 0.0)
	return {"occupation": occupation, "capital": capital, "battles": battles,
			"total": clampf(occupation + capital + battles, -c.max, c.max)}


static func war_score(gs: Node, war: War, tag: String) -> float:
	return score_parts(gs, war, tag).total


## Credits the winner of a finished battle. Called by Military when a battle is written into
## a war's record; the points scale with what the loser lost, and with how lopsided it was.
static func record_battle(war: War, record: Dictionary) -> void:
	war.last_fight_day = Clock.days_elapsed
	var winner: String = record.winner
	if winner.is_empty():
		return
	var c: Dictionary = cfg().score
	var loser := war.other(winner)
	var lost_loser: float = record.lost.get(loser, 0.0)
	var lost_winner: float = record.lost.get(winner, 0.0)
	var ratio := clampf(lost_loser / maxf(lost_winner, 1.0), c.battle_ratio_min, c.battle_ratio_max)
	war.battle_points[winner] += minf(c.battle_cap, c.battle_per_kmen * lost_loser / 1000.0 * ratio)


# --- Prices and checks ---------------------------------------------------------------------

## Score a province costs to take from `giver`: its share of the nation's weight, cheaper if
## the taker already holds it, dearer if it is the capital.
static func province_price(gs: Node, id: int, taker: String, giver: String) -> float:
	var p: Dictionary = cfg().price
	var price: float = p.province_scale * province_share(gs, id, giver)
	if gs.province_controller[id] == taker:
		price *= p.occupied_discount
	if id == gs.nations[giver].capital:
		price *= p.capital_multiplier
	return price


## What one demand costs the taker in score, or -1 if it cannot be made.
static func demand_cost(gs: Node, taker: String, giver: String, d: Dictionary) -> float:
	var p: Dictionary = cfg().price
	var war: War = gs.war_between(taker, giver)
	var f := WarGoal.price_factor(war, taker, d)
	match d.get("kind", ""):
		"province":
			var ids: Array = d.get("ids", [])
			if ids.is_empty():
				return -1.0
			var total := 0.0
			for id: int in ids:
				if id < 1 or id >= gs.province_owner.size() or gs.province_owner[id] != giver:
					return -1.0
				total += province_price(gs, id, taker, giver) * WarGoal.price_factor(war, taker, d, id)
			return total
		"indemnity":
			var share: float = d.get("share", 0.0)
			var months: int = d.get("months", 0)
			if share <= 0.0 or share > p.max_share or months < 1 or months > p.max_months:
				return -1.0
			return p.indemnity_points_per_year * share * months / 12.0 * f
		"release_ally":
			var other: String = d.get("nation", "")
			if not gs.nations.has(other) or other == taker or other == giver or _release_treaties(gs, giver, other).is_empty():
				return -1.0
			return p.release_ally * f
		"disarm_border":
			var years: int = d.get("years", 0)
			if years < 1 or years > p.disarm_years_max or Military.border_provinces(gs, giver, taker).is_empty():
				return -1.0
			return p.disarm_border_per_year * years * f
	return -1.0


## One demand in words, for the peace screens.
static func describe_demand(gs: Node, d: Dictionary) -> String:
	match d.get("kind", ""):
		"province":
			var names: Array[String] = []
			for id: int in d.ids:
				names.append(MapData.provinces[id].name)
			return "the provinces of %s" % ", ".join(names) if names.size() <= 6 else "%d provinces (%s and %d more)" % [names.size(), ", ".join(names.slice(0, 4)), names.size() - 4]
		"indemnity":
			return "an indemnity of %d%% of revenue a year for %d months" % [roundi(d.share * 100.0), d.months]
		"release_ally":
			return "an end to its ties with %s" % gs.nations[d.nation].display_name
		"disarm_border":
			return "its border armies withdrawn for %d years" % d.years
	return "?"


static func _release_treaties(gs: Node, giver: String, other: String) -> Array[Treaty]:
	var out: Array[Treaty] = []
	for t in Diplomacy.treaties_between(gs, giver, other):
		if t.kind == "alliance" or t.kind == "guarantee":
			out.append(t)
	return out


## Checks a proposal. Returns {ok, reason, cost, taker, giver, forced, war}. Reasons: no_war,
## pending (an offer is already waiting in this war), cooldown, invalid (a demand cannot be
## made), too_expensive (the taker's score does not pay for it).
static func check(gs: Node, from: String, to: String, mode: String, demands: Array) -> Dictionary:
	var out := {"ok": false, "reason": "", "cost": 0.0, "taker": "", "giver": "", "forced": false, "war": null}
	var war: War = gs.war_between(from, to)
	if war == null or mode not in ["demand", "offer"]:
		out.reason = "no_war"
		return out
	out.war = war
	out.taker = from if mode == "demand" else to
	out.giver = to if mode == "demand" else from
	for o: Dictionary in gs.pending_offers:
		if o.war_id == war.id:
			out.reason = "pending"
			return out
	if gs.peace_cooldown.get(Diplomacy.pair_key(from, to), -1) > Clock.days_elapsed and from != gs.player_tag:
		out.reason = "cooldown"
		return out
	var cost := 0.0
	for d: Dictionary in demands:
		var c := demand_cost(gs, out.taker, out.giver, d)
		if c < 0.0:
			out.reason = "invalid"
			return out
		cost += c
	out.cost = cost
	out.forced = capital_taken_by(gs, out.giver) == out.taker or gs.nations[out.giver].war_support <= Diplomacy.cfg.war_support.surrender_at
	if cost > 0.0 and cost > war_score(gs, war, out.taker) and not out.forced:
		out.reason = "too_expensive"
		return out
	out.ok = true
	return out


# --- Offers --------------------------------------------------------------------------------

## Makes a proposal. Returns {ok, reason, accepted}: `accepted` is true or false once the
## other side has answered, or null while the player still has to. An AI target answers at
## once by acceptable(); a refusal puts the proposer on a cooldown.
static func propose(gs: Node, from: String, to: String, mode: String, demands: Array) -> Dictionary:
	var c := check(gs, from, to, mode, demands)
	var result := {"ok": c.ok, "reason": c.reason, "accepted": false}
	if not c.ok:
		return result
	var offer := {
		"id": gs.next_offer_id, "war_id": c.war.id, "from": from, "to": to, "mode": mode,
		"taker": c.taker, "giver": c.giver, "demands": demands.duplicate(true), "cost": c.cost,
		"forced": c.forced, "day": Clock.days_elapsed,
	}
	gs.next_offer_id += 1
	if to == gs.player_tag:
		gs.pending_offers.append(offer)
		Clock.paused = true
		gs.peace_offered.emit(offer)
		result.accepted = null
		return result
	result.accepted = acceptable(gs, offer)
	_resolve(gs, offer, result.accepted)
	return result


## The player's answer to a pending offer. Returns false if no such offer is waiting.
static func answer(gs: Node, offer_id: int, accept: bool) -> bool:
	for i in gs.pending_offers.size():
		if gs.pending_offers[i].id != offer_id:
			continue
		var offer: Dictionary = gs.pending_offers[i]
		gs.pending_offers.remove_at(i)
		# The war may have changed under it (the other side made peace, a province was lost).
		accept = accept and check_offer_still_valid(gs, offer)
		_resolve(gs, offer, accept)
		return true
	return false


static func check_offer_still_valid(gs: Node, offer: Dictionary) -> bool:
	var war: War = gs.war_between(offer.from, offer.to)
	if war == null or war.id != offer.war_id:
		return false
	for d: Dictionary in offer.demands:
		if demand_cost(gs, offer.taker, offer.giver, d) < 0.0:
			return false
	return offer.forced or offer.cost <= war_score(gs, war, offer.taker)


static func _resolve(gs: Node, offer: Dictionary, accepted: bool) -> void:
	if accepted:
		var war: War = gs.war_between(offer.from, offer.to)
		if war != null:
			make_peace(gs, war, offer)
	else:
		gs.peace_cooldown[Diplomacy.pair_key(offer.from, offer.to)] = Clock.days_elapsed + cfg().ai.refuse_cooldown_days
		var war: War = gs.war_between(offer.from, offer.to)
		if war != null:
			war.add_log(Clock.date_string(), "refuse", "%s refuses the peace offered by %s." % [
					gs.nations[offer.to].display_name, gs.nations[offer.from].display_name])
	gs.peace_resolved.emit(offer, accepted)


## Whether an AI nation (the offer's target) takes the deal: see AIPeace.accepts.
static func acceptable(gs: Node, offer: Dictionary) -> bool:
	return AIPeace.accepts(gs, offer)


## Terms a losing nation can offer a winner: the winner's ground it holds, dearest first,
## as much as its war score can pay for. Empty if it holds none.
static func surrender_terms(gs: Node, war: War, loser: String, winner: String) -> Array:
	var budget: float = war_score(gs, war, winner) * cfg().ai.surrender_budget_share
	var held: Array = []
	for id: int in gs.nations[loser].provinces:
		if gs.province_controller[id] == winner:
			held.append(id)
	held.sort_custom(func(x: int, y: int) -> bool: return province_price(gs, x, winner, loser) > province_price(gs, y, winner, loser))
	var ids: Array = []
	var spent := 0.0
	for id: int in held:
		var price := province_price(gs, id, winner, loser)
		if spent + price <= budget:
			ids.append(id)
			spent += price
	if ids.is_empty():
		return []
	var terms: Array = [{"kind": "province", "ids": ids}]
	# A loser that has little ground left to give offers an indemnity for the rest of what it can be made to pay.
	var ind: Dictionary = AIPeace.indemnity_for(gs, winner, loser, budget - spent)
	if not ind.is_empty():
		terms.append(ind)
	return terms


# --- Making peace --------------------------------------------------------------------------

## Ends a war on the terms of an accepted offer: demands are carried out, ground still held
## goes back to its owner, armies on ground they may no longer stand on withdraw, and the
## war is filed.
static func make_peace(gs: Node, war: War, offer: Dictionary) -> void:
	var taker: String = offer.taker
	var giver: String = offer.giver
	var terms: Array[String] = []
	var score_taker := war_score(gs, war, taker)
	gs.set_war(war.a, war.b, false)
	for d: Dictionary in offer.demands:
		terms.append(_apply_demand(gs, taker, giver, d))
	var pair := [war.a, war.b]
	for id in range(1, gs.province_owner.size()):
		var o: String = gs.province_owner[id]
		var c: String = gs.province_controller[id]
		if o != c and o in pair and c in pair:
			gs.set_controller(id, o)
			gs.occupation.erase(id)
	_withdraw_armies(gs, pair)
	for f: Front in gs.fronts.values():
		f.dirty = true
	Economy.recompute(gs)
	gs.economy_updated.emit()
	var text := "%s and %s make peace" % [gs.nations[war.a].display_name, gs.nations[war.b].display_name]
	text += (": %s takes %s." % [gs.nations[taker].display_name, "; ".join(terms)]) if not terms.is_empty() else " (white peace)."
	text += offer.get("note", "")
	if not terms.is_empty():
		# Terms earn the taker standing, and cost the giver some of it.
		var pr: Dictionary = Diplomacy.cfg.points.prestige
		var earned := minf(pr.peace_cap, offer.get("cost", 0.0) * pr.peace_per_score)
		Diplomacy.gain_prestige(gs, taker, earned)
		Diplomacy.gain_prestige(gs, giver, -earned * pr.peace_loser_share)
	war.peace = {"taker": taker, "giver": giver, "terms": terms, "white": terms.is_empty(), "score": score_taker,
			"forced": offer.forced, "date": Clock.date_string()}
	war.add_log(Clock.date_string(), "peace", text)
	_separate_peace(gs, war)


static func _apply_demand(gs: Node, taker: String, giver: String, d: Dictionary) -> String:
	match d.kind:
		"province":
			var names: Array[String] = []
			var capital_lost := false
			for id: int in d.ids:
				names.append(MapData.provinces[id].name)
				capital_lost = capital_lost or id == gs.nations[giver].capital
				gs.transfer_province(id, taker)
			if capital_lost:
				_move_capital(gs, giver)
			return ", ".join(names)
		"indemnity":
			var monthly: float = d.share * gs.nations[giver].budget.revenue / 12.0
			gs.indemnities.append({"payer": giver, "receiver": taker, "monthly": monthly, "months_left": d.months})
			return "an indemnity of %.1f a month for %d months" % [monthly, d.months]
		"release_ally":
			for t in _release_treaties(gs, giver, d.nation):
				Diplomacy.end_treaty(gs, t)
			return "%s's ties to %s" % [gs.nations[giver].display_name, gs.nations[d.nation].display_name]
		"disarm_border":
			gs.restrictions.append({"nation": giver, "holder": taker,
					"provinces": Military.border_provinces(gs, giver, taker),
					"until_day": Clock.days_elapsed + int(d.years * 365)})
			return "%s's border armies withdrawn for %d years" % [gs.nations[giver].display_name, d.years]
	return ""


## A nation that loses its capital province moves to its most populous remaining one.
static func _move_capital(gs: Node, tag: String) -> void:
	var best := 0
	for id: int in gs.nations[tag].provinces:
		if best == 0 or gs.province_population[id] > gs.province_population[best]:
			best = id
	gs.nations[tag].capital = best


## Armies that now stand on ground their nation may not enter go to the nearest ground it may.
static func _withdraw_armies(gs: Node, pair: Array) -> void:
	var moved := false
	for a: Army in gs.armies.values().duplicate():
		if a.tag not in pair or a.embarked() or Military.can_enter(gs, a.tag, a.province):
			continue
		moved = true
		a.path.clear()
		a.still_days = 0
		a.attacking = false
		var seen := {a.province: true}
		var queue: Array = [a.province]
		var home := 0
		while not queue.is_empty() and home == 0:
			var here: int = queue.pop_front()
			for n: int in Military.neighbors(here):
				if seen.has(n):
					continue
				seen[n] = true
				if Military.can_enter(gs, a.tag, n):
					home = n
					break
				queue.append(n)
		if home == 0:
			gs.armies.erase(a.id)
		else:
			a.province = home
	if moved:
		gs.armies_changed.emit()


## A nation that makes peace while its side is still fighting the same enemy loses the trust
## of those still fighting, and leaves the conflict once it has no enemy left in it.
static func _separate_peace(gs: Node, war: War) -> void:
	var g: Dictionary = gs.war_groups.get(war.war_group, {})
	if g.is_empty():
		return
	var ai: Dictionary = cfg().ai
	for tag in [war.a, war.b]:
		var enemy := war.other(tag)
		var side: String = g.members.get(tag, "")
		var deserted := false
		for ally in Diplomacy.group_side(gs, g.id, side):
			if ally != tag and gs.at_war(ally, enemy):
				Diplomacy.change_relation(gs, tag, ally, ai.separate_peace_relations)
				deserted = true
		if deserted:
			gs.nations[tag].prestige += ai.separate_peace_prestige
		var still_fighting := false
		for foe in Diplomacy.group_side(gs, g.id, Diplomacy._opposite(side)):
			if gs.at_war(tag, foe):
				still_fighting = true
		if not still_fighting:
			g.members.erase(tag)


# --- Restrictions and indemnities ----------------------------------------------------------

## Whether a peace clause keeps `tag`'s armies out of a province.
static func restricted(gs: Node, tag: String, id: int) -> bool:
	for r: Dictionary in gs.restrictions:
		if r.nation == tag and Clock.days_elapsed < r.until_day and id in r.provinces and not gs.at_war(tag, r.holder):
			return true
	return false


## Monthly: battle points fade, indemnities are paid, old clauses lapse, and AI nations that
## are losing (or stuck) put an offer on the table.
static func step_month(gs: Node) -> void:
	var keep: float = 1.0 - cfg().score.decay_per_month
	for war: War in gs.wars.values():
		for tag: String in war.battle_points:
			war.battle_points[tag] *= keep
	for i in range(gs.indemnities.size() - 1, -1, -1):
		var ind: Dictionary = gs.indemnities[i]
		var payer: Nation = gs.nations[ind.payer]
		var pay := minf(ind.monthly, maxf(payer.treasury, 0.0))
		payer.treasury -= pay
		gs.nations[ind.receiver].treasury += pay
		ind.months_left -= 1
		if ind.months_left <= 0:
			gs.indemnities.remove_at(i)
	gs.restrictions = gs.restrictions.filter(func(r: Dictionary) -> bool: return Clock.days_elapsed < r.until_day)
	_ai_overtures(gs)


## AI nations at war weigh a proposal each month (see AIPeace). Offers to the player wait for
## an answer.
static func _ai_overtures(gs: Node) -> void:
	AIPeace.overtures(gs)
