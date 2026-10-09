class_name Diplomacy
extends RefCounted
## Diplomacy rules: the relations table, the treaty web and the questions the rest of the
## simulation asks about them. Static, like Economy and Military; the data lives in GameState
## (relations, treaties). Constants are in data/diplomacy.json, the starting web of treaties
## in the scenario (blocs, alliances, neutral_pacts, guarantees, passage, nap, relations).

const CONFIG_PATH := "res://data/diplomacy.json"

static var cfg: Dictionary = {}
## Land neighbours of each nation, kept while ownership has not changed (see neighbor_nations).
static var _neighbor_nations: Dictionary = {}
static var _neighbor_version := -1
static var _neighbor_gs := 0
## Province ids of each claim, by the names it lists (the map never changes).
static var _claim_cache: Dictionary = {}


static func load_config() -> void:
	cfg = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	assert(cfg is Dictionary, "diplomacy.json is invalid")


static func treaty_kinds() -> Array:
	return cfg.treaties.keys().filter(func(k: String) -> bool: return not k.begins_with("_"))


## Key for an unordered pair of tags ("A|B", sorted); same form as the war keys.
static func pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


# --- Setup ---------------------------------------------------------------------------------

## Builds treaties and relations from the scenario. Called by GameState.load_scenario once
## the nations exist.
static func load_scenario(gs: Node) -> void:
	gs.treaties.clear()
	gs.next_treaty_id = 1
	gs.relations.clear()
	gs.relation_base.clear()
	gs.mobilization_calls.clear()
	gs.casus_belli.clear()
	gs.grievance.clear()
	gs.war_groups.clear()
	gs.pending_joins.clear()
	gs.join_calls.clear()
	gs.alarms.clear()
	gs.next_decision_id = 1
	gs.pending_offers.clear()
	gs.relation_projects.clear()
	gs.next_offer_id = 1
	gs.peace_cooldown.clear()
	gs.indemnities.clear()
	gs.restrictions.clear()
	var s: Dictionary = gs.scenario

	for entry: Dictionary in s.get("alliances", []):
		_seed(gs, "alliance", entry.a, entry.b, entry)
	# A neutral pact: the first member is free to stay out of a war the others start. It is
	# an alliance that binds defensively only, plus the clause itself.
	for pact: Array in s.get("neutral_pacts", {}).values():
		for i in range(1, pact.size()):
			_seed(gs, "alliance", pact[0], pact[i], {"terms": {"defensive_only": true}})
			_seed(gs, "neutral_pact", pact[0], pact[i], {})
	for entry: Dictionary in s.get("guarantees", []):
		_seed(gs, "guarantee", entry.guarantor, entry.guaranteed, entry)
	for entry: Dictionary in s.get("passage", []):
		_seed(gs, "passage", entry.host, entry.mover, entry)
	for entry: Dictionary in s.get("nap", []):
		_seed(gs, "nap", entry.a, entry.b, entry)

	var tags: Array = gs.nations.keys()
	for i in tags.size():
		for j in range(i + 1, tags.size()):
			var key := pair_key(tags[i], tags[j])
			gs.relation_base[key] = _baseline(gs, tags[i], tags[j])
			gs.relations[key] = gs.relation_base[key]
	for entry: Dictionary in s.get("relations", []):
		var key := pair_key(entry.a, entry.b)
		assert(gs.relations.has(key), "relations entry names an unknown nation pair: %s" % key)
		gs.relation_base[key] = _clamp(float(entry.value))
		gs.relations[key] = gs.relation_base[key]


static func _seed(gs: Node, kind: String, a: String, b: String, entry: Dictionary) -> void:
	assert(gs.nations.has(a) and gs.nations.has(b), "treaty names an unknown nation: %s, %s" % [a, b])
	assert(cfg.treaties.has(kind), "unknown treaty kind %s" % kind)
	if has_treaty(gs, kind, a, b):
		return
	var t := Treaty.new(gs.next_treaty_id, kind, a, b, Clock.days_elapsed, -1, entry.get("terms", {}).duplicate(), entry.get("note", ""))
	gs.next_treaty_id += 1
	gs.treaties.append(t)


## What the pair's opinion settles at: bloc loyalty plus the bonus of every treaty between
## them. A scenario `relations` entry overrides it.
static func _baseline(gs: Node, a: String, b: String) -> float:
	var v: float = cfg.relations.neutral
	var bloc_a := bloc_of(gs, a)
	var bloc_b := bloc_of(gs, b)
	if bloc_a != "" and bloc_b != "":
		v += cfg.relations.same_bloc if bloc_a == bloc_b else cfg.relations.opposed_blocs
	for t in treaties_between(gs, a, b):
		v += cfg.treaties[t.kind].relation_bonus
	return _clamp(v)


static func _clamp(v: float) -> float:
	return clampf(v, cfg.relations.min, cfg.relations.max)


# --- Blocs ---------------------------------------------------------------------------------

## Name of the bloc a nation belongs to in the scenario, or "" if it stands alone.
static func bloc_of(gs: Node, tag: String) -> String:
	var blocs: Dictionary = gs.scenario.get("blocs", {})
	for bloc: String in blocs:
		if tag in blocs[bloc]:
			return bloc
	return ""


static func bloc_members(gs: Node, bloc: String) -> Array:
	return gs.scenario.get("blocs", {}).get(bloc, [])


# --- Relations -----------------------------------------------------------------------------

static func relation(gs: Node, a: String, b: String) -> float:
	if a == b:
		return cfg.relations.max
	return gs.relations.get(pair_key(a, b), cfg.relations.neutral)


static func set_relation(gs: Node, a: String, b: String, value: float) -> void:
	if a == b:
		return
	var old := relation(gs, a, b)
	var v := _clamp(value)
	if is_equal_approx(old, v):
		return
	gs.relations[pair_key(a, b)] = v
	gs.relations_changed.emit(a, b)


static func change_relation(gs: Node, a: String, b: String, delta: float) -> void:
	set_relation(gs, a, b, relation(gs, a, b) + delta)


## Monthly: every opinion moves a step toward its baseline.
static func step_month(gs: Node) -> void:
	_step_points(gs)
	_step_projects(gs)
	_step_prestige(gs)
	_step_grievance(gs)
	WarSupport.step_month(gs)
	Peace.step_month(gs)
	var step: float = cfg.relations.drift_per_month
	for key: String in gs.relations.keys():
		var base: float = gs.relation_base[key]
		var v: float = gs.relations[key]
		if is_equal_approx(v, base):
			continue
		var parts := key.split("|")
		set_relation(gs, parts[0], parts[1], move_toward(v, base, step))


# --- Treaties ------------------------------------------------------------------------------

## Treaties that are in force today.
static func active_treaties(gs: Node) -> Array[Treaty]:
	var out: Array[Treaty] = []
	for t: Treaty in gs.treaties:
		if t.active_on(Clock.days_elapsed):
			out.append(t)
	return out


## Treaties of any kind between two nations, in either direction.
static func treaties_between(gs: Node, a: String, b: String) -> Array[Treaty]:
	var out: Array[Treaty] = []
	for t in active_treaties(gs):
		if (t.a == a and t.b == b) or (t.a == b and t.b == a):
			out.append(t)
	return out


## Treaties a nation is party to, optionally of one kind.
static func treaties_of(gs: Node, tag: String, kind := "") -> Array[Treaty]:
	var out: Array[Treaty] = []
	for t in active_treaties(gs):
		if t.involves(tag) and (kind == "" or t.kind == kind):
			out.append(t)
	return out


## The treaty of this kind between a and b, or null. Directed kinds only match a -> b;
## symmetric ones match either way round.
static func find_treaty(gs: Node, kind: String, a: String, b: String) -> Treaty:
	var directed: bool = cfg.treaties[kind].directed
	for t in active_treaties(gs):
		if t.kind != kind:
			continue
		if (t.a == a and t.b == b) or (not directed and t.a == b and t.b == a):
			return t
	return null


static func has_treaty(gs: Node, kind: String, a: String, b: String) -> bool:
	return find_treaty(gs, kind, a, b) != null


## Adds a treaty and moves the pair's baseline by its relation bonus. Returns null if one of
## this kind already stands between the pair.
static func add_treaty(gs: Node, kind: String, a: String, b: String, end_day := -1, terms := {}, note := "") -> Treaty:
	if a == b or has_treaty(gs, kind, a, b):
		return null
	var t := Treaty.new(gs.next_treaty_id, kind, a, b, Clock.days_elapsed, end_day, terms, note)
	gs.next_treaty_id += 1
	gs.treaties.append(t)
	_shift_baseline(gs, a, b, cfg.treaties[kind].relation_bonus)
	gs.treaty_changed.emit(t, true)
	return t


## Ends a treaty now (it stays in the list as a record).
static func end_treaty(gs: Node, t: Treaty) -> void:
	if not t.active_on(Clock.days_elapsed):
		return
	t.end_day = Clock.days_elapsed
	_shift_baseline(gs, t.a, t.b, -cfg.treaties[t.kind].relation_bonus)
	gs.treaty_changed.emit(t, false)


static func _shift_baseline(gs: Node, a: String, b: String, delta: float) -> void:
	var key := pair_key(a, b)
	gs.relation_base[key] = _clamp(gs.relation_base.get(key, cfg.relations.neutral) + delta)


## Allies of a nation; `defensive_only` ones are included (the caller reads the terms).
static func allies_of(gs: Node, tag: String) -> Array[String]:
	var out: Array[String] = []
	for t in treaties_of(gs, tag, "alliance"):
		out.append(t.other(tag))
	return out


static func are_allied(gs: Node, a: String, b: String) -> bool:
	return has_treaty(gs, "alliance", a, b)


## Nations that guarantee `tag`.
static func guarantors_of(gs: Node, tag: String) -> Array[String]:
	var out: Array[String] = []
	for t in treaties_of(gs, tag, "guarantee"):
		if t.b == tag:
			out.append(t.a)
	return out


## Nations that `tag` guarantees.
static func guaranteed_by(gs: Node, tag: String) -> Array[String]:
	var out: Array[String] = []
	for t in treaties_of(gs, tag, "guarantee"):
		if t.a == tag:
			out.append(t.b)
	return out


## Whether `mover`'s armies may cross `host`'s land by treaty. A binding alliance opens it;
## an entente (a friendship, not a pact) does not.
static func has_passage(gs: Node, host: String, mover: String) -> bool:
	if host == mover or has_treaty(gs, "passage", host, mover):
		return true
	var t := find_treaty(gs, "alliance", host, mover)
	return t != null and not t.terms.get("entente", false)


# --- Diplomacy points ----------------------------------------------------------------------

## What an action costs in diplomacy points. `action` is declare_war (detail: the casus belli),
## propose (the treaty kind), cancel (the treaty kind) or gift.
static func cost_of(action: String, detail := "") -> float:
	var costs: Dictionary = cfg.points.costs
	if action == "gift" or action == "improve_relations":
		return float(costs[action])
	return float(costs.get(action, {}).get(detail, 0.0))


static func points(gs: Node, tag: String) -> float:
	return gs.nations[tag].diplomacy_points if gs.nations.has(tag) else 0.0


static func can_afford(gs: Node, tag: String, cost: float) -> bool:
	return points(gs, tag) >= cost


## Takes points away (never below zero).
static func spend(gs: Node, tag: String, amount: float) -> void:
	if amount > 0.0:
		_set_points(gs, tag, points(gs, tag) - amount)


## Adds points (never past the maximum).
static func gain(gs: Node, tag: String, amount: float) -> void:
	if amount > 0.0:
		_set_points(gs, tag, points(gs, tag) + amount)


static func _set_points(gs: Node, tag: String, value: float) -> void:
	var n: Nation = gs.nations[tag]
	var v := clampf(value, 0.0, float(cfg.points.max))
	if is_equal_approx(v, n.diplomacy_points):
		return
	n.diplomacy_points = v
	gs.diplomacy_points_changed.emit(tag, v)


## What a nation earns each month, and where it comes from: {base, prestige, output, program,
## ministry, total}. The ministry only counts while the nation holds its capital.
static func point_income_parts(gs: Node, tag: String) -> Dictionary:
	var inc: Dictionary = cfg.points.income
	var n: Nation = gs.nations[tag]
	var base: float = inc.base
	var prestige: float = n.prestige * inc.prestige_weight
	var output := 0.0
	var rank := Standings.rank_of(gs, tag, "gdp")
	if rank > 0 and rank <= int(inc.top_output_count):
		output = inc.top_output_bonus
	var program := 0.0
	for id: String in n.programs:
		program += Economy.cfg.programs[id].effects.get("diplomacy", 0.0)
	var ministry := 0.0
	if n.capital > 0 and gs.province_controller[n.capital] == tag:
		for type: String in gs.province_buildings[n.capital]:
			ministry += Economy.cfg.buildings[type].effects.get("diplomacy", 0.0) * gs.province_buildings[n.capital][type]
	return {"base": base, "prestige": prestige, "output": output, "program": program, "ministry": ministry,
			"total": maxf(base + prestige + output + program + ministry, float(inc.min))}


static func point_income(gs: Node, tag: String) -> float:
	return point_income_parts(gs, tag).total


## Monthly: every nation with land earns its income.
static func _step_points(gs: Node) -> void:
	for tag: String in gs.nations:
		if not gs.nations[tag].provinces.is_empty():
			gain(gs, tag, point_income(gs, tag))


## Prestige fades a little each month.
static func _step_prestige(gs: Node) -> void:
	var keep: float = 1.0 - cfg.points.prestige.decay_per_month
	for tag: String in gs.nations:
		var n: Nation = gs.nations[tag]
		n.prestige *= keep
		n.points_price = lerpf(1.0, n.points_price, cfg.points.purchase.price_decay)


## Prestige earned (or lost): a won battle, peace terms, a new treaty.
static func gain_prestige(gs: Node, tag: String, amount: float) -> void:
	if gs.nations.has(tag):
		gs.nations[tag].prestige += amount


# --- Buying points -------------------------------------------------------------------------

## What the next batch of points costs the treasury, GBP millions.
static func purchase_price(gs: Node, tag: String) -> float:
	return cfg.points.purchase.base_cost * gs.nations[tag].points_price


## Why a purchase cannot be made: "full" (the stock is at its maximum), "money", or "".
static func purchase_block(gs: Node, tag: String) -> String:
	if not gs.nations.has(tag):
		return "unknown"
	if points(gs, tag) >= float(cfg.points.max):
		return "full"
	if gs.nations[tag].treasury < purchase_price(gs, tag):
		return "money"
	return ""


## Pays for a batch of points. The price of the next one rises. Returns false if it cannot be made.
static func buy_points(gs: Node, tag: String) -> bool:
	if purchase_block(gs, tag) != "":
		return false
	var n: Nation = gs.nations[tag]
	n.treasury -= purchase_price(gs, tag)
	n.points_price *= cfg.points.purchase.price_growth
	gain(gs, tag, float(cfg.points.purchase.batch))
	return true


# --- Improving relations -------------------------------------------------------------------

## Why `from` cannot start improving relations with `to` ("" if it can): unknown, at_war, active
## (already under way), limit (every effort in use) or maxed (the opinion cannot go higher).
static func improve_block(gs: Node, from: String, to: String) -> String:
	if from == to or not gs.nations.has(from) or not gs.nations.has(to):
		return "unknown"
	if gs.at_war(from, to):
		return "at_war"
	if improving(gs, from, to) != null:
		return "active"
	if projects_of(gs, from).size() >= int(cfg.points.improve.max_active):
		return "limit"
	if relation(gs, from, to) >= float(cfg.relations.max) - 0.5:
		return "maxed"
	return ""


## The effort `from` has under way with `to`, or null.
static func improving(gs: Node, from: String, to: String) -> Variant:
	for p: Dictionary in gs.relation_projects:
		if p.from == from and p.to == to:
			return p
	return null


static func projects_of(gs: Node, from: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in gs.relation_projects:
		if p.from == from:
			out.append(p)
	return out


## Starts an effort to improve relations: for a year, each month the two think better of each
## other, and what their opinion settles at creeps up too. Returns false if it cannot be started.
static func improve_relations(gs: Node, from: String, to: String) -> bool:
	if improve_block(gs, from, to) != "":
		return false
	gs.relation_projects.append({"from": from, "to": to, "months_left": int(cfg.points.improve.months)})
	gs.relations_changed.emit(from, to)
	return true


## Monthly: every effort does its work, and ends when its time is up or the two go to war.
static func _step_projects(gs: Node) -> void:
	var imp: Dictionary = cfg.points.improve
	for i in range(gs.relation_projects.size() - 1, -1, -1):
		var p: Dictionary = gs.relation_projects[i]
		if gs.at_war(p.from, p.to):
			gs.relation_projects.remove_at(i)
			continue
		change_relation(gs, p.from, p.to, imp.monthly)
		_shift_baseline(gs, p.from, p.to, imp.base_monthly)
		p.months_left -= 1
		if p.months_left <= 0:
			gs.relation_projects.remove_at(i)


# --- Treaty proposals and gifts ------------------------------------------------------------

## Kinds of treaty a nation can propose.
const PROPOSABLE := ["alliance", "guarantee", "nap", "passage"]


## Why `from` cannot propose this treaty to `to` ("" if it can): unknown, kind, at_war, exists.
## For "guarantee" `from` guarantees `to`; for "passage" `from` asks `to` to let it cross.
static func proposal_block(gs: Node, from: String, to: String, kind: String) -> String:
	if from == to or not gs.nations.has(from) or not gs.nations.has(to):
		return "unknown"
	if kind not in PROPOSABLE:
		return "kind"
	if gs.at_war(from, to):
		return "at_war"
	var host_first: bool = kind == "passage"
	if has_treaty(gs, kind, to if host_first else from, from if host_first else to):
		return "exists"
	return ""


## Whether `to` would agree (the AI's rule): its opinion of `from` reaches the bar for the kind,
## and an alliance does not cross opposed blocs.
static func treaty_acceptable(gs: Node, from: String, to: String, kind: String) -> bool:
	if relation(gs, to, from) < cfg.actions.treaty_accept[kind]:
		return false
	if kind == "alliance":
		var a := bloc_of(gs, from)
		var b := bloc_of(gs, to)
		return a == "" or b == "" or a == b
	return true


## `from` proposes a treaty. Returns {ok, reason, accepted}.
static func propose_treaty(gs: Node, from: String, to: String, kind: String) -> Dictionary:
	var reason := proposal_block(gs, from, to, kind)
	var out := {"ok": reason == "", "reason": reason, "accepted": false}
	if not out.ok:
		return out
	out.accepted = treaty_acceptable(gs, from, to, kind)
	if out.accepted:
		if kind == "passage":
			add_treaty(gs, kind, to, from)
		else:
			add_treaty(gs, kind, from, to)
		var worth: float = cfg.points.prestige.treaty.get(kind, 0.0)
		gain_prestige(gs, from, worth)
		gain_prestige(gs, to, worth)
	return out


## `from` gives `to` money; the receiver thinks better of it. False if it cannot be afforded.
static func gift(gs: Node, from: String, to: String, amount: float) -> bool:
	if from == to or not gs.nations.has(from) or not gs.nations.has(to) or amount <= 0.0 or amount > gs.nations[from].treasury:
		return false
	gs.nations[from].treasury -= amount
	gs.nations[to].treasury += amount
	var a: Dictionary = cfg.actions
	change_relation(gs, from, to, minf(a.gift_max_relation, a.gift_relation_per_million * amount))
	return true


# --- Declaring war -------------------------------------------------------------------------

## Casus belli ids `a` could use against `b` today, best first. "none" is always last: a war
## nobody would justify is allowed, at a price (see data/diplomacy.json, war.casus_belli).
static func casus_belli_options(gs: Node, a: String, b: String) -> Array[String]:
	var out: Array[String] = []
	if a == b or not gs.nations.has(a) or not gs.nations.has(b):
		return out
	for claim: Dictionary in gs.scenario.get("claims", []):
		if claim.holder == a and _claim_applies(gs, claim, b) and claim.kind not in out:
			out.append(claim.kind)
	for ward in guaranteed_by(gs, a):
		if gs.at_war(ward, b):
			out.append("guarantee_defence")
			break
	for ally in allies_of(gs, a):
		if gs.at_war(ally, b):
			out.append("ally_called")
			break
	for cb: Dictionary in gs.casus_belli:
		if cb.holder == a and cb.target == b and cb.expires_day > Clock.days_elapsed:
			out.append(cb.kind)
			break
	out.append("none")
	return out


## Whether `b` holds a claimed province. A border claim also needs it to touch the claimant.
static func _claim_applies(gs: Node, claim: Dictionary, b: String) -> bool:
	for id in claim_provinces(claim):
		if gs.province_owner[id] != b:
			continue
		if claim.kind != "border_claim":
			return true
		for n: int in Military.neighbors(id):
			if gs.province_owner[n] == claim.holder:
				return true
	return false


## Province ids named by a scenario claim.
static func claim_provinces(claim: Dictionary) -> Array[int]:
	var key := ",".join(claim.provinces)
	var cached: Variant = _claim_cache.get(key)
	if cached != null:
		return cached
	var out: Array[int] = []
	for pname: String in claim.provinces:
		for id in range(1, MapData.provinces.size()):
			if MapData.provinces[id].name == pname:
				out.append(id)
	_claim_cache[key] = out
	return out


## Why `a` may not declare war on `b` at all ("" if it may): same, unknown, no_land, at_war,
## allied or nap. A non-aggression pact has to be cancelled first (CancelTreaty).
static func declare_block(gs: Node, a: String, b: String) -> String:
	if a == b:
		return "same"
	if not gs.nations.has(a) or not gs.nations.has(b):
		return "unknown"
	if gs.nations[a].provinces.is_empty() or gs.nations[b].provinces.is_empty():
		return "no_land"
	if gs.at_war(a, b):
		return "at_war"
	if are_allied(gs, a, b):
		return "allied"
	if has_treaty(gs, "nap", a, b):
		return "nap"
	return ""


## "mobilization" if `a` has not mobilized enough for a war with no casus belli, else "".
static func declare_gate(gs: Node, a: String, cb: String) -> String:
	if cb == "none" and gs.nations[a].mobilization < cfg.crisis.min_mobilization:
		return "mobilization"
	return ""


static func can_declare(gs: Node, a: String, b: String, cb := "none") -> bool:
	return declare_block(gs, a, b) == "" and cb in casus_belli_options(gs, a, b) 			and declare_gate(gs, a, cb) == ""


## `a` declares war on `b` with the given casus belli. Returns false (changing nothing) if
## that is not allowed. `group` ties the war to a conflict already begun (0 starts one).
static func declare_war(gs: Node, a: String, b: String, cb := "none", group := 0) -> bool:
	if not can_declare(gs, a, b, cb):
		return false
	var rules: Dictionary = cfg.war.casus_belli[cb]
	gs.set_war(a, b, true, cb, group)
	var conflict: Dictionary = _open_group(gs, a, b, gs.war_between(a, b).war_group)
	# A dated casus belli is used up.
	for held: Dictionary in gs.casus_belli.duplicate():
		if held.holder == a and held.target == b and held.kind == cb:
			gs.casus_belli.erase(held)
	change_relation(gs, a, b, rules.target_relations)
	for tag: String in gs.nations:
		if tag != a and tag != b:
			change_relation(gs, a, tag, rules.world_relations)
	gs.nations[a].prestige += rules.prestige
	WarSupport.change(gs, a, rules.war_support)
	if cb == "none":
		_earn_unprovoked_aggression(gs, a, b)
	AIDiplomacy.note_declaration(gs, a, cb)
	offer_joins(gs, conflict.id, [a, b])
	return true


## An unjustified war gives the aggressor's land neighbours and the victim's guarantors a
## casus belli against it for a few years, and stirs up their resentment.
static func _earn_unprovoked_aggression(gs: Node, aggressor: String, victim: String) -> void:
	var holders: Array[String] = neighbor_nations(gs, aggressor)
	for g in guarantors_of(gs, victim):
		if g not in holders:
			holders.append(g)
	var expires: int = Clock.days_elapsed + int(cfg.war.cb_years * 365)
	for tag in holders:
		if tag == victim or tag == aggressor:
			continue
		gs.casus_belli.append({"holder": tag, "target": aggressor, "kind": "unprovoked_aggression", "expires_day": expires})
		add_grievance(gs, tag, aggressor, cfg.war.provocation.grievance_on_unprovoked_war)


## Nations with land touching `tag`, not counting open-sea links.
static func neighbor_nations(gs: Node, tag: String) -> Array[String]:
	if _neighbor_version != gs.owner_version or _neighbor_gs != gs.get_instance_id():
		_neighbor_nations.clear()
		_neighbor_version = gs.owner_version
		_neighbor_gs = gs.get_instance_id()
	var cached: Variant = _neighbor_nations.get(tag)
	if cached != null:
		return cached
	var out: Array[String] = []
	for id: int in gs.nations[tag].provinces:
		for n: int in Military.neighbors(id):
			var o: String = gs.province_owner[n]
			if o != tag and o not in out:
				out.append(o)
	_neighbor_nations[tag] = out
	return out


# --- Grievance and provocation -------------------------------------------------------------

static func grievance(gs: Node, holder: String, target: String) -> float:
	return gs.grievance.get("%s>%s" % [holder, target], 0.0)


static func add_grievance(gs: Node, holder: String, target: String, amount: float) -> void:
	var key := "%s>%s" % [holder, target]
	gs.grievance[key] = clampf(gs.grievance.get(key, 0.0) + amount, 0.0, 100.0)


## Whether `holder` has been pushed far enough, and has a casus belli, to strike `target`.
static func provoked(gs: Node, holder: String, target: String) -> bool:
	return grievance(gs, holder, target) >= cfg.war.provocation.retaliation_threshold \
			and declare_block(gs, holder, target) == "" \
			and "unprovoked_aggression" in casus_belli_options(gs, holder, target)


## Monthly: resentment cools and dated casus belli lapse. A provoked AI nation strikes back
## through AIDiplomacy (grievance is part of its desire for war).
static func _step_grievance(gs: Node) -> void:
	var decay: float = cfg.war.provocation.grievance_decay_per_month
	for key: String in gs.grievance.keys():
		gs.grievance[key] = maxf(0.0, gs.grievance[key] - decay)
	var today: int = Clock.days_elapsed
	gs.casus_belli = gs.casus_belli.filter(func(cb: Dictionary) -> bool: return cb.expires_day > today)


# --- Cancelling treaties -------------------------------------------------------------------

## `canceller` tears up a treaty it is party to, paying the cost in data/diplomacy.json.
static func cancel_treaty(gs: Node, canceller: String, t: Treaty) -> bool:
	if not t.involves(canceller) or not t.active_on(Clock.days_elapsed):
		return false
	var cost: Dictionary = cfg.war.cancel[t.kind]
	var partner := t.other(canceller)
	end_treaty(gs, t)
	change_relation(gs, canceller, partner, cost.partner_relations)
	for tag: String in gs.nations:
		if tag != canceller and tag != partner:
			change_relation(gs, canceller, tag, cost.world_relations)
	gs.nations[canceller].prestige += cost.prestige
	return true


# --- Conflicts and join decisions ----------------------------------------------------------

## Registers a war that exists from the start of the scenario. With `call_allies` the allies
## are called at once (the scenario's start_crisis), and the crisis loop plays out from there.
static func start_war(gs: Node, a: String, b: String, call_allies := false) -> void:
	gs.set_war(a, b, true)
	var g := _open_group(gs, a, b, gs.war_between(a, b).war_group)
	if call_allies:
		offer_joins(gs, g.id, [a, b])


## The conflict record for a war group, created on first use. `a` is on the attacking side
## and `b` on the defending side unless the group already knows better.
static func _open_group(gs: Node, a: String, b: String, group_id: int) -> Dictionary:
	var g: Dictionary = gs.war_groups.get(group_id, {})
	if g.is_empty():
		g = {"id": group_id, "attacker": a, "defender": b, "members": {}, "declined": {}, "called": {}}
		gs.war_groups[group_id] = g
	var side_a: String = g.members.get(a, "")
	if side_a == "" and g.members.has(b):
		side_a = _opposite(g.members[b])
	if side_a == "":
		side_a = "attack"
	g.members[a] = side_a
	if not g.members.has(b):
		g.members[b] = _opposite(side_a)
	return g


static func _opposite(side: String) -> String:
	return "defend" if side == "attack" else "attack"


## Members of a conflict on one side ("attack" or "defend"), in tag order.
static func group_side(gs: Node, group_id: int, side: String) -> Array[String]:
	var out: Array[String] = []
	var g: Dictionary = gs.war_groups.get(group_id, {})
	for tag: String in g.get("members", {}):
		if g.members[tag] == side:
			out.append(tag)
	out.sort()
	return out


## Offers every ally and guarantor of `seeds` (members of the conflict) the choice to join.
## Each nation that joins brings its own allies in turn. An AI nation that is bound to join
## is called up: it mobilizes and enters the war when ready. The player gets a pending
## decision (GameState.pending_joins) and time stops until it is answered.
static func offer_joins(gs: Node, group_id: int, seeds: Array) -> void:
	var g: Dictionary = gs.war_groups.get(group_id, {})
	if g.is_empty():
		return
	var queue: Array = seeds.duplicate()
	while not queue.is_empty():
		var member: String = queue.pop_front()
		for tag in _candidates(gs, g, member):
			var d := _make_decision(gs, g, tag, member)
			if d.is_empty():
				continue
			if tag == gs.player_tag:
				gs.pending_joins.append(d)
				Clock.paused = true
				gs.join_requested.emit(d)
			elif d.conflict or not _ai_joins(gs, d):
				_decline(gs, d)
			else:
				# The AI mobilizes first and joins when it is ready (see _step_join_calls).
				g.called[tag] = true
				d["since"] = Clock.days_elapsed
				gs.join_calls["%s|%d" % [tag, g.id]] = d
				gs.join_called.emit(d)


## Nations that are allied with, or guarantee, a member and have not been asked already.
static func _candidates(gs: Node, g: Dictionary, member: String) -> Array[String]:
	var out: Array[String] = []
	for t in treaties_of(gs, member):
		if t.kind != "alliance" and t.kind != "guarantee":
			continue
		if t.kind == "guarantee" and t.b != member:
			continue
		var tag := t.other(member)
		if g.members.has(tag) or g.declined.has(tag) or g.called.has(tag) or tag in out or not gs.nations.has(tag):
			continue
		if gs.nations[tag].provinces.is_empty() or _pending_for(gs, tag, g.id):
			continue
		out.append(tag)
	out.sort()
	return out


static func _pending_for(gs: Node, tag: String, group_id: int) -> bool:
	for d: Dictionary in gs.pending_joins:
		if d.tag == tag and d.group == group_id:
			return true
	return false


## The decision `tag` faces because of its tie to `member`, or an empty dictionary if the
## tie asks nothing of it (a defensive-only ally of a nation that is not under attack).
## Keys: id, tag, group, side, kind, ally (the member), treaty_id, cb, conflict (it would
## have to fight an ally or pact partner), enemies, and the consequences of each answer.
static func _make_decision(gs: Node, g: Dictionary, tag: String, member: String) -> Dictionary:
	var attacked: bool = g.defender == member and g.members[member] == "defend"
	var kind := ""
	var treaty_id := -1
	var guarantee := find_treaty(gs, "guarantee", tag, member)
	var alliance := find_treaty(gs, "alliance", tag, member)
	if guarantee != null and attacked:
		kind = "guarantee"
		treaty_id = guarantee.id
	elif alliance != null:
		treaty_id = alliance.id
		if alliance.terms.get("entente", false):
			kind = "entente"
		elif attacked:
			kind = "alliance_defence"
		elif not alliance.terms.get("defensive_only", false):
			kind = "alliance_called"
	if kind == "":
		return {}
	var side: String = g.members[member]
	var enemies := group_side(gs, g.id, _opposite(side))
	var conflict: bool = enemies.is_empty() or gs.at_war(tag, member)
	for e in enemies:
		if declare_block(gs, tag, e) not in ["", "at_war"]:
			conflict = true
	var cb := "guarantee_defence" if kind == "guarantee" else "ally_called"
	var d := {
		"id": gs.next_decision_id, "tag": tag, "group": g.id, "side": side, "kind": kind,
		"ally": member, "treaty_id": treaty_id, "cb": cb, "conflict": conflict, "enemies": enemies,
	}
	gs.next_decision_id += 1
	d["join_cost"] = cfg.war.casus_belli[cb]
	d["decline_cost"] = cfg.join.decline[kind]
	return d


## The AI's answer to a join decision: a utility over the inputs in the decision (see
## AIDiplomacy.join_value).
static func _ai_joins(gs: Node, d: Dictionary) -> bool:
	return AIDiplomacy.joins(gs, d)


## `tag` enters the conflict on the side of the nation that asked, opening a war against
## every member of the other side. Returns false if there is no one to fight.
static func _join(gs: Node, d: Dictionary) -> bool:
	var g: Dictionary = gs.war_groups[d.group]
	var tag: String = d.tag
	var enemies := group_side(gs, d.group, _opposite(d.side))
	var rules: Dictionary = cfg.war.casus_belli[d.cb]
	var opened := false
	for e in enemies:
		if e == tag or gs.at_war(tag, e):
			continue
		gs.set_war(tag, e, true, d.cb, d.group)
		AIDiplomacy.note_declaration(gs, tag, d.cb)
		opened = true
		var war: War = gs.war_between(tag, e)
		war.add_log(Clock.date_string(), "join", "%s joins the war on the side of %s (%s)." % [
				gs.nations[tag].display_name, gs.nations[d.ally].display_name, _kind_label(d.kind)])
		change_relation(gs, tag, e, rules.target_relations)
	if not opened and tag not in g.members:
		return false
	g.members[tag] = d.side
	gs.nations[tag].prestige += rules.prestige
	WarSupport.change(gs, tag, rules.war_support)
	gs.join_resolved.emit(d, true)
	return true


## `tag` stays out. Failing a bound obligation costs what the config says.
static func _decline(gs: Node, d: Dictionary) -> void:
	var g: Dictionary = gs.war_groups[d.group]
	g.declined[d.tag] = true
	var cost: Dictionary = d.decline_cost
	if not d.conflict:
		change_relation(gs, d.tag, d.ally, cost.ally_relations)
		gs.nations[d.tag].prestige += cost.prestige
		if cost.end_treaty:
			for t in treaties_between(gs, d.tag, d.ally):
				if t.id == d.treaty_id:
					end_treaty(gs, t)
	gs.join_resolved.emit(d, false)


static func _kind_label(kind: String) -> String:
	match kind:
		"guarantee": return "guarantor"
		"entente": return "entente partner"
	return "ally"


## The player's answer to a pending decision. Returns false if no
## such decision is waiting.
static func answer_join(gs: Node, decision_id: int, joins: bool) -> bool:
	for i in gs.pending_joins.size():
		var d: Dictionary = gs.pending_joins[i]
		if d.id != decision_id:
			continue
		gs.pending_joins.remove_at(i)
		if joins and not d.conflict and _join(gs, d):
			offer_joins(gs, d.group, [d.tag])
		else:
			_decline(gs, d)
		return true
	return false


## A nation's armies crossed into a guaranteed nation's land without a war being declared:
## the guarantors are asked to defend it, as if it had been attacked.
static func violate_border(gs: Node, violator: String, victim: String) -> void:
	var group_id: int = gs.next_war_group
	gs.next_war_group += 1
	var g := _open_group(gs, violator, victim, group_id)
	g["violation"] = true
	offer_joins(gs, g.id, [victim])


# --- Mobilization and the crisis loop ------------------------------------------------------

## Daily: mobilization alarms neighbours, AI nations answer it, wars pull nations up to a
## war footing, and called nations that have mobilized enough enter their wars.
static func step_day(gs: Node) -> void:
	_step_alarms(gs)
	var changed := _step_mobilization(gs)
	_step_join_calls(gs)
	if changed:
		Economy.recompute(gs)
		gs.economy_updated.emit()


## A nation mobilizing past alarm_level alarms each land neighbour that is neither allied nor
## at war with it, once: they think worse of it, resent it, and their allies are called up.
static func _step_alarms(gs: Node) -> void:
	var c: Dictionary = cfg.crisis
	for tag: String in gs.nations:
		var n: Nation = gs.nations[tag]
		if n.provinces.is_empty():
			continue
		if n.mobilization >= c.alarm_level:
			for other in neighbor_nations(gs, tag):
				var key := "%s>%s" % [tag, other]
				if gs.alarms.has(key) or gs.at_war(tag, other) or are_allied(gs, tag, other):
					continue
				gs.alarms[key] = Clock.days_elapsed
				change_relation(gs, tag, other, c.alarm_relations)
				add_grievance(gs, other, tag, c.alarm_grievance)
				_call_up_allies(gs, other, tag)
				gs.mobilization_alarm.emit(tag, other)
		elif n.mobilization < c.alarm_clear_level:
			for key: String in gs.alarms.keys():
				if key.begins_with(tag + ">"):
					gs.alarms.erase(key)
			for key: String in gs.mobilization_calls.keys():
				if gs.mobilization_calls[key].against == tag:
					gs.mobilization_calls.erase(key)


## The allies of an alarmed nation may call up too (they follow the threat, see below).
static func _call_up_allies(gs: Node, threatened: String, threat: String) -> void:
	for t in treaties_of(gs, threatened, "alliance"):
		var ally := t.other(threatened)
		if ally == threat or t.terms.get("entente", false) or t.terms.get("defensive_only", false) or are_allied(gs, ally, threat):
			continue
		gs.mobilization_calls["%s|%s" % [ally, threat]] = {"tag": ally, "for": threatened, "against": threat, "day": Clock.days_elapsed}


## The mobilization level an AI nation wants: match_response of what threatens it, call_response
## of what threatens an ally, called_level if called to a war, war_floor if at war.
static func mobilization_target(gs: Node, tag: String) -> float:
	var c: Dictionary = cfg.crisis
	var target := 0.0
	for key: String in gs.alarms:
		var parts := key.split(">")
		if parts[1] == tag:
			target = maxf(target, gs.nations[parts[0]].mobilization * c.match_response)
	for call: Dictionary in gs.mobilization_calls.values():
		if call.tag == tag:
			target = maxf(target, gs.nations[call.against].mobilization * c.call_response)
	for key: String in gs.join_calls:
		if gs.join_calls[key].tag == tag:
			target = maxf(target, c.called_level)
	if not gs.wars_of(tag).is_empty():
		target = maxf(target, c.war_floor)
	return target


## Moves every nation's mobilization one day: the AI toward what it wants, the player only up
## to the war floor (their slider is their own business). Returns whether anything moved.
static func _step_mobilization(gs: Node) -> bool:
	var c: Dictionary = cfg.crisis
	var changed := false
	for tag: String in gs.nations:
		var n: Nation = gs.nations[tag]
		if n.provinces.is_empty():
			continue
		var at_war: bool = not gs.wars_of(tag).is_empty()
		var before := n.mobilization
		if tag == gs.player_tag:
			if at_war and n.mobilization < c.war_floor:
				n.mobilization = minf(c.war_floor, n.mobilization + c.war_step_up)
		else:
			var target := mobilization_target(gs, tag)
			if n.mobilization < target:
				n.mobilization = minf(target, n.mobilization + c.ai_step_up)
			elif n.mobilization > target and not at_war:
				n.mobilization = maxf(target, n.mobilization - c.ai_step_down)
		if not is_equal_approx(before, n.mobilization):
			changed = true
	return changed


## Called nations that have mobilized enough enter their wars (and call their own allies).
static func _step_join_calls(gs: Node) -> void:
	for key: String in gs.join_calls.keys():
		var d: Dictionary = gs.join_calls[key]
		var g: Dictionary = gs.war_groups.get(d.group, {})
		if g.is_empty() or not _group_active(gs, d.group):
			gs.join_calls.erase(key)
			continue
		if gs.nations[d.tag].mobilization < cfg.crisis.join_mobilization:
			continue
		gs.join_calls.erase(key)
		if _join(gs, d):
			offer_joins(gs, d.group, [d.tag])
		else:
			g.declined[d.tag] = true  # nobody left to fight


static func _group_active(gs: Node, group_id: int) -> bool:
	if gs.war_groups.get(group_id, {}).get("violation", false):
		return true
	for war: War in gs.wars.values():
		if war.war_group == group_id:
			return true
	return false
