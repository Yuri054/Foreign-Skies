extends SceneTree
## Headless test of plans of attack (docs/FRONTLINES.md, stage F5): planning built up on the front and what it adds to an
## attack, the aggressiveness rules, a broad push taking its target line and turning to the next phase, and a spearhead
## striking one province after another toward its target.
## Run: godot --headless --path . -s res://tests/offensive_test.gd

var _failures := 0
var gs: Node
var clock: Node
var FS
var Mil
var Off


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _days(n: int) -> void:
	for i in n:
		clock.advance_day()


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	FS = load("res://scripts/sim/front_solver.gd")
	Mil = load("res://scripts/sim/military.gd")
	Off = load("res://scripts/sim/offensives.gd")
	_test_rules()
	_test_push()
	_test_spearhead()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


## Germany at war with Russia alone, the AI off; a German army of `divisions` on a front facing Russia. Returns
## [front, army].
func _setup(divisions: int) -> Array:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("GER")
	gs.ai_enabled = false
	for w in gs.wars.values().duplicate():
		gs.set_war(w.a, w.b, false)
	gs.pending_joins.clear()
	gs.set_war("GER", "RUS", true)
	gs.pending_joins.clear()
	var make = load("res://scripts/sim/designate_front.gd").new("GER", "East", [] as Array[int], "RUS")
	gs.issue(make)
	var front = gs.fronts[make.front_id]
	var line: Array[int] = FS.order_line(front.provinces)
	var army = Mil.new_army(gs, "GER", "Strike Army", line[line.size() / 2])
	var UnitC = load("res://scripts/sim/unit.gd")
	for i in divisions:
		army.units.append(UnitC.new("infantry" if i % 4 != 3 else "artillery"))
	gs.issue(load("res://scripts/sim/assign_to_front.gd").new("GER", front.id, [army.id] as Array[int]))
	return [front, army]


## Russian provinces `depth` steps from the German border (the ring that far in).
func _ring(depth: int) -> Array[int]:
	var seen := {}
	var ring: Array[int] = []
	for id in range(1, gs.province_controller.size()):
		if gs.province_controller[id] == "GER":
			for n: int in Mil.neighbors(id):
				if gs.province_controller[n] == "RUS" and not seen.has(n):
					seen[n] = true
					ring.append(n)
	for d in depth - 1:
		var next: Array[int] = []
		for p in ring:
			for n: int in Mil.neighbors(p):
				if gs.province_controller[n] == "RUS" and not seen.has(n):
					seen[n] = true
					next.append(n)
		ring = next
	return ring


func _test_rules() -> void:
	var setup := _setup(16)
	var army = setup[1]
	var o = load("res://scripts/sim/offensive.gd").new()
	o.aggressiveness = "careful"
	_check(not Off.may_attack(o, 1.5, 0.9) and Off.may_attack(o, 2.5, 0.9), "careful attacks only at good odds (2 to 1)")
	_check(not Off.may_attack(o, 3.0, 0.5), "and not once morale is low")
	o.aggressiveness = "aggressive"
	_check(Off.may_attack(o, 0.9, 0.05), "aggressive attacks at even odds, whatever its morale")
	_days(30)
	var target: Array[int] = _ring(2)
	var plan = load("res://scripts/sim/plan_offensive.gd").new("GER", army.id, "broad", target, "balanced")
	_check(gs.issue(plan), "a plan to push to a line two provinces in is made")
	_check(not gs.issue(load("res://scripts/sim/plan_offensive.gd").new("GER", army.id, "spearhead", target, "balanced")), "a spearhead must aim at one province")
	_days(14)
	_check(Off.planning_of(gs, army) > 0.8, "standing on the front with a plan, the army plans (%.2f)" % Off.planning_of(gs, army))
	var stack = FS.stacks_of(gs, army)[0]
	var standing: float = stack.power()
	_check(Off.attack_power(stack) > standing * 1.2, "planning adds to the power of an attack (%.0f against %.0f)" % [Off.attack_power(stack), standing])
	gs.issue(load("res://scripts/sim/set_offensive.gd").new("GER", plan.offensive_id, "cancel"))
	_days(10)
	_check(Off.planning_of(gs, army) < 0.1, "with the plan cancelled, planning fades (%.2f)" % Off.planning_of(gs, army))


func _test_push() -> void:
	var setup := _setup(48)
	var army = setup[1]
	_days(30)
	var first: Array[int] = _ring(1)
	var second: Array[int] = _ring(2)
	var plan = load("res://scripts/sim/plan_offensive.gd").new("GER", army.id, "broad", first, "aggressive")
	gs.issue(plan)
	_check(gs.issue(load("res://scripts/sim/set_offensive.gd").new("GER", plan.offensive_id, "phase", second)), "a second phase line is added")
	gs.issue(load("res://scripts/sim/set_offensive.gd").new("GER", plan.offensive_id, "launch", true))
	var o = gs.offensives[plan.offensive_id]
	var taken_first := 0
	var reached_second := false
	for d in 150:
		_days(1)
		if o.phase >= 1 and not reached_second:
			reached_second = true
	for p in first:
		if gs.province_controller[p] == "GER":
			taken_first += 1
	_check(taken_first >= first.size() / 2, "the push takes ground on its target line (%d of %d)" % [taken_first, first.size()])
	# A short first line, quickly taken: the plan turns to its second line and plans for it again.
	setup = _setup(48)
	army = setup[1]
	_days(30)
	var centre: Vector2 = root.get_node("MapData").provinces[army.province].center
	var near: Array[int] = _ring(1)
	near.sort_custom(func(a: int, b: int) -> bool: return (root.get_node("MapData").provinces[a].center as Vector2).distance_to(centre) < (root.get_node("MapData").provinces[b].center as Vector2).distance_to(centre))
	var line_a: Array[int] = near.slice(0, 2)
	var plan2 = load("res://scripts/sim/plan_offensive.gd").new("GER", army.id, "broad", line_a, "aggressive")
	gs.issue(plan2)
	gs.issue(load("res://scripts/sim/set_offensive.gd").new("GER", plan2.offensive_id, "phase", _ring(2)))
	gs.issue(load("res://scripts/sim/set_offensive.gd").new("GER", plan2.offensive_id, "launch", true))
	var o2 = gs.offensives[plan2.offensive_id]
	var turned_day := -1
	var planning_at_turn := 1.0
	for d in 120:
		_days(1)
		if o2.phase >= 1:
			turned_day = d
			planning_at_turn = Off.planning_of(gs, army)
			break
	_check(turned_day >= 0, "once line A (%s) is taken the plan turns to line B (day %d)" % [", ".join(line_a.map(func(p: int) -> String: return root.get_node("MapData").provinces[p].name)), turned_day])
	_check(turned_day >= 0 and planning_at_turn < 0.1, "and the planning for line B starts afresh (%.2f; an aggressive plan pushes on at once)" % planning_at_turn)


func _test_spearhead() -> void:
	var setup := _setup(40)
	var army = setup[1]
	_days(30)
	var warsaw := 0
	for c in gs.cities:
		if c.name == "Warsaw":
			warsaw = c.province
	var plan = load("res://scripts/sim/plan_offensive.gd").new("GER", army.id, "spearhead", [warsaw] as Array[int], "aggressive")
	_check(gs.issue(plan), "a spearhead is aimed at Warsaw")
	gs.issue(load("res://scripts/sim/set_offensive.gd").new("GER", plan.offensive_id, "launch", true))
	var first_objective: int = Off.next_objective(gs, "GER", warsaw)
	_check(first_objective > 0 and gs.province_controller[first_objective] == "RUS", "its first objective is the Russian province on the way nearest to Warsaw")
	var start: float = (root.get_node("MapData").provinces[first_objective].center as Vector2).distance_to(root.get_node("MapData").provinces[warsaw].center)
	_days(120)
	var nearest := INF
	for id in range(1, gs.province_controller.size()):
		if gs.province_controller[id] == "GER":
			nearest = minf(nearest, (root.get_node("MapData").provinces[id].center as Vector2).distance_to(root.get_node("MapData").provinces[warsaw].center))
	_check(gs.province_controller[first_objective] == "GER", "the spearhead takes its first objective (%s)" % root.get_node("MapData").provinces[first_objective].name)
	_check(gs.province_controller[warsaw] == "GER" or nearest < start or start == 0.0, "and gets nearer to Warsaw (nearest held %.0f px from it)" % nearest)
