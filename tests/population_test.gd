extends SceneTree
## Headless test of population: the people do not grow (or shrink in peace, or under occupation); soldiers killed
## leave the nation's people in proportion, no province is emptied, a province's base income stays what its people
## made it at the start, and it all survives a save.
## Run: godot --headless --path . -s res://tests/population_test.gd

var _failures := 0
var gs: Node
var Pop


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	Pop = load("res://scripts/sim/population.gd")
	_test_still()
	_test_war()
	_test_save()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.ai_enabled = false


func _year() -> void:
	for i in 12:
		Pop.step_month(gs)


func _test_still() -> void:
	_fresh()
	var rus = gs.nations["RUS"]
	var p0: int = rus.population
	var sum := 0
	for id: int in rus.provinces:
		sum += gs.province_population[id]
	_check(sum == p0, "the nation's total is the sum of its provinces")
	_year()
	_check(rus.population == p0, "a year of peace: Russia's people neither grow nor shrink")
	gs.set_war("GER", "RUS", true)
	var held: int = rus.provinces[0]
	var a: int = gs.province_population[held]
	gs.set_controller(held, "GER")
	_year()
	_check(gs.province_population[held] == a, "nor does a province under occupation")
	gs.set_war("GER", "RUS", false)


func _test_war() -> void:
	_fresh()
	var fra = gs.nations["FRA"]
	var p0: float = fra.population
	var id: int = fra.provinces[0]
	var income0: float = gs.province_base_income[id]
	fra.deaths_month = 400000.0
	Pop.step_month(gs)
	_check(absf((p0 - fra.population) - 400000.0) < 400.0, "400,000 dead leave France's people (%d)" % int(p0 - fra.population))
	_check(fra.deaths_month == 0.0 and is_equal_approx(fra.war_dead, 400000.0), "and are counted as war dead")
	var small: int = fra.provinces[0]
	for p in fra.provinces:
		if gs.province_population[p] < gs.province_population[small]:
			small = p
	_check(gs.province_population[small] >= 1000, "no province is emptied")
	gs.economy_dirty = true
	load("res://scripts/sim/economy.gd").recompute(gs)
	_check(is_equal_approx(gs.province_base_income[id], income0), "a province's base income stays what its people made it at the start")


func _test_save() -> void:
	var SaveGame = load("res://scripts/sim/save_game.gd")
	SaveGame.dir = "user://test_population_saves/"
	_fresh()
	var fra = gs.nations["FRA"]
	fra.deaths_month = 123456.0
	Pop.step_month(gs)
	var id: int = fra.provinces[0]
	var pop: int = gs.province_population[id]
	var frac: float = gs.province_pop_frac[id]
	var path: String = SaveGame.dir + "population.sav"
	_check(gs.save_game(path) == "", "a game saves")
	_fresh()
	_check(gs.load_game(path) == "", "and loads")
	_check(gs.province_population[id] == pop and is_equal_approx(gs.province_pop_frac[id], frac), "the people and the fraction are as saved")
	DirAccess.remove_absolute(path)
