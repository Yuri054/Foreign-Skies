extends SceneTree
## Headless test for cavalry's role (step 6 of PLAN.md): it takes contested ground in a fraction of the time, and it
## harries a beaten army as it falls back.
## Run: godot --headless --path . -s res://tests/cavalry_test.gd

var _failures := 0
var gs: Node
var Mil
var UnitC


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _army(tag: String, province: int, kinds: Array):
	var a = Mil.new_army(gs, tag, "Test", province)
	for k: String in kinds:
		a.units.append(UnitC.new(k))
	return a


## A French province beside Germany.
func _border() -> int:
	for id: int in gs.nations["FRA"].provinces:
		for n: int in Mil.neighbors(id):
			if gs.province_owner[n] == "GER":
				return id
	return 0


## Days for Germany to take `id` just after a battle there, with the given units.
func _days_to_take(id: int, kinds: Array) -> int:
	gs.load_scenario("res://data/scenarios/jan_1900/")
	gs.ai_enabled = false
	gs.set_player("ESP")
	gs.armies.clear()
	gs.set_war("GER", "FRA", true)
	_army("GER", id, kinds)
	gs.last_battle_day[id] = root.get_node("Clock").days_elapsed
	for d in 30:
		Mil._upkeep_and_occupy(gs)
		if gs.province_controller[id] == "GER":
			return d + 1
	return 99


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	Mil = load("res://scripts/sim/military.gd")
	UnitC = load("res://scripts/sim/unit.gd")
	gs.load_scenario("res://data/scenarios/jan_1900/")
	var id := _border()
	var foot := _days_to_take(id, ["infantry", "infantry"])
	var horse := _days_to_take(id, ["infantry", "cavalry"])
	_check(foot > 1 and horse < foot and horse >= 1, "after a battle, infantry takes the ground in %d days, with cavalry in %d" % [foot, horse])

	# The pursuit.
	gs.load_scenario("res://data/scenarios/jan_1900/")
	gs.armies.clear()
	gs.set_war("GER", "FRA", true)
	var beaten = _army("FRA", id, ["infantry", "infantry"])
	var foot_army = _army("GER", id, ["infantry", "infantry", "infantry"])
	var at := {id: [beaten, foot_army]}
	var plain: float = Mil.pursuit(gs, beaten, at)
	var horse_army = _army("GER", id, ["cavalry", "cavalry", "cavalry", "cavalry", "cavalry", "cavalry"])
	at = {id: [beaten, foot_army, horse_army]}
	var chased: float = Mil.pursuit(gs, beaten, at)
	_check(plain == 0.0 and chased > 0.0 and chased <= float(Mil.cfg.combat.pursuit_max), "a beaten army loses more as it falls back before cavalry (%.0f%% more)" % (chased * 100.0))
	var men: float = beaten.men()
	Mil._retreat(gs, beaten, at)
	_check(beaten.men() < men * (1.0 - float(Mil.cfg.combat.routed_loss)) + 1.0, "and the retreat takes it (%dk of %dk left)" % [roundi(beaten.men() / 1000.0), roundi(men / 1000.0)])
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
