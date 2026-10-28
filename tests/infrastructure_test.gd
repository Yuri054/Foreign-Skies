extends SceneTree
## Headless test of infrastructure: a province's railway level plus half the best of its neighbours' (of the
## same nation), the numbers the build map writes on a province (level out of the most), and a railway
## that shortens the march and the supply line.
## Run: godot --headless --path . -s res://tests/infrastructure_test.gd

var _failures := 0
var gs: Node
var Eco
var Labels
var Mil


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	Eco = load("res://scripts/sim/economy.gd")
	Labels = load("res://scripts/map/slot_labels.gd")
	Mil = load("res://scripts/sim/military.gd")
	_fresh()
	_test_level()
	_test_network()
	_test_labels()
	_test_march()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.ai_enabled = false
	# The big cities begin with railways; these tests start from none.
	for built in gs.province_buildings:
		built.erase("railway")
	Eco.recompute(gs)
	gs.set_player("FRA")


func _province_with_neighbour(tag: String) -> Array:
	for id in gs.nations[tag].provinces:
		for n in Mil.neighbors(id):
			if gs.province_owner[n] == tag:
				return [id, n]
	return [0, 0]


func _test_level() -> void:
	var id: int = _province_with_neighbour("FRA")[0]
	_check(Eco.infrastructure(gs, id) == 0.0, "nothing has a railway at the start")
	gs.province_buildings[id]["railway"] = 2
	_check(is_equal_approx(Eco.infrastructure(gs, id), 2.0), "a railway is infrastructure (%.1f)" % Eco.infrastructure(gs, id))
	gs.province_buildings[id].erase("railway")


func _test_network() -> void:
	_fresh()
	var pair := _province_with_neighbour("FRA")
	var a: int = pair[0]
	var b: int = pair[1]
	gs.province_buildings[b]["railway"] = 3
	_check(is_equal_approx(Eco.infrastructure(gs, a), 1.5), "a neighbour's railway lifts a province by half (%.1f)" % Eco.infrastructure(gs, a))
	gs.province_buildings[a]["railway"] = 1
	_check(is_equal_approx(Eco.infrastructure(gs, a), 2.5), "on top of its own")
	# A neighbour of another nation does not count.
	gs.province_buildings[b].erase("railway")
	gs.province_buildings[a].erase("railway")
	for n in Mil.neighbors(a):
		if gs.province_owner[n] != "FRA":
			gs.province_buildings[n]["railway"] = 3
	_check(Eco.infrastructure(gs, a) == 0.0, "but a foreign neighbour's does not")


func _test_labels() -> void:
	_fresh()
	var fra = gs.nations["FRA"]
	var entries: Array = Labels.entries(gs, "railway")
	_check(entries.size() == fra.provinces.size(), "every province of the player is written on (%d)" % entries.size())
	var e: Dictionary = entries[0]
	var most: int = load("res://scripts/sim/economy.gd").cfg.buildings.railway.max_level
	_check(e.text == "0/%d" % most and not e.full, "a railway shows its level out of the most (%s)" % e.text)
	gs.province_buildings[e.id]["railway"] = most
	var again: Dictionary = {}
	for x in Labels.entries(gs, "railway"):
		if x.id == e.id:
			again = x
	_check(again.text == "%d/%d" % [most, most] and again.full, "and a full one is marked (%s)" % again.text)
	_check(Labels.entries(gs, "").is_empty(), "nothing is written for no building")


func _test_march() -> void:
	_fresh()
	var pair := _province_with_neighbour("FRA")
	var a: int = pair[0]
	var b: int = pair[1]
	var plain: float = Mil.move_days(gs, "FRA", 15.0, a, b)
	gs.province_buildings[b]["railway"] = 5
	var by_rail: float = Mil.move_days(gs, "FRA", 15.0, a, b)
	_check(by_rail <= plain, "a railway into a province does not slow the march (%.0f days from %.0f)" % [by_rail, plain])
	_check(Mil.hop_cost(gs, "FRA", b) < 1.0, "and makes a supply hop through it cheaper (%.2f)" % Mil.hop_cost(gs, "FRA", b))
