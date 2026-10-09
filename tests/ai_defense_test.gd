extends SceneTree
## Headless test for the AI's defence: border fronts, assignment, reserve, rebalancing,
## merging, retaking home ground, and holding rather than marching out.
## Run: godot --headless --path . -s res://tests/ai_defense_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var clock: Node
var map: Node
var A
var Def
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
	Def = load("res://scripts/ai/ai_defense.gd")
	Mil = load("res://scripts/sim/military.gd")
	UnitC = load("res://scripts/sim/unit.gd")

	_test_fronts_and_assignment()
	_test_holds_the_line()
	_test_front_follows_ground()
	_test_rebalance()
	_test_reserve_and_merge()
	_test_retake()
	_test_no_cheating()

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


func _province(name: String, tag: String) -> int:
	for id in range(1, gs.province_owner.size()):
		if map.provinces[id].name == name and gs.province_owner[id] == tag:
			return id
	return 0


func _army(tag: String, province: int, infantry: int):
	var a = Mil.new_army(gs, tag, "Test army", province)
	for i in infantry:
		a.units.append(UnitC.new("infantry"))
	return a


## A province of `tag` that touches ground of `other` (the lowest id, so runs repeat).
func _border(tag: String, other: String) -> int:
	return Mil.border_provinces(gs, tag, other)[0]


func _step(days: int) -> void:
	for i in days:
		clock.days_elapsed += 1
		A.step_day(gs)
		Mil.step_day(gs)


func _fronts_of(tag: String) -> Array:
	return gs.fronts.values().filter(func(f) -> bool: return f.tag == tag)


func _test_fronts_and_assignment() -> void:
	_fresh()
	gs.set_war("GER", "BEL", true)
	var line: Array = Mil.border_provinces(gs, "BEL", "GER")
	_check(not line.is_empty(), "Belgium and Germany share a border")
	_army("BEL", line[0], 4)
	_army("BEL", gs.nations["BEL"].capital, 2)
	Def.step(gs, "BEL")
	var fronts := _fronts_of("BEL")
	_check(fronts.size() == 1 and fronts[0].against == "GER", "Belgium draws a border front against Germany")
	var assigned := 0
	for a in Mil.armies_of(gs, "BEL"):
		if a.front_id == fronts[0].id:
			assigned += 1
	_check(assigned == 2, "both armies go onto the front (%d)" % assigned)
	var log_size: int = gs.command_log.size()
	Def.step(gs, "BEL")
	_check(gs.command_log.size() == log_size, "a second turn with nothing changed gives no orders")

	# A second enemy that it touches gets a front of its own; peace removes the first.
	gs.set_war("FRA", "BEL", true)
	Def.step(gs, "BEL")
	_check(_fronts_of("BEL").size() == 2, "a second enemy gets a second front")
	gs.set_war("GER", "BEL", false)
	Def.step(gs, "BEL")
	var left := _fronts_of("BEL")
	_check(left.size() == 1 and left[0].against == "FRA", "the front against a former enemy is dropped")
	gs.set_war("FRA", "BEL", false)
	Def.step(gs, "BEL")
	_check(_fronts_of("BEL").is_empty(), "no fronts at peace")


func _test_holds_the_line() -> void:
	_fresh(true)
	# Serbia, outmatched, holds its ground rather than marching into Austria-Hungary.
	gs.set_war("AUH", "SRB", true)
	Def.step(gs, "SRB")
	_check(not Mil.armies_of(gs, "SRB").is_empty(), "Serbia has armies")
	var line = Mil.border_provinces(gs, "SRB", "AUH")
	for a in Mil.armies_of(gs, "SRB"):
		var into_enemy := false
		for step: int in a.path:
			into_enemy = into_enemy or gs.province_owner[step] == "AUH"
		_check(not into_enemy, "no Serbian army is ordered into Austria-Hungary")
	_step(40)
	var ventured := 0
	var dug_in := 0
	for a in Mil.armies_of(gs, "SRB"):
		if gs.province_owner[a.province] == "AUH":
			ventured += 1
		if a.entrenchment() > 0:
			dug_in += 1
	_check(ventured == 0, "no Serbian army marched into Austria-Hungary")
	_check(dug_in > 0, "Serbian armies dug in (%d)" % dug_in)
	_check(not line.is_empty(), "Serbia has a line to hold")


func _test_front_follows_ground() -> void:
	_fresh()
	gs.set_war("GER", "BEL", true)
	var line: Array = Mil.border_provinces(gs, "BEL", "GER")
	_army("BEL", line[0], 3)
	Def.step(gs, "BEL")
	var front = _fronts_of("BEL")[0]
	var lost: int = line[0]
	gs.set_controller(lost, "GER")
	Mil.step_fronts(gs)
	_check(lost not in front.provinces, "a province lost to the enemy leaves the line")
	_check(front.provinces == Mil.border_provinces(gs, "BEL", "GER"), "the front is re-read from who holds what")


func _test_rebalance() -> void:
	_fresh()
	gs.set_war("GER", "BEL", true)
	gs.set_war("FRA", "BEL", true)
	var ger_line: Array = Mil.border_provinces(gs, "BEL", "GER")
	var fra_line: Array = Mil.border_provinces(gs, "BEL", "FRA")
	# Four Belgian armies; a big French force masses at the French border, nothing near Germany.
	var spots: Array = [fra_line[0], ger_line[0], gs.nations["BEL"].capital]
	for s in spots:
		_army("BEL", s, 2)
	for n: int in Mil.neighbors(fra_line[0]):
		if gs.province_owner[n] == "FRA":
			_army("FRA", n, 20)
			break
	Def.step(gs, "BEL")
	var on := {}
	for f in _fronts_of("BEL"):
		on[f.against] = f.army_ids.size()
	# First turn assigns everyone greedily by need: the threatened front gets the lion's share.
	_check(on.get("FRA", 0) >= on.get("GER", 0) and on.get("GER", 0) >= 1, "the front facing the big army gets at least as many, and the other is not bare (%s)" % str(on))
	var armies_total := 0
	for k in on:
		armies_total += on[k]
	_check(armies_total + (1 if gs.ai_reserve.has("BEL") else 0) == 3, "every army is on a front or is the reserve")

	# Rebalance: put every army on the quiet front by hand, then let a few turns pass.
	var ger_front = null
	var fra_front = null
	for f in _fronts_of("BEL"):
		if f.against == "GER":
			ger_front = f
		else:
			fra_front = f
	var ids: Array[int] = []
	for a in Mil.armies_of(gs, "BEL"):
		ids.append(a.id)
	gs.issue_quiet(load("res://scripts/sim/assign_to_front.gd").new("BEL", ger_front.id, ids))
	for i in 4:
		for a in Mil.armies_of(gs, "BEL"):
			a.path.clear()
		Def.step(gs, "BEL")
	_check(fra_front.army_ids.size() > 0, "armies idle behind a quiet front move to the overrun one")


func _test_reserve_and_merge() -> void:
	_fresh()
	gs.set_war("GER", "BEL", true)
	var line: Array = Mil.border_provinces(gs, "BEL", "GER")
	var home: int = gs.nations["BEL"].capital
	var spare: int = 0
	for id: int in gs.nations["BEL"].provinces:
		if id != home and id != line[0] and spare == 0:
			spare = id
	_army("BEL", home, 6)
	_army("BEL", spare, 6)
	_army("BEL", line[0], 6)
	_army("BEL", gs.nations["BEL"].provinces[gs.nations["BEL"].provinces.size() - 1], 1)
	Def.step(gs, "BEL")
	_check(gs.ai_reserve.has("BEL"), "with enough armies a reserve is kept")
	var reserve = gs.armies.get(gs.ai_reserve["BEL"])
	_check(reserve != null and reserve.front_id == 0, "the reserve belongs to no front")
	_check(reserve.power() <= 0.2 * 19 * 12.0 + 0.001, "the reserve is small enough not to strip the line")
	# Two stacks in one province on one front are merged.
	var a1 = _army("BEL", line[0], 2)
	var a2 = _army("BEL", line[0], 2)
	var f = _fronts_of("BEL")[0]
	var ids: Array[int] = [a1.id, a2.id]
	gs.issue_quiet(load("res://scripts/sim/assign_to_front.gd").new("BEL", f.id, ids))
	var before: int = Mil.armies_of(gs, "BEL").size()
	Def.step(gs, "BEL")
	_check(Mil.armies_of(gs, "BEL").size() < before and not gs.armies.has(a2.id), "stacks standing together on one front are merged")


func _test_retake() -> void:
	_fresh()
	gs.set_war("AUH", "SRB", true)
	var line: Array = Mil.border_provinces(gs, "SRB", "AUH")
	var lost: int = line[0]
	gs.set_controller(lost, "AUH")
	# Army two steps back, none of the enemy about: take it back.
	var back := -1
	for n: int in Mil.neighbors(lost):
		if gs.province_controller[n] == "SRB":
			back = n
			break
	_check(back > 0, "the lost province has a Serbian neighbour")
	var a = _army("SRB", back, 3)
	Def.step(gs, "SRB")
	_check(not a.path.is_empty() and a.path[a.path.size() - 1] == lost, "an army is sent to retake a province nobody defends")
	_step(40)
	_check(gs.province_controller[lost] == "SRB", "the province is retaken")

	# A strong stack dug in there: nothing is sent.
	_fresh()
	gs.set_war("AUH", "SRB", true)
	lost = Mil.border_provinces(gs, "SRB", "AUH")[0]
	gs.set_controller(lost, "AUH")
	for n: int in Mil.neighbors(lost):
		if gs.province_controller[n] == "SRB":
			back = n
			break
	var small = _army("SRB", back, 2)
	var big = _army("AUH", lost, 12)
	big.still_days = 40
	Def.step(gs, "SRB")
	_check(small.path.is_empty(), "no attack is made on a much stronger, dug-in stack")
	# Reinforce past the odds: now it goes.
	_army("SRB", back, 80)
	Def.step(gs, "SRB")
	var moving := 0
	for s in Mil.armies_of(gs, "SRB"):
		if not s.path.is_empty() and s.path[s.path.size() - 1] == lost:
			moving += 1
	_check(moving > 0, "with the odds in its favour it attacks")


func _test_no_cheating() -> void:
	# Run the 1914 crisis for a while with the AI at the helm; no AI order breaks the rules.
	_fresh_scenario_with_war()
	var bad := 0
	for d in 60:
		clock.days_elapsed += 1
		A.step_day(gs)
		Mil.step_day(gs)
		for a in gs.armies.values():
			if not Mil.can_enter(gs, a.tag, a.province):
				bad += 1
	_check(bad == 0, "no army ever stands where its nation may not enter")


func _fresh_scenario_with_war() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("FRA")
