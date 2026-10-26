class_name Crisis
extends RefCounted
## Dynamic crises between nations (data/crises.json): a nation makes a demand of a rival with a deadline, and the
## rival yields, refuses, mobilizes or appeals; third nations may mediate or back a side. Static, like Pressure;
## the crises under way are in GameState.crises and the finished ones in crisis_log. A crisis is
## {id, kind, a, b, demand, goal, start_day, think_day, deadline_day, backers_a, backers_b, text}: `a` is the
## demander, `b` the nation asked, `demand` a peace demand (see Peace) and `goal` what a war over it would be for
## (see WarGoal).

const CONFIG_PATH := "res://data/crises.json"

static var cfg: Dictionary = {}


static func load_config() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	assert(data is Dictionary, "crises.json is invalid")
	cfg = data


static func load_scenario(gs: Node) -> void:
	gs.crises.clear()
	gs.crisis_log.clear()
	gs.crisis_cooldown.clear()
	gs.next_crisis_id = 1


# --- Reading ---------------------------------------------------------------------------------

static func find(gs: Node, id: int) -> Dictionary:
	for c: Dictionary in gs.crises:
		if c.id == id:
			return c
	return {}


## The crises a nation is a party to.
static func of(gs: Node, tag: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Dictionary in gs.crises:
		if c.a == tag or c.b == tag:
			out.append(c)
	return out


## The nations on a side of a crisis ("a" or "b"): the party, its allies and guarantors (those not allied to the
## other side), and whoever was asked to back it.
static func side(gs: Node, c: Dictionary, which: String) -> Array[String]:
	var own: String = c[which]
	var other: String = c.b if which == "a" else c.a
	var out: Array[String] = [own]
	var friends: Array[String] = Diplomacy.allies_of(gs, own)
	friends.append_array(Diplomacy.guarantors_of(gs, own) if which == "b" else [])
	for t in friends + Array(c["backers_" + which], TYPE_STRING, "", null):
		if t not in out and t != other and gs.nations.has(t) and not Diplomacy.are_allied(gs, t, other) and not gs.at_war(t, own):
			out.append(t)
	return out


## How much stronger `a`'s side is than `b`'s (armies in the field).
static func odds_a(gs: Node, c: Dictionary) -> float:
	return AIDiplomacy.side_power(gs, side(gs, c, "a")) / maxf(AIDiplomacy.side_power(gs, side(gs, c, "b")), 0.01)


## What the demand is, in words.
static func what(gs: Node, c: Dictionary) -> String:
	return Peace.describe_demand(gs, c.demand)


## The great powers (not the parties) that could mediate, best chance first: [{tag, chance}].
static func mediators(gs: Node, c: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tag: String in Pressure.GREAT:
		if tag == c.a or tag == c.b or not gs.nations.has(tag) or gs.nations[tag].provinces.is_empty():
			continue
		if gs.at_war(tag, c.a) or gs.at_war(tag, c.b):
			continue
		out.append({"tag": tag, "chance": mediation_chance(gs, c, tag)})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.chance > y.chance or (x.chance == y.chance and x.tag < y.tag))
	return out


## The chance that `tag` brings the two to a compromise: its standing and the goodwill it holds with both.
static func mediation_chance(gs: Node, c: Dictionary, tag: String) -> float:
	var m: Dictionary = cfg.mediate
	var rel: float = Diplomacy.relation(gs, tag, c.a) + Diplomacy.relation(gs, tag, c.b)
	return clampf(float(m.base) + float(m.prestige_weight) * gs.nations[tag].prestige + float(m.relation_weight) * rel, 0.0, 0.95)


static func _succeeds(gs: Node, c: Dictionary, tag: String) -> bool:
	return mediation_chance(gs, c, tag) + 0.2 * AI.noise(gs, "mediate|%d|%s" % [c.id, tag]) >= float(cfg.mediate.threshold)


# --- Opening ---------------------------------------------------------------------------------

## Monthly: old crises that nobody answered lapse, and the worst quarrel in the world may open a new one.
static func step_month(gs: Node) -> void:
	if not gs.pressure_ai or Clock.days_elapsed < int(cfg.gate.start_days):
		return
	if gs.crisis_cooldown.get("_any", -1) > Clock.days_elapsed:
		return
	# Europe already at war has no attention for new quarrels.
	if gs.wars.size() > int(cfg.gate.max_wars):
		return
	var opened := 0
	while opened < int(cfg.gate.per_month) and gs.crises.size() < int(cfg.gate.max_active):
		var found := best_candidate(gs)
		if found.is_empty():
			break
		if not open(gs, found).is_empty():
			gs.crisis_cooldown["_any"] = Clock.days_elapsed + int(cfg.gate.min_gap_months) * 30
		opened += 1


## The score of a quarrel: how much `a` is set against `b` and able to press it.
static func score(gs: Node, a: String, b: String) -> float:
	var w: Dictionary = cfg.score
	var hostile := clampf(-Diplomacy.relation(gs, b, a) / 100.0, 0.0, 1.0)
	var s: float = float(w.hostile) * hostile
	s += float(w.grievance) * Diplomacy.grievance(gs, a, b) / 100.0
	# Ground lost at a living memory's peace is pressed at any tension; an old scenario claim only once Europe is tense.
	if not Diplomacy.revanche_ids(gs, a, b).is_empty():
		s += float(w.claim)
	elif _claim_cb(gs, a, b) != "" and gs.tension >= float(cfg.gate.get("claim_min_tension", 0.0)):
		s += float(w.claim)
	if gs.alarms.has("%s>%s" % [b, a]):
		s += float(w.alarm)
	s += float(w.tension) * gs.tension / 100.0
	var odds := AIDiplomacy.side_power(gs, [a]) / maxf(AIDiplomacy.side_power(gs, [b]), 0.01)
	s += float(w.edge) * clampf(odds - 1.0, 0.0, 1.0)
	return s


static func _claim_cb(gs: Node, a: String, b: String) -> String:
	for cb in Diplomacy.casus_belli_options(gs, a, b):
		if cb in ["reconquest", "border_claim", "national_claim"]:
			return cb
	return ""


## Whether a crisis may open between the two now.
static func may_quarrel(gs: Node, a: String, b: String) -> bool:
	if a == gs.player_tag or not gs.nations.has(a) or not gs.nations.has(b):
		return false
	if gs.nations[a].provinces.is_empty() or gs.nations[b].provinces.is_empty():
		return false
	if Diplomacy.declare_block(gs, a, b) != "" or AIDiplomacy.in_truce(gs, a, b):
		return false
	for c: Dictionary in gs.crises:
		if a in [c.a, c.b] or b in [c.a, c.b]:
			return false
	if gs.crisis_cooldown.get(Diplomacy.pair_key(a, b), -1) > Clock.days_elapsed:
		return false
	# The odds of the two sides, allies and guarantors with them, as the nation asked will weigh them.
	var draft := {"a": a, "b": b, "backers_a": [], "backers_b": []}
	return odds_a(gs, draft) >= float(cfg.gate.min_odds)


## The best quarrel at or above the gate: {a, b, score}, or {}.
static func best_candidate(gs: Node) -> Dictionary:
	var best := {}
	var tags: Array = gs.nations.keys()
	tags.sort()
	for a: String in tags:
		if gs.nations[a].provinces.is_empty() or a == gs.player_tag:
			continue
		var targets: Array[String] = Diplomacy.neighbor_nations(gs, a).duplicate()
		if a in Pressure.GREAT:
			for g: String in Pressure.GREAT:
				if g != a and g not in targets:
					targets.append(g)
		targets.sort()
		for b: String in targets:
			if not may_quarrel(gs, a, b):
				continue
			var s := score(gs, a, b) + 0.05 * AI.noise(gs, "crisis|%s|%s|%d" % [a, b, Clock.year * 12 + Clock.month])
			if s >= float(cfg.gate.min_score) and (best.is_empty() or s > best.score):
				best = {"a": a, "b": b, "score": s}
	return best


## Every demand `a` could make of `b` now: [{kind, label, demand, goal}], best first (the weights of data/crises.json).
static func demand_options(gs: Node, a: String, b: String) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	# Revanche: ground `a` lost to `b` at a peace, as much of it as could be handed over.
	var lost := Diplomacy.revanche_ids(gs, a, b)
	if not lost.is_empty():
		var back: Array = Peace.pick_takeable(gs, a, b, lost, func(_id: int) -> float: return 0.0, INF).ids
		if not back.is_empty():
			options.append({"kind": "revanche", "demand": {"kind": "province", "ids": back}, "goal": WarGoal.provinces_goal(back)})
	var cb := _claim_cb(gs, a, b)
	# An old claim is pressed only once Europe is tense enough for it (not the first spring of a calm 1900).
	if cb != "" and gs.tension >= float(cfg.gate.get("claim_min_tension", 0.0)):
		var goal := WarGoal.for_declaration(gs, a, b, cb)
		if goal.has("ids") and not goal.ids.is_empty():
			# Only what could be handed over: the claimed ground that touches the demander's, never the capital alone.
			var ids: Array = Peace.pick_takeable(gs, a, b, goal.ids, func(_id: int) -> float: return 0.0, INF).ids
			if not ids.is_empty():
				goal.ids = ids
				options.append({"kind": "claim", "demand": {"kind": "province", "ids": ids}, "goal": goal})
	var border: Dictionary = cfg.kinds.border
	var edge: Array = []
	for id: int in gs.nations[b].provinces:
		if id == gs.nations[b].capital:
			continue
		for n: int in Military.neighbors(id):
			if gs.province_owner[n] == a:
				var share := Peace.province_share(gs, id, b)
				if share <= float(border.max_share):
					edge.append([id, share])
				break
	if not edge.is_empty():
		edge.sort_custom(func(x: Array, y: Array) -> bool: return x[1] > y[1] or (x[1] == y[1] and x[0] < y[0]))
		var ids: Array = []
		for e: Array in edge.slice(0, int(border.max_provinces)):
			ids.append(e[0])
		options.append({"kind": "border", "demand": {"kind": "province", "ids": ids}, "goal": WarGoal.provinces_goal(ids)})
	var ind: Dictionary = cfg.kinds.indemnity
	if Diplomacy.grievance(gs, a, b) >= float(ind.min_grievance):
		var d := {"kind": "indemnity", "share": ind.share, "months": ind.months}
		options.append({"kind": "indemnity", "demand": d, "goal": WarGoal.concession_goal(d)})
	if gs.alarms.has("%s>%s" % [b, a]) and not Military.border_provinces(gs, b, a).is_empty():
		var d2 := {"kind": "disarm_border", "years": cfg.kinds.disarm.years}
		options.append({"kind": "disarm", "demand": d2, "goal": WarGoal.concession_goal(d2)})
	# A naval rivalry: a great power with a fleet of some weight asks another to build no more warships.
	var naval: Dictionary = cfg.kinds.naval
	if a in Pressure.GREAT and b in Pressure.GREAT and not Peace.fleet_limited(gs, b):
		var theirs := Navy.strength_of(gs, b)
		if theirs > 0.0 and Navy.strength_of(gs, a) >= theirs * float(naval.min_ratio):
			var d3 := {"kind": "fleet_limit", "years": naval.years}
			options.append({"kind": "naval", "demand": d3, "goal": WarGoal.concession_goal(d3)})
	for o: Dictionary in options:
		o["label"] = Peace.describe_demand(gs, o.demand)
		o["weight"] = float(cfg.kinds[o.kind].weight) + 0.05 * AI.noise(gs, "kind|%s|%s|%s" % [a, b, o.kind])
	options.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.weight > y.weight)
	return options


## The demand `a` would make of `b`: {kind, demand, goal} or {} when nothing is there to ask for.
static func choose_demand(gs: Node, a: String, b: String) -> Dictionary:
	var options := demand_options(gs, a, b)
	return options[0] if not options.is_empty() else {}


## Why the player (`a`) cannot press a demand on `b` now ("" if it can): unknown, points, at_war, allied, nap, busy (one of
## them is in a crisis), rest (they quarrelled lately), nothing (no demand to make).
static func press_block(gs: Node, a: String, b: String) -> String:
	var why := Diplomacy.declare_block(gs, a, b)
	if why != "":
		return why
	for c: Dictionary in gs.crises:
		if a in [c.a, c.b] or b in [c.a, c.b]:
			return "busy"
	if gs.crisis_cooldown.get(Diplomacy.pair_key(a, b), -1) > Clock.days_elapsed:
		return "rest"
	if not Diplomacy.can_afford(gs, a, float(cfg.press.cost_points)):
		return "points"
	if demand_options(gs, a, b).is_empty():
		return "nothing"
	return ""


## `a` (the player) presses a demand of `kind` on `b`: opens the crisis, for points. Returns it, or {} if it cannot be done.
static func press(gs: Node, a: String, b: String, kind: String) -> Dictionary:
	if press_block(gs, a, b) != "":
		return {}
	var pick := {}
	for o: Dictionary in demand_options(gs, a, b):
		if o.kind == kind:
			pick = o
	if pick.is_empty():
		return {}
	Diplomacy.spend(gs, a, float(cfg.press.cost_points))
	return open(gs, {"a": a, "b": b, "score": 0.0}, pick)


## Opens a crisis for a found quarrel. Returns the crisis ({} if there is nothing to demand).
static func open(gs: Node, found: Dictionary, chosen := {}) -> Dictionary:
	var a: String = found.a
	var b: String = found.b
	var pick := chosen if not chosen.is_empty() else choose_demand(gs, a, b)
	if pick.is_empty():
		gs.crisis_cooldown[Diplomacy.pair_key(a, b)] = Clock.days_elapsed + 90
		return {}
	var c := {"id": gs.next_crisis_id, "kind": pick.kind, "a": a, "b": b, "demand": pick.demand, "goal": pick.goal,
			"start_day": Clock.days_elapsed, "think_day": Clock.days_elapsed + int(cfg.gate.think_days),
			"deadline_day": Clock.days_elapsed + int(cfg.gate.deadline_days), "backers_a": [], "backers_b": []}
	gs.next_crisis_id += 1
	_ai_backers(gs, c)
	gs.crises.append(c)
	var def: Dictionary = cfg.kinds[pick.kind]
	var deadline := Clock.date_after(int(cfg.gate.deadline_days))
	var roles := {"a": a, "b": b}
	c["title"] = Pressure._fill(gs, def.title, roles)
	c["text"] = Pressure._fill(gs, def.text, roles).replace("{what}", what(gs, c)).replace("{date}", deadline)
	gs.tension_impulse += float(cfg.open.tension)
	Diplomacy.change_relation(gs, a, b, float(cfg.open.relation))
	gs.crisis_cooldown[Diplomacy.pair_key(a, b)] = Clock.days_elapsed + int(cfg.gate.pair_cooldown_months) * 30
	Pressure._record(gs, c.title, c.text, 1, "crisis")
	gs.crisis_opened.emit(c)
	if b == gs.player_tag:
		_ask_player(gs, c)
	return c


## AI nations with a tie to one side and none to the other stand behind it from the start.
static func _ai_backers(gs: Node, c: Dictionary) -> void:
	var need: float = cfg.back.ai_relation
	for tag: String in Pressure.GREAT:
		if tag in [c.a, c.b, gs.player_tag] or not gs.nations.has(tag):
			continue
		var ra := Diplomacy.relation(gs, tag, c.a)
		var rb := Diplomacy.relation(gs, tag, c.b)
		if rb >= need and ra < 0.0:
			c.backers_b.append(tag)
		elif ra >= need and rb < 0.0:
			c.backers_a.append(tag)


# --- Answering -------------------------------------------------------------------------------

## What `b` does in a crisis when the AI answers for it: yield, refuse, mobilize or appeal.
static func choose_response(gs: Node, c: Dictionary) -> String:
	var ai: Dictionary = cfg.ai
	var odds_b := 1.0 / maxf(odds_a(gs, c), 0.01)
	var caution: float = AI.temperament(gs, c.b).caution
	if odds_b >= float(ai.resist_odds) * (0.7 + 0.6 * caution):
		return "refuse" if odds_b >= float(ai.mobilize_below) else "mobilize"
	var med := mediators(gs, c)
	if not med.is_empty() and med[0].chance >= float(ai.mediator_chance_min):
		return "appeal"
	var cost := Peace.demand_cost(gs, c.a, c.b, c.demand)
	if cost >= 0.0 and (cost <= float(ai.yield_cost_max) or odds_b < float(ai.yield_odds)):
		return "yield"
	return "mobilize"


## Daily: the AI answers when it has thought long enough; a crisis whose demand has gone stale, or whose time is
## up, ends.
static func step_day(gs: Node) -> void:
	if gs.crises.is_empty():
		return
	var today: int = Clock.days_elapsed
	for c: Dictionary in gs.crises.duplicate():
		if Diplomacy.declare_block(gs, c.a, c.b) != "" or not _demand_valid(gs, c):
			end(gs, c, "lapsed", "The quarrel between %s and %s has been overtaken by events." % [_name(gs, c.a), _name(gs, c.b)])
			continue
		if c.b == gs.player_tag:
			if today >= c.deadline_day:
				_cancel_prompt(gs, c)
				respond(gs, c.id, c.b, "refuse")
			continue
		if today >= c.think_day:
			respond(gs, c.id, c.b, choose_response(gs, c))


static func _demand_valid(gs: Node, c: Dictionary) -> bool:
	if c.demand.kind == "province":
		for id: int in c.demand.ids:
			if gs.province_owner[id] != c.b:
				return false
	return true


static func _name(gs: Node, tag: String) -> String:
	return gs.nations[tag].display_name


## `tag` answers the crisis as the nation asked: "yield", "refuse", "mobilize" or "appeal". Returns false if it
## cannot (no such crisis, not the nation asked, not enough points).
static func respond(gs: Node, id: int, tag: String, action: String) -> bool:
	var c := find(gs, id)
	if c.is_empty() or tag != c.b or action not in ["yield", "refuse", "mobilize", "appeal"]:
		return false
	if action == "appeal":
		var cost: float = cfg.mediate.appeal_cost_points
		if tag == gs.player_tag:
			if not Diplomacy.can_afford(gs, tag, cost):
				return false
			Diplomacy.spend(gs, tag, cost)
		var med := mediators(gs, c)
		if not med.is_empty() and _succeeds(gs, c, med[0].tag):
			_compromise(gs, c, med[0].tag)
			return true
		Pressure._record(gs, c.title, "%s asks the powers to step in, but no one can bring %s to terms." % [_name(gs, c.b), _name(gs, c.a)], 0)
		action = "refuse"
	match action:
		"yield":
			_yield(gs, c)
		"refuse":
			_refuse(gs, c)
		"mobilize":
			_mobilize(gs, c)
	return true


static func _yield(gs: Node, c: Dictionary) -> void:
	var y: Dictionary = cfg["yield"]
	var terms := Peace._apply_demand(gs, c.a, c.b, c.demand, false)
	Diplomacy.gain_prestige(gs, c.a, float(y.a_prestige))
	Diplomacy.gain_prestige(gs, c.b, float(y.b_prestige))
	WarSupport.change(gs, c.b, float(y.b_war_support))
	gs.tension_impulse += float(y.tension)
	Diplomacy.change_relation(gs, c.a, c.b, float(y.relation))
	Economy.recompute(gs)
	gs.economy_updated.emit()
	end(gs, c, "yielded", "%s yields to %s: %s." % [_name(gs, c.b), _name(gs, c.a), terms])


static func _refuse(gs: Node, c: Dictionary) -> void:
	var r: Dictionary = cfg.refuse
	Diplomacy.change_relation(gs, c.a, c.b, float(r.relation))
	Diplomacy.add_grievance(gs, c.a, c.b, float(r.grievance))
	gs.tension_impulse += float(r.tension)
	# The demand becomes a casus belli with the demand as its goal.
	gs.casus_belli.append({"holder": c.a, "target": c.b, "kind": "fabricated_claim", "goal": c.goal.duplicate(true),
			"expires_day": Clock.days_elapsed + int(Diplomacy.cfg.war.cb_years * 365), "refused_day": Clock.days_elapsed})
	end(gs, c, "refused", "%s refuses %s. %s now has a claim to press." % [_name(gs, c.b), _name(gs, c.a), _name(gs, c.a)])
	if c.a != gs.player_tag:
		var option := AIDiplomacy.war_option(gs, c.a, c.b)
		if not option.is_empty():
			gs.issue_quiet(DeclareWar.new(c.a, c.b, option.cb))


static func _mobilize(gs: Node, c: Dictionary) -> void:
	var m: Dictionary = cfg.mobilize
	var n: Nation = gs.nations[c.b]
	n.mobilization = clampf(n.mobilization + float(m.mobilization), 0.0, 1.0)
	gs.tension_impulse += float(m.tension)
	# Mobilization changes the odds: a demander that can no longer win backs down.
	if odds_a(gs, c) < AI.required_odds(gs, c.a) * float(m.deter_margin) and c.a != gs.player_tag:
		Diplomacy.gain_prestige(gs, c.a, float(m.a_backdown_prestige))
		Diplomacy.gain_prestige(gs, c.b, float(m.b_prestige))
		gs.tension_impulse += float(m.backdown_tension)
		end(gs, c, "backed_down", "%s mobilizes and %s backs down." % [_name(gs, c.b), _name(gs, c.a)])
		return
	_refuse(gs, c)


## The powers' mediator brings the two to a smaller demand: a modest indemnity, or nothing for an indemnity.
static func _compromise(gs: Node, c: Dictionary, mediator: String) -> void:
	var m: Dictionary = cfg.mediate
	var terms := "no concession"
	if c.demand.kind == "province":
		var d := {"kind": "indemnity", "share": m.compromise_share, "months": m.compromise_months}
		terms = Peace._apply_demand(gs, c.a, c.b, d, false)
	gs.tension_impulse += float(m.tension)
	Diplomacy.gain_prestige(gs, mediator, float(m.prestige))
	Diplomacy.change_relation(gs, mediator, c.a, 3.0)
	Diplomacy.change_relation(gs, mediator, c.b, 3.0)
	end(gs, c, "mediated", "%s brings %s and %s to terms: %s." % [_name(gs, mediator), _name(gs, c.a), _name(gs, c.b), terms])


## A third nation acts: "mediate", "back_a" or "back_b". Returns false if it cannot (a nation backs one side once, and
## never both).
static func act(gs: Node, id: int, tag: String, action: String) -> bool:
	var c := find(gs, id)
	if c.is_empty() or tag in [c.a, c.b] or not gs.nations.has(tag) or action not in ["mediate", "back_a", "back_b"]:
		return false
	if action != "mediate" and backs(c, tag) != "":
		return false
	var cost: float = cfg.mediate.cost_points if action == "mediate" else cfg.back.cost_points
	if not Diplomacy.can_afford(gs, tag, cost):
		return false
	Diplomacy.spend(gs, tag, cost)
	if action == "mediate":
		if _succeeds(gs, c, tag):
			_compromise(gs, c, tag)
		else:
			Diplomacy.gain_prestige(gs, tag, float(cfg.mediate.failed_prestige))
			Pressure._record(gs, c.title, "%s tries to mediate between %s and %s and fails." % [_name(gs, tag), _name(gs, c.a), _name(gs, c.b)], 0)
		return true
	var backed: String = c.a if action == "back_a" else c.b
	var against: String = c.b if action == "back_a" else c.a
	c["backers_" + backed_side(c, backed)].append(tag)
	Diplomacy.change_relation(gs, tag, backed, float(cfg.back.relation))
	Diplomacy.change_relation(gs, tag, against, float(cfg.back.against_relation))
	gs.tension_impulse += float(cfg.back.tension)
	Pressure._record(gs, c.title, "%s stands behind %s." % [_name(gs, tag), _name(gs, backed)], 0)
	return true


static func backed_side(c: Dictionary, tag: String) -> String:
	return "a" if tag == c.a else "b"


## The side `tag` already backs in a crisis ("a" or "b"), or "" if neither.
static func backs(c: Dictionary, tag: String) -> String:
	if tag in c.backers_a:
		return "a"
	if tag in c.backers_b:
		return "b"
	return ""


## Files a crisis as ended.
static func end(gs: Node, c: Dictionary, outcome: String, text: String) -> void:
	gs.crises.erase(c)
	gs.crisis_log.append({"id": c.id, "kind": c.kind, "a": c.a, "b": c.b, "title": c.title, "start": c.start_day, "end_day": Clock.days_elapsed,
			"end_date": Clock.date_string(), "outcome": outcome, "goal": c.goal})
	if gs.crisis_log.size() > int(cfg.gate.log_max):
		gs.crisis_log.pop_front()
	_cancel_prompt(gs, c)
	Pressure._record(gs, c.title, text, 1, "crisis")
	gs.crisis_ended.emit(c, outcome)


# --- The player's side -----------------------------------------------------------------------

## Asks the player (the nation asked) how to answer: time stops, as for an event.
static func _ask_player(gs: Node, c: Dictionary) -> void:
	var me: String = gs.player_tag
	var odds_b := 1.0 / maxf(odds_a(gs, c), 0.01)
	var y: Dictionary = cfg["yield"]
	var med := mediators(gs, c)
	var options: Array = [
		{"label": "Yield to the demand", "text": "Give up %s. The crisis ends." % what(gs, c),
				"effects": [{"crisis": [c.id, "yield", "b"]}],
				"tip": "You lose %s.\nPrestige %+d, war support %+d; tension eases." % [what(gs, c), roundi(float(y.b_prestige)), roundi(float(y.b_war_support))]},
		{"label": "Refuse", "text": "Say no. %s may take it as a cause for war." % _name(gs, c.a),
				"effects": [{"crisis": [c.id, "refuse", "b"]}],
				"tip": "%s gains a casus belli to press the demand, and may declare war.\nRelations with %s %+d." % [_name(gs, c.a), _name(gs, c.a), roundi(float(cfg.refuse.relation))]},
		{"label": "Mobilize and refuse", "text": "Show that you will fight; they may back down if they cannot win.",
				"effects": [{"crisis": [c.id, "mobilize", "b"]}],
				"tip": "Mobilization %+d%%; tension %+d.\nIf %s cannot win it backs down, otherwise this is a refusal." % [roundi(float(cfg.mobilize.mobilization) * 100.0), roundi(float(cfg.mobilize.tension)), _name(gs, c.a)]},
	]
	if not med.is_empty() and Diplomacy.can_afford(gs, me, float(cfg.mediate.appeal_cost_points)):
		options.append({"label": "Appeal to the powers (%d points)" % int(cfg.mediate.appeal_cost_points),
				"text": "Ask %s to bring %s to terms." % [_name(gs, med[0].tag), _name(gs, c.a)],
				"effects": [{"crisis": [c.id, "appeal", "b"]}],
				"tip": "A %d%% chance %s succeeds, with a small payment instead of the demand.\nIf it fails, this is a refusal." % [roundi(med[0].chance * 100.0), _name(gs, med[0].tag)]})
	var power := "Your side outweighs theirs %.1f to 1." % odds_b if odds_b >= 1.0 else "Their side outweighs yours %.1f to 1." % (1.0 / odds_b)
	var decision := {"id": gs.next_event_uid, "event": "crisis:%d" % c.id, "title": c.title, "text": c.text + "\n\n" + power,
			"roles": {"a": c.a, "b": me}, "options": options, "deferred": [], "date": Clock.date_string(), "as_b": true}
	gs.next_event_uid += 1
	gs.pending_events.append(decision)
	Clock.paused = true
	gs.event_posted.emit(decision)


static func _cancel_prompt(gs: Node, c: Dictionary) -> void:
	for i in range(gs.pending_events.size() - 1, -1, -1):
		if gs.pending_events[i].event == "crisis:%d" % c.id:
			var d: Dictionary = gs.pending_events[i]
			gs.pending_events.remove_at(i)
			gs.event_resolved.emit(d, -1)
