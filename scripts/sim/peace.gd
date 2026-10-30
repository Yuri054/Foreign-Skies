class_name Peace
extends RefCounted
## War score, peace offers and peace terms (phase 5, step 5). Static, like Diplomacy; the data
## lives in GameState (pending_offers, indemnities, restrictions) and in each War. Constants
## are in data/diplomacy.json under "peace".
##
## War score is one number per pairwise war, from a nation's side: positive means it is
## winning. It is the ground each holds of the other (by province value: people, cities and
## buildings, the capital weighing about a third, see Capitulation), the battles won, which fade
## with time, and a capitulation.
##
## A peace offer is a set of demands. In "demand" mode the proposer takes them from the
## target; in "offer" mode the proposer gives them to the target. The side that takes can
## only ask for what its war score pays for, unless the other side has lost its capital to it.
## Demands: {kind: "province", ids}, {kind: "indemnity", share, months},
## {kind: "release_ally", nation}, {kind: "disarm_border", years}. No demands is a white peace.


static func cfg() -> Dictionary:
	return Diplomacy.cfg.peace


# --- War score -----------------------------------------------------------------------------

## What a province is worth in a war (diplomacy.json capitulation.value): its people, its city and its buildings. The
## capital's bonus is added by Capitulation.value_of. Worked out once a day.
static func province_value(gs: Node, id: int) -> float:
	var stamp := [Clock.days_elapsed, gs.get_instance_id()]
	if stamp != _value_stamp:
		_value_cache.clear()
		_city_pop.clear()
		for c in gs.cities:
			_city_pop[int(c.province)] = _city_pop.get(int(c.province), 0) + Cities.population(gs, c)
		_value_stamp = stamp
	if _value_cache.has(id):
		return _value_cache[id]
	var w: Dictionary = Diplomacy.cfg.capitulation.value
	var v: float = float(w.population) * gs.province_population[id] / 1e6 + float(w.city) * float(_city_pop.get(id, 0)) / 1e6
	var built: Dictionary = gs.province_buildings[id]
	for type: String in built:
		v += float(w.buildings.get(type, 0.0)) * float(built[type])
	v = maxf(v, float(w.minimum))
	_value_cache[id] = v
	return v


static var _value_cache := {}
static var _city_pop := {}
static var _value_stamp: Array = []


## Forgets the day's province values (a new game or a loaded save).
static func clear_cache() -> void:
	_value_stamp = []
	Capitulation._stamp = []


## Share of a nation's whole value (Capitulation.whole_value) that one province carries, the capital bonus included, 0..1.
static func province_share(gs: Node, id: int, tag: String) -> float:
	var whole := Capitulation.whole_value(gs, tag)
	return Capitulation.value_of(gs, id, tag) / whole if whole > 0.0 else 0.0


## Score `holder` earns for the share of `owner`'s value it holds.
static func occupation_points(gs: Node, holder: String, owner: String) -> float:
	return Capitulation.progress(gs, owner, holder) * float(cfg().score.occupation_points)


## The part of occupation_points that is the capital bonus: what `holder` earns for holding `owner`'s capital (home, and
## a moved one).
static func capital_points(gs: Node, holder: String, owner: String) -> float:
	var whole := Capitulation.whole_value(gs, owner)
	if whole <= 0.0:
		return 0.0
	var bonus := Capitulation.capital_bonus(gs, owner)
	var held := 0.0
	var home := Capitulation.home_capital(gs, owner)
	if home > 0 and gs.province_controller[home] == holder:
		held += bonus
	if Capitulation.relocated(gs, owner) and gs.province_controller[gs.nations[owner].capital] == holder:
		held += bonus * float(Diplomacy.cfg.capitulation.relocated_bonus)
	return held / whole * float(cfg().score.occupation_points)


## The share of `owner`'s weight (people and output) that `holder` occupies, 0..1.
static func occupied_share(gs: Node, holder: String, owner: String) -> float:
	return occupation_points(gs, holder, owner) / float(cfg().score.occupation_points)


static func _owned_by(gs: Node, ids: Array, tag: String) -> bool:
	if ids.is_empty():
		return false
	for id in ids:
		if not (id is int) or id < 1 or id >= gs.province_owner.size() or gs.province_owner[id] != tag:
			return false
	return true


## Whether `giver` is beaten badly enough that `taker` may dictate terms (see check): its people will not fight on,
## or the taker holds its capital and its war support is at the floor, or the taker holds most of it.
static func is_forced(gs: Node, taker: String, giver: String) -> bool:
	if Capitulation.capitulated(gs, giver):
		return true
	var support: float = gs.nations[giver].war_support
	var ws: Dictionary = Diplomacy.cfg.war_support
	if support <= float(ws.surrender_at):
		return true
	if capital_taken_by(gs, giver) == taker and support <= float(ws.floor):
		return true
	return occupied_share(gs, taker, giver) >= float(cfg().forced.occupied_share)


## Who holds a nation's (home) capital if it is not the nation itself, else "".
static func capital_taken_by(gs: Node, tag: String) -> String:
	var home := Capitulation.home_capital(gs, tag)
	if home <= 0:
		return ""
	var holder: String = gs.province_controller[home]
	return "" if holder == tag else holder


## The parts of `tag`'s war score in a war, and their sum (clamped): occupation (ground held, by province value), capital
## (the part of that ground that is the capital bonus), battles, capitulation and total.
static func score_parts(gs: Node, war: War, tag: String) -> Dictionary:
	var c: Dictionary = cfg().score
	var other := war.other(tag)
	var capital := capital_points(gs, tag, other) - capital_points(gs, other, tag)
	var occupation := occupation_points(gs, tag, other) - occupation_points(gs, other, tag) - capital
	var battles: float = war.battle_points.get(tag, 0.0) - war.battle_points.get(other, 0.0)
	var surrender := 0.0
	var points := float(Diplomacy.cfg.capitulation.score)
	if war.capitulated.has(other):
		surrender += points
	if war.capitulated.has(tag):
		surrender -= points
	return {"occupation": occupation, "capital": capital, "battles": battles, "capitulation": surrender,
			"total": clampf(occupation + capital + battles + surrender, -c.max, c.max)}


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

## Score a province costs to take from `giver`: its share of the nation's value (the capital's bonus included), cheaper
## if the taker already holds it.
static func province_price(gs: Node, id: int, taker: String, giver: String) -> float:
	var p: Dictionary = cfg().price
	var price: float = p.province_scale * province_share(gs, id, giver)
	if gs.province_controller[id] == taker:
		price *= p.occupied_discount
	return price


static func _sea_link(gs: Node, taker: String, id: int) -> bool:
	var pz: Dictionary = MapData.port_zones.get(id, {})
	for zone: int in [int(pz.get("zone", 0)), int(pz.get("zone2", 0))]:
		if zone <= 0:
			continue
		if Blockade.holds(gs, taker, zone):
			return true
		for q: int in MapData.ports_in_zone(zone):
			if gs.province_owner[q] == taker:
				return true
	return false


## The provinces of `ids` that would not touch the taker's land, by land or by a sea it holds or opens on: one search
## outward from those that touch it directly, through the rest of `ids`.
static func detached(gs: Node, taker: String, ids: Array) -> Array:
	var wanted := {}
	for id: int in ids:
		wanted[id] = true
	var reached := {}
	var queue: Array = []
	for id: int in ids:
		if _touches(gs, taker, id):
			reached[id] = true
			queue.append(id)
	while not queue.is_empty():
		var p: int = queue.pop_back()
		for n: int in Military.neighbors(p):
			if wanted.has(n) and not reached.has(n):
				reached[n] = true
				queue.append(n)
	var out: Array = []
	for id: int in ids:
		if not reached.has(id):
			out.append(id)
	return out


## Whether a province touches the taker's own land, or a sea it holds or has a coast on.
static func _touches(gs: Node, taker: String, id: int) -> bool:
	for n: int in Military.neighbors(id):
		if gs.province_owner[n] == taker:
			return true
	return _sea_link(gs, taker, id)


## Why a set of the giver's provinces cannot be taken ("" if it can): "detached" (some would not touch the taker's
## land) or "capital" (the capital, without the whole nation).
static func province_problem(gs: Node, taker: String, giver: String, ids: Array) -> String:
	var cap: int = gs.nations[giver].capital
	if cap in ids and ids.size() < gs.nations[giver].provinces.size():
		return "capital"
	if not detached(gs, taker, ids).is_empty():
		return "detached"
	return ""


## Whether `id` could join `chosen`, a set of the giver's provinces that can already be taken, and keep it so: it
## touches the taker's land or one of `chosen`, and it is not the capital unless it completes the nation.
static func can_add(gs: Node, taker: String, giver: String, id: int, chosen: Array) -> bool:
	if id == gs.nations[giver].capital and chosen.size() + 1 < gs.nations[giver].provinces.size():
		return false
	if _touches(gs, taker, id):
		return true
	for n: int in Military.neighbors(id):
		if n in chosen:
			return true
	return false


## The most provinces `giver` may hand over in one treaty: a great power at most peace.great_power_max_share of what it
## has (a great power is not carved up at one peace table); any other nation all of them.
static func max_cession(gs: Node, giver: String) -> int:
	var count: int = gs.nations[giver].provinces.size()
	if giver not in Pressure.GREAT:
		return count
	return maxi(1, floori(count * float(cfg().get("great_power_max_share", 1.0))))


## Picks from `candidates` (the giver's provinces, best first) what `budget` pays for at `price_of(id)` and can be
## taken together (see province_problem), at most max_cession of them: passes over the list until nothing more fits,
## since a province can only join once one between it and the taker's land has. Returns {ids, spent}.
static func pick_takeable(gs: Node, taker: String, giver: String, candidates: Array, price_of: Callable, budget: float) -> Dictionary:
	var ids: Array = []
	var spent := 0.0
	var added := true
	var cap := max_cession(gs, giver)
	while added and ids.size() < cap:
		added = false
		for id: int in candidates:
			if ids.size() >= cap:
				break
			if id in ids:
				continue
			var price: float = price_of.call(id)
			if spent + price <= budget and can_add(gs, taker, giver, id, ids):
				ids.append(id)
				spent += price
				added = true
	return {"ids": ids, "spent": spent}


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
			if province_problem(gs, taker, giver, ids) != "":
				return -1.0
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
		"fleet_limit":
			var years: int = d.get("years", 0)
			if years < 1 or years > p.disarm_years_max or Navy.strength_of(gs, giver) <= 0.0:
				return -1.0
			return float(p.fleet_limit_per_year) * years * f
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
			return "an indemnity of %d%% of income for %d months" % [roundi(d.share * 100.0), d.months]
		"release_ally":
			return "an end to its ties with %s" % gs.nations[d.nation].display_name
		"disarm_border":
			return "its border armies withdrawn for %d years" % d.years
		"fleet_limit":
			return "no new warships for %d years" % d.years
	return "?"


static func _release_treaties(gs: Node, giver: String, other: String) -> Array[Treaty]:
	var out: Array[Treaty] = []
	for t in Diplomacy.treaties_between(gs, giver, other):
		if t.kind == "alliance" or t.kind == "guarantee":
			out.append(t)
	return out


## Checks a proposal. Returns {ok, reason, cost, budget, taker, giver, forced, war}. Reasons: no_war,
## pending (an offer is already waiting in this war), cooldown, detached (a province would not touch the taker's
## land), capital (the capital without the whole nation), invalid (another demand cannot be made), forced_terms (a
## beaten nation is asked for ground the taker neither holds nor fights for), too_much (more of a great power's provinces
## than max_cession), too_expensive (the taker's score, or
## a beaten nation's larger budget, does not pay for it).
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
	var terms := check_terms(gs, war, out.taker, out.giver, demands)
	for k: String in terms:
		out[k] = terms[k]
	out.ok = terms.reason == ""
	return out


## The part of check that looks at the terms alone: {reason, cost, budget, forced}, reason "" when they can be made.
static func check_terms(gs: Node, war: War, taker: String, giver: String, demands: Array) -> Dictionary:
	var out := {"reason": "", "cost": 0.0, "budget": 0.0, "forced": false, "taker": taker, "giver": giver}
	var cost := 0.0
	var ceded := 0
	for d: Dictionary in demands:
		if d.get("kind", "") == "province":
			ceded += d.get("ids", []).size()
	if ceded > max_cession(gs, out.giver):
		out.reason = "too_much"
		return out
	for d: Dictionary in demands:
		var c := demand_cost(gs, out.taker, out.giver, d)
		if c < 0.0:
			out.reason = "invalid"
			if d.get("kind", "") == "province" and _owned_by(gs, d.get("ids", []), out.giver):
				var problem := province_problem(gs, out.taker, out.giver, d.ids)
				if problem != "":
					out.reason = problem
			return out
		cost += c
	out.cost = cost
	out.forced = is_forced(gs, out.taker, out.giver)
	var score := war_score(gs, war, out.taker)
	out.budget = score
	if out.forced:
		# A beaten nation gives more than the score pays for, but only the ground the taker holds, the war's goal and money.
		out.budget = maxf(score, 0.0) * float(cfg().forced.budget_mult)
		var goal_ids: Array = war.goal.get("ids", []) if war.a == out.taker else []
		for d: Dictionary in demands:
			if d.get("kind", "") != "province":
				continue
			for id: int in d.ids:
				if gs.province_controller[id] != out.taker and id not in goal_ids:
					out.reason = "forced_terms"
					return out
	if cost > 0.0 and cost > out.budget:
		out.reason = "too_expensive"
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
	if to == gs.player_tag and Capitulation.capitulated(gs, to) and mode == "demand":
		# The player has capitulated: the victor's terms are not asked, they are imposed.
		result.accepted = true
		_resolve(gs, offer, true)
		gs.news_posted.emit("%s dictates its peace: %s." % [gs.nations[from].display_name,
				"; ".join(demands.map(func(d: Dictionary) -> String: return describe_demand(gs, d))) if not demands.is_empty() else "a white peace"], 2)
		return result
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
	return check_terms(gs, war, offer.taker, offer.giver, offer.demands).reason == ""


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
	var picked := pick_takeable(gs, winner, loser, held, func(id: int) -> float: return province_price(gs, id, winner, loser), budget)
	var ids: Array = picked.ids
	var spent: float = picked.spent
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
	History.refine_last(gs, "peace", text)
	_separate_peace(gs, war)


## `at_war`: carried out at a peace (false for a demand yielded in a crisis; see Diplomacy.revanche).
static func _apply_demand(gs: Node, taker: String, giver: String, d: Dictionary, at_war := true) -> String:
	match d.kind:
		"province":
			var names: Array[String] = []
			var capital_lost := false
			for id: int in d.ids:
				names.append(MapData.provinces[id].name)
				capital_lost = capital_lost or id == gs.nations[giver].capital
				gs.transfer_province(id, taker)
			Diplomacy.revanche(gs, giver, taker, d.ids, at_war)
			if capital_lost:
				_move_capital(gs, giver)
			return ", ".join(names)
		"indemnity":
			var monthly: float = d.share * gs.nations[giver].budget.income
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
		"fleet_limit":
			gs.restrictions.append({"nation": giver, "holder": taker, "kind": "fleet_limit", "provinces": [],
					"until_day": Clock.days_elapsed + int(d.years * 365)})
			return "no new warships for %s for %d years" % [gs.nations[giver].display_name, d.years]
	return ""


## A nation that loses its capital province moves to its most populous remaining one (its new home capital).
static func _move_capital(gs: Node, tag: String) -> void:
	var best := 0
	for id: int in gs.nations[tag].provinces:
		if best == 0 or gs.province_population[id] > gs.province_population[best]:
			best = id
	gs.nations[tag].capital = best
	gs.nations[tag].home_capital = best


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


## The nations making peace together at a conference (see Conference): none of them deserts another.
static var joint_tags: Array[String] = []


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
			if ally != tag and gs.at_war(ally, enemy) and not (ally in joint_tags and tag in joint_tags):
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


## Whether a peace clause or a yielded demand forbids `tag` new warships (not while it fights the nation that holds it).
static func fleet_limited(gs: Node, tag: String) -> bool:
	for r: Dictionary in gs.restrictions:
		if r.nation == tag and r.get("kind", "") == "fleet_limit" and Clock.days_elapsed < r.until_day and not gs.at_war(tag, r.holder):
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
