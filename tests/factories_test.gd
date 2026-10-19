extends SceneTree
## Headless test of factories: the starting factories match each nation's industry and leave the
## calibrated economy as it was, slots limit building, a civilian factory retooled for the army
## costs its output, and the factories survive a save.
## Run: godot --headless --path . -s res://tests/factories_test.gd

var _failures := 0
var gs: Node
var Clock: Node
var Eco
var Convert
var Build


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
	Eco = load("res://scripts/sim/economy.gd")
	Convert = load("res://scripts/sim/convert_factory.gd")
	Build = load("res://scripts/sim/construct_building.gd")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	_test_start()
	_test_calibration()
	_test_slots()
	_test_convert()
	_test_save()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _count(tag: String, type: String) -> int:
	var total := 0
	for id in gs.nations[tag].provinces:
		total += gs.province_buildings[id].get(type, 0)
	return total


func _test_start() -> void:
	var ger = gs.nations["GER"]
	var civ := _count("GER", "factory")
	var mil := _count("GER", "military_factory")
	var worth: float = ger.budget.industry / Eco.factory_output(ger)
	_check(absi(civ + mil - roundi(worth)) <= 1, "Germany's %d factories are worth its industry (%.1f)" % [civ + mil, worth])
	_check(mil == roundi(ger.peacetime_army / float(Eco.cfg.factories.army_per_military_factory)), "its military factories follow its peacetime army (%d)" % mil)
	_check(civ > mil * 3, "most of the factories are civilian")
	_check(_count("GBR", "military_factory") >= 1 and _count("LUX", "military_factory") == 0, "a big army has an arsenal, a tiny one has none")
	var all_arsenal := 0
	for id in ger.provinces:
		var c: int = gs.province_buildings[id].get("factory", 0)
		var m: int = gs.province_buildings[id].get("military_factory", 0)
		if m > (c + m + 1) / 2:
			all_arsenal += 1
	_check(all_arsenal == 0, "no province is mostly arsenal")
	var first: int = ger.provinces[0]
	_check(gs.province_civ_base[first] == gs.province_buildings[first].get("factory", 0), "the calibrated base is the civilian factories at the start")


## The factories change nothing at the start: output is what it was without them.
func _test_calibration() -> void:
	var map: Node = root.get_node("MapData")
	for tag in ["GER", "GBR", "BEL"]:
		var n = gs.nations[tag]
		var plain := 0.0
		var industry := 0.0
		for id in n.provinces:
			var b: Dictionary = gs.province_buildings[id].duplicate()
			b.erase("factory")
			b.erase("military_factory")
			var o = Eco.province_output(gs.province_population[id], map.provinces[id].area * map.KM2_PER_PX, n, b, gs.province_deposit[id])
			plain += o.gdp
			industry += o.industry
		_check(absf(plain - n.budget.gdp) < 0.01 * plain and absf(industry - n.budget.industry) < 0.01 * industry, "%s: output at the start is what it was before factories (%.1f)" % [tag, plain])


func _test_slots() -> void:
	var ger = gs.nations["GER"]
	var ok := true
	for id in ger.provinces:
		var used: int = gs.province_buildings[id].get("factory", 0) + gs.province_buildings[id].get("military_factory", 0)
		ok = ok and gs.province_slots[id] >= maxi(int(Eco.cfg.factories.slot_min), used + 1)
	_check(ok, "every province has the minimum slots and room above its factories")
	var id: int = ger.provinces[0]
	ger.treasury = 5000.0
	gs.province_slots[id] = Eco.slots_used(gs, id) + 1
	_check(gs.issue(Build.new("GER", id, "military_factory")), "a military factory takes the last slot")
	_check(Eco.slots_used(gs, id) == gs.province_slots[id] and not gs.issue(Build.new("GER", id, "factory")), "and a queued one counts: no slot is left for another")
	_check(Eco.build_problem(gs, "GER", id, "military_factory") == "No free slot", "the reason is given")


func _test_convert() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	var ger = gs.nations["GER"]
	ger.treasury = 5000.0
	var id := 0
	for p in ger.provinces:
		if gs.province_buildings[p].get("factory", 0) >= 2:
			id = p
			break
	var civ0: int = gs.province_buildings[id].get("factory", 0)
	var mil0: int = gs.province_buildings[id].get("military_factory", 0)
	var gdp0: float = ger.budget.gdp
	var cash: float = ger.treasury
	var cmd = Convert.new("GER", id, "military_factory")
	_check(gs.issue(cmd), "a civilian factory is retooled")
	_check(is_equal_approx(cash, ger.treasury) and ger.construction.back().points_total == Convert.cost_of("military_factory"), "it costs a share of a new factory in IC, not money")
	_check(gs.province_buildings[id].get("factory", 0) == civ0 - 1 and gs.province_buildings[id].get("military_factory", 0) == mil0, "the civilian factory stops at once")
	var lost: float = gdp0 - ger.budget.gdp
	_check(lost > 0.0 and absf(lost - Eco.factory_output(ger) * ger.budget.gdp_scale) < 0.05 * lost, "and its output is lost (£%.1fM a year)" % lost)
	_check(ger.construction.size() == 1 and ger.construction[0].type == "military_factory", "the new factory is under construction")
	for i in Eco.cfg.factories.convert_days - 1:
		Clock.advance_day()
	_check(gs.province_buildings[id].get("military_factory", 0) == mil0, "it is not there a day early")
	Clock.advance_day()
	_check(gs.province_buildings[id].get("military_factory", 0) == mil0 + 1 and not ger.construction.any(func(j: Dictionary) -> bool: return j.get("convert", false)), "it stands after the conversion time")
	_check(gs.issue(Convert.new("GER", id, "factory")) and gs.province_buildings[id].get("military_factory", 0) == mil0, "a military factory can be turned back")
	for i in Eco.cfg.factories.convert_days:
		Clock.advance_day()
	_check(gs.province_buildings[id].get("factory", 0) == civ0, "the civilian factory is back")
	var cmd2 = Convert.new("GER", gs.nations["FRA"].provinces[0], "military_factory")
	_check(not gs.issue(cmd2) and cmd2.reason != "", "another nation's province is refused: " + cmd2.reason)
	var empty := 0
	for p in ger.provinces:
		if gs.province_buildings[p].get("military_factory", 0) == 0:
			empty = p
			break
	var cmd3 = Convert.new("GER", empty, "factory")
	_check(not gs.issue(cmd3) and cmd3.reason != "", "a province with none to retool is refused: " + cmd3.reason)
	ger.treasury = 0.0
	var cmd4 = Convert.new("GER", id, "military_factory")
	_check(not ("money" in cmd4.reason), "conversion never needs money: " + cmd4.reason)


func _test_save() -> void:
	var SaveGame = load("res://scripts/sim/save_game.gd")
	SaveGame.dir = "user://test_factory_saves/"
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	var id: int = gs.nations["GER"].provinces[0]
	gs.nations["GER"].treasury = 5000.0
	var retool := 0
	for p in gs.nations["GER"].provinces:
		if gs.province_buildings[p].get("factory", 0) > 0:
			retool = p
			break
	_check(gs.issue(Convert.new("GER", retool, "military_factory")), "a retooling is under way")
	var civ := _count("GER", "factory")
	var mil := _count("GER", "military_factory")
	var slots: int = gs.province_slots[id]
	var path: String = SaveGame.dir + "factories.sav"
	_check(gs.save_game(path) == "", "a game with factories saves")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	_check(gs.load_game(path) == "", "and loads")
	_check(_count("GER", "factory") == civ and _count("GER", "military_factory") == mil and gs.province_slots[id] == slots, "the factories and slots are as saved")
	_check(gs.nations["GER"].construction.any(func(j: Dictionary) -> bool: return j.get("convert", false)), "so is the retooling in progress")
	DirAccess.remove_absolute(path)
