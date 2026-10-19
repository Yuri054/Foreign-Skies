extends SceneTree
## Headless test for the naval AI: roles, cordons, stationing by odds, repair, landings, building,
## determinism.
## Run: godot --headless --path . -s res://tests/ai_navy_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var map: Node
var clock: Node
var Nav
var AN
var AL
var Block
var ShipC
var UnitC
var Mil


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


func _fleet(tag: String, fleet_name: String):
	for f in gs.fleets.values():
		if f.tag == tag and f.display_name == fleet_name:
			return f
	return null


func _reset(war := true) -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("SUI")
	gs.join_calls.clear()
	gs.wars.clear()
	gs.treaties.clear()  # a war between two nations, with nobody called in
	if war:
		gs.set_war("GBR", "GER", true)


func _days(n: int) -> void:
	for i in n:
		clock.advance_day()


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	map = root.get_node("MapData")
	clock = root.get_node("Clock")
	Nav = load("res://scripts/sim/navy.gd")
	AN = load("res://scripts/ai/ai_navy.gd")
	AL = load("res://scripts/ai/ai_landing.gd")
	Block = load("res://scripts/sim/blockade.gd")
	ShipC = load("res://scripts/sim/ship.gd")
	UnitC = load("res://scripts/sim/unit.gd")
	Mil = load("res://scripts/sim/military.gd")

	_test_roles()
	_test_cordon()
	_test_stationing()
	_test_repair()
	_test_landing()
	_test_building()
	_test_determinism()
	print("\n%s: %d failure(s)" % ["FAILED" if _failures > 0 else "PASSED", _failures])
	quit(1 if _failures > 0 else 0)


func _test_roles() -> void:
	_reset()
	var channel = _fleet("GBR", "Channel Fleet")
	_check(AN.role(channel) == "warfleet" and channel.count_of("transport") == 3, "the Channel Fleet starts as a mixed warfleet with transports")
	for i in 6:
		AN.step(gs, "GBR")
	var mixed := 0
	var carriers := 0
	var raiders := 0
	for f in Nav.fleets_of(gs, "GBR"):
		var r: String = AN.role(f)
		if f.count_of("transport") > 0 and f.ships.size() > f.count_of("transport"):
			mixed += 1
		if r == "transport":
			carriers += f.capacity()
		if r == "raider":
			raiders += 1
	_check(mixed == 0 and carriers >= 120000, "transports are split off into their own fleets (%d men of capacity)" % carriers)
	_check(raiders >= 2, "and so are the submarines (%d raider fleets)" % raiders)
	var patrol := false
	for f in Nav.fleets_of(gs, "GBR"):
		patrol = patrol or f.display_name.ends_with("patrol")
	_check(patrol, "a big fleet detaches a patrol")
	_check(AN.role(_fleet("GBR", "Grand Fleet")) == "warfleet", "the main fleet stays a warfleet")
	# Peace: nothing happens.
	_reset(false)
	var before: int = gs.fleets.size()
	for i in 6:
		AN.step(gs, "GBR")
	_check(gs.fleets.size() == before, "at peace fleets are left alone")


func _test_cordon() -> void:
	_reset()
	var zones: Array[int] = AN.cordon_zones(gs, "GER")
	_check(zones.size() >= 2 and zones.size() <= 6, "a cordon on Germany takes a few zones (%d)" % zones.size())
	for z in zones:
		var f = Nav.new_fleet(gs, "GBR", "Test", 0)
		f.ships.append(ShipC.new("dreadnought"))
		f.zone = z
	Block.update_control(gs)
	var info: Dictionary = Block.assess(gs, "GER")
	_check(info.share > 0.99, "holding those zones seals Germany's ports (%.2f)" % info.share)
	var names := []
	for z in zones:
		names.append(map.sea_zones[z].name)
	_check(not zones.has(_zone("German Bight")), "and it does not need the German Bight itself (%s)" % ", ".join(names))
	var britain: Array[int] = AN.cordon_zones(gs, "GBR")
	_check(britain.size() > zones.size(), "an island nation with ports on many seas takes more to seal (%d against %d)" % [britain.size(), zones.size()])


func _test_stationing() -> void:
	_reset()
	_days(40)
	var at_sea := 0
	var in_cordon := false
	var cordon: Array[int] = AN.cordon_zones(gs, "GER")
	for f in Nav.fleets_of(gs, "GBR"):
		if f.zone > 0 and f.port == 0 and f.power() > 0:
			at_sea += 1
			in_cordon = in_cordon or cordon.has(f.zone) or cordon.has(f.path.back() if not f.path.is_empty() else 0)
	_check(at_sea >= 2, "the stronger navy puts to sea (%d fleets)" % at_sea)
	_check(in_cordon, "and heads for the zones that seal its enemy")
	_days(80)
	var ger = gs.nations["GER"]
	_check(ger.blockade > 0.0, "Germany comes under blockade (%.2f)" % ger.blockade)
	var seas = _fleet("GER", "High Seas Fleet")
	_check(seas != null and seas.is_in_port(), "while the weaker High Seas Fleet stays in port rather than offer battle")
	_check(gs.nations["GER"].ships_lost == 0, "and loses nothing")
	# A fleet never heads where it is outgunned.
	var odds: float = load("res://scripts/ai/ai.gd").required_odds(gs, "GER")
	var f2 = Nav.new_fleet(gs, "GER", "Lone cruiser", 394)
	f2.ships.append(ShipC.new("cruiser"))
	var brit = Nav.new_fleet(gs, "GBR", "Picket", 0)
	for i in 3:
		brit.ships.append(ShipC.new("dreadnought"))
	brit.zone = _zone("German Bight")
	for i in 12:
		AN.step(gs, "GER")
	var heading: int = f2.path.back() if not f2.path.is_empty() else f2.zone
	var map_now: Dictionary = AN.enemy_map(gs, "GER")
	_check(heading == 0 or odds * float(map_now.get(heading, 0.0)) <= f2.power(), "a lone cruiser never heads where it is outgunned")
	# Weak British forces and strong German ones: the roles reverse.
	_reset()
	for f in Nav.fleets_of(gs, "GBR").duplicate():
		gs.fleets.erase(f.id)
	var small = Nav.new_fleet(gs, "GBR", "Home Guard", 330)
	small.ships.append(ShipC.new("cruiser"))
	_days(30)
	var sortie := false
	for f in Nav.fleets_of(gs, "GER"):
		sortie = sortie or (f.zone > 0 and f.port == 0 and f.power() > 0)
	_check(sortie, "against a weaker enemy the German fleet does put to sea")


func _test_repair() -> void:
	_reset()
	var grand = _fleet("GBR", "Grand Fleet")
	for s in grand.ships:
		s.strength = 0.5
	AN.step(gs, "GBR")
	_check(grand.is_in_port() and not grand.is_moving(), "a damaged fleet in port stays to repair")
	# At sea and worn: goes home.
	var f = Nav.new_fleet(gs, "GBR", "Worn", 0)
	f.ships.append(ShipC.new("cruiser"))
	f.zone = _zone("Central North Sea")
	f.ships[0].strength = 0.5
	AN.step(gs, "GBR")
	_check(f.is_moving() and f.dest_port > 0, "a worn fleet at sea sets course for a port")


func _landing_setup() -> Dictionary:
	_reset()
	# Britain against Germany: no land border, a strong navy.
	for a in Mil.armies_of(gs, "GBR").duplicate():
		gs.armies.erase(a.id)
	var army = Mil.new_army(gs, "GBR", "Expeditionary Force", 294)
	for i in 10:
		army.units.append(UnitC.new("infantry"))
	for a in Mil.armies_of(gs, "GER").duplicate():
		if a.province in [373, 378, 393, 394, 416]:
			gs.armies.erase(a.id)
	return {"army": army}


func _test_landing() -> void:
	var s := _landing_setup()
	for i in 4:
		AN.step(gs, "GBR")
	var c: Variant = AL._start(gs, "GBR")
	_check(c != null and c.enemy == "GER" and gs.province_controller[c.target] == "GER", "Britain picks a German coast to land on")
	_check(c != null and map.zones_of_port(c.target).has(c.zone) or c == null, "the landing zone is the coast's")
	# No transports: it asks for them.
	_landing_setup()
	for f in Nav.fleets_of(gs, "GBR"):
		for i in range(f.ships.size() - 1, -1, -1):
			if f.ships[i].type == "transport":
				f.ships.remove_at(i)
	var none: Variant = AL._start(gs, "GBR")
	_check(none == null and gs.ai_navy_need.get("GBR", "") == "transport", "without transports there is no landing, and the budget is told")
	# An enemy fleet in the way.
	_landing_setup()
	for i in 4:
		AN.step(gs, "GBR")
	for f in Nav.fleets_of(gs, "GBR"):
		if f.power() > 0:
			f.ships.resize(maxi(1, f.ships.size() / 4))
	var strong = Nav.new_fleet(gs, "GER", "Wall", 0)
	for i in 8:
		strong.ships.append(ShipC.new("dreadnought"))
	strong.zone = _zone("Southern North Sea")
	var blocked: Variant = AL._start(gs, "GBR")
	_check(blocked == null, "it does not set out under the guns of a stronger fleet")
	# The whole business, under the day step.
	_landing_setup()
	var landed := false
	var started := false
	var escorted := false
	for day in 160:
		_days(1)
		if gs.ai_landing.has("GBR"):
			started = true
			escorted = escorted or gs.ai_landing["GBR"].phase != "gather"
		for a in Mil.armies_of(gs, "GBR"):
			if gs.province_owner[a.province] == "GER":
				landed = true
		if landed:
			break
	_check(started, "a landing is prepared")
	_check(landed, "and the army goes ashore in Germany")
	_check(gs.nations["GBR"].blockade < 0.01, "at no cost to Britain's own trade")


func _test_building() -> void:
	_reset(false)
	var gbr = gs.nations["GBR"]
	for i in 6:
		AN.build(gs, "GBR")
	_check(gbr.shipbuilding.is_empty(), "at peace no ships are laid down")
	gs.set_war("GBR", "GER", true)
	var wall = Nav.new_fleet(gs, "GER", "Big fleet", 394)
	for i in 30:
		wall.ships.append(ShipC.new("dreadnought"))
	gbr.treasury = 80.0
	var net_before: float = gbr.budget.net
	AN.build(gs, "GBR")
	_check(gbr.shipbuilding.size() == 1, "at war against a bigger navy Britain lays down a squadron (net %.0f a year)" % net_before)
	var type: String = gbr.shipbuilding[0].type
	_check(Nav.cfg.types.has(type) and Nav.build_problem(gs, "GBR", gbr.shipbuilding[0].province, type, 1, false) != "Needs a port", "at a yard that can build it (%s)" % type)
	var treasury: float = gbr.treasury
	for i in 6:
		AN.build(gs, "GBR")
	_check(gbr.shipbuilding.size() <= int(AN.cfg().build.max_building), "never more than the limit at once (%d)" % gbr.shipbuilding.size())
	_check(gbr.treasury >= float(AN.cfg().build.build_floor), "and the treasury stays above the floor (%.1f)" % gbr.treasury)
	# Over a year the mix follows the shares.
	gbr.treasury = 400.0
	var seen := {}
	for m in 24:
		for job in gbr.shipbuilding:
			seen[job.type] = true
		for job in gbr.shipbuilding:
			job.points_left = 0.0
		clock.days_elapsed += 30
		Nav.step_day(gs)
		AN.build(gs, "GBR")
		gbr.treasury = maxf(gbr.treasury, 400.0)
	_check(seen.size() >= 3, "it builds a mix of types (%s)" % ", ".join(seen.keys()))
	# A poor nation builds nothing.
	_reset(false)
	gs.set_war("GBR", "DEN", true)
	var den = gs.nations["DEN"]
	den.treasury = 1.0
	var big = Nav.new_fleet(gs, "GBR", "Big fleet", 330)
	for i in 30:
		big.ships.append(ShipC.new("dreadnought"))
	AN.build(gs, "DEN")
	_check(den.shipbuilding.is_empty(), "a poor nation builds nothing")
	# A nation that wants to land asks for transports and gets one.
	_reset()
	for f in Nav.fleets_of(gs, "GBR"):
		for i in range(f.ships.size() - 1, -1, -1):
			if f.ships[i].type == "transport":
				f.ships.remove_at(i)
	gbr = gs.nations["GBR"]
	gbr.treasury = 200.0
	gs.ai_navy_need["GBR"] = "transport"
	AN.build(gs, "GBR")
	_check(gbr.shipbuilding.size() == 1 and gbr.shipbuilding[0].type == "transport" and not gs.ai_navy_need.has("GBR"), "a nation that needs transports lays one down")


func _run_war() -> Array:
	_reset()
	clock.days_elapsed = 0
	_days(60)
	var out := []
	for f in Nav.fleets_of(gs, "GBR") + Nav.fleets_of(gs, "GER"):
		out.append([f.id, f.zone, f.port, f.ships.size(), snappedf(f.power(), 0.001)])
	out.append(gs.command_log.size())
	return out


func _test_determinism() -> void:
	var a := _run_war()
	var b := _run_war()
	_check(a == b, "the same war run twice moves the fleets the same way (%d fleets)" % (a.size() - 1))
