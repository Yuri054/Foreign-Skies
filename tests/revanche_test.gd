extends SceneTree
## Headless test for step 4, after the war: ground lost at a peace leaves a claim and a lasting resentment (revanche),
## the crises it feeds (revanche, and the naval limit between great powers), events that pick their nations from the
## state of the world, repeatable foci that keep a nation busy, and tension's arms base that follows the armies.
## Run: godot --headless --path . -s res://tests/revanche_test.gd

var _failures := 0
var gs: Node
var clock: Node
var D
var P
var C
var Pr


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _fresh() -> void:
	gs.load_scenario("res://data/scenarios/jan_1900/")
	gs.ai_enabled = false
	gs.set_player("ESP")


## A province of `giver`, not its capital, that touches `taker`'s land.
func _border(taker: String, giver: String) -> int:
	var ids: Array = gs.nations[giver].provinces.duplicate()
	ids.sort()
	for id: int in ids:
		if id == gs.nations[giver].capital:
			continue
		for n: int in load("res://scripts/sim/military.gd").neighbors(id):
			if gs.province_owner[n] == taker:
				return id
	return 0


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	D = load("res://scripts/sim/diplomacy.gd")
	P = load("res://scripts/sim/peace.gd")
	C = load("res://scripts/sim/crisis.gd")
	Pr = load("res://scripts/sim/pressure.gd")
	_test_revanche()
	_test_naval()
	_test_events()
	_test_foci()
	_test_arms_base()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _test_revanche() -> void:
	_fresh()
	var id := _border("SRB", "BUL")
	_check(id > 0, "Bulgaria has a province on the Serbian border")
	var before: float = D.grievance(gs, "BUL", "SRB")
	P._apply_demand(gs, "SRB", "BUL", {"kind": "province", "ids": [id]})
	_check(gs.province_owner[id] == "SRB", "Bulgaria cedes it at a peace")
	_check(gs.claims.size() == 1 and gs.claims[0].holder == "BUL" and id in gs.claims[0].ids, "and keeps a claim to it")
	var floor_now: float = float(D.cfg.revanche.rivalry) + float(D.cfg.revanche.rivalry_per_province)
	_check(gs.rivalries.get("BUL>SRB", 0.0) >= floor_now and D.grievance(gs, "BUL", "SRB") >= before, "and a lasting resentment of Serbia (%.0f)" % D.grievance(gs, "BUL", "SRB"))
	_check("reconquest" in D.casus_belli_options(gs, "BUL", "SRB"), "which is a casus belli to win it back")
	_check(D.revanche_ids(gs, "BUL", "SRB") == [id], "the claim names the lost ground")
	var kinds: Array = C.demand_options(gs, "BUL", "SRB").map(func(o: Dictionary) -> String: return o.kind)
	_check(kinds.size() > 0 and kinds[0] == "revanche", "and the first demand Bulgaria would make in a crisis (%s)" % ", ".join(kinds))
	_check(C.score(gs, "BUL", "SRB") > C.score(gs, "BUL", "GRE"), "a lost province makes the quarrel likelier than one with a neighbour that took nothing")
	# Months later the resentment still stands; the grievance from a single act would have faded.
	for i in 24:
		D._step_grievance(gs)
	_check(D.grievance(gs, "BUL", "SRB") >= float(D.cfg.revanche.rivalry) - 3.0, "two years on the resentment holds (%.0f)" % D.grievance(gs, "BUL", "SRB"))
	# Saved with the game.
	var SG = load("res://scripts/sim/save_game.gd")
	SG.dir = "user://test_saves/"
	DirAccess.make_dir_recursive_absolute(SG.dir)
	var path: String = SG.dir + "revanche.sav"
	_check(SG.write(gs, path) == "", "the game is saved")
	gs.claims.clear()
	_check(SG.read(gs, path) == "" and gs.claims.size() == 1 and id in gs.claims[0].ids, "the claim is saved and loaded")
	DirAccess.remove_absolute(path)
	# Won back: the claim is gone.
	gs.transfer_province(id, "BUL")
	D._step_grievance(gs)
	_check(gs.claims.is_empty(), "once Bulgaria has its ground back the claim lapses")
	# It lapses with time too.
	P._apply_demand(gs, "SRB", "BUL", {"kind": "province", "ids": [id]})
	clock.days_elapsed += int(float(D.cfg.revanche.years) * 365.0) + 1
	D._step_grievance(gs)
	_check(gs.claims.is_empty(), "or after %d years" % int(D.cfg.revanche.years))


func _test_naval() -> void:
	_fresh()
	var kinds: Array = C.demand_options(gs, "GBR", "GER").map(func(o: Dictionary) -> String: return o.kind)
	_check("naval" in kinds, "Britain may ask Germany to build no more warships (%s)" % ", ".join(kinds))
	_check(not ("naval" in C.demand_options(gs, "SRB", "BUL").map(func(o: Dictionary) -> String: return o.kind)), "a small nation may not")
	var Navy = load("res://scripts/sim/navy.gd")
	gs.nations["GER"].treasury = 10000.0
	var port := 0
	var ship := ""
	for p: int in gs.nations["GER"].provinces:
		for type: String in Navy.cfg.types:
			if port == 0 and Navy.build_problem(gs, "GER", p, type, 1) == "":
				port = p
				ship = type
	_check(port > 0, "Germany can lay down a %s at peace" % ship)
	_check(P.demand_cost(gs, "GBR", "GER", {"kind": "fleet_limit", "years": 5}) > 0.0, "a fleet limit has a price at a peace table")
	P._apply_demand(gs, "GBR", "GER", {"kind": "fleet_limit", "years": 5})
	_check(P.fleet_limited(gs, "GER") and Navy.build_problem(gs, "GER", port, ship, 1) != "", "yielding stops new warships (%s)" % Navy.build_problem(gs, "GER", port, ship, 1))
	gs.set_war("GBR", "GER", true)
	_check(not P.fleet_limited(gs, "GER"), "but not against the nation that holds it, once at war with it")


func _test_events() -> void:
	_fresh()
	_check(Pr._pick_role(gs, "$lost_ground") == "", "no nation has lost ground at the start")
	var id := _border("SRB", "BUL")
	P._apply_demand(gs, "SRB", "BUL", {"kind": "province", "ids": [id]})
	_check(Pr._pick_role(gs, "$lost_ground") == "BUL" and Pr._pick_role(gs, "$winner") == "SRB", "after a peace the loser and the winner are picked")
	var e: Dictionary = Pr._event("lost_provinces")
	_check(not e.is_empty() and not Pr._condition_ok(gs, e), "the lost provinces wait out the scenario's first year")
	var later: int = (int(Pr.cfg.picks.recent_months) + 1) * 30
	clock.days_elapsed += later
	_check(Pr._pick_role(gs, "$lost_ground") == "", "the memory is fresh only for a while")
	clock.days_elapsed -= later
	var most: String = Pr._pick_role(gs, "$most_armed")
	var second: String = Pr._pick_role(gs, "$second_armed")
	_check(most in Pr.GREAT and second in Pr.GREAT and most != second and gs.nations[most].men_in_units >= gs.nations[second].men_in_units, "the arms conference turns to the most armed powers (%s, %s)" % [most, second])
	gs.nations["OTT"].war_support = 10.0
	_check(Pr._pick_role(gs, "$empire") == "OTT", "and unrest to a troubled empire")


func _test_foci() -> void:
	_fresh()
	var F = load("res://scripts/sim/focus.gd")
	var AF = load("res://scripts/ai/ai_focus.gd")
	var n = gs.nations["GER"]
	var forever: Array = F.tree_of("GER").filter(func(f: Dictionary) -> bool: return f.get("repeatable", false) and int(f.get("max", 1)) == 0)
	_check(forever.size() >= 2, "every great power has foci it may take for ever (%d)" % forever.size())
	var id: String = forever[0].id
	for i in 20:
		F.start(gs, "GER", id)
		F.complete(gs, "GER")
	_check(F.block(gs, "GER", id) == "" and id not in n.focus_done, "one taken twenty times may be taken again")
	_fresh()
	n = gs.nations["GER"]
	gs.ai_enabled = true
	AF.step(gs, "GER")
	_check(not n.focus.is_empty() and not F.find("GER", n.focus.id).get("repeatable", false), "the AI takes its tree first")
	for f: Dictionary in F.tree_of("GER"):
		if not f.get("repeatable", false):
			n.focus_done.append(f.id)
	n.focus = {}
	AF.step(gs, "GER")
	_check(not n.focus.is_empty(), "and with the tree done it still has a focus in hand (%s)" % n.focus.get("id", ""))


func _test_arms_base() -> void:
	_fresh()
	var base: float = gs.tension_arms_base
	var arms0: float = Pr.parts(gs).arms
	var army = load("res://scripts/sim/military.gd").new_army(gs, "GER", "More", gs.nations["GER"].capital)
	var UnitC = load("res://scripts/sim/unit.gd")
	for i in 40:
		army.units.append(UnitC.new("infantry"))
	load("res://scripts/sim/military.gd").refresh_men(gs)
	var arms1: float = Pr.parts(gs).arms
	_check(arms1 > arms0, "a great power arming raises tension's arms part (%.1f to %.1f)" % [arms0, arms1])
	for i in 24:
		Pr.step_month(gs)
	_check(is_equal_approx(gs.tension_arms_base, base), "before the great powers have fought, the arms race counts from the start")
	gs.set_war("FRA", "ITA", true)
	gs.set_war("FRA", "ITA", false)
	for i in 120:
		Pr.step_month(gs)
	_check(gs.tension_arms_base > base and Pr.parts(gs).arms < arms1, "after a war between them, a larger army kept for years becomes the norm and the part eases (%.1f)" % Pr.parts(gs).arms)
	army.units.clear()
	load("res://scripts/sim/military.gd").refresh_men(gs)
	_check(Pr.parts(gs).arms <= 0.001, "sent home, it gives no tension at all")
