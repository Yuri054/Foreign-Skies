extends SceneTree
## Headless test for the cabinet briefing and the "why" explanations: the issues a nation sees (worst
## first, each read from the state), the tension breakdown, and the explanations of the AI's
## intentions and peace urge, which are built from the same numbers the AI uses.
## Run: godot --headless --path . -s res://tests/briefing_test.gd

var _failures := 0
var gs: Node
var clock: Node
var B
var AD
var AP
var G


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _fresh(player := "GER") -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.set_player(player)
	gs.ai_enabled = false
	clock.advance_day()


func _ids(list: Array) -> Array:
	return list.map(func(i: Dictionary) -> String: return i.id)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	B = load("res://scripts/sim/briefing.gd")
	AD = load("res://scripts/ai/ai_diplomacy.gd")
	AP = load("res://scripts/ai/ai_peace.gd")
	G = load("res://scripts/sim/war_goal.gd")

	# --- Issues ----------------------------------------------------------------------------
	_fresh()
	var all: Array = B.issues(gs, "GER")
	var severities: Array = all.map(func(i: Dictionary) -> float: return i.severity)
	var sorted := severities.duplicate()
	sorted.sort()
	sorted.reverse()
	_check(severities == sorted, "the issues come worst first")
	_check(B.top(gs, "GER").size() <= 3, "the briefing shows at most three")
	for i: Dictionary in all:
		_check(i.title != "" and i.why != "" and i.page != "", "an issue has a title, a reason and a tab (%s)" % i.id)
		break

	var n = gs.nations["GER"]
	_check(not ("idle_money" in _ids(B.issues(gs, "GER"))), "a treasury of a few months' revenue is not idle")
	n.treasury = float(n.budget.income) * 24.0
	var idle: Array = B.issues(gs, "GER").filter(func(i: Dictionary) -> bool: return i.id == "idle_money")
	_check(idle.size() == 1 and idle[0].why.contains("divisions") and idle[0].why.contains("months of full mobilization"), "two years' revenue in peace is money lying idle, and it says what it buys: %s" % (idle[0].why if idle.size() > 0 else ""))
	n.treasury = -40.0
	clock.advance_day()
	n.treasury = -40.0
	var ids := _ids(B.issues(gs, "GER"))
	_check("debt" in ids and B.top(gs, "GER")[0].id == "debt", "a treasury in debt is the first thing to look at (%s)" % str(ids.slice(0, 3)))
	_check(B.top(gs, "GER")[0].page == "Economy", "and points to the Economy tab")
	n.treasury = 500.0

	# A war whose capital has fallen is worse than debt.
	n.treasury = -40.0
	gs.set_war("GER", "FRA", true, "none")
	gs.province_controller[n.capital] = "FRA"
	ids = _ids(B.issues(gs, "GER"))
	_check(B.top(gs, "GER")[0].id == "capital" and "occupied" in ids, "a fallen capital comes before debt, with the occupation listed (%s)" % str(ids.slice(0, 3)))
	gs.province_controller[n.capital] = "GER"
	n.war_support = 20.0
	_check("war_support" in _ids(B.issues(gs, "GER")), "low war support in a war is an issue")
	gs.wars.clear()
	n.war_support = 60.0
	n.treasury = 500.0

	# A demand made of the nation.
	gs.nations["FRA"].diplomacy_points = 200.0
	var C = load("res://scripts/sim/crisis.gd")
	var near := 0
	for id: int in gs.nations["GER"].provinces:
		if load("res://scripts/sim/peace.gd").province_problem(gs, "FRA", "GER", [id]) == "":
			near = id
			break
	var goal: Dictionary = G.provinces_goal([near])
	gs.issue(load("res://scripts/sim/press_demand.gd").new("FRA", "GER", "", {"demand": C.demand_for(goal), "goal": goal}))
	var made: Array = C.of(gs, "GER")
	var crisis_key := "crisis_%d" % (made[0].id if not made.is_empty() else -1)
	var case: Array = B.issues(gs, "GER").filter(func(i: Dictionary) -> bool: return i.id == crisis_key)
	_check(case.size() == 1 and case[0].page == "Diplomacy", "a demand made of the nation is an issue pointing to Diplomacy")
	_check(B.issues(gs, "FRA").filter(func(i: Dictionary) -> bool: return i.id == crisis_key).is_empty(), "and not an issue for the one making it")
	_check(gs.nations.has("GER") and B.issues(gs, "XXX").is_empty(), "an unknown nation has none")

	# Unspent points and no focus.
	_fresh()
	gs.nations["GER"].diplomacy_points = 100.0
	gs.nations["GER"].focus = {}
	ids = _ids(B.issues(gs, "GER"))
	_check("points" in ids, "a large stock of diplomacy points is mentioned")

	# --- Tension ---------------------------------------------------------------------------
	_fresh()
	var big: Dictionary = B.biggest_tension_part(gs)
	var parts: Dictionary = load("res://scripts/sim/pressure.gd").parts(gs)
	_check(big.value >= parts.arms - 0.001 and big.value >= parts.rivalry - 0.001 and big.value >= parts.wars - 0.001, "the biggest part of tension is the largest (%s %.1f)" % [big.name, big.value])
	var rivals: Array = B.rivalries(gs, 3)
	_check(rivals.size() <= 3 and (rivals.size() < 2 or rivals[0].hostility >= rivals[1].hostility), "the rivalries come worst first")

	# --- Explanations ----------------------------------------------------------------------
	_fresh()
	var check: Dictionary = AD.war_check(gs, "GER", "BEL")
	var option: Dictionary = AD.war_option(gs, "GER", "BEL")
	_check((check.reason == "") == (not option.is_empty()), "war_check and war_option agree (%s)" % check.reason)
	var text: String = AD.explain_declare(gs, "GER", "BEL")
	_check(text.contains("German Empire") and text.contains("Belgium"), "the intent line names both nations: %s" % text)
	_check(AD.explain_declare(gs, "GER", "AUH").contains("cannot attack"), "allies cannot attack each other: %s" % AD.explain_declare(gs, "GER", "AUH"))
	gs.set_war("GER", "FRA", true, "none")
	var war: War = gs.war_between("GER", "FRA")
	var up: Dictionary = AP.urge_parts(gs, "GER", war)
	_check(is_equal_approx(up.total, AP.urge(gs, "GER", war)), "the urge is the sum of its parts (%.1f)" % up.total)
	var sum := 0.0
	for key: String in ["score", "support", "debt", "duration", "quiet", "capital", "allies"]:
		sum += up[key]
	_check(absf(sum - up.total) < 0.0001, "and the parts add up")
	var why: String = AP.explain(gs, "GER", war)
	_check(why.contains("German Empire") and (why.contains("wants peace") or why.contains("will fight on")), "the peace line says where it stands: %s" % why)
	gs.nations["GER"].war_support = 5.0
	_check(AP.explain(gs, "GER", war).contains("war support is low"), "low war support is named as a push to peace: %s" % AP.explain(gs, "GER", war))

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
