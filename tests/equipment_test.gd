extends SceneTree
## Headless test of equipment: starting units are fully equipped, missing equipment weakens a
## unit down to a floor, casualties destroy it with the men, units draw what they lack from the
## national stockpile, trained units are issued what is in store, military factories fill the
## stockpile, and units and stockpile survive a save.
## Run: godot --headless --path . -s res://tests/equipment_test.gd

var _failures := 0
var gs: Node
var Clock: Node
var UnitC
var ArmyC
var Mil
var Raise


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	Clock = root.get_node("Clock")
	UnitC = load("res://scripts/sim/unit.gd")
	ArmyC = load("res://scripts/sim/army.gd")
	Mil = load("res://scripts/sim/military.gd")
	Raise = load("res://scripts/sim/raise_units.gd")
	_fresh()
	_test_start()
	_test_power()
	_test_casualties()
	_test_issue()
	_test_training()
	_test_raise()
	_test_reinforce()
	_test_production()
	_test_save()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.ai_enabled = false


func _first_army(tag: String) -> Object:
	for a in gs.armies.values():
		if a.tag == tag and a.units.size() > 0:
			return a
	return null


func _test_start() -> void:
	var a = _first_army("GER")
	var covered := true
	for u in a.units:
		covered = covered and is_equal_approx(u.coverage_min(), 1.0)
	_check(covered, "the starting units are fully equipped")
	var ger = gs.nations["GER"]
	_check(ger.equipment.arms > 0.0 and ger.equipment.artillery > 0.0, "Germany starts with equipment in store (%s)" % str(ger.equipment))
	_check(gs.nations["GER"].equipment.arms > gs.nations["BEL"].equipment.arms, "a nation with more military factories holds more")


func _test_power() -> void:
	var u = UnitC.new("infantry")
	var full = u.power()
	u.equip["arms"] = 6.0
	u.refresh_factor()
	_check(is_equal_approx(u.coverage("arms"), 0.5), "half the arms is half coverage")
	_check(u.power() < full and u.power() > full * Mil.cfg.equipment.categories.arms.floor, "and weakens the unit, but not to the floor")
	u.equip["arms"] = 0.0
	u.refresh_factor()
	_check(is_equal_approx(u.power(), full * Mil.cfg.equipment.categories.arms.floor), "with none it is down to the floor")
	var g = UnitC.new("artillery")
	g.equip["artillery"] = 0.0
	g.refresh_factor()
	_check(g.power() < UnitC.new("artillery").power(), "artillery without guns is weak")


func _test_casualties() -> void:
	var a = ArmyC.new()
	a.units.append(UnitC.new("infantry"))
	var arms_before: float = a.units[0].equip.arms
	Mil._apply_casualties(a, a.men() * 0.25)
	_check(is_equal_approx(a.units[0].equip.arms, arms_before * 0.75), "casualties destroy equipment with the men")
	_check(is_equal_approx(a.units[0].coverage("arms"), 1.0), "and coverage is unchanged")


func _test_issue() -> void:
	_fresh()
	var a = _first_army("GER")
	var n = gs.nations["GER"]
	var u = a.units[0]
	u.equip["arms"] = 0.0
	a.supplied = true
	a.fighting = false
	n.equipment.arms = 1000.0
	Mil._issue(gs)
	var drawn: float = u.equip.arms
	_check(drawn > 0.0 and drawn <= u.needs().arms * Mil.cfg.equipment.resupply_rate + 0.0001, "a unit draws at most the resupply rate a day (%.2f)" % drawn)
	_check(is_equal_approx(n.equipment.arms, 1000.0 - drawn), "and the stockpile pays for it")
	n.equipment.arms = 0.0
	u.equip["arms"] = 0.0
	Mil._issue(gs)
	_check(u.equip.arms == 0.0, "with an empty stockpile nothing arrives")
	a.fighting = true
	u.equip["arms"] = 12.0
	Mil._issue(gs)
	_check(u.equip.arms < 12.0, "fighting uses up arms")


func _test_training() -> void:
	_fresh()
	var n = gs.nations["GER"]
	var province := 0
	for id in n.provinces:
		province = id
		break
	n.equipment.arms = 5.0
	n.recruiting.append({"type": "infantry", "province": province, "days_left": 1})
	var before := 0
	for a in gs.armies.values():
		before += a.units.size() if a.tag == "GER" else 0
	Mil._train(gs)
	var after := 0
	var fresh = null
	for a in gs.armies.values():
		if a.tag == "GER":
			after += a.units.size()
			for u in a.units:
				if is_equal_approx(u.equip.get("arms", 0.0), 5.0) and u.strength == 1.0:
					fresh = u
	_check(fresh != null and after == before + 1, "the trained unit arrives")
	if fresh != null:
		_check(fresh.equip.arms < fresh.needs().arms, "with only what the store could give (%.1f of %d)" % [fresh.equip.arms, fresh.needs().arms])


func _test_raise() -> void:
	_fresh()
	var n = gs.nations["GER"]
	var province := 0
	for id in n.provinces:
		province = id
		break
	n.manpower = 100000
	n.treasury = 1000.0
	n.equipment.arms = 20.0
	_check(gs.issue(Raise.new("GER", province, "infantry", 2)), "two divisions can be raised")
	_check(is_equal_approx(n.equipment.arms, 0.0) or n.equipment.arms < 20.0, "the order takes their equipment from the store at once (%.1f left)" % n.equipment.arms)
	var job = n.recruiting[0]
	var second = n.recruiting[1]
	_check(is_equal_approx(job.equip.arms, 12.0) and is_equal_approx(second.equip.arms, 8.0), "the first gets its full 12, the second what was left (%.1f)" % second.equip.arms)
	n.equipment.arms = 0.0
	n.recruiting.clear()
	n.recruiting.append(job)
	job.days_left = 1
	var before := 0
	for a in gs.armies.values():
		before += a.units.size() if a.tag == "GER" else 0
	Mil._train(gs)
	var after := 0
	for a in gs.armies.values():
		if a.tag == "GER":
			after += a.units.size()
	_check(after == before + 1 and n.equipment.arms == 0.0, "the unit arrives, with nothing more taken from an empty store")


func _test_reinforce() -> void:
	_fresh()
	var a = _first_army("GER")
	var n = gs.nations["GER"]
	var u = a.units[0]
	u.strength = 0.5
	u.equip["arms"] = u.needs().arms * 0.25
	u.refresh_factor()
	n.manpower = 100000
	a.fighting = false
	a.supplied = true
	n.equipment.arms = 0.0
	var other = UnitC.new("infantry", 0.5)
	a.units.append(other)
	Mil._upkeep_and_occupy(gs)
	var slow = u.strength - 0.5
	var fast = other.strength - 0.5
	_check(is_equal_approx(fast, Mil.cfg.supply.reinforce_rate), "a fully equipped unit reinforces at the usual rate (%.4f)" % fast)
	_check(slow > 0.0 and slow < fast, "a unit missing equipment reinforces more slowly (%.4f)" % slow)


func _test_production() -> void:
	_fresh()
	var n = gs.nations["GER"]
	var before: float = n.equipment.arms
	for i in 10:
		Clock.advance_day()
	var made: float = n.equipment.arms - before
	var expected: float = (n.budget.military_factories + Mil.cfg.equipment.base_factories) * Mil.cfg.equipment.categories.arms.output * 10.0
	_check(made > 0.0 and made <= expected + 0.001, "military factories add to the stockpile (%.1f in ten days, at most %.1f)" % [made, expected])


func _test_save() -> void:
	var SaveGame = load("res://scripts/sim/save_game.gd")
	SaveGame.dir = "user://test_equipment_saves/"
	_fresh()
	var a = _first_army("GER")
	a.units[0].equip["arms"] = 3.5
	gs.nations["GER"].equipment.arms = 77.0
	var id = a.id
	var path: String = SaveGame.dir + "equipment.sav"
	_check(gs.save_game(path) == "", "a game with equipment saves")
	_fresh()
	_check(gs.load_game(path) == "", "and loads")
	_check(is_equal_approx(gs.armies[id].units[0].equip.arms, 3.5), "a unit's equipment is as saved")
	_check(is_equal_approx(gs.nations["GER"].equipment.arms, 77.0), "and so is the stockpile")
	DirAccess.remove_absolute(path)
