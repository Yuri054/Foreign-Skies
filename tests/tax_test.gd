extends SceneTree
## Headless test of what heavy taxes cost: nothing at the default rate, growth and the level war
## support settles at fall as the rate climbs, and war support wears away faster at war.
## Run: godot --headless --path . -s res://tests/tax_test.gd

var _failures := 0
var gs: Node
var Eco
var WS
var Policy
var Clock: Node


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
	WS = load("res://scripts/sim/war_support.gd")
	Policy = load("res://scripts/sim/set_economy_policy.gd")
	_fresh()
	_test_strain()
	_test_growth()
	_test_support()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.ai_enabled = false


func _test_strain() -> void:
	var fra = gs.nations["FRA"]
	fra.tax_rate = Eco.cfg.default_tax_rate
	_check(Eco.tax_strain(fra) == 0.0, "no strain at the default rate")
	fra.tax_rate = Eco.cfg.min_tax_rate
	_check(Eco.tax_strain(fra) == 0.0, "nor below it")
	fra.tax_rate = Eco.cfg.max_tax_rate
	_check(is_equal_approx(Eco.tax_strain(fra), 1.0), "full strain at the top rate")
	fra.tax_rate = (Eco.cfg.default_tax_rate + Eco.cfg.max_tax_rate) / 2.0
	_check(is_equal_approx(Eco.tax_strain(fra), 0.25), "a quarter of it half way up (squared)")


func _test_growth() -> void:
	_fresh()
	var fra = gs.nations["FRA"]
	var ger = gs.nations["GER"]
	ger.tax_rate = Eco.cfg.default_tax_rate
	fra.tax_rate = Eco.cfg.max_tax_rate
	gs.issue(Policy.new("FRA", "tax_rate", Eco.cfg.max_tax_rate))
	var dev_fra: float = fra.development
	var dev_ger: float = ger.development
	for i in 12:
		Eco.step_month(gs)
	var g_fra: float = fra.development / dev_fra - 1.0
	var g_ger: float = ger.development / dev_ger - 1.0
	_check(g_ger > 0.01, "a lightly taxed economy grows (%.3f in a year)" % g_ger)
	_check(g_fra < 0.0 and g_fra < g_ger - 0.03, "a heavily taxed one shrinks (%.3f in a year)" % g_fra)


func _test_support() -> void:
	_fresh()
	var fra = gs.nations["FRA"]
	var ger = gs.nations["GER"]
	fra.war_support = fra.war_support_base
	ger.war_support = ger.war_support_base
	fra.tax_rate = Eco.cfg.max_tax_rate
	for i in 24:
		WS.step_month(gs)
	var drop: float = fra.war_support_base - fra.war_support
	_check(is_equal_approx(drop, Eco.cfg.tax_strain.support_penalty), "in peace war support settles lower under heavy taxes (%.1f)" % drop)
	_check(is_equal_approx(ger.war_support, ger.war_support_base), "and stays at its level under ordinary ones")
	gs.set_war("GER", "ITA", true)
	gs.set_war("FRA", "ESP", true)
	fra.war_support = 60.0
	ger.war_support = 60.0
	ger.tax_rate = Eco.cfg.default_tax_rate
	WS.step_month(gs)
	_check(fra.war_support < ger.war_support - 0.5, "at war heavy taxes wear support away faster (%.1f against %.1f)" % [fra.war_support, ger.war_support])
