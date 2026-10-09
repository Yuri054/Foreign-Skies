extends SceneTree
## Headless test for fighting at sea: contact, damage, sinking, routs, retreat and repair,
## battle records, and the wear of long voyages.
## Run: godot --headless --path . -s res://tests/naval_combat_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var map: Node
var clock: Node
var Nav
var Combat
var ShipC


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
	gs.ai_enabled = false


## A fleet of the given squadrons standing at sea in a zone.
func _fleet_at(tag: String, zone: int, comp: Dictionary):
	var f = Nav.new_fleet(gs, tag, "%s test fleet" % tag, 0)
	for type in comp:
		for i in comp[type]:
			f.ships.append(ShipC.new(type))
	f.zone = zone
	f.port = 0
	return f


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
	Combat = load("res://scripts/sim/naval_combat.gd")
	ShipC = load("res://scripts/sim/ship.gd")

	_test_peace()
	_test_contact()
	_test_battle()
	_test_submarines()
	_test_retreat_and_repair()
	_test_determinism()
	_test_range()
	print("\n%s: %d failure(s)" % ["FAILED" if _failures > 0 else "PASSED", _failures])
	quit(1 if _failures > 0 else 0)


func _test_peace() -> void:
	_reset()
	var zone := _zone("Central North Sea")
	var a = _fleet_at("GBR", zone, {"dreadnought": 3})
	var b = _fleet_at("GER", zone, {"dreadnought": 3})
	a.engaged = true
	b.engaged = true
	_days(10)
	_check(not a.fighting and not b.fighting and gs.sea_battles.is_empty(), "fleets of nations at peace do not fight")
	_check(a.ships[0].strength == 1.0 and b.ships[0].strength == 1.0, "and take no damage")


func _test_contact() -> void:
	_reset()
	var zone := _zone("Central North Sea")
	var d1 = _fleet_at("GBR", zone, {"dreadnought": 2})
	var d2 = _fleet_at("GER", zone, {"dreadnought": 2})
	var s1 = _fleet_at("GBR", zone, {"submarine": 2})
	var s2 = _fleet_at("GER", zone, {"submarine": 2})
	var c1 = _fleet_at("GBR", zone, {"cruiser": 2})
	var c2 = _fleet_at("GER", zone, {"cruiser": 2})
	var seen := {"dread": 0, "sub": 0, "cruiser": 0}
	var first: Array = []
	for day in 400:
		clock.days_elapsed = day
		seen.dread += 1 if Combat.contact(d1, d2) else 0
		seen.sub += 1 if Combat.contact(s1, s2) else 0
		seen.cruiser += 1 if Combat.contact(c1, c2) else 0
		first.append(Combat.contact(d1, d2))
	_check(seen.sub < seen.dread and seen.dread < seen.cruiser, "cruisers find the enemy most often, submarines least (%d, %d, %d of 400 days)" % [seen.cruiser, seen.dread, seen.sub])
	_check(seen.sub > 0 and seen.cruiser < 400, "but no contact is certain or impossible")
	var again: Array = []
	for day in 400:
		clock.days_elapsed = day
		again.append(Combat.contact(d1, d2))
	_check(first == again, "the same day gives the same answer")
	d1.engaged = true
	d2.engaged = true
	var always := true
	for day in 50:
		clock.days_elapsed = day
		always = always and Combat.contact(d1, d2)
	_check(always, "fleets already fighting stay in touch")
	var screened = _fleet_at("GER", zone, {"dreadnought": 2, "destroyer": 3})
	_check(Combat.firepower(s1, screened) < Combat.firepower(s1, d2), "a destroyer screen blunts submarines")
	_check(Combat.firepower(d1, screened) == Combat.firepower(d1, d2), "and does nothing against a battle fleet")


func _setup_battle() -> Array:
	_reset()
	gs.set_war("GBR", "GER", true)
	var zone := _zone("Central North Sea")
	var strong = _fleet_at("GBR", zone, {"dreadnought": 4, "cruiser": 2})
	var weak = _fleet_at("GER", zone, {"dreadnought": 2, "cruiser": 1})
	strong.engaged = true
	weak.engaged = true
	return [strong, weak, zone]


func _test_battle() -> void:
	var s := _setup_battle()
	var strong = s[0]
	var weak = s[1]
	var zone: int = s[2]
	var gbr_before: int = gs.nations["GBR"].men_lost_month
	var ger_before: int = gs.nations["GER"].men_lost_month
	_days(1)
	_check(strong.fighting and weak.fighting and gs.sea_battles.has(zone), "hostile fleets in one zone fight and a battle is recorded")
	var battle: Dictionary = gs.sea_battles[zone]
	_check(battle.start_ships["GBR"] == 6 and battle.start_ships["GER"] == 3, "it records the squadrons each side brought")
	_check(weak.ships[0].strength < strong.ships[0].strength, "the weaker fleet takes more damage per ship")
	_check(gs.nations["GER"].men_lost_month > ger_before and gs.nations["GBR"].men_lost_month > gbr_before, "crews lost count as casualties")
	var war = gs.war_between("GBR", "GER")
	_check(war != null and war.losses["GER"] > 0.0, "and are charged to the war")
	_days(40)
	var strong_share := 1.0 - _mean_strength(strong)
	_check(not gs.sea_battles.has(zone) and not gs.sea_battle_archive.is_empty(), "the battle ends and is archived")
	var record: Dictionary = gs.sea_battle_archive.values()[0]
	_check(record.winner == "GBR" and not record.active and record.days >= 1 and not record.events.is_empty(), "the stronger fleet is recorded as the winner, with the day's events")
	_check(weak.retreating or weak.is_in_port() or weak.ships.is_empty(), "the beaten fleet ran for port or went down")
	_check(strong.ships.size() >= 5, "the stronger fleet kept most of its squadrons (%d of 6)" % strong.ships.size())
	_check(strong_share < 0.5, "and took a lighter beating than the other (%.2f of its strength lost)" % strong_share)
	_check(gs.nations["GER"].ships_lost >= gs.nations["GBR"].ships_lost, "Germany lost at least as many squadrons")


func _mean_strength(f) -> float:
	if f.ships.is_empty():
		return 0.0
	var t := 0.0
	for s in f.ships:
		t += s.strength
	return t / f.ships.size()


func _test_submarines() -> void:
	_reset()
	gs.set_war("GBR", "GER", true)
	var zone := _zone("Central North Sea")
	var fleet = _fleet_at("GBR", zone, {"dreadnought": 3, "destroyer": 2})
	var subs = _fleet_at("GER", zone, {"submarine": 2})
	fleet.engaged = true
	subs.engaged = true
	_days(6)
	_check(subs.ships.size() < 2 or _mean_strength(subs) < 0.5, "a submarine flotilla caught by a battle fleet is hit hard")
	_check(_mean_strength(fleet) > 0.9, "and barely marks it")
	_reset()
	gs.set_war("GBR", "GER", true)
	var lone = _fleet_at("GBR", zone, {"dreadnought": 3})
	var hidden = _fleet_at("GER", zone, {"submarine": 2})
	lone.engaged = true
	hidden.engaged = true
	_days(1)
	var no_screen := _mean_strength(hidden)
	_reset()
	gs.set_war("GBR", "GER", true)
	var screened = _fleet_at("GBR", zone, {"dreadnought": 3, "destroyer": 1})
	var hunted = _fleet_at("GER", zone, {"submarine": 2})
	screened.engaged = true
	hunted.engaged = true
	_days(1)
	_check(no_screen > _mean_strength(hunted), "destroyers make submarines easier to kill (%.2f without, %.2f with)" % [no_screen, _mean_strength(hunted)])


func _test_retreat_and_repair() -> void:
	var s := _setup_battle()
	var weak = s[1]
	var days := 0
	while days < 60 and weak.port == 0 and not weak.ships.is_empty():
		_days(1)
		days += 1
	_check(weak.is_in_port() and Nav.can_dock(gs, "GER", weak.port), "the beaten fleet reaches a German port (after %d days)" % days)
	var low := _mean_strength(weak)
	_check(low < 1.0, "damaged (%.2f)" % low)
	_days(1)
	_check(not weak.retreating, "it is no longer retreating once docked")
	_days(30)
	_check(_mean_strength(weak) > low, "and repairs in port (%.2f after a month)" % _mean_strength(weak))
	var mor := 0.0
	for sh in weak.ships:
		mor += sh.morale
	_check(mor / weak.ships.size() > 0.9, "morale recovers in port")
	# A fleet in port is out of reach.
	var enemy = _fleet_at("GBR", weak.current_zone(), {"dreadnought": 4})
	enemy.engaged = true
	weak.engaged = true
	var before := _mean_strength(weak)
	_days(5)
	_check(_mean_strength(weak) >= before, "a fleet in port is not attacked from the sea")


func _run_battle() -> Array:
	var s := _setup_battle()
	_days(15)
	var out := []
	for f in [s[0], s[1]]:
		out.append(snappedf(_mean_strength(f), 0.00001))
		out.append(f.ships.size())
	return out


func _test_determinism() -> void:
	clock.days_elapsed = 0
	var a := _run_battle()
	clock.days_elapsed = 0
	var b := _run_battle()
	_check(a == b, "the same battle run twice ends the same way %s" % [a])


func _test_range() -> void:
	_reset()
	var zone := _zone("Central North Sea")
	var raider = _fleet_at("GER", zone, {"destroyer": 2})
	raider.days_out = 0
	_days(20)
	_check(raider.days_out == 20, "days at sea are counted")
	_check(_mean_strength(raider) < 1.0 and _mean_strength(raider) >= Nav.cfg.range_floor, "a flotilla beyond its range wears down (%.2f)" % _mean_strength(raider))
	var cruisers = _fleet_at("GER", zone, {"cruiser": 2})
	_days(20)
	_check(_mean_strength(cruisers) == 1.0, "a long-range ship is fine for the same time")
