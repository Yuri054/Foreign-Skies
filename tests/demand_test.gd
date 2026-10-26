extends SceneTree
## Headless test for demands, which took the place of war justification (step 5 of PLAN.md): a demand chosen in full,
## its price, the casus belli a refusal gives, the penalties for a war with no cause at all, the AI making a demand
## where it once built a case, and an old save's case under way becoming the claim it would have made.
## Run: godot --headless --path . -s res://tests/demand_test.gd

var _failures := 0
var gs: Node
var clock: Node
var D
var C
var G
var AD
var Mil
var UnitC
var Press


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
	D = load("res://scripts/sim/diplomacy.gd")
	C = load("res://scripts/sim/crisis.gd")
	G = load("res://scripts/sim/war_goal.gd")
	AD = load("res://scripts/ai/ai_diplomacy.gd")
	Mil = load("res://scripts/sim/military.gd")
	UnitC = load("res://scripts/sim/unit.gd")
	Press = load("res://scripts/sim/press_demand.gd")

	_fresh()
	var n = gs.nations["GER"]
	n.diplomacy_points = 100.0
	_check(D.casus_belli_options(gs, "GER", "BEL") == ["none"], "Germany has no casus belli on Belgium to begin with")
	var goal: Dictionary = G.concession_goal({"kind": "indemnity", "share": 0.1, "months": 12})
	var cost: float = C.press_cost(gs, "GER", goal)
	_check(gs.issue(Press.new("GER", "BEL", "", {"demand": C.demand_for(goal), "goal": goal})), "Germany demands an indemnity of Belgium")
	_check(absf(n.diplomacy_points - (100.0 - cost)) < 0.001, "it costs %d points" % roundi(cost))
	var c: Dictionary = C.of(gs, "BEL")[0]
	_check(C.press_block(gs, "GER", "BEL", true) == "busy", "and no second demand can be made while it stands")
	C.respond(gs, c.id, "BEL", "refuse")
	_check(D.casus_belli_options(gs, "GER", "BEL")[0] == "fabricated_claim", "Belgium refuses: Germany holds a casus belli (%s)" % D.cfg.war.casus_belli.fabricated_claim.label)

	# Declaring with it is cheaper in standing than with no cause at all.
	var rel: float = D.relation(gs, "BEL", "GER")
	var prestige: float = n.prestige
	var support: float = gs.nations["GER"].war_support
	n.diplomacy_points = 100.0
	_check(gs.issue(load("res://scripts/sim/declare_war.gd").new("GER", "BEL", "fabricated_claim")), "the war is declared on the refused demand")
	var with_claim: float = prestige - n.prestige
	var rel_with: float = rel - D.relation(gs, "BEL", "GER")
	_fresh()
	n = gs.nations["GER"]
	n.diplomacy_points = 100.0
	n.mobilization = 0.5
	var rel2: float = D.relation(gs, "BEL", "GER")
	var prestige2: float = n.prestige
	_check(gs.issue(load("res://scripts/sim/declare_war.gd").new("GER", "BEL", "none")), "a war with no casus belli is allowed")
	_check(prestige2 - n.prestige > with_claim and rel2 - D.relation(gs, "BEL", "GER") > rel_with, "but costs more prestige (%.0f against %.0f) and relations" % [prestige2 - n.prestige, with_claim])
	_check(gs.nations["GER"].war_support < support, "and war support")

	# Refusals.
	_fresh()
	n = gs.nations["GER"]
	n.diplomacy_points = 2.0
	var poor = Press.new("GER", "BEL", "", {"demand": C.demand_for(goal), "goal": goal})
	_check(not gs.issue(poor) and poor.reason == "points", "too few points: refused")
	n.diplomacy_points = 100.0
	var ally = Press.new("GER", "AUH", "", {"demand": C.demand_for(goal), "goal": goal})
	_check(not gs.issue(ally) and ally.reason == "allied", "no demand of an ally (%s)" % ally.reason)

	# The AI makes a demand where it cannot strike: the cap on wars with no cause forbids it.
	_fresh()
	gs.nations["GER"].mobilization = 0.5
	gs.nations["GER"].diplomacy_points = 100.0
	gs.armies.clear()
	var a = Mil.new_army(gs, "GER", "Test army", gs.nations["GER"].provinces[0])
	for i in 60:
		a.units.append(UnitC.new("infantry"))
	var b = Mil.new_army(gs, "BEL", "Test army", gs.nations["BEL"].provinces[0])
	for i in 3:
		b.units.append(UnitC.new("infantry"))
	gs.ai_declarations = {"total": 3, "unjustified": 0}
	gs.ai_traits["GER"] = {"aggression": 0.5, "caution": 0.5}
	gs.ai_plans.append({"nation": "GER", "enemy": "BEL", "posture": "offensive", "objectives": [{"province": gs.nations["BEL"].capital, "weight": 1.0}]})
	# Belgium is only a weak neighbour here: the weights against a neutral, guaranteed nation are off (ai_diplomacy_test has them).
	var w: Dictionary = load("res://scripts/ai/ai.gd").cfg.diplomacy.war
	w.neutral_penalty = 0.0
	w.guaranteed_penalty = 0.0
	_check(AD.war_option(gs, "GER", "BEL").is_empty(), "the cap forbids a war with no cause on Belgium")
	AD.consider_war(gs, "GER")
	var made: Array = C.of(gs, "BEL")
	_check(gs.wars.is_empty() and not made.is_empty() and made[0].a == "GER", "so Germany makes a demand of it (%s)" % (made[0].title if not made.is_empty() else "none"))

	# An old save: a case being built becomes the claim it would have made.
	var SG = load("res://scripts/sim/save_game.gd")
	var state := {"casus_belli": [], "justifications": [SG._encode({"holder": "GER", "target": "BEL", "goal": goal, "done_day": 400})]}
	SG._migrate(state, 3)
	var cbs: Array = SG._decode(state.casus_belli)
	_check(not state.has("justifications") and cbs.size() == 1 and cbs[0].kind == "fabricated_claim" and cbs[0].holder == "GER" and cbs[0].goal.kind == "concession",
			"a version 3 save's case under way loads as a casus belli with its goal")
	_check(int(cbs[0].expires_day) == 400 + int(D.cfg.war.cb_years * 365), "lasting from the day it would have been ready")

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.set_player("ESP")
	gs.ai_enabled = false
