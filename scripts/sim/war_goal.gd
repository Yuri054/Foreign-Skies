class_name WarGoal
extends RefCounted
## What a war is fought for. The aggressor's goal is a dictionary {kind, ids, demand, label}:
##   provinces    named provinces of the target (a demand for them), `ids`
##   nationality  the provinces of a scenario claim (a national claim, reconquest or border claim), `ids`
##   concession   one peace demand (`demand`: an indemnity, a border disarmament, a fleet limit or a release of an ally)
##   defence      defending a guarantee or an ally: it asks for no land, only for the aggressor to pay
## The goal is what a demand asked (Crisis), kept in the casus belli its refusal gives, and copied onto the War
## when it is declared. At peace Peace.demand_cost prices what matches it at a discount and
## everything else at a premium (see data/diplomacy.json, war.goals).


static func cfg() -> Dictionary:
	return Diplomacy.cfg.war.goals


static func provinces_goal(ids: Array, label := "") -> Dictionary:
	return {"kind": "provinces", "ids": ids.duplicate(), "label": label}


static func concession_goal(demand: Dictionary, label := "") -> Dictionary:
	return {"kind": "concession", "demand": demand.duplicate(true), "label": label}


## The goal of a scenario claim.
static func from_claim(claim: Dictionary, target_owned: Array) -> Dictionary:
	var ids: Array = []
	for id: int in Diplomacy.claim_provinces(claim):
		if id in target_owned:
			ids.append(id)
	var kind := "provinces" if claim.kind == "border_claim" else "nationality"
	return {"kind": kind, "ids": ids, "label": claim.get("note", "")}


## The goal a war declared now by `a` on `b` with this casus belli would have ({} for none).
static func for_declaration(gs: Node, a: String, b: String, cb: String) -> Dictionary:
	match cb:
		"none":
			return {}
		"guarantee_defence", "ally_called":
			return {"kind": "defence", "label": ""}
		"fabricated_claim":
			for held: Dictionary in gs.casus_belli:
				if held.holder == a and held.target == b and held.kind == cb and held.has("goal"):
					return held.goal.duplicate(true)
			return {}
		"unprovoked_aggression":
			return {}
	for claim: Dictionary in Diplomacy.all_claims(gs):
		if claim.holder == a and claim.kind == cb and Diplomacy._claim_applies(gs, claim, b):
			var owned: Array = []
			for id: int in gs.nations[b].provinces:
				owned.append(id)
			var goal := from_claim(claim, owned)
			if not goal.ids.is_empty():
				return goal
	return {}


## Why `goal` cannot be pursued by `a` against `b` ("" if it can): kind, provinces, count, detached, capital, demand.
static func invalid(gs: Node, a: String, b: String, goal: Dictionary) -> String:
	match goal.get("kind", ""):
		"provinces":
			var ids: Array = goal.get("ids", [])
			if ids.is_empty():
				return "provinces"
			if ids.size() > int(cfg().max_provinces):
				return "count"
			for id: int in ids:
				if id < 1 or id >= gs.province_owner.size() or gs.province_owner[id] != b:
					return "provinces"
			# A goal must be ground that could be handed over at peace (see Peace.province_problem).
			var problem := Peace.province_problem(gs, a, b, ids)
			if problem != "":
				return problem
			return ""
		"concession":
			var d: Dictionary = goal.get("demand", {})
			match d.get("kind", ""):
				"indemnity", "disarm_border", "fleet_limit":
					return ""
				"release_ally":
					var other: String = d.get("nation", "")
					if not gs.nations.has(other) or other == a or other == b or Peace._release_treaties(gs, b, other).is_empty():
						return "demand"
					return ""
			return "demand"
	return "kind"


## The goal's price multiplier for the points to press it as a demand (Crisis.press_cost).
static func cost_mult(goal: Dictionary) -> float:
	var def: Dictionary = cfg().get(goal.get("kind", ""), {})
	var m: float = def.get("cost_mult", 1.0)
	m += float(def.get("cost_per_province", 0.0)) * maxi(goal.get("ids", []).size() - 1, 0)
	return m


## The price multiplier for one peace demand `d` that `taker` makes against `giver` in `war`:
## the discount for what the aggressor's goal asks, the premium for the rest.
static func price_factor(war: War, taker: String, d: Dictionary, province_id := 0) -> float:
	if war == null or taker != war.a:
		return 1.0
	var goal: Dictionary = war.goal
	var c := cfg()
	if goal.is_empty():
		return float(c.none_premium) if war.casus_belli == "none" else 1.0
	var kind: String = d.get("kind", "")
	match goal.kind:
		"provinces", "nationality":
			if kind == "province":
				return float(c.discount) if province_id in goal.ids else float(c.premium)
			return float(c.premium)
		"concession":
			return float(c.discount) if kind == goal.demand.get("kind", "") else float(c.premium)
		"defence":
			return float(c.discount) if kind in ["indemnity", "disarm_border", "release_ally", "fleet_limit"] else float(c.premium)
	return 1.0


## How far the aggressor has got toward its goal, 0 to 1 (1 for no goal: the general rule has no aim).
static func progress(gs: Node, war: War) -> float:
	var goal: Dictionary = war.goal
	if goal.is_empty():
		return 1.0
	match goal.kind:
		"provinces", "nationality":
			var held := 0
			for id: int in goal.ids:
				if gs.province_controller[id] == war.a:
					held += 1
			return float(held) / maxf(goal.ids.size(), 1.0)
		"concession":
			var need: float = cfg().concession.met_score
			var score := Peace.war_score(gs, war, war.a)
			return 1.0 if score >= need else clampf(score / maxf(need, 1.0), 0.0, 0.99)
		"defence":
			# Met while none of the aggressor's own land is in the enemy's hands.
			for id: int in gs.nations[war.a].provinces:
				if gs.province_controller[id] == war.b:
					return 0.0
			return 1.0
	return 1.0


## The goal in words.
static func describe(gs: Node, goal: Dictionary) -> String:
	if goal.is_empty():
		return "no stated goal"
	var label: String = goal.get("label", "")
	match goal.kind:
		"provinces", "nationality":
			var names: Array[String] = []
			for id: int in goal.ids:
				names.append(MapData.provinces[id].name)
			var what := label if label != "" else (", ".join(names) if names.size() <= 4 else "%d provinces" % names.size())
			return ("to win %s" if goal.kind == "provinces" else "to claim %s") % what
		"concession":
			return "to force " + Peace.describe_demand(gs, goal.demand)
		"defence":
			return "to defend and make the aggressor pay"
	return "?"


## The "why" line of a war: its goal and the aggressor's progress.
static func line(gs: Node, war: War) -> String:
	if war.casus_belli == "none" and war.goal.is_empty():
		return "%s fights with no casus belli and no stated goal." % gs.nations[war.a].display_name
	if war.goal.is_empty():
		return ""
	var p := progress(gs, war)
	return "%s fights %s (%d%% there)." % [gs.nations[war.a].display_name, describe(gs, war.goal), roundi(p * 100.0)]
