extends SceneTree
## Headless test for the navy: data, starting fleets, upkeep, sailing, ports and shipbuilding.
## Run: godot --headless --path . -s res://tests/navy_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var map: Node
var Nav
var ShipC
var MoveC
var RaiseC
var MergeC
var SplitC
var MissionC


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _fleet(tag: String, fleet_name: String):
	for f in gs.fleets.values():
		if f.tag == tag and f.display_name == fleet_name:
			return f
	return null


func _zone(zone_name: String) -> int:
	for z in map.sea_zones:
		if z.get("name", "") == zone_name:
			return z.id
	return 0


func _days(n: int) -> void:
	for i in n:
		Nav.step_day(gs)


## Days with the economy too: the hulls draw their IC from the construction pool.
func _econ_days(n: int) -> void:
	var econ = load("res://scripts/sim/economy.gd")
	for i in n:
		econ.step_day(gs)
		Nav.step_day(gs)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	map = root.get_node("MapData")
	Nav = load("res://scripts/sim/navy.gd")
	ShipC = load("res://scripts/sim/ship.gd")
	MoveC = load("res://scripts/sim/move_fleet.gd")
	RaiseC = load("res://scripts/sim/raise_ships.gd")
	MergeC = load("res://scripts/sim/merge_fleets.gd")
	SplitC = load("res://scripts/sim/split_fleet.gd")
	MissionC = load("res://scripts/sim/set_fleet_mission.gd")

	_test_data()
	_test_upkeep()
	_test_sailing()
	_test_ports()
	_test_building()
	_test_fleet_orders()
	print("\n%s: %d failure(s)" % ["FAILED" if _failures > 0 else "PASSED", _failures])
	quit(1 if _failures > 0 else 0)


func _test_data() -> void:
	_check(Nav.type_ids().size() == 5, "five ship types")
	var bad := 0
	for t in Nav.type_ids():
		var d: Dictionary = Nav.cfg.types[t]
		for k in ["name", "attack", "speed", "range_days", "detection", "upkeep", "cost", "build_days", "min_port", "materials", "capacity"]:
			if not d.has(k):
				bad += 1
	_check(bad == 0, "every ship type has every field")
	var grand = _fleet("GBR", "Grand Fleet")
	_check(grand != null and grand.port == 330 and grand.count_of("dreadnought") == 4 and grand.count_of("cruiser") == 2, "the Grand Fleet lies at Orkney with 4 battle and 2 cruiser squadrons")
	var seas = _fleet("GER", "High Seas Fleet")
	_check(seas != null and seas.port == 394 and seas.count_of("submarine") == 2, "the High Seas Fleet lies at Wilhelmshaven")
	_check(Nav.port_level(gs, 330) == 3 and Nav.port_level(gs, 394) == 3, "a base that holds battle squadrons has a level 3 yard")
	_check(Nav.port_level(gs, 302) == 1, "a destroyer base has a level 1 yard")
	var count := 0
	var misplaced := 0
	for f in gs.fleets.values():
		count += f.ships.size()
		if f.ships.is_empty() or f.port == 0 or f.zone != 0:
			misplaced += 1
	_check(misplaced == 0, "every fleet starts in a port")
	_check(count > 100, "%d squadrons afloat at the start" % count)
	_check(grand.speed() == Nav.cfg.types.dreadnought.speed, "a fleet sails at its slowest ship's speed")
	_check(Nav.can_dock(gs, "GBR", 330) and not Nav.can_dock(gs, "GBR", 394), "a nation docks in its own ports and not a stranger's")
	_check(not Nav.can_dock(gs, "GBR", 1), "a province without a port cannot be docked in")


func _test_upkeep() -> void:
	var worst := 0.0
	var neg := 0
	for tag in gs.nations:
		var n = gs.nations[tag]
		var hist: float = gs.scenario.nations.get(tag, {}).get("naval_budget", 0.0)
		worst = maxf(worst, absf(n.naval_budget - hist))
		if n.naval_overhead < 0.0:
			neg += 1
	_check(worst < 0.001, "each nation's naval cost at the start equals its historical budget (off by %.4f)" % worst)
	_check(neg == 0, "no nation has negative overhead")
	var gbr = gs.nations["GBR"]
	_check(absf(Nav.ship_upkeep(gs, "GBR") + gbr.naval_overhead - gbr.naval_budget) < 0.001, "naval cost is overhead plus ship upkeep")
	_check(absf(gbr.budget.naval - gbr.naval_budget) < 0.001, "the budget carries the naval cost")
	var before: float = gbr.naval_budget
	var dover = _fleet("GBR", "Dover Patrol")
	dover.ships.append(ShipC.new("cruiser"))
	gs.issue(MissionC.new("GBR", dover.id, "patrol"))
	_check(absf(gbr.naval_budget - before - Nav.cfg.types.cruiser.upkeep) < 0.001, "a new ship raises the naval cost by its upkeep")
	dover.ships.pop_back()
	gs.issue(MissionC.new("GBR", dover.id, "station"))


func _test_sailing() -> void:
	var seas = _fleet("GER", "High Seas Fleet")
	var central := _zone("Central North Sea")
	var bight := _zone("German Bight")
	_check(map.sea_adjacency[bight].has(_zone("Southern North Sea")), "the German Bight opens on the Southern North Sea")
	var cmd = MoveC.new("GER", seas.id, central)
	_check(gs.issue(cmd), "Germany can send its fleet to the Central North Sea")
	_check(cmd.path.size() >= 2 and cmd.path[0] in map.zones_of_port(394) and cmd.path[-1] == central, "the route starts at the port's zone and ends in the target zone")
	_check(seas.is_in_port() and seas.is_moving(), "the fleet is still in port on the day of the order")
	var arrived := 0
	for d in 40:
		_days(1)
		if seas.zone == central and seas.path.is_empty():
			arrived = d + 1
			break
	_check(arrived > 0 and seas.port == 0, "the fleet reaches the Central North Sea (after %d days) and has left port" % arrived)
	_check(arrived >= cmd.path.size(), "it takes at least a day for each zone")
	_check(gs.issue(MoveC.new("GER", seas.id, _zone("Skagerrak"))), "a fleet at sea can be re-ordered")
	_days(20)
	_check(seas.zone == _zone("Skagerrak"), "and reaches the new zone")
	_check(gs.issue(MoveC.new("GER", seas.id, 0, 394)), "a fleet can be sent home to port")
	_days(40)
	_check(seas.port == 394 and seas.zone == 0 and not seas.is_moving(), "and docks in it")
	_check(not gs.issue(MoveC.new("GER", seas.id, 0, 330)), "Germany cannot enter a British port")
	_check(not gs.issue(MoveC.new("GBR", seas.id, central)), "a nation cannot order another's fleet")
	_check(not gs.issue(MoveC.new("GER", seas.id, 0)), "no destination is no order")
	_check(not gs.issue(MoveC.new("GER", seas.id, 999)), "an unknown zone is no destination")
	_check(gs.issue(MoveC.new("GER", seas.id, 0, 394)), "ordering a fleet to the port it is in is accepted")
	var far: Array = Nav.find_path(430.0, [_zone("Southern Baltic")], [_zone("Western Black Sea")])
	_check(far.size() > 10 and far[0] == _zone("Southern Baltic") and far[-1] == _zone("Western Black Sea"), "the Baltic reaches the Black Sea by sea (%d zones)" % far.size())
	_check(Nav.find_path(430.0, [central], [central]).size() == 1, "a path to where you are is one zone")
	var fast: float = Nav.zone_days(560.0, central, bight)
	var slow: float = Nav.zone_days(300.0, central, bight)
	_check(fast <= slow and fast >= 1.0, "faster ships need fewer days (%d against %d)" % [fast, slow])


func _test_ports() -> void:
	var grand = _fleet("GBR", "Grand Fleet")
	_check(gs.issue(MoveC.new("GBR", grand.id, 0, 294)), "the Grand Fleet can sail to Portsmouth")
	_days(60)
	_check(grand.port == 294, "and docks there")
	_check(Nav.fleets_in_port(gs, 294).has(grand) and Nav.fleets_in_zone(gs, _zone("Eastern Channel")).is_empty(), "it is counted in the port, not at sea")
	gs.issue(MoveC.new("GBR", grand.id, 0, 330))
	_days(60)
	_check(grand.port == 330, "and goes home again")


func _test_building() -> void:
	var n = gs.nations["GER"]
	n.treasury = 100.0
	_check(Nav.build_problem(gs, "GER", 394, "dreadnought", 1) == "", "Germany can build a battle squadron at Wilhelmshaven")
	var plan: Dictionary = Nav.ship_plan(gs, "GER", "dreadnought", 1)
	var treasury: float = n.treasury
	var iron: float = n.stock.iron
	_check(gs.issue(RaiseC.new("GER", 394, "dreadnought", 1)), "the order is accepted")
	_check(n.shipbuilding.size() == 1 and absf(treasury - n.treasury - plan.total) < 0.001 and plan.gold == 0.0, "it costs no gold, only imported materials (%.1fM)" % plan.total)
	_check(absf(n.shipbuilding[0].points_total - 10000.0) < 0.001, "the hull costs 10,000 IC")
	_check(absf(iron - n.stock.iron - plan.from_stock.iron) < 0.001, "materials come out of the stockpile")
	_check(Nav.build_problem(gs, "GER", 394, "dreadnought", 6) == "The yard is full", "a port builds only so many at once")
	var seas = _fleet("GER", "High Seas Fleet")
	var before: int = seas.ships.size()
	_econ_days(1)
	_check(n.shipbuilding.size() == 1 and n.shipbuilding[0].given > 0.0 and n.shipbuilding[0].points_left < 10000.0 and seas.ships.size() == before, "each day takes IC from the construction pool, nothing launches early")
	_check(n.construction_used > 0.0, "and the pool shows it in use")
	n.shipbuilding[0].points_left = n.shipbuilding[0].rate * 1.5
	_econ_days(1)
	_check(n.shipbuilding.size() == 1 and seas.ships.size() == before, "the last points are not yet in")
	_econ_days(1)
	_check(n.shipbuilding.is_empty() and seas.ships.size() == before + 1 and seas.ships[-1].type == "dreadnought", "the squadron joins the fleet in port")
	var c = gs.nations["GBR"]
	c.treasury = 100.0
	_check(Nav.build_problem(gs, "GBR", 302, "dreadnought", 1) == "Needs a level 3 port", "a level 1 port cannot build a battle squadron")
	_check(Nav.build_problem(gs, "GBR", 302, "destroyer", 1) == "", "but builds destroyers")
	_check(Nav.build_problem(gs, "GBR", 1, "destroyer", 1) != "", "no ships in a province that is not British")
	_check(Nav.build_problem(gs, "GBR", 330, "submarine", 0) != "", "a count of none is no order")
	_check(Nav.build_problem(gs, "XXX", 330, "destroyer", 1) != "", "an unknown nation builds nothing")
	var poor = gs.nations["DEN"]
	poor.treasury = 0.0
	poor.stock.iron = 0.0
	poor.stock.wood = 0.0
	_check(Nav.build_problem(gs, "DEN", 91, "cruiser", 1).begins_with("Not enough money") or Nav.build_problem(gs, "DEN", 91, "cruiser", 1) == "Needs a level 2 port", "no money for imported materials, no ships")
	_check(not gs.issue(RaiseC.new("DEN", 91, "cruiser", 1)), "and the order is refused")
	var g = gs.nations["FRA"]
	g.treasury = 100.0
	g.stock.iron = 0.0
	g.blockade = 0.8
	_check(Nav.build_problem(gs, "FRA", 247, "dreadnought", 1).begins_with("Blockade"), "a blockaded nation cannot buy the iron for a squadron")
	g.blockade = 0.0
	_check(Nav.build_problem(gs, "FRA", 247, "dreadnought", 1) == "", "but can once the blockade lifts (it buys at a markup)")
	n.treasury = 100.0
	gs.issue(RaiseC.new("GER", 394, "destroyer", 1))
	n.shipbuilding[0].points_left = 0.001
	gs.set_controller(394, "FRA")
	_econ_days(1)
	_check(n.shipbuilding.is_empty() and seas.ships.size() == before + 1, "a captured yard launches nothing")
	gs.set_controller(394, "GER")


func _test_fleet_orders() -> void:
	var grand = _fleet("GBR", "Grand Fleet")
	var total: int = grand.ships.size()
	var picked: Array[int] = SplitC.indices_of_type(grand, "cruiser", 2)
	var split = SplitC.new("GBR", grand.id, picked)
	_check(gs.issue(split), "a fleet can be split")
	var part = gs.fleets[split.new_fleet_id]
	_check(part.count_of("cruiser") == 2 and grand.ships.size() == total - 2 and part.port == grand.port, "the detachment holds the cruisers and stands in the same port")
	var all: Array[int] = []
	for i in grand.ships.size():
		all.append(i)
	_check(not gs.issue(SplitC.new("GBR", grand.id, all)), "a fleet cannot be split into nothing")
	var mixed: Array[int] = [grand.id, _fleet("GER", "High Seas Fleet").id]
	_check(not gs.issue(MergeC.new("GBR", mixed)), "fleets of two nations do not merge")
	var ids: Array[int] = [grand.id, part.id]
	_check(gs.issue(MergeC.new("GBR", ids)) and grand.ships.size() == total and not gs.fleets.has(part.id), "and merged again")
	_check(gs.issue(MissionC.new("GBR", grand.id, "blockade")) and grand.mission == "blockade", "a fleet takes a mission")
	_check(not gs.issue(MissionC.new("GBR", grand.id, "bogus")), "an unknown mission is refused")
	_check(gs.command_log[-1].type == "SetFleetMission", "orders are in the command log")

