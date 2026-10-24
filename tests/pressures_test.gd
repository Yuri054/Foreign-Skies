extends SceneTree
## Headless test of the daily macro pressures: the labor penalty (1.2 times the share of the
## people under arms), war weariness taking workers (1% for every 100,000 men lost, easing in
## peace) and starvation under a blockade (under 30% of imports through: -30% of the workers
## and war support lost each day).
## Run: godot --headless --path . -s res://tests/pressures_test.gd

var _failures := 0
var gs: Node
var Clock: Node
var Eco


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
	_fresh()
	_test_labor()
	_test_weariness()
	_test_starvation()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.ai_enabled = false


func _test_labor() -> void:
	var ger = gs.nations["GER"]
	var peace: float = Eco.worker_share(ger)
	_check(peace > 0.97 and peace < 1.0, "a peacetime army costs the factories a little (%.3f)" % peace)
	ger.men_in_units = int(ger.population * 0.1)
	_check(is_equal_approx(Eco.worker_share(ger), 1.0 - 1.2 * 0.1), "10%% of the people under arms: output x%.2f" % Eco.worker_share(ger))
	ger.men_in_units = int(ger.population * 0.9)
	_check(is_equal_approx(Eco.worker_share(ger), Eco.cfg.labor.floor), "the loss is floored (%.2f)" % Eco.worker_share(ger))
	_fresh()


func _test_weariness() -> void:
	var ger = gs.nations["GER"]
	var peace: float = Eco.worker_share(ger)
	gs.set_war("GER", "FRA", true)
	ger.war_dead = 300000.0
	Clock.advance_day()
	_check(is_equal_approx(ger.weariness, 0.03), "300,000 dead take 3%% of the workers (%.3f)" % ger.weariness)
	_check(is_equal_approx(Eco.worker_share(ger), peace - 0.03), "which shows in the workers left (%.3f from %.3f)" % [Eco.worker_share(ger), peace])
	ger.war_dead = 1e8
	Clock.advance_day()
	_check(is_equal_approx(ger.weariness, Eco.cfg.weariness.max), "weariness is capped (%.2f)" % ger.weariness)
	gs.set_war("GER", "FRA", false)
	var before: float = ger.weariness
	Clock.advance_day()
	_check(ger.weariness < before, "it eases in peace")
	_fresh()


func _test_starvation() -> void:
	var gbr = gs.nations["GBR"]
	var ws0: float = gbr.war_support
	Clock.advance_day()
	_check(not gbr.starving and gbr.war_support >= ws0 - 0.001, "an unblockaded Britain does not starve")
	gbr.blockade_pinned = 0.8
	gbr.blockade = 0.8
	Clock.advance_day()
	_check(gbr.starving, "with 80%% of its imports cut Britain starves")
	_check(gbr.war_support < ws0, "war support falls (%.2f from %.2f)" % [gbr.war_support, ws0])
	_check(Eco.worker_share(gbr) < 0.75, "the workers left fall by 30%% (x%.2f)" % Eco.worker_share(gbr))
	gbr.blockade_pinned = 0.5
	gbr.blockade = 0.5
	Clock.advance_day()
	_check(not gbr.starving, "half the imports getting through is not starvation")
	_fresh()
