extends SceneTree
## Headless test for control of the sea and blockade: who holds a zone, which ports a cordon
## cuts off, how Nation.blockade follows, and what it does to the economy.
## Run: godot --headless --path . -s res://tests/blockade_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var map: Node
var clock: Node
var Nav
var Block
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


func _fleet_at(tag: String, zone_name: String, comp: Dictionary):
	var f = Nav.new_fleet(gs, tag, "%s test fleet" % tag, 0)
	for type in comp:
		for i in comp[type]:
			f.ships.append(ShipC.new(type))
	f.zone = _zone(zone_name)
	f.port = 0
	return f


func _cordon(tag: String, zones: Array) -> Array:
	var out := []
	for z in zones:
		out.append(_fleet_at(tag, z, {"dreadnought": 2}))
	return out


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
	Block = load("res://scripts/sim/blockade.gd")
	ShipC = load("res://scripts/sim/ship.gd")

	_test_control()
	_test_cordon()
	_test_drift_and_economy()
	_test_other_nations()
	print("\n%s: %d failure(s)" % ["FAILED" if _failures > 0 else "PASSED", _failures])
	quit(1 if _failures > 0 else 0)


func _test_control() -> void:
	_reset()
	gs.set_war("GBR", "GER", true)
	var cns := _zone("Central North Sea")
	var a = _fleet_at("GBR", "Central North Sea", {"dreadnought": 2})
	Block.update_control(gs)
	_check(Block.holds(gs, "GBR", cns) and not Block.holds(gs, "GER", cns), "a fleet alone in a zone holds it")
	_check(Block.blockaders(gs, "GER", cns) == ["GBR"] and Block.blockaders(gs, "GBR", cns).is_empty(), "it holds it against its enemy, not against itself")
	var b = _fleet_at("FRA", "Central North Sea", {"cruiser": 1})
	gs.set_war("FRA", "GER", true)
	Block.update_control(gs)
	_check(Block.holds(gs, "FRA", cns) and Block.blockaders(gs, "GER", cns).size() == 2, "an ally's ships share the hold")
	var g = _fleet_at("GER", "Central North Sea", {"cruiser": 1})
	Block.update_control(gs)
	_check(gs.sea_control[cns].contested and not Block.holds(gs, "GBR", cns) and not Block.holds(gs, "GER", cns), "enemy ships on both sides make the zone contested")
	_check(Block.blockaders(gs, "GER", cns).is_empty(), "and nobody blockades from it")
	gs.fleets.erase(g.id)
	gs.fleets.erase(a.id)
	gs.fleets.erase(b.id)
	var t = _fleet_at("GBR", "Central North Sea", {"transport": 3})
	Block.update_control(gs)
	_check(not gs.sea_control.has(cns), "transports hold nothing")
	gs.fleets.erase(t.id)
	var p = Nav.new_fleet(gs, "GBR", "In port", 330)
	p.ships.append(ShipC.new("dreadnought"))
	Block.update_control(gs)
	_check(gs.sea_control.is_empty(), "a fleet in port holds nothing")


func _test_cordon() -> void:
	_reset()
	gs.set_war("GBR", "GER", true)
	var open: Dictionary = Block.open_zones(gs, "GER")
	_check(open.has(_zone("German Bight")) and open.has(_zone("Southern Baltic")), "with no ships about, Germany's ports reach the open sea")
	_check(Block.assess(gs, "GER").target == 0.0, "and nothing is blockaded")
	var partial := _cordon("GBR", ["Central North Sea", "Eastern Channel"])
	Block.update_control(gs)
	var info: Dictionary = Block.assess(gs, "GER")
	_check(info.target == 0.0 and info.share == 0.0, "a cordon with a gap (the way north past Norway) cuts nothing")
	for f in partial:
		gs.fleets.erase(f.id)
	var full := _cordon("GBR", ["Northern North Sea", "Central North Sea", "Eastern Channel"])
	Block.update_control(gs)
	info = Block.assess(gs, "GER")
	_check(info.share > 0.99 and info.by == ["GBR"], "holding the North Sea and the Channel cuts off all of Germany's port trade")
	_check(info.target > 0.0 and info.target < Nav.cfg.blockade.max, "the target stays under the cap (%.2f of %.2f)" % [info.target, Nav.cfg.blockade.max])
	_check(absf(info.cap - Nav.cfg.blockade.max * (1.0 - Nav.cfg.blockade.land_leak * Block.open_border_share(gs, "GER"))) < 0.0001, "the cap falls with open land frontiers")
	var gbr: Dictionary = Block.assess(gs, "GBR")
	_check(gbr.target == 0.0, "the blockaders themselves are not blockaded")
	_check(Block.open_border_share(gs, "GBR") == 0.0 or Block.open_border_share(gs, "GBR") > 0.0, "an island has a border share too")
	var weights: Dictionary = Block.port_weights(gs, "GER")
	_check(weights.size() == 3 and weights.has(_zone("German Bight")), "Germany's trade is in three zones: the Bight, the Straits and the Baltic")
	var landlocked: Dictionary = Block.port_weights(gs, "LUX")
	_check(landlocked.is_empty(), "Luxembourg has no port trade to cut")


func _test_drift_and_economy() -> void:
	_reset()
	gs.set_war("GBR", "GER", true)
	var ger = gs.nations["GER"]
	_days(8)
	_check(ger.blockade == 0.0, "no blockade without ships")
	var before: float = ger.budget.income
	_cordon("GBR", ["Northern North Sea", "Central North Sea", "Eastern Channel"])
	_days(8)
	var early: float = ger.blockade
	_check(early > 0.0 and early <= Nav.cfg.blockade.rise_per_day * 8 + 0.0001, "the blockade starts to bite slowly (%.2f after 8 days)" % early)
	_days(100)
	_check(absf(ger.blockade - ger.blockade_target) < 0.0001 and ger.blockade > 0.4, "and settles at its target (%.2f)" % ger.blockade)
	_check(ger.blockade_by == ["GBR"], "the nation records who holds it")
	Economy_recompute()
	_check(ger.budget.income < before, "income falls under blockade (%.1f against %.1f)" % [ger.budget.income, before])
	var support: float = ger.war_support
	_days(1)
	# Ships leave: the blockade lifts, but slower than a sortie could end it.
	for f in gs.fleets.values().duplicate():
		gs.fleets.erase(f.id)
	var high: float = ger.blockade
	_days(5)
	_check(ger.blockade < high and ger.blockade > high - 0.2, "it eases gradually once the cordon is gone (%.2f to %.2f)" % [high, ger.blockade])
	_days(80)
	_check(ger.blockade == 0.0, "and ends")
	# A contested zone breaks the cordon.
	_cordon("GBR", ["Northern North Sea", "Central North Sea", "Eastern Channel"])
	_days(60)
	var held: float = ger.blockade
	_check(held > 0.4, "the cordon is back (%.2f)" % held)
	var raider = _fleet_at("GER", "Central North Sea", {"cruiser": 2})
	Block.update_control(gs)
	_check(gs.sea_control[_zone("Central North Sea")].contested, "a German squadron contests the Central North Sea")
	_check(Block.assess(gs, "GER").target == 0.0, "so the cordon is broken for as long as it lasts")
	gs.fleets.erase(raider.id)
	# Peace ends it.
	gs.set_war("GBR", "GER", false)
	_days(80)
	_check(ger.blockade == 0.0, "peace lifts the blockade")


func Economy_recompute() -> void:
	load("res://scripts/sim/economy.gd").recompute(gs)


func _test_other_nations() -> void:
	_reset()
	gs.set_war("GER", "BEL", true)
	var zones: Dictionary = Block.port_weights(gs, "BEL")
	var antwerp := _zone("Southern North Sea")
	var total := 0.0
	for z in zones:
		total += zones[z]
	_check(zones.has(antwerp) and zones[antwerp] / total > 0.5, "most of Belgium's trade runs through the Southern North Sea (%.0f%%)" % (100.0 * zones[antwerp] / total))
	_fleet_at("GER", "Southern North Sea", {"dreadnought": 2})
	_fleet_at("GER", "Eastern Channel", {"dreadnought": 2})
	Block.update_control(gs)
	var info: Dictionary = Block.assess(gs, "BEL")
	_check(info.share > 0.99, "with both zones held, Belgium is cut off")
	for f in gs.fleets.values().duplicate():
		gs.fleets.erase(f.id)
	_fleet_at("GER", "Southern North Sea", {"dreadnought": 2})
	Block.update_control(gs)
	info = Block.assess(gs, "BEL")
	_check(info.share < 0.01 or info.share > 0.5, "Belgium's trade follows its zones")
	# A landlocked nation is never blockaded.
	_reset()
	gs.set_war("GBR", "SUI", true)
	_cordon("GBR", ["Northern North Sea", "Central North Sea", "Eastern Channel", "Western Channel", "Bay of Biscay", "Strait of Gibraltar"])
	_days(60)
	_check(gs.nations["SUI"].blockade == 0.0, "a landlocked nation is not blockaded by sea")
	# Nations at peace are never blockaded.
	_reset()
	_cordon("GBR", ["Northern North Sea", "Central North Sea", "Eastern Channel"])
	_days(30)
	_check(gs.nations["GER"].blockade == 0.0, "no war, no blockade")
