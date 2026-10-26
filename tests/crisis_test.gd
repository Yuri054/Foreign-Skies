extends SceneTree
## Headless test for dynamic crises: how one opens (the demand, the deadline, who may quarrel), how the nation asked
## answers (yield, refuse, mobilize, appeal), what a third nation can do (mediate, back a side), the AI's own
## answers, the question put to the player, and that a crisis survives a save.
## Run: godot --headless --path . -s res://tests/crisis_test.gd

var _failures := 0
var gs: Node
var clock: Node
var C
var P
var D


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _fresh(player := "ESP") -> void:
	gs.load_scenario("res://data/scenarios/jan_1900/")
	gs.join_calls.clear()
	gs.wars.clear()
	gs.set_player(player)
	gs.ai_enabled = false
	clock.advance_day()


func _open(a: String, b: String) -> Dictionary:
	return C.open(gs, {"a": a, "b": b, "score": 1.0})


func _outcome(id: int) -> String:
	for e: Dictionary in gs.crisis_log:
		if e.id == id:
			return e.outcome
	return ""


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	C = load("res://scripts/sim/crisis.gd")
	P = load("res://scripts/sim/pressure.gd")
	D = load("res://scripts/sim/diplomacy.gd")
	var Action = load("res://scripts/sim/crisis_action.gd")

	# --- Opening ---------------------------------------------------------------------------
	_fresh()
	var c: Dictionary = _open("FRA", "GER")
	_check(not c.is_empty() and c.kind == "claim", "France opens a crisis over its claim on Germany (%s)" % c.get("kind", ""))
	_check(c.demand.kind == "province" and not c.demand.ids.is_empty() and c.goal.kind == "nationality", "the demand is the claimed provinces, with a national goal")
	_check(gs.crises.size() == 1 and c.deadline_day - c.start_day == int(C.cfg.gate.deadline_days), "it is under way, with a deadline of %d days" % int(C.cfg.gate.deadline_days))
	_check(c.title.contains("France") and c.text.contains("German Empire"), "its title and text name both nations: %s" % c.title)
	_check(not C.may_quarrel(gs, "FRA", "GER") and not C.may_quarrel(gs, "GER", "FRA"), "the two cannot open another while it lasts")
	_check(not C.may_quarrel(gs, "GER", "AUH"), "allies do not quarrel")
	_check(not C.may_quarrel(gs, gs.player_tag, "GER"), "the player never opens a crisis")
	var c_id: int = c.id

	# --- Yielding --------------------------------------------------------------------------
	var ids: Array = c.demand.ids.duplicate()
	var prestige_a: float = gs.nations["FRA"].prestige
	var prestige_b: float = gs.nations["GER"].prestige
	_check(C.respond(gs, c_id, "GER", "yield"), "Germany yields")
	_check(gs.province_owner[ids[0]] == "FRA", "the provinces pass to France")
	_check(gs.nations["FRA"].prestige > prestige_a and gs.nations["GER"].prestige < prestige_b, "France gains prestige and Germany loses it")
	_check(gs.crises.is_empty() and _outcome(c_id) == "yielded", "the crisis is filed as yielded")
	_check(not C.respond(gs, c_id, "GER", "yield"), "an ended crisis cannot be answered again")

	# --- Refusing ---------------------------------------------------------------------------
	_fresh()
	c = _open("FRA", "GER")
	var rel: float = D.relation(gs, "FRA", "GER")
	var goal: Dictionary = c.goal
	_check(C.respond(gs, c.id, "GER", "refuse"), "Germany refuses")
	var held := false
	for cb: Dictionary in gs.casus_belli:
		if cb.holder == "FRA" and cb.target == "GER" and cb.get("goal", {}) == goal:
			held = true
	var war: War = gs.war_between("FRA", "GER")
	_check(held or (war != null and war.goal == goal), "France gets a casus belli with the demand as its goal (or has gone to war on it)")
	_check(D.relation(gs, "FRA", "GER") < rel, "relations worsen")
	_check(_outcome(c.id) == "refused", "the crisis is filed as refused")

	# --- Mobilizing ---------------------------------------------------------------------------
	_fresh()
	c = _open("FRA", "GER")
	var mobilization: float = gs.nations["GER"].mobilization
	var margin: float = C.cfg.mobilize.deter_margin
	C.cfg.mobilize.deter_margin = 1000.0
	_check(C.respond(gs, c.id, "GER", "mobilize"), "Germany mobilizes")
	C.cfg.mobilize.deter_margin = margin
	_check(gs.nations["GER"].mobilization > mobilization, "its mobilization rises")
	_check(_outcome(c.id) == "backed_down", "a demander that cannot win backs down")
	_fresh()
	c = _open("FRA", "GER")
	C.cfg.mobilize.deter_margin = 0.0
	C.respond(gs, c.id, "GER", "mobilize")
	C.cfg.mobilize.deter_margin = margin
	_check(_outcome(c.id) == "refused", "one that can win takes it as a refusal")

	# --- Third nations --------------------------------------------------------------------
	_fresh("GBR")
	c = _open("FRA", "GER")
	gs.nations["GBR"].diplomacy_points = 100.0
	var odds0: float = C.odds_a(gs, c)
	var rel_b: float = D.relation(gs, "GBR", "GER")
	var rel_a: float = D.relation(gs, "GBR", "FRA")
	_check(gs.issue(Action.new("GBR", c.id, "back_b")), "Britain backs Germany")
	_check("GBR" in C.find(gs, c.id).backers_b, "it is listed among Germany's backers")
	_check(D.relation(gs, "GBR", "GER") > rel_b and D.relation(gs, "GBR", "FRA") < rel_a, "relations with Germany rise, with France fall")
	_check(C.odds_a(gs, C.find(gs, c.id)) < odds0, "and France's odds fall (%.2f to %.2f)" % [odds0, C.odds_a(gs, C.find(gs, c.id))])
	gs.nations["GBR"].diplomacy_points = 0.0
	_check(not gs.issue(Action.new("GBR", c.id, "mediate")), "a third nation without the points cannot mediate")
	gs.nations["GBR"].diplomacy_points = 100.0
	var thr: float = C.cfg.mediate.threshold
	C.cfg.mediate.threshold = 5.0
	var pr: float = gs.nations["GBR"].prestige
	_check(gs.issue(Action.new("GBR", c.id, "mediate")) and gs.nations["GBR"].prestige < pr and not C.find(gs, c.id).is_empty(), "a failed mediation costs prestige and the crisis goes on")
	C.cfg.mediate.threshold = -5.0
	pr = gs.nations["GBR"].prestige
	_check(gs.issue(Action.new("GBR", c.id, "mediate")), "a mediation that succeeds")
	C.cfg.mediate.threshold = thr
	_check(_outcome(c.id) == "mediated" and gs.nations["GBR"].prestige > pr, "ends the crisis and earns the mediator prestige")
	var paid := false
	for ind: Dictionary in gs.indemnities:
		paid = paid or (ind.payer == "GER" and ind.receiver == "FRA")
	_check(paid and gs.province_owner[gs.nations["FRA"].provinces[0]] == "FRA", "Germany pays a modest indemnity in place of the provinces")

	# --- The AI answers -------------------------------------------------------------------
	_fresh()
	c = _open("FRA", "GER")
	var act: String = C.choose_response(gs, c)
	_check(act in ["yield", "refuse", "mobilize", "appeal"], "the AI chooses an answer (%s)" % act)
	for i in int(C.cfg.gate.think_days) - 1:
		clock.advance_day()
	_check(not C.find(gs, c.id).is_empty(), "it keeps thinking before the days are up")
	clock.advance_day()
	clock.advance_day()
	_check(C.find(gs, c.id).is_empty() and _outcome(c.id) != "", "and then answers (%s)" % _outcome(c.id))

	# --- A demand gone stale lapses ------------------------------------------------------------
	_fresh()
	c = _open("FRA", "GER")
	gs.transfer_province(c.demand.ids[0], "AUH")
	C.step_day(gs)
	_check(_outcome(c.id) == "lapsed", "a crisis whose province has changed hands lapses")

	# --- The player is asked ---------------------------------------------------------------------
	_fresh("GER")
	c = _open("FRA", "GER")
	var decision: Dictionary = {}
	for d: Dictionary in gs.pending_events:
		if d.event == "crisis:%d" % c.id:
			decision = d
	_check(not decision.is_empty() and decision.options.size() >= 3, "the player is asked how to answer (%d options)" % decision.get("options", []).size())
	_check(decision.options[0].has("tip") and P.effect_lines(gs, decision.options[0], decision.roles).size() >= 1, "each option says what it does")
	var chronicle: int = gs.chronicle.size()
	var answered: bool = P.answer(gs, decision.id, 0)
	_check(answered and gs.crises.is_empty() and _outcome(c.id) == "yielded", "answering Yield yields")
	_check(gs.pending_events.is_empty(), "and the question is gone")
	_fresh("GER")
	c = _open("FRA", "GER")
	for i in int(C.cfg.gate.deadline_days) + 2:
		clock.advance_day()
		if gs.pending_events.is_empty() and not C.find(gs, c.id).is_empty():
			continue
	_check(C.find(gs, c.id).is_empty() and _outcome(c.id) == "refused" and gs.pending_events.is_empty(), "left unanswered past the deadline, it counts as a refusal (%s)" % _outcome(c.id))

	# --- The monthly search -------------------------------------------------------------------
	_fresh()
	gs.pressure_ai = false
	C.step_month(gs)
	_check(gs.crises.is_empty(), "a scenario without pressure has no crises")
	gs.pressure_ai = true
	var gate: float = C.cfg.gate.min_score
	C.cfg.gate.min_score = 0.0
	var start: int = C.cfg.gate.start_days
	C.cfg.gate.start_days = 0
	C.step_month(gs)
	_check(gs.crises.size() == 1, "with a low bar the monthly search opens one crisis (%d)" % gs.crises.size())
	C.step_month(gs)
	_check(gs.crises.size() == 1, "and not another at once (the gap between crises)")
	gs.crises.clear()
	gs.crisis_cooldown.clear()
	gs.set_war("GER", "FRA", true, "none")
	gs.set_war("GER", "RUS", true, "none")
	gs.set_war("GER", "GBR", true, "none")
	gs.set_war("AUH", "ITA", true, "none")
	C.step_month(gs)
	_check(gs.crises.is_empty(), "no crisis opens while Europe is at war (%d wars)" % gs.wars.size())
	C.cfg.gate.min_score = gate
	C.cfg.gate.start_days = start

	# --- The player presses a demand -----------------------------------------------------------------
	_fresh("FRA")
	gs.nations["FRA"].diplomacy_points = 100.0
	var options: Array = C.demand_options(gs, "FRA", "GER")
	_check(not options.is_empty() and options[0].has("label") and options[0].has("goal"), "the player has demands to choose from (%d)" % options.size())
	var Press = load("res://scripts/sim/press_demand.gd")
	var points: float = gs.nations["FRA"].diplomacy_points
	var press = Press.new("FRA", "GER", options[0].kind)
	_check(gs.issue(press), "France presses a demand on Germany")
	_check(gs.nations["FRA"].diplomacy_points < points and not C.of(gs, "GER").is_empty(), "it costs points and a crisis opens")
	_check(C.of(gs, "GER")[0].a == "FRA", "with the player as the one demanding")
	_check(C.press_block(gs, "FRA", "GER") == "busy" and not gs.issue(Press.new("FRA", "GER", options[0].kind)), "and it cannot be pressed twice")
	var pressed_id: int = C.of(gs, "GER")[0].id
	for i in int(C.cfg.gate.think_days) + 2:
		clock.advance_day()
	_check(C.of(gs, "GER").is_empty() and _outcome(pressed_id) != "", "Germany answers by itself (%s)" % _outcome(pressed_id))
	_fresh("FRA")
	gs.nations["FRA"].diplomacy_points = 0.0
	_check(C.press_block(gs, "FRA", "GER") == "points", "without the points it cannot be pressed")
	gs.nations["FRA"].diplomacy_points = 100.0
	_check(C.press_block(gs, "FRA", "RUS") == "allied", "nor on an ally")

	# --- A save keeps the crisis ----------------------------------------------------------------
	_fresh()
	c = _open("FRA", "GER")
	var SaveGame = load("res://scripts/sim/save_game.gd")
	var path := "user://crisis_test.sav"
	SaveGame.write(gs, path)
	gs.crises.clear()
	SaveGame.read(gs, path)
	var back: Dictionary = C.find(gs, c.id)
	_check(not back.is_empty() and back.demand == c.demand and back.goal == c.goal and back.a == "FRA", "a saved and loaded crisis is whole")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
