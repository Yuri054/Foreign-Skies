extends SceneTree
## Headless test of infrastructure: railway levels (and half the best neighbour's) add building
## slots, factories can use them, the Construction map mode writes slots used out of slots on the
## provinces, and the AI sees a railway as worth building where the slots are full.
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
	_test_slots()
	_test_network()
	_test_build()
	_test_labels()
	_test_ai()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.ai_enabled = false
	gs.set_player("FRA")


func _province_with_neighbour(tag: String) -> Array:
	for id in gs.nations[tag].provinces:
		for n in Mil.neighbors(id):
			if gs.province_owner[n] == tag:
				return [id, n]
	return [0, 0]


func _test_slots() -> void:
	var pair := _province_with_neighbour("FRA")
	var id: int = pair[0]
	_check(Eco.infrastructure(gs, id) == 0.0, "nothing has a railway at the start")
	var base: int = Eco.slots_of(gs, id)
	gs.province_buildings[id]["railway"] = 2
	_check(Eco.infrastructure(gs, id) >= 2.0, "a railway is infrastructure (%.1f)" % Eco.infrastructure(gs, id))
	_check(Eco.slots_of(gs, id) == base + int(Eco.infrastructure(gs, id)), "and every point of it is a slot (%d to %d)" % [base, Eco.slots_of(gs, id)])
	gs.province_buildings[id].erase("railway")
	_check(Eco.slots_of(gs, id) == base, "without it the slots are as they were")


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


func _test_build() -> void:
	_fresh()
	var fra = gs.nations["FRA"]
	fra.treasury = 10000.0
	fra.stock.iron = 1e7
	fra.stock.wood = 1e7
	fra.stock.coal = 1e7
	var id: int = fra.provinces[0]
	# Fill the province.
	while Eco.slots_used(gs, id) < Eco.slots_of(gs, id):
		gs.province_buildings[id]["factory"] = gs.province_buildings[id].get("factory", 0) + 1
	_check(Eco.build_problem(gs, "FRA", id, "factory") == "No free slot", "a full province has no slot for a factory")
	gs.province_buildings[id]["railway"] = 1
	_check(Eco.build_problem(gs, "FRA", id, "factory") == "", "a railway there makes room")


func _test_labels() -> void:
	_fresh()
	var entries: Array = Labels.entries(gs, "factory")
	var fra = gs.nations["FRA"]
	_check(entries.size() == fra.provinces.size(), "every province of the player is written on (%d)" % entries.size())
	var e: Dictionary = entries[0]
	_check(e.text == "%d/%d" % [Eco.slots_used(gs, e.id), Eco.slots_of(gs, e.id)], "with slots used out of slots (%s)" % e.text)
	var rail: Array = Labels.entries(gs, "railway")
	_check(rail[0].text == "0/5" and not rail[0].full, "a railway shows its level out of the most (%s)" % rail[0].text)
	_check(Labels.entries(gs, "").is_empty(), "nothing is written for no building")


func _test_ai() -> void:
	_fresh()
	var AIB = load("res://scripts/ai/ai_budget.gd")
	var fra = gs.nations["FRA"]
	var id: int = fra.provinces[0]
	var plan: Dictionary = Eco.build_plan(gs, id, "railway")
	var open_value: float = AIB.build_return(gs, "FRA", id, "railway", plan)
	while Eco.slots_used(gs, id) < Eco.slots_of(gs, id):
		gs.province_buildings[id]["factory"] = gs.province_buildings[id].get("factory", 0) + 1
	var full_value: float = AIB.build_return(gs, "FRA", id, "railway", plan)
	_check(full_value > open_value, "the AI values a railway more where the slots are full (%.3f against %.3f)" % [full_value, open_value])
