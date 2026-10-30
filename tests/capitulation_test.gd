extends SceneTree
## Headless test for capitulation (docs/REWORK.md R1): the capital's weight, moving the capital (AI and player), going
## home, capitulating at 80% or with no city left, the armies laying down their arms and the peace that follows.
## Run: godot --headless --path . -s res://tests/capitulation_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var clock: Node
var C
var P
var Mil
var MoveC
var RaiseC


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
	C = load("res://scripts/sim/capitulation.gd")
	P = load("res://scripts/sim/peace.gd")
	Mil = load("res://scripts/sim/military.gd")
	MoveC = load("res://scripts/sim/move_capital.gd")
	RaiseC = load("res://scripts/sim/raise_units.gd")

	_test_value()
	_test_ai_moves()
	_test_player_moves()
	_test_capitulate()
	_test_no_city()

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


## France and Germany at war, the player in neutral Spain.
func _war(player := "ESP") -> Object:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.scenario["war_plans"] = []
	gs.wars.clear()
	gs.set_player(player)
	gs.set_war("FRA", "GER", true)
	return gs.war_between("FRA", "GER")


## `by` takes the provinces of `owner`, from the least valuable up (the capital is the most valuable), until `owner`'s
## capitulation progress reaches `share`.
func _occupy_to(owner: String, by: String, share: float, spare_capital := false) -> void:
	var ids: Array = gs.nations[owner].provinces.duplicate()
	ids.sort_custom(func(a: int, b: int) -> bool: return P.province_value(gs, a) < P.province_value(gs, b))
	for id: int in ids:
		if C.progress(gs, owner) >= share:
			return
		if not (spare_capital and id == gs.nations[owner].capital):
			gs.set_controller(id, by)


func _test_value() -> void:
	_war()
	var whole: float = C.whole_value(gs, "FRA")
	_check(whole > 10.0, "France has a value (%.1f)" % whole)
	_check(is_equal_approx(C.value_of(gs, 233, "FRA") / whole, 0.33), "Paris with its bonus is a third of it")
	var city := 0.0
	var plain := 0.0
	for id: int in gs.nations["FRA"].provinces:
		if id != 233 and id in C.capital_candidates(gs, "FRA"):
			city = maxf(city, P.province_value(gs, id))
		elif id != 233:
			plain = maxf(plain, P.province_value(gs, id))
	_check(city > 0.0 and not C.capital_candidates(gs, "FRA").is_empty(), "France has cities to fall back on (best %.2f)" % city)
	gs.set_controller(233, "GER")
	_check(is_equal_approx(C.progress(gs, "FRA"), 0.33), "Germany holding Paris is a third of the way to France capitulating")
	_check(is_equal_approx(C.progress(gs, "FRA", "GER"), 0.33) and C.progress(gs, "FRA", "ITA") == 0.0, "measured per enemy too")
	gs.set_war("FRA", "GER", false)


func _test_ai_moves() -> void:
	var war = _war()
	var moved := []
	gs.capital_moved.connect(func(t: String, f: int, to: int) -> void: moved.append([t, f, to]))
	gs.set_controller(233, "GER")
	var best: int = C.capital_candidates(gs, "FRA")[0]
	C.step_day(gs)
	var n = gs.nations["FRA"]
	_check(n.capital == best and n.home_capital == 233 and C.relocated(gs, "FRA"), "France (AI) moves its government to %s" % root.get_node("MapData").provinces[best].name)
	_check(not n.capitulated and moved.size() == 1 and moved[0][1] == 233, "and fights on")
	_check(war.log.any(func(e: Dictionary) -> bool: return e.get("kind", "") == "capital"), "the move is in the war's log")
	var before: float = C.progress(gs, "FRA")
	_check(is_equal_approx(before, 0.33), "Paris still counts its whole bonus to the enemy")
	gs.set_controller(best, "GER")
	var after: float = C.progress(gs, "FRA")
	var bonus: float = C.capital_bonus(gs, "FRA") * 0.5 / C.whole_value(gs, "FRA")
	_check(after > before + bonus, "the new capital carries half the bonus (%.3f -> %.3f)" % [before, after])
	gs.set_controller(best, "FRA")
	gs.set_controller(233, "FRA")
	C.step_day(gs)
	_check(n.capital == 233 and not C.relocated(gs, "FRA"), "retaking Paris brings the government home")
	gs.set_war("FRA", "GER", false)


func _test_player_moves() -> void:
	_war("FRA")
	gs.set_controller(233, "GER")
	clock.paused = false
	var posted := []
	gs.capital_choice_posted.connect(func(c: Dictionary) -> void: posted.append(c))
	C.step_day(gs)
	var n = gs.nations["FRA"]
	_check(posted.size() == 1 and gs.capital_choice.get("tag", "") == "FRA", "the player is asked where to move")
	_check(clock.paused and gs.has_pending(), "time stops until the player chooses")
	_check(n.capital == 233, "nothing moves by itself")
	C.step_day(gs)
	_check(posted.size() == 1, "the question is asked once")
	var cands: Array = gs.capital_choice.candidates
	_check(not gs.issue(MoveC.new("FRA", 233)), "the fallen capital is no choice")
	var pick: int = cands[cands.size() - 1]
	_check(gs.issue(MoveC.new("FRA", pick)) and n.capital == pick, "the player moves the government to %s" % root.get_node("MapData").provinces[pick].name)
	_check(gs.capital_choice.is_empty(), "and the choice is closed")
	gs.set_war("FRA", "GER", false)


func _test_capitulate() -> void:
	var war = _war()
	var n = gs.nations["GER"]
	var armies: int = Mil.armies_of(gs, "GER").size()
	var men := 0.0
	for a in Mil.armies_of(gs, "GER"):
		men += a.men()
	var manpower: int = n.manpower
	var fallen := []
	gs.nation_capitulated.connect(func(t: String) -> void: fallen.append(t))
	_occupy_to("GER", "FRA", 0.79, true)
	C.step_day(gs)
	_check(not n.capitulated and C.progress(gs, "GER") > 0.6, "Germany, all but Berlin lost, fights on (%d%% held)" % roundi(C.progress(gs, "GER") * 100.0))
	_check(P.score_parts(gs, war, "FRA").capitulation == 0.0, "no capitulation in the score yet")
	_occupy_to("GER", "FRA", 0.8)
	var held: float = C.progress(gs, "GER")
	C.step_day(gs)
	_check(n.capitulated and fallen == ["GER"] and held >= 0.8, "at 80%% held Germany capitulates (%d%%)" % roundi(held * 100.0))
	_check(armies > 0 and Mil.armies_of(gs, "GER").is_empty(), "its %d armies lay down their arms" % armies)
	_check(n.manpower >= manpower + roundi(men) - 1, "their men go back to the reserve")
	_check(war.capitulated.has("GER"), "the war records it")
	_check(not gs.at_war("FRA", "GER"), "and France (AI) dictates its peace at once")
	_check(n.provinces.size() < 100 or gs.nations["FRA"].provinces.size() > 0, "the peace is made")
	C.step_day(gs)
	_check(not n.capitulated, "at peace the capitulation is over")

	# Against the player the victor's terms are imposed, and the capitulated player raises no armies.
	war = _war("GER")
	n = gs.nations["GER"]
	_occupy_to("GER", "FRA", 0.8)
	C.step_day(gs)
	_check(n.capitulated, "the player capitulates too")
	_check(not gs.at_war("FRA", "GER") and gs.pending_offers.is_empty(), "the AI's peace is imposed, not asked")
	gs.set_war("FRA", "GER", true)
	n.capitulated = true
	var home: int = n.provinces[0]
	for id: int in n.provinces:
		if gs.province_controller[id] == "GER":
			home = id
			break
	_check(RaiseC.problem(gs, "GER", home, "infantry", 1).contains("capitulated"), "a capitulated nation raises no armies")
	gs.set_war("FRA", "GER", false)

	# A player who beats an AI dictates the peace.
	war = _war("FRA")
	var asked := []
	gs.dictate_peace.connect(func(id: int) -> void: asked.append(id))
	_occupy_to("GER", "FRA", 0.8)
	C.step_day(gs)
	_check(gs.nations["GER"].capitulated and asked == [war.id] and gs.at_war("FRA", "GER"), "the player is handed the peace to dictate")
	_check(P.score_parts(gs, war, "FRA").capitulation == 25.0, "the capitulation adds 25 to the player's score")
	_check(P.is_forced(gs, "FRA", "GER"), "and the beaten nation must take the terms")
	gs.set_war("FRA", "GER", false)


## A nation with nowhere left to move to (one province) capitulates when its capital falls; one with only towns moves to
## its best town.
func _test_no_city() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.scenario["war_plans"] = []
	gs.wars.clear()
	gs.set_player("ESP")
	var tag := ""
	var enemy := ""
	for t: String in gs.nations:
		var n = gs.nations[t]
		if n.provinces.size() != 1 or n.capital <= 0 or t == "ESP":
			continue
		for id: int in n.provinces:
			for nb: int in Mil.neighbors(id):
				var o: String = gs.province_owner[nb]
				if o != "" and o != t and o != "ESP" and gs.nations.has(o) and not gs.nations[o].provinces.is_empty():
					enemy = o
			if enemy != "":
				break
		if enemy != "":
			tag = t
			break
	_check(tag != "", "found a nation of one province (%s, against %s)" % [tag, enemy])
	if tag == "":
		return
	gs.set_war(tag, enemy, true)
	gs.set_controller(gs.nations[tag].capital, enemy)
	C.step_day(gs)
	_check(gs.nations[tag].capitulated or not gs.at_war(tag, enemy), "%s, with nowhere to move to, capitulates" % gs.nations[tag].display_name)
	if gs.at_war(tag, enemy):
		gs.set_war(tag, enemy, false)

	gs.set_war("SRB", "AUH", true)
	var belgrade: int = gs.nations["SRB"].capital
	gs.set_controller(belgrade, "AUH")
	C.step_day(gs)
	var srb = gs.nations["SRB"]
	_check(not srb.capitulated and srb.capital != belgrade and srb.capital > 0, "Serbia, with no other city, moves to its best town (%s)" % root.get_node("MapData").provinces[srb.capital].name)
	gs.set_war("SRB", "AUH", false)
