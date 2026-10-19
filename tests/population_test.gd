extends SceneTree
## Headless test of population: provinces grow by their nation's yearly rate, a famine and an
## occupation shrink them, soldiers killed leave the people in proportion, small provinces still
## grow (the fraction is kept), and it all survives a save.
## Run: godot --headless --path . -s res://tests/population_test.gd

var _failures := 0
var gs: Node
var Eco
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
	Eco = load("res://scripts/sim/economy.gd")
	Pop = load("res://scripts/sim/population.gd")
	_fresh()
	_test_growth()
	_test_famine()
	_test_war()
	_test_small()
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


func _test_growth() -> void:
	var rus = gs.nations["RUS"]
	var fra = gs.nations["FRA"]
	rus.budget.food_shortage = 0.0
	fra.budget.food_shortage = 0.0
	var r0: float = rus.population
	var f0: float = fra.population
	_year()
	var gr: float = rus.population / r0 - 1.0
	var gf: float = fra.population / f0 - 1.0
	_check(absf(gr - 0.015) < 0.002, "Russia grows about 1.5%% a year (%.4f)" % gr)
	_check(absf(gf - 0.002) < 0.001 and gr > gf * 4.0, "France hardly at all (%.4f)" % gf)
	var sum := 0
	for id in rus.provinces:
		sum += gs.province_population[id]
	_check(sum == rus.population, "the nation's total is the sum of its provinces")


func _test_famine() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	ger.budget.food_shortage = 1.0
	var g0: float = ger.population
	_year()
	var g: float = ger.population / g0 - 1.0
	_check(g < 0.0 and absf(g - (0.012 - 0.05)) < 0.003, "a full famine shrinks Germany (%.4f)" % g)
	_check(Pop.growth_rate(ger) < 0.0, "and the nation window shows it as a loss")


func _test_war() -> void:
	_fresh()
	var fra = gs.nations["FRA"]
	var ger = gs.nations["GER"]
	fra.pop_growth = 0.0
	ger.pop_growth = 0.0
	fra.budget.food_shortage = 0.0
	ger.budget.food_shortage = 0.0
	var p0: float = fra.population
	fra.deaths_month = 400000.0
	Pop.step_month(gs)
	_check(absf((p0 - fra.population) - 400000.0) < 400.0, "400,000 dead leave France's people (%d)" % int(p0 - fra.population))
	_check(fra.deaths_month == 0.0 and is_equal_approx(fra.war_dead, 400000.0), "and are counted as war dead")
	var big: int = fra.provinces[0]
	var small: int = fra.provinces[0]
	for id in fra.provinces:
		if gs.province_population[id] > gs.province_population[big]:
			big = id
		if gs.province_population[id] < gs.province_population[small]:
			small = id
	_check(gs.province_population[big] > 0 and gs.province_population[small] >= 1000, "no province is emptied")
	# Occupation.
	_fresh()
	fra = gs.nations["FRA"]
	fra.pop_growth = 0.0
	fra.budget.food_shortage = 0.0
	gs.set_war("FRA", "GER", true)
	var held: int = fra.provinces[0]
	var kept: int = fra.provinces[1]
	gs.set_controller(held, "GER")
	var a: int = gs.province_population[held]
	var b: int = gs.province_population[kept]
	_year()
	_check(gs.province_population[held] < a and gs.province_population[kept] == b, "an occupied province shrinks, the rest do not")


func _test_small() -> void:
	_fresh()
	var lux = gs.nations["LUX"]
	lux.budget.food_shortage = 0.0
	var id: int = lux.provinces[0]
	var p0: int = gs.province_population[id]
	_year()
	_check(gs.province_population[id] > p0, "a small province grows (%d to %d)" % [p0, gs.province_population[id]])
	# A tiny province gaining a quarter of a person a month still gains one in four months.
	gs.province_population[id] = 1500
	gs.province_pop_frac[id] = 0.0
	lux.pop_growth = 0.002
	var tiny0 := 1500
	_year()
	var tiny: int = gs.province_population[id]
	_check(tiny >= tiny0 + 2 and tiny <= tiny0 + 4, "the fraction is kept: 1500 people at 0.2%% grow to %d in a year" % tiny)
	var smallest := 0
	for pid in range(1, gs.province_population.size()):
		if smallest == 0 or gs.province_population[pid] < gs.province_population[smallest]:
			smallest = pid
	_check(gs.province_population[smallest] >= 1000, "none is under the minimum")


func _test_save() -> void:
	var SaveGame = load("res://scripts/sim/save_game.gd")
	SaveGame.dir = "user://test_population_saves/"
	_fresh()
	gs.nations["RUS"].budget.food_shortage = 0.0
	_year()
	var id: int = gs.nations["RUS"].provinces[0]
	var pop: int = gs.province_population[id]
	var frac: float = gs.province_pop_frac[id]
	var path: String = SaveGame.dir + "population.sav"
	_check(gs.save_game(path) == "", "a game saves")
	_fresh()
	_check(gs.load_game(path) == "", "and loads")
	_check(gs.province_population[id] == pop and is_equal_approx(gs.province_pop_frac[id], frac), "the people and the fraction are as saved")
	DirAccess.remove_absolute(path)
