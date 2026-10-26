class_name Conference
extends RefCounted
## A peace conference: the nations on one side of a war between groups of nations make peace with the same enemy together.
## Each partner at war with the enemy asks for what its own goal and its own war score pay for (see WarGoal and Peace);
## the package is offered to the enemy whole and taken or refused whole. A refusal may bring a counter-offer, the
## package with the dearest of the demands struck out until the enemy would take it. The partner with the highest war
## score chairs the conference and gains standing. Static, like Peace; a counter-offer waiting for the player is in
## GameState.conference_counter.


## The nations on `tag`'s side that are at war with `enemy`, tag order (not `tag` itself).
static func partners(gs: Node, tag: String, enemy: String) -> Array[String]:
	var out: Array[String] = []
	var war: War = gs.war_between(tag, enemy)
	if war == null:
		return out
	var g: Dictionary = gs.war_groups.get(war.war_group, {})
	var side: String = g.get("members", {}).get(tag, "")
	if side == "":
		return out
	for member: String in Diplomacy.group_side(gs, g.id, side):
		if member != tag and gs.at_war(member, enemy):
			out.append(member)
	return out


## What a partner would ask of the enemy: terms for its goal that its war score pays for, {} (a white peace for it) if none.
static func partner_terms(gs: Node, partner: String, enemy: String) -> Array:
	var war: War = gs.war_between(partner, enemy)
	if war == null:
		return []
	var terms := AIPeace.price_terms(gs, partner, enemy, war)
	return terms if Peace.check(gs, partner, enemy, "demand", terms).ok else []


## The package as entries [{tag, demands}]: the proposer's own demands first, then each included partner's.
static func entries_for(gs: Node, tag: String, enemy: String, own: Array, included: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"tag": tag, "demands": own.duplicate(true)}]
	for p in partners(gs, tag, enemy):
		if p in included:
			out.append({"tag": p, "demands": partner_terms(gs, p, enemy)})
	return out


## The offer one entry makes (the shape Peace.propose builds), with its check; {} if it cannot be made.
static func offer_of(gs: Node, entry: Dictionary, enemy: String) -> Dictionary:
	var c := Peace.check(gs, entry.tag, enemy, "demand", entry.demands)
	if not c.ok:
		return {}
	return {"id": gs.next_offer_id, "war_id": c.war.id, "from": entry.tag, "to": enemy, "mode": "demand", "taker": c.taker, "giver": c.giver,
			"demands": entry.demands.duplicate(true), "cost": c.cost, "forced": c.forced, "day": Clock.days_elapsed}


## Whether every entry can be made and the enemy (an AI) would take the package whole: each entry on its own, the
## cost of all of them together against its strongest wish for peace (what a beaten nation must give aside), and every
## indemnity together against what it can carry.
static func acceptable(gs: Node, entries: Array, enemy: String) -> bool:
	var total := 0.0
	var urge := -INF
	var indemnities: Array = []
	for e: Dictionary in entries:
		var offer := offer_of(gs, e, enemy)
		if offer.is_empty() or not AIPeace.accepts(gs, offer):
			return false
		if not offer.forced:
			total += float(offer.cost)
		urge = maxf(urge, AIPeace.urge(gs, enemy, gs.war_between(e.tag, enemy)))
		for d: Dictionary in e.demands:
			if d.get("kind", "") == "indemnity":
				indemnities.append(d)
	if entries.size() > 1 and total > 0.0 and total > urge:
		return false
	return indemnities.is_empty() or AIPeace.affordable(gs, enemy, indemnities)


## The nation that chairs: the partner (or proposer) with the highest war score against the enemy.
static func chairman(gs: Node, entries: Array, enemy: String) -> String:
	var best := ""
	var best_score := -INF
	for e: Dictionary in entries:
		var war: War = gs.war_between(e.tag, enemy)
		if war == null:
			continue
		var s := Peace.war_score(gs, war, e.tag)
		if s > best_score:
			best = e.tag
			best_score = s
	return best


## The package with demands struck out, the dearest that are not the entry's goal first, until the enemy would take it:
## {entries} or {} if nothing smaller will do. The proposer's own entry keeps its goal demands to the last.
static func counter(gs: Node, entries: Array, enemy: String) -> Dictionary:
	var trimmed: Array[Dictionary] = []
	for e: Dictionary in entries:
		trimmed.append({"tag": e.tag, "demands": e.demands.duplicate(true)})
	for _round in 12:
		if acceptable(gs, trimmed, enemy):
			var any := false
			for e: Dictionary in trimmed:
				any = any or not e.demands.is_empty()
			return {"entries": trimmed} if any else {}
		# Strike the dearest demand left, goal demands last.
		var pick := {"entry": -1, "demand": -1, "key": -INF}
		for i in trimmed.size():
			var war: War = gs.war_between(trimmed[i].tag, enemy)
			for j in trimmed[i].demands.size():
				var d: Dictionary = trimmed[i].demands[j]
				var cost := Peace.demand_cost(gs, trimmed[i].tag, enemy, d)
				var is_goal: bool = war != null and WarGoal.price_factor(war, trimmed[i].tag, d, d.get("ids", [0])[0]) < 1.0
				var key := cost - (1000.0 if is_goal else 0.0)
				if key > pick.key:
					pick = {"entry": i, "demand": j, "key": key}
		if pick.entry < 0:
			return {}
		var d: Dictionary = trimmed[pick.entry].demands[pick.demand]
		# A demand for several provinces loses its dearest province first (one whose loss leaves the rest takeable);
		# any other is struck out.
		if d.get("kind", "") == "province" and d.ids.size() > 1:
			var tag: String = trimmed[pick.entry].tag
			var ids: Array = d.ids.duplicate()
			ids.sort_custom(func(x: int, y: int) -> bool: return Peace.province_price(gs, x, tag, enemy) > Peace.province_price(gs, y, tag, enemy))
			var drop := 0
			for k in ids.size():
				var rest := ids.duplicate()
				rest.remove_at(k)
				if Peace.province_problem(gs, tag, enemy, rest) == "":
					drop = k
					break
			ids.remove_at(drop)
			trimmed[pick.entry].demands[pick.demand] = {"kind": "province", "ids": ids}
		else:
			trimmed[pick.entry].demands.remove_at(pick.demand)
	return {}


## Makes the peace of every entry with the enemy. Returns the entries that went through.
static func execute(gs: Node, entries: Array, enemy: String) -> Array[String]:
	var done: Array[String] = []
	var chair := chairman(gs, entries, enemy)
	Peace.joint_tags.clear()
	for e: Dictionary in entries:
		Peace.joint_tags.append(e.tag)
	for e: Dictionary in entries:
		var offer := offer_of(gs, e, enemy)
		var war: War = gs.war_between(e.tag, enemy)
		if offer.is_empty() or war == null:
			continue
		gs.next_offer_id += 1
		Peace.make_peace(gs, war, offer)
		done.append(e.tag)
	Peace.joint_tags.clear()
	if chair != "" and done.size() > 1:
		Diplomacy.gain_prestige(gs, chair, float(Peace.cfg().conference_prestige))
		History.note(gs, "peace", "%s chaired the conference that ended the war with %s (%d nations at the table)." % [gs.nations[chair].display_name, gs.nations[enemy].display_name, done.size()])
	return done


## The proposer offers the package to the enemy. Returns {ok, reason, accepted}: `accepted` is true or false once an AI
## enemy has answered (a refusal may leave a counter-offer for the proposer, see counter_for); null while a player enemy must.
static func propose(gs: Node, tag: String, enemy: String, own: Array, included: Array) -> Dictionary:
	var result := {"ok": false, "reason": "", "accepted": false}
	var entries := entries_for(gs, tag, enemy, own, included)
	if gs.war_between(tag, enemy) == null:
		result.reason = "no_war"
		return result
	for e: Dictionary in entries:
		if offer_of(gs, e, enemy).is_empty():
			result.reason = "invalid"
			return result
	result.ok = true
	if enemy == gs.player_tag:
		# An enemy that is the player is not asked through a conference: it gets the peace offers one by one.
		for e: Dictionary in entries:
			Peace.propose(gs, e.tag, enemy, "demand", e.demands)
		result.accepted = null
		return result
	if acceptable(gs, entries, enemy):
		result.accepted = true
		execute(gs, entries, enemy)
		return result
	# Refused: the proposer may be offered less.
	var c := counter(gs, entries, enemy)
	if not c.is_empty() and tag == gs.player_tag:
		gs.conference_counter = {"from": tag, "enemy": enemy, "entries": c.entries, "day": Clock.days_elapsed,
				"until_day": Clock.days_elapsed + int(Peace.cfg().counter_days)}
	gs.peace_cooldown[Diplomacy.pair_key(tag, enemy)] = Clock.days_elapsed + Peace.cfg().ai.refuse_cooldown_days
	return result


## The counter-offer waiting for the player, or {} if there is none or it has lapsed (an old one is dropped).
static func waiting_counter(gs: Node) -> Dictionary:
	var c: Dictionary = gs.conference_counter
	if c.is_empty():
		return c
	if Clock.days_elapsed > int(c.get("until_day", int(c.get("day", 0)) + int(Peace.cfg().counter_days))) or gs.war_between(c.from, c.enemy) == null:
		gs.conference_counter = {}
		return {}
	return c


## The player's answer to a counter-offer. Returns false if none is waiting, it has lapsed, or the enemy would no
## longer take it (the war has moved on since it was made).
static func answer_counter(gs: Node, accept: bool) -> bool:
	var c := waiting_counter(gs)
	if c.is_empty():
		return false
	gs.conference_counter = {}
	if not accept:
		return true
	if not acceptable(gs, c.entries, c.enemy):
		return false
	return not execute(gs, c.entries, c.enemy).is_empty()
