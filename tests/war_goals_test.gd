extends SceneTree
## Headless test for war goals: a demand names what a war over it would be for, the goal rides on the
## casus belli its refusal gives onto the War, peace terms matching it cost half and the rest more, scenario claims
## and defence give goals of their own, the AI picks and pursues goals, and a save keeps the goal.
## Run: godot --headless --path . -s res://tests/war_goals_test.gd

var _failures := 0
var gs: Node
var clock: Node
var D
var G
var P
var AD
var AP


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.set_player("ESP")
	gs.ai_enabled = false


func _province(owner: String, index := 0) -> int:
	return gs.nations[owner].provinces[index]


## A province of `owner` that `taker` could take on its own (it touches the taker's land), not one of `besides`.
func _takeable(owner: String, taker: String, besides := []) -> int:
	for id: int in gs.nations[owner].provinces:
		if id not in besides and P.province_problem(gs, taker, owner, [id]) == "":
			return id
	return 0


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	D = load("res://scripts/sim/diplomacy.gd")
	G = load("res://scripts/sim/war_goal.gd")
	P = load("res://scripts/sim/peace.gd")
	AD = load("res://scripts/ai/ai_diplomacy.gd")
	AP = load("res://scripts/ai/ai_peace.gd")
	var Press = load("res://scripts/sim/press_demand.gd")
	var C = load("res://scripts/sim/crisis.gd")
	var Declare = load("res://scripts/sim/declare_war.gd")
	var demand := func(goal: Dictionary) -> bool: return gs.issue(Press.new("GER", "BEL", "", {"demand": C.demand_for(goal), "goal": goal}))

	# --- A demand for provinces --------------------------------------------------------------
	_fresh()
	gs.nations["GER"].diplomacy_points = 200.0
	# Belgian ground Germany could take: on its border first (a goal must touch the claimant's land).
	var belgian: Array = P.pick_takeable(gs, "GER", "BEL", Array(gs.nations["BEL"].provinces), func(_id: int) -> float: return 1.0, 6.0).ids
	var one: Array = [belgian[0]]
	var two: Array = [belgian[0], belgian[1]]
	_check(not demand.call(G.provinces_goal([])), "a demand for no provinces is refused")
	_check(not demand.call(G.provinces_goal([_province("FRA")])), "so is one naming land the target does not own")
	_check(not demand.call({"kind": "mystery"}), "and an unknown kind")
	_check(C.press_cost(gs, "GER", G.provinces_goal(two)) > C.press_cost(gs, "GER", G.provinces_goal(one)), "each extra province makes the demand dearer")
	var rel: float = D.relation(gs, "BEL", "GER")
	var before: float = gs.nations["GER"].diplomacy_points
	var goal: Dictionary = G.provinces_goal(two)
	var cost: float = C.press_cost(gs, "GER", goal)
	_check(demand.call(goal), "Germany demands two Belgian provinces")
	_check(absf((before - gs.nations["GER"].diplomacy_points) - cost) < 0.01, "it is paid for in diplomacy points (%d)" % roundi(cost))
	_check(D.relation(gs, "BEL", "GER") < rel, "and Belgium thinks less of Germany for it")
	var crisis: Dictionary = C.of(gs, "BEL")[0]
	_check(crisis.a == "GER" and crisis.goal.kind == "provinces" and crisis.goal.ids == two, "the crisis holds the goal")
	C.respond(gs, crisis.id, "BEL", "refuse")
	var held: Dictionary = {}
	for cb: Dictionary in gs.casus_belli:
		if cb.holder == "GER" and cb.target == "BEL":
			held = cb
	_check(not held.is_empty() and held.goal.ids == two, "Belgium refuses, and the claim Germany holds carries the goal")
	_check(G.for_declaration(gs, "GER", "BEL", "fabricated_claim").ids == two, "and a declaration on it takes the goal")
	gs.nations["GER"].diplomacy_points = 200.0
	var seen_goal: Array = []
	var listen := func(a: String, b: String, at_war: bool) -> void:
		if at_war and a == "GER" and b == "BEL":
			seen_goal.append(gs.war_between(a, b).goal.duplicate(true))
	gs.war_changed.connect(listen)
	_check(gs.issue(Declare.new("GER", "BEL", "fabricated_claim")), "Germany declares war on it")
	gs.war_changed.disconnect(listen)
	_check(seen_goal.size() == 1 and seen_goal[0].get("ids", []) == two, "whoever hears of the war hears its goal with it")
	var war: War = gs.war_between("GER", "BEL")
	_check(war.goal.kind == "provinces" and war.goal.ids == two, "the war is fought for those provinces")
	_check(G.line(gs, war).contains("fights"), "and the why line says so: %s" % G.line(gs, war))
	_check(is_equal_approx(G.progress(gs, war), 0.0), "with no progress yet")

	# --- Peace terms priced by the goal ----------------------------------------------------
	var goal_id: int = two[0]
	# A province beyond the goal, priced as part of a demand that reaches it through the goal's ground.
	var other_id: int = belgian[2]
	var base_goal: float = P.province_price(gs, goal_id, "GER", "BEL")
	var base_other: float = P.province_price(gs, other_id, "GER", "BEL")
	var c_goal: float = P.demand_cost(gs, "GER", "BEL", {"kind": "province", "ids": [goal_id]})
	var c_other: float = P.demand_cost(gs, "GER", "BEL", {"kind": "province", "ids": two + [other_id]}) - P.demand_cost(gs, "GER", "BEL", {"kind": "province", "ids": two})
	_check(absf(c_goal - base_goal * float(G.cfg().discount)) < 0.0001, "a goal province costs the discount (%.2f of %.2f)" % [c_goal, base_goal])
	_check(absf(c_other - base_other * float(G.cfg().premium)) < 0.0001, "another province costs the premium (%.2f of %.2f)" % [c_other, base_other])
	var ind := {"kind": "indemnity", "share": 0.1, "months": 12}
	_check(P.demand_cost(gs, "GER", "BEL", ind) > P.cfg().price.indemnity_points_per_year * 0.1 * 12.0 / 12.0, "an indemnity costs more than its base in a province war")
	_check(P.demand_cost(gs, "BEL", "GER", ind) > 0.0 and absf(P.demand_cost(gs, "BEL", "GER", ind) - P.cfg().price.indemnity_points_per_year * 0.1) < 0.0001, "the defender pays plain prices")
	# Holding the goal is progress, and meets the aim.
	for id in two:
		gs.province_controller[id] = "GER"
	_check(is_equal_approx(G.progress(gs, war), 1.0), "holding both goal provinces is full progress")
	_check(is_equal_approx(AP.aims_met(gs, "GER", "BEL"), 1.0), "the AI counts its aim as met")
	var terms: Array = AP.price_terms(gs, "GER", "BEL", war)
	_check(not terms.is_empty() and terms[0].kind == "province" and two[0] in terms[0].ids, "and asks for the goal first (%s)" % str(terms))

	# --- No casus belli: dearer terms, no goal --------------------------------------------
	_fresh()
	gs.nations["GER"].mobilization = 1.0
	gs.nations["GER"].diplomacy_points = 200.0
	gs.issue(Declare.new("GER", "BEL", "none"))
	war = gs.war_between("GER", "BEL")
	_check(war != null and war.goal.is_empty(), "a war with no casus belli has no goal")
	var near: int = _takeable("BEL", "GER")
	var plain: float = P.province_price(gs, near, "GER", "BEL")
	_check(absf(P.demand_cost(gs, "GER", "BEL", {"kind": "province", "ids": [near]}) - plain * float(G.cfg().none_premium)) < 0.0001, "and every term costs the premium for it")
	_check(G.line(gs, war).contains("no casus belli"), "the why line says it: %s" % G.line(gs, war))

	# --- A scenario claim gives its goal ---------------------------------------------------
	_fresh()
	var claim_goal: Dictionary = G.for_declaration(gs, "FRA", "GER", "reconquest")
	_check(claim_goal.get("kind", "") == "nationality" and not claim_goal.ids.is_empty(), "France's reconquest claim is a national goal on Alsace-Lorraine")
	gs.nations["FRA"].diplomacy_points = 200.0
	gs.issue(Declare.new("FRA", "GER", "reconquest"))
	war = gs.war_between("FRA", "GER")
	_check(war != null and war.goal.kind == "nationality", "the war is fought for it")

	# --- Defence ---------------------------------------------------------------------------
	_fresh()
	var defence: Dictionary = G.for_declaration(gs, "FRA", "GER", "ally_called")
	_check(defence.kind == "defence", "an ally called to arms fights a defence")
	gs.set_war("FRA", "GER", true, "ally_called")
	war = gs.war_between("FRA", "GER")
	war.goal = defence
	var dprice: float = P.demand_cost(gs, "FRA", "GER", {"kind": "indemnity", "share": 0.1, "months": 12})
	_check(absf(dprice - P.cfg().price.indemnity_points_per_year * 0.1 * float(G.cfg().discount)) < 0.0001, "a defender's indemnity costs the discount")
	var border: int = _takeable("GER", "FRA")
	_check(P.demand_cost(gs, "FRA", "GER", {"kind": "province", "ids": [border]}) > P.province_price(gs, border, "FRA", "GER"), "but land costs more")

	# --- A concession -----------------------------------------------------------------------
	_fresh()
	gs.nations["GER"].diplomacy_points = 200.0
	var cgoal: Dictionary = G.concession_goal({"kind": "indemnity", "share": 0.15, "months": 24})
	_check(G.invalid(gs, "GER", "BEL", cgoal) == "", "an indemnity goal is valid")
	_check(G.invalid(gs, "GER", "BEL", G.concession_goal({"kind": "release_ally", "nation": "ESP"})) == "demand", "ending ties that do not exist is not")
	_check(demand.call(cgoal), "Germany demands an indemnity")
	_check(C.of(gs, "BEL")[0].kind == "indemnity", "and the crisis is of that kind")

	# --- The AI picks a goal ----------------------------------------------------------------
	_fresh()
	var chosen: Dictionary = AD.choose_goal(gs, "GER", "BEL")
	_check(chosen.kind == "provinces" and not chosen.ids.is_empty() and G.invalid(gs, "GER", "BEL", chosen) == "", "the AI chooses a valid province goal on a neighbour (%d provinces)" % chosen.get("ids", []).size())

	# --- A save keeps the goal --------------------------------------------------------------
	_fresh()
	gs.set_war("GER", "BEL", true, "fabricated_claim")
	war = gs.war_between("GER", "BEL")
	war.goal = G.provinces_goal([_province("BEL")], "test")
	var SaveGame = load("res://scripts/sim/save_game.gd")
	var path := "user://war_goals_test.sav"
	SaveGame.write(gs, path)
	gs.wars.clear()
	SaveGame.read(gs, path)
	war = gs.war_between("GER", "BEL")
	_check(war != null and war.goal.get("kind", "") == "provinces" and war.goal.ids == [_province("BEL")], "a saved and loaded war still has its goal")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
