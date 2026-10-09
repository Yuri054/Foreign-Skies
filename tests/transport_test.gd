extends SceneTree
## Headless test for moving armies by sea: embarking, convoys and landings, losses when
## transports sink, short sea crossings, and supply through ports.
## Run: godot --headless --path . -s res://tests/transport_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

const PORTSMOUTH := 294
const CALAIS := 234  # Pas-de-Calais, French, on the Eastern Channel (a strait away from Kent)
const CALVADOS := 177  # French, on the Eastern Channel, with no British ground near
const BELFAST := 258

var _failures := 0
var gs: Node
var map: Node
var clock: Node
var Nav
var Mil
var Block
var ShipC
var UnitC
var EmbarkC
var DisembarkC
var SendC
var MoveArmyC


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _zone(zone_name: String) -> int:
	for z in map.sea_zones:
		if z.get("name", "") == zone_name:
			return z.id
	return 0


func _reset() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.fleets.clear()
	gs.armies.clear()
	gs.ai_enabled = false


func _convoy(tag: String, port: int, transports: int, escorts := 0):
	var f = Nav.new_fleet(gs, tag, "%s convoy" % tag, port)
	for i in transports:
		f.ships.append(ShipC.new("transport"))
	for i in escorts:
		f.ships.append(ShipC.new("cruiser"))
	return f


func _army(tag: String, province: int, divisions: int):
	var a = Mil.new_army(gs, tag, "Test army", province)
	for i in divisions:
		a.units.append(UnitC.new("infantry"))
	return a


func _days(n: int) -> void:
	for i in n:
		clock.days_elapsed += 1
		Nav.step_day(gs)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	map = root.get_node("MapData")
	clock = root.get_node("Clock")
	Nav = load("res://scripts/sim/navy.gd")
	Mil = load("res://scripts/sim/military.gd")
	Block = load("res://scripts/sim/blockade.gd")
	ShipC = load("res://scripts/sim/ship.gd")
	UnitC = load("res://scripts/sim/unit.gd")
	EmbarkC = load("res://scripts/sim/embark_army.gd")
	DisembarkC = load("res://scripts/sim/disembark_army.gd")
	SendC = load("res://scripts/sim/send_overseas.gd")
	MoveArmyC = load("res://scripts/sim/move_army.gd")

	_test_embark()
	_test_crossing()
	_test_sinking()
	_test_ferries()
	_test_supply()
	print("\n%s: %d failure(s)" % ["FAILED" if _failures > 0 else "PASSED", _failures])
	quit(1 if _failures > 0 else 0)


func _test_embark() -> void:
	_reset()
	var f = _convoy("GBR", PORTSMOUTH, 3)
	_check(f.capacity() == 120000, "three transport squadrons carry 120000 men")
	var small = _army("GBR", PORTSMOUTH, 3)
	var big = _army("GBR", PORTSMOUTH, 11)
	var elsewhere = _army("GBR", 302, 2)
	_check(Nav.embark_problem(gs, "GBR", big, f) == "Not enough transports", "an army too big for the ships cannot board")
	_check(Nav.embark_problem(gs, "GBR", elsewhere, f) != "", "an army in another port cannot board")
	_check(gs.issue(EmbarkC.new("GBR", small.id, f.id)), "an army in the fleet's port boards")
	_check(small.embarked() and Nav.armies_aboard(gs, f) == [small], "it is aboard")
	_check(Nav.free_capacity(gs, f) == 120000 - small.men(), "and takes its share of the capacity")
	_check(not gs.issue(MoveArmyC.new("GBR", small.id, 302)), "an embarked army cannot be ordered about on land")
	_check(not (small in Mil.armies_at(gs, PORTSMOUTH)), "it no longer counts as standing in the port")
	_check(not gs.issue(EmbarkC.new("GBR", small.id, f.id)), "it cannot board twice")
	_check(gs.issue(DisembarkC.new("GBR", small.id, PORTSMOUTH)) and not small.embarked() and small.province == PORTSMOUTH, "an army can go ashore in the port it sailed from")
	_check(small.landing_days == 0, "with no landing penalty")


func _test_crossing() -> void:
	_reset()
	gs.set_war("GBR", "FRA", true)
	var f = _convoy("GBR", PORTSMOUTH, 3)
	var a = _army("GBR", PORTSMOUTH, 3)
	var ids: Array[int] = [a.id]
	_check(SendC.problem(gs, "GBR", f.id, ids, CALAIS) == "", "Britain can send an army to Pas-de-Calais")
	var neutral := 90  # West Flanders, Belgian and neutral
	_check(SendC.problem(gs, "GBR", f.id, ids, neutral) == "You may not land there.", "but not onto a neutral coast")
	_check(SendC.problem(gs, "GBR", f.id, ids, 1) != "", "nor an inland province")
	_check(SendC.problem(gs, "GBR", f.id, [] as Array[int], CALAIS) != "", "an order with no army is nothing")
	var cmd = SendC.new("GBR", f.id, ids, CALAIS)
	_check(gs.issue(cmd), "the order is accepted")
	_check(a.embarked() and f.landing == CALAIS and f.is_moving(), "the army is aboard and the fleet sails")
	_check(cmd.path.size() >= 1 and cmd.path[-1] in map.zones_of_port(CALAIS), "the route ends where the coast opens")
	var landed := 0
	for d in 20:
		_days(1)
		if not a.embarked():
			landed = d + 1
			break
	_check(landed > 0 and a.province == CALAIS, "the army lands at Pas-de-Calais (after %d days)" % landed)
	_check(a.landing_days == Mil.cfg.landing.days and a.attacking == false, "a landing on the enemy's coast is an assault")
	var raw := 0.0
	for u in a.units:
		raw += u.power()
	_check(a.power() < raw * 0.6 and a.power() > raw * 0.4, "it fights at half strength while landing (%.1f of %.1f)" % [a.power(), raw])
	_check(a.entrenchment() == 0, "and has not dug in")
	_check(a.landed_supply > 0, "it brought supplies ashore")
	_check(f.landing == 0, "the fleet's task is done")
	a.landing_days = 0
	var full := 0.0
	for u in a.units:
		full += u.power()
	_check(is_equal_approx(a.power(), full * a.general_skill), "the penalty ends")
	# Landing in friendly territory is no assault.
	_reset()
	var f2 = _convoy("GBR", PORTSMOUTH, 2)
	var a2 = _army("GBR", PORTSMOUTH, 2)
	var ids2: Array[int] = [a2.id]
	_check(gs.issue(SendC.new("GBR", f2.id, ids2, BELFAST)), "an army can be sent to a British port")
	_days(40)
	_check(not a2.embarked() and a2.province == BELFAST and a2.landing_days == 0, "and lands without a penalty")
	# A landing opposed by an enemy army.
	_reset()
	gs.set_war("GBR", "FRA", true)
	var f3 = _convoy("GBR", PORTSMOUTH, 3)
	var a3 = _army("GBR", PORTSMOUTH, 3)
	var defender = _army("FRA", CALAIS, 2)
	var ids3: Array[int] = [a3.id]
	gs.issue(SendC.new("GBR", f3.id, ids3, CALAIS))
	_days(20)
	_check(not a3.embarked() and a3.attacking, "landing among enemy troops makes the landing army the attacker")
	_check(a3.province == defender.province, "in the same province")


func _test_sinking() -> void:
	_reset()
	gs.set_war("GBR", "FRA", true)
	var f = _convoy("GBR", PORTSMOUTH, 3)
	var a = _army("GBR", PORTSMOUTH, 3)
	var ids: Array[int] = [a.id]
	gs.issue(SendC.new("GBR", f.id, ids, CALAIS))
	var war = gs.war_between("GBR", "FRA")
	var lost_before: float = war.losses["GBR"]
	f.ships.clear()
	_days(1)
	_check(not gs.armies.has(a.id), "an army whose convoy is sunk is lost with it")
	_check(war.losses["GBR"] >= lost_before + 30000.0, "and its men count as losses in the war (%.0f)" % (war.losses["GBR"] - lost_before))
	# Partly sunk: the men the remaining ships cannot carry drown.
	_reset()
	gs.set_war("GBR", "FRA", true)
	var f2 = _convoy("GBR", PORTSMOUTH, 3)
	var a2 = _army("GBR", PORTSMOUTH, 9)
	var ids2: Array[int] = [a2.id]
	gs.issue(SendC.new("GBR", f2.id, ids2, CALAIS))
	var before: float = a2.men()
	f2.ships.pop_back()
	_days(1)
	_check(a2.men() < before and a2.men() <= f2.capacity() + 12000, "losing a transport drowns the men it carried (%.0f of %.0f left)" % [a2.men(), before])
	# A damaged transport still carries its load.
	_reset()
	var f3 = _convoy("GBR", PORTSMOUTH, 3)
	var a3 = _army("GBR", PORTSMOUTH, 9)
	gs.issue(EmbarkC.new("GBR", a3.id, f3.id))
	f3.ships[0].strength = 0.3
	var full: float = a3.men()
	_days(1)
	_check(a3.men() == full, "a damaged transport carries as many as a whole one")
	# A real battle at sea.
	_reset()
	gs.set_war("GBR", "FRA", true)
	var f4 = _convoy("GBR", PORTSMOUTH, 3)
	var a4 = _army("GBR", PORTSMOUTH, 3)
	var ids4: Array[int] = [a4.id]
	gs.issue(SendC.new("GBR", f4.id, ids4, CALAIS))
	var raider = Nav.new_fleet(gs, "FRA", "Raiders", 0)
	for i in 4:
		raider.ships.append(ShipC.new("dreadnought"))
	raider.zone = f4.path[0] if not f4.path.is_empty() else map.zones_of_port(PORTSMOUTH)[0]
	raider.engaged = true
	var gone := false
	for d in 15:
		_days(1)
		if not gs.armies.has(a4.id):
			gone = true
			break
	_check(gone or a4.province == CALAIS or f4.is_in_port() or not gs.fleets.has(f4.id), "a convoy that meets a battle fleet is sunk, lands, or turns back")


func _test_ferries() -> void:
	_reset()
	var pembroke := 332
	var wexford := 352
	var link: String = map.sea_links.get(Vector2i(mini(pembroke, wexford), maxi(pembroke, wexford)), "")
	_check(link == "sea", "Pembrokeshire and Wexford are linked across the Irish Sea")
	var near: Array = Mil.neighbors(pembroke)
	_check(not near.has(wexford), "plain neighbours skip open-sea links")
	_check(Mil.neighbors_for(gs, "GBR", pembroke).has(wexford), "but an army can ferry across")
	var a = _army("GBR", pembroke, 2)
	var path: Array[int] = Mil.find_path(gs, "GBR", a.speed(), pembroke, wexford)
	_check(path == [wexford], "and the path is one crossing")
	_check(Mil.move_days(gs, "GBR", a.speed(), pembroke, wexford) >= Mil.cfg.movement.sea_link_days, "which takes a few days at sea")
	# An enemy fleet holding the water closes it.
	gs.set_war("GBR", "FRA", true)
	var raider = Nav.new_fleet(gs, "FRA", "Raiders", 0)
	raider.ships.append(ShipC.new("dreadnought"))
	raider.zone = map.zones_of_port(pembroke)[0]
	Block.update_control(gs)
	_check(not Mil.neighbors_for(gs, "GBR", pembroke).has(wexford), "enemy ships holding the zone close the crossing")
	_check(Mil.find_path(gs, "GBR", a.speed(), pembroke, wexford) != [wexford], "so the direct route is gone")


func _test_supply() -> void:
	_reset()
	gs.set_war("GBR", "FRA", true)
	var a = _army("GBR", CALVADOS, 3)
	gs.set_controller(CALVADOS, "GBR")
	Block.update_control(gs)
	_check(Mil.home_connected(gs, "GBR", CALVADOS), "a captured port with a clear sea route is tied to home")
	_check(Mil.supply_cost(gs, "GBR", CALVADOS) == 0.0, "so the bridgehead is supplied")
	var raider = Nav.new_fleet(gs, "FRA", "Raiders", 0)
	raider.ships.append(ShipC.new("dreadnought"))
	raider.zone = map.zones_of_port(CALVADOS)[0]
	Block.update_control(gs)
	Mil._home_day = -1
	_check(not Mil.home_connected(gs, "GBR", CALVADOS), "an enemy fleet holding its water cuts it off")
	_check(Mil.supply_cost(gs, "GBR", CALVADOS) == INF, "and the bridgehead is out of supply")
	gs.fleets.erase(raider.id)
	Block.update_control(gs)
	Mil._home_day = -1
	_check(Mil.home_connected(gs, "GBR", CALVADOS), "until the fleet goes")
	_check(Mil.home_connected(gs, "GBR", 294), "ground a nation owns is always home")
	# Ground joined to home by land needs no ships.
	_check(Mil.home_connected(gs, "FRA", CALVADOS), "French ground is French")
	# Landed supplies carry a fresh landing for a while.
	_reset()
	gs.set_war("GBR", "FRA", true)
	var f = _convoy("GBR", PORTSMOUTH, 3)
	var b = _army("GBR", PORTSMOUTH, 3)
	var ids: Array[int] = [b.id]
	gs.issue(SendC.new("GBR", f.id, ids, CALVADOS))
	_days(20)
	_check(not b.embarked() and Mil.supply_cost(gs, "GBR", CALVADOS) == INF, "an army put ashore on enemy soil has no supply line")
	var men: float = b.men()
	Mil.step_day(gs)
	_check(b.supplied and b.men() == men, "yet its own stores keep it fed at first")
	b.landed_supply = 0
	b.units[0].strength = 1.0
	Mil.step_day(gs)
	_check(not b.supplied and b.men() < men, "and then it wastes away")
