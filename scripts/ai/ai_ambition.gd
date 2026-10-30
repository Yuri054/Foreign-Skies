class_name AIAmbition
extends RefCounted
## What an AI nation wants once the opening crisis is over (see "ambition" in data/ai.json): a
## neighbour it could beat and has a reason to fight. It makes a plan against it, mobilizes, works
## for a casus belli and lets the ordinary war rules do the declaring. Called once a month per nation.


static func step(gs: Node, tag: String) -> void:
	var c: Dictionary = AI.cfg.ambition
	var n: Nation = gs.nations[tag]
	if not c.enabled or n.provinces.is_empty():
		return
	var today: int = Clock.days_elapsed
	if today < int(c.start_delay_days):
		return
	if not gs.wars_of(tag).is_empty():
		if gs.ai_ambition.has(tag):
			drop(gs, tag, 0)
		return
	if gs.ai_ambition.has(tag):
		var held: Dictionary = gs.ai_ambition[tag]
		var why_not := _unfit(gs, tag, held.target)
		if why_not or today - int(held.since) > int(c.give_up_days):
			drop(gs, tag, int(c.cooldown_days))
		return
	if today < int(gs.ai_ambition_wait.get(tag, 0)) or (today + _offset(tag)) % int(c.review_days) >= int(AI.cfg.think_days):
		return
	var choice := best_target(gs, tag)
	if choice.is_empty():
		return
	gs.ai_ambition[tag] = {"target": choice.target, "since": today}
	_make_plan(gs, tag, choice.target)


static func _offset(tag: String) -> int:
	return tag.hash() % 90


## Why `target` is no longer a fit for `tag` ("" if it still is).
static func _unfit(gs: Node, tag: String, target: String) -> bool:
	var c: Dictionary = AI.cfg.ambition
	if not gs.nations.has(target) or gs.nations[target].provinces.is_empty():
		return true
	if Diplomacy.declare_block(gs, tag, target) != "" or AIDiplomacy.in_truce(gs, tag, target):
		return true
	return AIDiplomacy.odds_against(gs, tag, target) < AI.required_odds(gs, tag) * float(c.odds_margin) * 0.8


## The land neighbour `tag` would most like to fight, as {target, score}, or {} if none is worth it.
static func best_target(gs: Node, tag: String) -> Dictionary:
	var c: Dictionary = AI.cfg.ambition
	if float(AI.temperament(gs, tag).aggression) < float(c.min_aggression) or not Pressure.ai_may_declare(gs):
		return {}
	var best := {}
	var own_income := maxf(float(gs.nations[tag].budget.get("income", 0.0)), 0.01)
	for target in Diplomacy.neighbor_nations(gs, tag):
		if Diplomacy.declare_block(gs, tag, target) != "" or AIDiplomacy.in_truce(gs, tag, target):
			continue
		if AIDiplomacy.odds_against(gs, tag, target) < AI.required_odds(gs, tag) * float(c.odds_margin):
			continue
		var score := score_of(gs, tag, target, own_income)
		if score >= float(c.threshold) and (best.is_empty() or score > best.score + 0.000001):
			best = {"target": target, "score": score}
	return best


static func score_of(gs: Node, tag: String, target: String, own_income: float) -> float:
	var c: Dictionary = AI.cfg.ambition
	var options := Diplomacy.casus_belli_options(gs, tag, target)
	var claim := 1.0 if options[0] != "none" else 0.0
	var hostile := clampf(-Diplomacy.relation(gs, tag, target) / 100.0, 0.0, 1.0)
	var grievance := clampf(Diplomacy.grievance(gs, tag, target) / 100.0, 0.0, 1.0)
	var weak := clampf(1.0 - float(gs.nations[target].budget.get("income", 0.0)) / own_income, 0.0, 1.0)
	var margin := AIDiplomacy.odds_against(gs, tag, target) / maxf(AI.required_odds(gs, tag), 0.01)
	var opportunity := clampf(log(maxf(margin, 1.0)) / log(10.0), 0.0, 1.0)
	return float(c.w_claim) * claim + float(c.w_opportunity) * opportunity + float(c.w_hostile) * hostile + float(c.w_grievance) * grievance \
			+ float(c.w_weak) * weak + float(c.get("w_tension", 0.0)) * gs.tension / 100.0 * hostile - float(c.w_guarantee) * Diplomacy.guarantors_of(gs, target).size() \
			- (float(c.get("w_neutral", 0.0)) if Diplomacy.is_neutral(gs, target) else 0.0)


## Ends an ambition: its plan goes, and the nation waits `cooldown` days before the next.
static func drop(gs: Node, tag: String, cooldown: int) -> void:
	gs.ai_ambition.erase(tag)
	gs.ai_ambition_wait[tag] = Clock.days_elapsed + cooldown
	for i in range(gs.ai_plans.size() - 1, -1, -1):
		if gs.ai_plans[i].nation == tag and gs.ai_plans[i].get("dynamic", false):
			gs.ai_plans.remove_at(i)


## An offensive plan whose objectives are the target's provinces along the border, the capital worth most.
static func _make_plan(gs: Node, tag: String, target: String) -> void:
	var objectives: Array[Dictionary] = []
	var border: Array[int] = []
	for id: int in gs.nations[target].provinces:
		for nb: int in Military.neighbors(id):
			if gs.province_owner[nb] == tag:
				border.append(id)
				break
	border.sort()
	for id in border.slice(0, int(AI.cfg.ambition.objectives)):
		objectives.append({"province": id, "weight": 1.0})
	var capital: int = gs.nations[target].capital
	if capital > 0 and capital not in border:
		objectives.append({"province": capital, "weight": 2.0})
	gs.ai_plans.append({"nation": tag, "enemy": target, "posture": "offensive", "objectives": objectives, "dynamic": true})
