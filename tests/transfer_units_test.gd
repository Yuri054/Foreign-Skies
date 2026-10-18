extends SceneTree
## Headless test of TransferUnits: divisions move between armies in one province, an emptied army
## is dissolved, and bad moves change nothing.
## Run: godot --headless --path . -s res://tests/transfer_units_test.gd

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
	var Mil = load("res://scripts/sim/military.gd")
	var UnitC = load("res://scripts/sim/unit.gd")
	var TransferC = load("res://scripts/sim/transfer_units.gd")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	var province := 0
	for a in gs.armies.values():
		if a.tag == "GER":
			province = a.province
			break
	var x = Mil.new_army(gs, "GER", "X", province)
	var y = Mil.new_army(gs, "GER", "Y", province)
	for i in 3:
		x.units.append(UnitC.new("infantry"))
	y.units.append(UnitC.new("cavalry"))
	var moved = x.units[1]
	var one: Array[int] = [1]
	_check(gs.issue(TransferC.new("GER", x.id, one, y.id)), "a division moves to another army in the province")
	_check(x.units.size() == 2 and y.units.size() == 2 and y.units.has(moved) and not x.units.has(moved), "it leaves one army and joins the other")

	_check(not gs.issue(TransferC.new("FRA", x.id, one, y.id)), "another nation cannot move them")
	_check(not gs.issue(TransferC.new("GER", x.id, one, x.id)), "an army cannot give units to itself")
	var bad: Array[int] = [5]
	_check(not gs.issue(TransferC.new("GER", x.id, bad, y.id)), "an index out of range is refused")
	var twice: Array[int] = [0, 0]
	_check(not gs.issue(TransferC.new("GER", x.id, twice, y.id)), "the same division twice is refused")
	var elsewhere = null
	for a in gs.armies.values():
		if a.tag == "GER" and a.province != province:
			elsewhere = a
			break
	_check(not gs.issue(TransferC.new("GER", x.id, one, elsewhere.id)) and x.units.size() == 2, "armies in different provinces cannot exchange units")
	_check(TransferC.block(gs, x, elsewhere) == "not in the same province", "and the reason is given")
	y.fighting = true
	_check(not gs.issue(TransferC.new("GER", x.id, one, y.id)), "an army in a battle takes no part")
	y.fighting = false

	# Moving every unit dissolves the army, frees its general and leaves its group.
	gs.player_tag = "GER"  # an AI nation would put the freed general in charge of another army at once
	var g = Mil.new_general(gs, "GER", "Test General", 1.0)
	Mil.set_general(gs, g, x)
	var grp = Mil.new_group(gs, "GER", "Test")
	Mil.put_in_group(gs, grp, [x.id, y.id] as Array[int])
	var all: Array[int] = [0, 1]
	_check(gs.issue(TransferC.new("GER", x.id, all, y.id)), "all of an army's units can be moved")
	_check(not gs.armies.has(x.id) and y.units.size() == 4, "the emptied army is dissolved")
	_check(g.army_id == 0 and not grp.army_ids.has(x.id), "its general is free and its group forgets it")

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
