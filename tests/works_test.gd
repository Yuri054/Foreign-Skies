extends SceneTree
## Headless test of the province works in the military: trenches and heavy fortifications add
## defense in the owner's province and take damage off shelling and assault; railways cut supply
## hops (more with each level) and speed movement, but only while the nation has coal to run them.
## Run: godot --headless --path . -s res://tests/works_test.gd

var _failures := 0
var gs: Node
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
	Mil = load("res://scripts/sim/military.gd")
	gs.ai_enabled = false
	_test_defense()
	_test_railway()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _army_of(tag: String):
	for a in gs.armies.values():
		if a.tag == tag and gs.province_owner[a.province] == tag:
			return a
	return null


func _test_defense() -> void:
	var a = _army_of("FRA")
	_check(a != null, "France has an army at home")
	var base: float = Mil.defense_multiplier(a)
	var built: Dictionary = gs.province_buildings[a.province]
	built["trench"] = 4
	var dug: float = Mil.defense_multiplier(a)
	_check(dug > base, "four trench levels raise the defense (%.2f to %.2f)" % [base, dug])
	built["fortification"] = 2
	var forted: float = Mil.defense_multiplier(a)
	_check(forted > dug, "heavy fortifications raise it more (%.2f)" % forted)
	var b: Dictionary = load("res://scripts/sim/economy.gd").cfg.buildings
	_check(is_equal_approx(Mil.works_reduction(gs, a, 1.0), 4.0 * float(b.trench.shell_reduction)), "each trench level takes its share off shelling (%.2f for four)" % Mil.works_reduction(gs, a, 1.0))
	_check(is_equal_approx(Mil.works_reduction(gs, a, 0.0), 2.0 * float(b.fortification.hard_reduction)), "each fort level its share off assault (%.2f for two)" % Mil.works_reduction(gs, a, 0.0))
	var other: String = "GER" if a.tag != "GER" else "FRA"
	var foreign = _army_of(other)
	foreign.province = a.province
	_check(is_equal_approx(Mil.defense_multiplier(foreign), Mil.defense_multiplier(a) - Mil.works_defense(gs, a) + Mil.works_defense(gs, foreign)) and Mil.works_defense(gs, foreign) == 0.0, "an enemy that holds the ground gets nothing from the works")
	built.erase("trench")
	built.erase("fortification")


func _test_railway() -> void:
	var fra = gs.nations["FRA"]
	var id: int = fra.provinces[0]
	var built: Dictionary = gs.province_buildings[id]
	built["railway"] = 0
	_check(Mil.hop_cost(gs, "FRA", id) == 1.0, "no railway, a full hop")
	built["railway"] = 1
	var one: float = Mil.hop_cost(gs, "FRA", id)
	built["railway"] = 5
	var five: float = Mil.hop_cost(gs, "FRA", id)
	_check(is_equal_approx(one, Mil.cfg.supply.railway_hop_cost) and five < one, "each level makes a hop cheaper (%.2f, %.2f)" % [one, five])
	built.erase("railway")
