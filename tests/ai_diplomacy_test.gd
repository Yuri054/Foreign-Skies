extends SceneTree
## Headless test for AI diplomacy: join decisions, declaring war (and the unjustified cap),
## answering provocation, treaties and improving relations.
## Run: godot --headless --path . -s res://tests/ai_diplomacy_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var clock: Node
var AD
var A
var D
var Mil
var UnitC


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	AD = load("res://scripts/ai/ai_diplomacy.gd")
	A = load("res://scripts/ai/ai.gd")
	D = load("res://scripts/sim/diplomacy.gd")
	Mil = load("res://scripts/sim/military.gd")
	UnitC = load("res://scripts/sim/unit.gd")

	_test_joins()
	_test_cap()
	_test_unjustified_conditions()
	_test_provocation()
	_test_quiet_world()
	_test_treaties()
	_test_temperaments()

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.set_player("ESP")
	gs.ai_enabled = false


func _army(tag: String, province: int, infantry: int):
	var a = Mil.new_army(gs, tag, "Test army", province)
	for i in infantry:
		a.units.append(UnitC.new("infantry"))
	return a


## The decision `tag` would face because of its tie to `member` in a war that has begun.
func _decision(attacker: String, defender: String, tag: String, member: String) -> Dictionary:
	D.start_war(gs, attacker, defender)
	var g: Dictionary = gs.war_groups[gs.war_between(attacker, defender).war_group]
	return D._make_decision(gs, g, tag, member)


func _test_joins() -> void:
	_fresh()
	var d := _decision("GER", "BEL", "GBR", "BEL")
	_check(d.kind == "guarantee" and AD.joins(gs, d), "Britain joins to defend a nation it guarantees")
	var value: float = AD.join_value(gs, d)

	_fresh()
	d = _decision("AUH", "SRB", "RUS", "SRB")
	_check(d.kind == "alliance_defence" and AD.joins(gs, d), "Russia joins when its protege is attacked")

	_fresh()
	var entente: bool = D.find_treaty(gs, "alliance", "GBR", "RUS") != null
	d = _decision("RUS", "GER", "GBR", "RUS")
	_check(entente and d.kind == "entente" and not AD.joins(gs, d), "Britain does not join an entente partner's war on its own account")
	_check(AD.join_value(gs, d) < value, "an entente weighs less than a guarantee")

	# The odds matter: the same tie, with the sides' armies swapped, is a different answer.
	_fresh()
	d = _decision("AUH", "MNE", "SRB", "MNE")
	var outnumbered: float = AD.join_value(gs, d)
	for a in gs.armies.values():
		if a.tag in ["AUH", "GER"]:
			for u in a.units:
				u.strength = 0.1
	_check(AD.join_value(gs, d) > outnumbered, "a weaker enemy makes joining more attractive (%.1f against %.1f)" % [AD.join_value(gs, d), outnumbered])
	var cheap: Dictionary = d.duplicate(true)
	cheap.decline_cost = {"ally_relations": 0, "prestige": 0, "end_treaty": false}
	_check(AD.join_value(gs, cheap) < AD.join_value(gs, d), "and the price of declining pushes toward joining")
	var before: float = AD.join_value(gs, d)
	gs.nations["SRB"].war_support = 10.0
	_check(AD.join_value(gs, d) < before, "while a war-weary people pull the other way")


func _test_cap() -> void:
	_fresh()
	gs.ai_declarations = {"total": 0, "unjustified": 0}
	_check(not AD.unjustified_allowed(gs), "the very first AI war cannot be unjustified")
	gs.ai_declarations = {"total": 5, "unjustified": 0}
	_check(not AD.unjustified_allowed(gs), "nor can the sixth: one in six is over 15%")
	gs.ai_declarations = {"total": 6, "unjustified": 0}
	_check(AD.unjustified_allowed(gs), "after six justified wars one is allowed (1 in 7)")
	gs.ai_declarations = {"total": 7, "unjustified": 1}
	_check(not AD.unjustified_allowed(gs), "but not a second at once (2 in 8)")
	gs.ai_declarations = {"total": 0, "unjustified": 0}
	AD.note_declaration(gs, "GER", "none")
	AD.note_declaration(gs, "FRA", "ally_called")
	AD.note_declaration(gs, "ESP", "none")
	_check(gs.ai_declarations == {"total": 2, "unjustified": 1}, "declarations are counted, the player's apart")
	# The real thing: joining and declaring both count.
	_fresh()
	gs.ai_declarations = {"total": 0, "unjustified": 0}
	D.start_war(gs, "AUH", "SRB", true)
	for i in 10:
		clock.advance_day()
	_check(gs.ai_declarations.total >= 4 and gs.ai_declarations.unjustified == 0, "nations joining a war count as justified declarations (%d)" % gs.ai_declarations.total)


func _ready_to_strike(aggression := 0.5) -> void:
	_fresh()
	gs.nations["GER"].mobilization = 0.5
	gs.nations["GER"].diplomacy_points = 100.0
	gs.armies.clear()
	_army("GER", gs.nations["GER"].provinces[0], 60)
	_army("BEL", gs.nations["BEL"].provinces[0], 3)
	gs.ai_declarations = {"total": 6, "unjustified": 0}
	gs.ai_traits["GER"] = {"aggression": aggression, "caution": 0.5}
	# The plan is given here (the AI makes its own as it picks targets; no scenario scripts one).
	gs.ai_plans.append({"nation": "GER", "enemy": "BEL", "posture": "offensive", "objectives": [{"province": gs.nations["BEL"].capital, "weight": 1.0}]})
	# Belgium stands apart and is guaranteed by others: the weights against that are tested on their own below, and
	# switched off here, where Belgium is only a weak neighbour.
	_neutral_weights(0.0, 0.0)


func _neutral_weights(neutral: float, guaranteed: float) -> void:
	var w: Dictionary = load("res://scripts/ai/ai.gd").cfg.diplomacy.war
	w.neutral_penalty = neutral
	w.guaranteed_penalty = guaranteed


func _test_unjustified_conditions() -> void:
	_ready_to_strike()
	var desire_plain: float = AD.war_desire(gs, "GER", "BEL", false)
	_neutral_weights(0.6, 0.3)
	_check(D.is_neutral(gs, "BEL") and AD.war_desire(gs, "GER", "BEL", false) < desire_plain - 0.8, "Belgium stands apart and others guarantee it, so Germany wants it far less (%.2f against %.2f)" % [AD.war_desire(gs, "GER", "BEL", false), desire_plain])
	_check(AD.war_option(gs, "GER", "BEL").is_empty(), "and will not reach for it")
	_neutral_weights(0.0, 0.0)
	var o: Dictionary = AD.war_option(gs, "GER", "BEL")
	_check(not o.is_empty() and o.cb == "none" and o.odds >= 4.0, "with a plan, mobilization, odds and room under the cap, Germany would invade Belgium")

	_ready_to_strike()
	gs.ai_declarations = {"total": 3, "unjustified": 0}
	_check(AD.war_option(gs, "GER", "BEL").is_empty(), "not while the cap would be broken")
	_ready_to_strike()
	gs.nations["GER"].mobilization = 0.0
	_check(AD.war_option(gs, "GER", "BEL").is_empty(), "not unmobilized")
	_ready_to_strike(0.2)
	_check(AD.war_option(gs, "GER", "BEL").is_empty(), "not with low aggression")
	_ready_to_strike()
	gs.ai_plans.clear()
	_check(AD.war_option(gs, "GER", "BEL").is_empty(), "not without a plan against the target")
	_ready_to_strike()
	for a in gs.armies.values():
		if a.tag == "BEL":
			for i in 40:
				a.units.append(UnitC.new("infantry"))
	_check(AD.war_option(gs, "GER", "BEL").is_empty(), "not without overwhelming odds")
	_ready_to_strike()
	gs.nations["GER"].diplomacy_points = 5.0
	_check(AD.war_option(gs, "GER", "BEL").is_empty(), "not without the diplomacy points to pay for it")
	# And through the AI's own turn.
	_ready_to_strike()
	AD.consider_war(gs, "GER")
	_check(gs.wars.size() == 1 and gs.ai_declarations.unjustified == 1, "one declaration is made, and counted (the best-wanted target)")
	var share: float = float(gs.ai_declarations.unjustified) / gs.ai_declarations.total
	_check(share <= 0.15 + 0.0001, "and leaves the unjustified share at %.1f%%, within the cap" % (share * 100.0))


func _test_provocation() -> void:
	_fresh()
	gs.nations["GER"].mobilization = 0.5
	D.declare_war(gs, "GER", "BEL", "none")
	gs.nations["FRA"].mobilization = 0.0
	gs.nations["FRA"].diplomacy_points = 100.0
	gs.armies.clear()
	_army("FRA", gs.nations["FRA"].provinces[0], 80)
	_army("GER", gs.nations["GER"].provinces[0], 10)
	D.add_grievance(gs, "FRA", "GER", 70.0)
	var o: Dictionary = AD.war_option(gs, "FRA", "GER")
	_check(not o.is_empty() and o.cb != "none", "a provoked nation with the means answers with a casus belli, mobilized or not")
	# No grievance and no mobilization: nothing.
	gs.grievance.clear()
	_check(AD.war_option(gs, "FRA", "GER").is_empty(), "calm, it does not")
	# Too weak to answer.
	D.add_grievance(gs, "FRA", "GER", 70.0)
	gs.armies.clear()
	_army("FRA", gs.nations["FRA"].provinces[0], 5)
	_army("GER", gs.nations["GER"].provinces[0], 60)
	_check(AD.war_option(gs, "FRA", "GER").is_empty(), "and a provoked nation too weak to win bides its time")


func _test_quiet_world() -> void:
	_fresh()
	gs.ai_enabled = true
	gs.ai_traits.clear()
	for i in 150:
		clock.advance_day()
	var declared: bool = gs.command_log.any(func(c: Dictionary) -> bool: return c.type == "DeclareWar")
	_check(gs.wars.is_empty() and not declared, "nations in no danger declare no wars in five months")


func _test_treaties() -> void:
	_fresh()
	gs.ai_enabled = true
	gs.nations["BEL"].diplomacy_points = 100.0
	D.set_relation(gs, "NED", "BEL", 90.0)
	D.set_relation(gs, "BEL", "NED", 90.0)
	D.set_relation(gs, "GER", "BEL", -40.0)
	var best: Dictionary = AD.best_treaty(gs, "BEL")
	_check(not best.is_empty() and best.value >= A.cfg.diplomacy.treaties.propose_threshold, "a nation with a menacing neighbour and a friend finds a treaty worth proposing (%s)" % str(best))
	var before: float = gs.nations["BEL"].diplomacy_points
	AD.consider_treaties(gs, "BEL")
	_check(gs.command_log.any(func(c: Dictionary) -> bool: return c.type == "ProposeTreaty" and c.from == "BEL"), "and proposes it")
	_check(gs.nations["BEL"].diplomacy_points < before, "paying in diplomacy points")
	var count: int = gs.command_log.size()
	AD.consider_treaties(gs, "BEL")
	_check(gs.command_log.size() == count, "once a month at most")
	gs.nations["BEL"].diplomacy_points = 45.0
	gs.ai_diplo_stamp.clear()
	_check(AD.best_treaty(gs, "BEL").is_empty(), "it keeps a reserve of points for a crisis (%.0f points)" % 45.0)
	# Friends short of the bar get an effort to improve relations.
	_fresh()
	gs.nations["FRA"].diplomacy_points = 100.0
	D.set_relation(gs, "RUS", "FRA", 20.0)
	D.set_relation(gs, "FRA", "RUS", 20.0)
	var friend: Dictionary = AD.best_friend(gs, "FRA")
	_check(friend.get("to", "") != "", "a nation works on relations with a bloc friend short of an alliance bar (%s)" % str(friend))
	gs.ai_enabled = true
	AD.consider_treaties(gs, "FRA")
	_check(not gs.relation_projects.is_empty(), "and starts an effort")


## The 1914 chain depends on temperament: with a cautious Germany there is no march on Belgium.
func _test_temperaments() -> void:
	_fresh()
	gs.ai_enabled = true
	gs.join_calls.clear()
	gs.scenario["start_crisis"] = true
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("ESP")
	gs.ai_traits["GER"] = {"aggression": 0.2, "caution": 0.8}
	for i in 30:
		clock.advance_day()
	_check(gs.at_war("GER", "RUS") and not gs.at_war("GER", "BEL"), "with a cautious Germany the great war starts but Belgium is left alone")
