extends SceneTree
## Headless test of exercises (the Train button): an army on exercise standing still drills its divisions to
## experience, which adds to their power; its men cost more upkeep; marching it does not drill; losses dilute it; and
## taking it off exercise stops both.
## Run: godot --headless --path . -s res://tests/training_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("Clock")
	var Mil = load("res://scripts/sim/military.gd")
	var Econ = load("res://scripts/sim/economy.gd")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("GER")
	gs.ai_enabled = false
	var berlin := 0
	for c in gs.cities:
		if c.name == "Berlin":
			berlin = c.province
	var army = Mil.new_army(gs, "GER", "Drill Army", berlin)
	for i in 6:
		army.units.append(load("res://scripts/sim/unit.gd").new("infantry"))
	var untrained: float = army.power()
	var n = gs.nations["GER"]
	Mil.refresh_men(gs)
	var upkeep_before: float = Econ.nation_budget(gs, n, gs.economy_sums["GER"], 1.0).army
	_check(gs.issue(load("res://scripts/sim/set_training.gd").new("GER", [army.id] as Array[int], true)) and army.training, "the army goes on exercise")
	_check(n.men_exercising >= roundi(army.men()) - 1, "its men count as exercising (%d)" % n.men_exercising)
	var upkeep_during: float = Econ.nation_budget(gs, n, gs.economy_sums["GER"], 1.0).army
	_check(upkeep_during > upkeep_before, "and cost more upkeep (%.2f against %.2f)" % [upkeep_during, upkeep_before])
	for d in 60:
		clock.advance_day()
	var drill: float = army.units[0].experience
	_check(drill > 0.45 and drill < 0.55, "two months of exercise give about half the drill (%.2f)" % drill)
	_check(army.power() > untrained * 1.08, "drill adds to its power (%.0f against %.0f)" % [army.power(), untrained])
	# Marching, it does not drill.
	var dest := 0
	for nb: int in Mil.neighbors(berlin):
		if gs.province_controller[nb] == "GER":
			dest = nb
	gs.issue(load("res://scripts/sim/move_army.gd").new("GER", army.id, dest))
	clock.advance_day()
	var marching: float = army.units[0].experience
	_check(not army.path.is_empty() and is_equal_approx(marching, drill), "an army on the march does not drill")
	# Losses dilute it.
	Mil._apply_casualties(army, army.men() * 0.5)
	_check(army.units[0].experience < marching * 0.8, "losing half its men dilutes the drill (%.2f to %.2f)" % [marching, army.units[0].experience])
	# Off exercise: no more drill, no more cost.
	gs.issue(load("res://scripts/sim/set_training.gd").new("GER", [army.id] as Array[int], false))
	var held: float = army.units[0].experience
	for d in 20:
		clock.advance_day()
	_check(not army.training and is_equal_approx(army.units[0].experience, held) and n.men_exercising == 0, "taken off exercise it keeps its drill but gains no more and costs no more")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
