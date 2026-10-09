class_name WarSupport
extends RefCounted
## War support (phase 5, step 6): how far a nation's people stand behind the war, 0..100.
## It falls with casualties, blockade and lost ground and rises with victories; in peace it
## drifts back to the nation's base level. While a nation is at war its support scales tax
## and recruitment (economy_mult) and the fighting power of its armies (morale_mult). Weary
## nations take worse terms (see Peace), and one at the end of its tether is forced into a
## white peace unless it is clearly losing. Constants: data/diplomacy.json, "war_support".


static func cfg() -> Dictionary:
	return Diplomacy.cfg.war_support


## What a government type starts with (the scenario can set a nation's own).
static func start_value(government: String) -> float:
	var start: Dictionary = cfg().start
	return float(start.get(government, start.default))


## Piecewise-linear curve through the at_0, at_50 and at_100 values of a multiplier.
static func _curve(curve: Dictionary, support: float) -> float:
	if support <= 50.0:
		return lerpf(curve.at_0, curve.at_50, support / 50.0)
	return lerpf(curve.at_50, curve.at_100, (support - 50.0) / 50.0)


## Multiplier on tax and recruitment; 1 in peace.
static func economy_mult(gs: Node, tag: String) -> float:
	if gs.wars_of(tag).is_empty():
		return 1.0
	return _curve(cfg().economy_mult, gs.nations[tag].war_support)


## Multiplier on the fighting power of the nation's armies; 1 in peace.
static func morale_mult(gs: Node, tag: String) -> float:
	if gs.wars_of(tag).is_empty():
		return 1.0
	return _curve(cfg().morale_mult, gs.nations[tag].war_support)


static func change(gs: Node, tag: String, delta: float) -> void:
	if is_zero_approx(delta):
		return
	var n: Nation = gs.nations[tag]
	var v := clampf(n.war_support + delta, 0.0, 100.0)
	if is_equal_approx(v, n.war_support):
		return
	n.war_support = v
	gs.war_support_changed.emit(tag, v)


## A finished battle: the winner gains (more when it held its own ground), the loser loses.
static func on_battle(gs: Node, record: Dictionary) -> void:
	var winner: String = record.winner
	if winner.is_empty():
		return
	var c: Dictionary = cfg()
	var loser: String = record.get("loser", "")
	var home: bool = gs.province_owner[record.province] == winner
	change(gs, winner, c.home_win_bonus if home else c.win_bonus)
	if loser != "":
		change(gs, loser, -c.loss_penalty)


## Share of a nation's people living in provinces an enemy holds.
static func occupied_share(gs: Node, tag: String) -> float:
	var n: Nation = gs.nations[tag]
	var held := 0.0
	for id: int in n.provinces:
		var holder: String = gs.province_controller[id]
		if holder != tag and gs.at_war(tag, holder):
			held += gs.province_population[id]
	return held / maxf(float(n.population), 1.0)


## Monthly: support moves with what the war has cost, then the weary are forced to terms.
static func step_month(gs: Node) -> void:
	var c: Dictionary = cfg()
	for tag: String in gs.nations:
		var n: Nation = gs.nations[tag]
		if n.provinces.is_empty():
			continue
		if gs.wars_of(tag).is_empty():
			change(gs, tag, clampf(n.war_support_base - n.war_support, -c.recovery_per_month, c.recovery_per_month))
		else:
			var lost := n.men_lost_month / maxf(float(n.total_men()) + n.men_lost_month, 1.0)
			var debt: float = maxf(-n.treasury, 0.0) / maxf(n.budget.get("revenue", 1.0), 1.0)
			change(gs, tag, -c.weariness - c.casualty_weight * lost - c.blockade_weight * n.blockade
					- c.occupied_weight * occupied_share(gs, tag) - minf(c.debt_cap, c.debt_weight * debt))
		n.men_lost_month = 0.0
	Economy.recompute(gs)
	gs.economy_updated.emit()
	_force_peace(gs)


## A nation whose support has collapsed makes a white peace with every enemy that it is not
## clearly losing to; where it is losing, the enemy can dictate terms instead.
static func _force_peace(gs: Node) -> void:
	var c: Dictionary = cfg()
	for tag: String in gs.nations:
		if gs.nations[tag].war_support > c.white_peace_below:
			continue
		for war: War in gs.wars_of(tag):
			if Peace.war_score(gs, war, tag) < c.white_peace_score:
				continue
			Peace.make_peace(gs, war, {"taker": war.other(tag), "giver": tag, "demands": [], "forced": false,
					"note": " (%s's people will not fight on)" % gs.nations[tag].display_name})
