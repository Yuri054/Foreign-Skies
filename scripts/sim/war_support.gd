class_name WarSupport
extends RefCounted
## War support (phase 5, step 6): how far a nation's people stand behind the war, 0..100.
## It falls with casualties, blockade and lost ground and rises with victories; in peace it
## drifts back to the nation's base level. While a nation is at war its support scales income
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


## Multiplier on income and recruitment; 1 in peace.
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
	Diplomacy.gain_prestige(gs, winner, Diplomacy.cfg.points.prestige.battle_win)
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


## What moves a nation's war support this month, by cause: {label: points}. At war it is the
## weariness of fighting, the men lost so far this month, the blockade, ground under the enemy and
## debt; in peace it is the people settling back to their level.
static func monthly_changes(gs: Node, tag: String) -> Dictionary:
	var c: Dictionary = cfg()
	var n: Nation = gs.nations[tag]
	if gs.wars_of(tag).is_empty():
		return {"settling back": clampf(n.war_support_base - n.war_support, -c.recovery_per_month, c.recovery_per_month)}
	var lost := n.men_lost_month / maxf(float(n.total_men()) + n.men_lost_month, 1.0)
	var debt: float = maxf(-n.treasury, 0.0) / maxf(12.0 * float(n.budget.get("income", 0.0)), 1.0)
	return {
		"the war itself": -c.weariness,
		"men lost": -c.casualty_weight * lost,
		"blockade": -c.blockade_weight * n.blockade,
		"ground lost": -c.occupied_weight * occupied_share(gs, tag),
		"debt": -minf(c.debt_cap, c.debt_weight * debt),
	}


## What a nation's support does now, in words: at war its fighting power, recruits and income.
static func effects_text(gs: Node, tag: String) -> String:
	var n: Nation = gs.nations[tag]
	if gs.wars_of(tag).is_empty():
		return "At peace war support does nothing; at war it sets how hard the army fights and how much income and how many recruits the people give (now %d: fighting x%.2f, income and recruits x%.2f)." % [
				roundi(n.war_support), _curve(cfg().morale_mult, n.war_support), _curve(cfg().economy_mult, n.war_support)]
	return "Fighting power x%.2f, income and recruits x%.2f. At %d or less the people are forced into a peace." % [
			morale_mult(gs, tag), economy_mult(gs, tag), int(cfg().white_peace_below)]


## The month's changes as lines of text, biggest first, for a tooltip.
static func drivers_text(gs: Node, tag: String) -> String:
	var items := monthly_changes(gs, tag)
	var names: Array = items.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return absf(items[a]) > absf(items[b]))
	var lines: PackedStringArray = []
	for name: String in names:
		if absf(items[name]) >= 0.05:
			lines.append("%+.1f  %s" % [items[name], name])
	return "\n".join(lines) if not lines.is_empty() else "Nothing is moving it."


## Monthly: support moves with what the war has cost, then the weary are forced to terms.
static func step_month(gs: Node) -> void:
	var c: Dictionary = cfg()
	for tag: String in gs.nations:
		var n: Nation = gs.nations[tag]
		if n.provinces.is_empty():
			continue
		var total := 0.0
		for v: float in monthly_changes(gs, tag).values():
			total += v
		change(gs, tag, total)
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
