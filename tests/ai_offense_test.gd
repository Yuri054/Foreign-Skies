extends SceneTree
## Headless test for the AI's offence: choosing and taking a target, waiting on bad odds,
## the supply limit, falling back, plans and aggression.
## Run: godot --headless --path . -s res://tests/ai_offense_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var clock: Node
var map: Node
var A
var Off
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
	map = root.get_node("MapData")
	A = load("res://scripts/ai/ai.gd")
	Off = load("res://scripts/ai/ai_offense.gd")
	Mil = load("res://scripts/sim/military.gd")
	UnitC = load("res://scripts/sim/unit.gd")

	_test_attack_weak_neighbour()
	_test_waits_on_bad_odds()
	_test_supply_limit()
	_test_fall_back()
	_test_no_path_no_attack()
	_test_aggression_and_plans()

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _fresh(keep_armies := false) -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	if not keep_armies:
		gs.armies.clear()
	for tag in gs.nations:
		gs.nations[tag].recruiting.clear()
	Mil.refresh_men(gs)
	gs.set_player("")


func _army(tag: String, province: int, infantry: int):
	var a = Mil.new_army(gs, tag, "Test army", province)
	for i in infantry:
		a.units.append(UnitC.new("infantry"))
	return a


## Six stacks of ten infantry (a merge cap keeps them apart).
func _big(tag: String, province: int) -> void:
	for i in 3:
		_army(tag, province, 10)


func _step(days: int) -> void:
	for i in days:
		clock.days_elapsed += 1
		A.step_day(gs)
		Mil.step_day(gs)


## A German border province and a Belgian one it touches.
func _pair() -> Array:
	for p: int in Mil.border_provinces(gs, "GER", "BEL"):
		for n: int in Mil.neighbors(p):
			if gs.province_controller[n] == "BEL":
				return [p, n]
	return []


func _moves_of(tag: String) -> int:
	var n := 0
	for c in gs.command_log:
		if c.type == "MoveArmy" and c.tag == tag:
			n += 1
	return n


func _test_attack_weak_neighbour() -> void:
	_fresh()
	gs.set_war("GER", "BEL", true)
	var pair := _pair()
	_check(pair.size() == 2, "Germany and Belgium touch")
	_big("GER", pair[0])
	_big("GER", pair[0])
	_army("BEL", gs.nations["BEL"].capital, 1)
	var before := 0
	for id: int in gs.nations["BEL"].provinces:
		if gs.province_controller[id] == "GER":
			before += 1
	_step(60)
	var held := 0
	for id: int in gs.nations["BEL"].provinces:
		if gs.province_controller[id] == "GER":
			held += 1
	_check(_moves_of("GER") > 0, "Germany ordered its armies forward")
	_check(held > before, "a big stack takes ground from a weak neighbour (%d provinces)" % held)
	_check(gs.fronts.values().any(func(f) -> bool: return f.tag == "GER"), "Germany also keeps a front")


func _test_waits_on_bad_odds() -> void:
	_fresh()
	gs.set_war("GER", "BEL", true)
	var pair := _pair()
	_army("GER", pair[0], 10)
	_army("GER", pair[0], 10)
	var dug = _army("BEL", pair[1], 20)
	dug.still_days = 60
	_step(30)
	_check(_moves_of("GER") == 0, "a stack does not attack an equal one that is dug in")
	_check(not gs.ai_campaign.has("GER"), "no campaign is started on bad odds")
	for a in Mil.armies_of(gs, "GER"):
		_check(a.province == pair[0], "the stack stays where it is")
		break


func _test_supply_limit() -> void:
	_fresh()
	gs.set_war("GER", "BEL", true)
	var pair := _pair()
	_big("GER", pair[0])
	_big("GER", pair[0])
	_army("BEL", gs.nations["BEL"].capital, 1)
	var unsupplied := 0
	for d in 150:
		_step(1)
		for a in Mil.armies_of(gs, "GER"):
			if not a.supplied:
				unsupplied += 1
	_check(unsupplied == 0, "an offence never walks past the edge of supply")


func _test_fall_back() -> void:
	_fresh()
	gs.set_war("GER", "BEL", true)
	var pair := _pair()
	var a = _army("GER", pair[1], 10)
	a.path.clear()
	gs.ai_campaign["GER"] = {"enemy": "BEL", "target": pair[1], "staging": pair[0], "armies": [a.id] as Array[int],
			"phase": "advance", "started": clock.days_elapsed}
	_army("BEL", pair[1], 40)
	Off.step(gs, "GER")
	_check(not gs.ai_campaign.has("GER"), "a stack facing a much bigger one ends its campaign")
	_check(not a.path.is_empty() and a.path[a.path.size() - 1] == pair[0], "and falls back to its staging province")


func _test_no_path_no_attack() -> void:
	_fresh(true)
	gs.set_war("GBR", "GER", true)
	_step(30)
	_check(not gs.ai_campaign.has("GBR") and _moves_of("GBR") == 0, "Britain cannot reach Germany by land and orders no attack")


func _test_aggression_and_plans() -> void:
	_fresh()
	gs.ai_traits["GER"] = {"aggression": 0.0, "caution": 0.5}
	gs.set_war("GER", "BEL", true)
	var pair := _pair()
	_big("GER", pair[0])
	_big("GER", pair[0])
	_step(12)
	_check(not gs.ai_campaign.has("GER"), "a nation with no aggression puts nothing on offence")

	_fresh()
	gs.ai_plans.append({"nation": "GER", "enemy": "BEL", "posture": "defensive", "objectives": []})
	gs.set_war("GER", "BEL", true)
	pair = _pair()
	_big("GER", pair[0])
	_big("GER", pair[0])
	_step(12)
	_check(not gs.ai_campaign.has("GER"), "a defensive plan keeps a nation from attacking that enemy")

	_fresh()
	var brussels: int = A.province_named("Brussels")
	gs.ai_plans.append({"nation": "GER", "enemy": "BEL", "posture": "offensive", "objectives": [{"province": brussels, "weight": 5.0}]})
	gs.set_war("GER", "BEL", true)
	_check(Off._plan_weight(gs, "GER", "BEL", brussels) == 5.0, "an objective carries its full weight")
	var far := 0
	for p: int in gs.nations["BEL"].provinces:
		if A.hops_from(brussels, 8).get(p, 99) > 6:
			far = p
	_check(far == 0 or Off._plan_weight(gs, "GER", "BEL", far) < 1.0, "weight falls away from the objective")
	pair = _pair()
	_big("GER", pair[0])
	_big("GER", pair[0])
	_step(6)
	_check(gs.ai_campaign.has("GER") or _moves_of("GER") > 0, "a plan against Belgium sets an offence going")
