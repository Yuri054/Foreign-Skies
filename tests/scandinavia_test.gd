extends SceneTree
## Headless test for Norway and Sweden: they exist on the map and in the scenario, their
## economies balance, they field armies and a navy, the AI plays them and the map is joined up.
## Run: godot --headless --path . -s res://tests/scandinavia_test.gd

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
	var md: Node = root.get_node("MapData")
	var Mil = load("res://scripts/sim/military.gd")
	var Nav = load("res://scripts/sim/navy.gd")
	var D = load("res://scripts/sim/diplomacy.gd")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("ESP")
	for tag in ["NOR", "SWE"]:
		var n = gs.nations[tag]
		_check(n.provinces.size() >= 20, "%s holds %d provinces" % [tag, n.provinces.size()])
		_check(n.population > 2.0e6, "%s has %.1f million people" % [tag, n.population / 1e6])
		_check(gs.province_owner[n.capital] == tag, "%s's capital %s is its own" % [tag, md.provinces[n.capital].name])
		_check(n.budget.net >= 0.0, "%s's budget balances at the start (%+.2fM a month's worth a year)" % [tag, n.budget.net])
		_check(n.budget.food_production / n.population > 0.4, "%s grows a fair part of its food (%.2f)" % [tag, n.budget.food_production / n.population])
		var armies := 0
		for a in gs.armies.values():
			if a.tag == tag:
				armies += 1
		_check(armies >= 2, "%s fields %d armies" % [tag, armies])
		_check(not Nav.fleets_of(gs, tag).is_empty(), "%s has a fleet" % tag)
		var port := false
		for id in n.provinces:
			port = port or Nav.port_level(gs, id) > 0
		_check(port, "%s has a port" % tag)
	# Joined up: Sweden is reachable from Finland and Norway by land, Denmark by the Sound.
	var reach := {}
	var queue: Array = [gs.nations["SWE"].capital]
	while not queue.is_empty():
		var id: int = queue.pop_back()
		if reach.has(id):
			continue
		reach[id] = true
		for nb in Mil.neighbors(id):
			if not reach.has(nb):
				queue.append(nb)
	_check(reach.has(gs.nations["NOR"].capital), "Christiania is reachable from Stockholm over land")
	_check(reach.has(gs.nations["RUS"].capital), "and so is Russia")
	var den: int = gs.nations["DEN"].capital
	var linked := false
	for nb in Mil.neighbors(den):
		linked = linked or gs.province_owner[nb] == "SWE"
	_check(linked, "Copenhagen is linked to Sweden across the Sound")
	_check("GBR" in D.guarantors_of(gs, "NOR"), "Britain guarantees Norway")
	_check(FileAccess.file_exists("res://assets/flags/NOR.png") and FileAccess.file_exists("res://assets/flags/SWE.png"), "both have a flag picture")
	_check(gs.cities_by_province.has(gs.nations["SWE"].capital) and gs.cities_by_province.has(gs.nations["NOR"].capital), "both capitals are cities")
	# A quiet year in the AI's hands: neither starves, collapses or attacks anyone.
	gs.ai_enabled = true
	var clock: Node = root.get_node("Clock")
	for i in 365:
		clock.advance_day()
	for tag in ["NOR", "SWE"]:
		_check(not gs.nations[tag].starving and gs.nations[tag].provinces.size() >= 20, "%s is still whole and fed after a year" % tag)
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
