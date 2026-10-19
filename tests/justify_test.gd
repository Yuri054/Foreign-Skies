extends SceneTree
## Headless test for war justification: the command, its cost and delay, the casus belli it
## yields, the penalties for skipping it, and the AI's use of it.
## Run: godot --headless --path . -s res://tests/justify_test.gd

var _failures := 0
var gs: Node
var clock: Node
var D
var AD
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
	D = load("res://scripts/sim/diplomacy.gd")
	AD = load("res://scripts/ai/ai_diplomacy.gd")
	Mil = load("res://scripts/sim/military.gd")
	UnitC = load("res://scripts/sim/unit.gd")
	var Cmd = load("res://scripts/sim/justify_war.gd")

	_fresh()
	var n = gs.nations["GER"]
	n.diplomacy_points = 100.0
	_check(D.casus_belli_options(gs, "GER", "BEL") == ["none"], "Germany has no casus belli on Belgium to begin with")
	var cmd = Cmd.new("GER", "BEL")
	_check(gs.issue(cmd), "Germany starts justifying a war on Belgium")
	_check(absf(n.diplomacy_points - (100.0 - D.cost_of("justify"))) < 0.001, "it costs %d points" % int(D.cost_of("justify")))
	_check(D.justifying(gs, "GER", "BEL") != null and D.justify_block(gs, "GER", "BEL") == "active", "the work is under way, and cannot be started twice")
	var g0: float = D.grievance(gs, "BEL", "GER")
	_check(g0 > 0.0, "Belgium resents it (grievance %.0f)" % g0)
	for i in int(D.cfg.war.justify.days) - 2:
		clock.advance_day()
	_check("fabricated_claim" not in D.casus_belli_options(gs, "GER", "BEL"), "the claim is not ready early")
	for i in 4:
		clock.advance_day()
	_check(D.casus_belli_options(gs, "GER", "BEL")[0] == "fabricated_claim" and gs.justifications.is_empty(), "after %d days Germany holds a fabricated claim" % int(D.cfg.war.justify.days))
	_check(D.justify_block(gs, "GER", "BEL") == "has_cause", "and cannot justify the same war again")

	# Declaring with it is cheaper in standing than without.
	var rel: float = D.relation(gs, "BEL", "GER")
	var prestige: float = n.prestige
	var support: float = gs.nations["GER"].war_support
	n.diplomacy_points = 100.0
	_check(gs.issue(load("res://scripts/sim/declare_war.gd").new("GER", "BEL", "fabricated_claim")), "the war is declared on the claim")
	var with_claim: float = prestige - n.prestige
	var rel_with: float = rel - D.relation(gs, "BEL", "GER")
	_fresh()
	n = gs.nations["GER"]
	n.diplomacy_points = 100.0
	n.mobilization = 0.5
	var rel2: float = D.relation(gs, "BEL", "GER")
	var prestige2: float = n.prestige
	_check(gs.issue(load("res://scripts/sim/declare_war.gd").new("GER", "BEL", "none")), "a war without justification is allowed")
	_check(prestige2 - n.prestige > with_claim and rel2 - D.relation(gs, "BEL", "GER") > rel_with, "but costs more prestige (%.0f against %.0f) and relations" % [prestige2 - n.prestige, with_claim])
	_check(gs.nations["GER"].war_support < support, "and war support")

	# Refusals.
	_fresh()
	n = gs.nations["GER"]
	n.diplomacy_points = 5.0
	var poor = Cmd.new("GER", "BEL")
	_check(not gs.issue(poor) and poor.reason == "points", "too few points: refused")
	n.diplomacy_points = 100.0
	_check(not gs.issue(Cmd.new("GER", "AUH")) and D.justify_block(gs, "GER", "AUH") != "", "no justifying against an ally (%s)" % D.justify_block(gs, "GER", "AUH"))
	gs.issue(Cmd.new("GER", "BEL"))
	gs.issue(Cmd.new("GER", "DEN"))
	_check(D.justify_block(gs, "GER", "FRA") == "limit", "at most %d efforts at a time" % int(D.cfg.war.justify.max_active))
	gs.set_war("GER", "BEL", true)
	clock.advance_day()
	_check(D.justifying(gs, "GER", "BEL") == null, "an effort ends if the war comes first")

	# Saves keep it.
	_fresh()
	gs.nations["GER"].diplomacy_points = 100.0
	gs.issue(Cmd.new("GER", "BEL"))
	var save = load("res://scripts/sim/save_game.gd")
	var data: Dictionary = save.snapshot(gs)
	_check(data.state.has("justifications") and data.state.justifications.size() == 1, "justifications are saved")

	# The AI works for a claim instead of striking unjustified when the cap forbids the latter.
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
	_check(AD.war_option(gs, "GER", "BEL").is_empty(), "the cap forbids an unjustified war on Belgium")
	AD.consider_war(gs, "GER")
	_check(gs.wars.is_empty() and not D.justifications_of(gs, "GER").is_empty(), "so Germany starts justifying one")

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.set_player("ESP")
	gs.ai_enabled = false
