extends SceneTree
## Headless test of equipment production lines: nations start on automatic lines that share the
## factories, a line's output grows with its efficiency and costs money and materials, a line
## short of either makes less, changing a line's product starts its efficiency over, the player's
## lines are limited by the free factories, and lines survive a save.
## Run: godot --headless --path . -s res://tests/production_test.gd

var _failures := 0
var gs: Node
var Clock: Node
var Prod
var SetLine
var SetAuto
var Mil
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
	Prod = load("res://scripts/sim/production.gd")
	SetLine = load("res://scripts/sim/set_production_line.gd")
	SetAuto = load("res://scripts/sim/set_production_auto.gd")
	Mil = load("res://scripts/sim/military.gd")
	Eco = load("res://scripts/sim/economy.gd")
	_fresh()
	_test_auto()
	_test_output()
	_test_shortage()
	_test_budget()
	_test_commands()
	_test_shells()
	_test_efficiency()
	_test_save()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.join_calls.clear()
	gs.wars.clear()
	gs.ai_enabled = false


func _line(n, cat: String) -> Dictionary:
	for line in n.production_lines:
		if line.category == cat:
			return line
	return {}


func _test_auto() -> void:
	var ger = gs.nations["GER"]
	Clock.advance_day()
	_check(ger.lines_auto and ger.production_lines.size() == 3, "a nation starts on three automatic lines (arms, artillery, shells)")
	_check(Prod.assigned(ger) == Prod.total_factories(ger) and Prod.free_factories(ger) == 0, "which use all its factories (%d)" % Prod.total_factories(ger))
	_check(Prod.efficiency(_line(ger, "arms")) >= Mil.cfg.equipment.efficiency_cap - 0.001, "running at the efficiency cap")


func _test_output() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	Clock.advance_day()
	var arms_before: float = ger.equipment.arms
	var money_before: float = ger.treasury
	var line = _line(ger, "arms")
	var expected: float = line.factories * Mil.cfg.equipment.categories.arms.output * Eco.law_of(ger).military * Eco.worker_share(ger)
	Clock.advance_day()
	_check(is_equal_approx(_line(ger, "arms").made, expected), "a line makes factories x output (%.2f)" % expected)
	_check(ger.equipment.arms > arms_before, "and adds it to the store")
	_check(ger.treasury >= money_before and _line(ger, "arms").made > 0.0, "and the items cost no money (they cost IC and materials)")
	_check(ger.equipment.shells > 0.0 and _line(ger, "shells").made > 0.0, "the shell line fills the shell stockpile")


func _test_shortage() -> void:
	_fresh()
	var srb = gs.nations["SRB"]
	Clock.advance_day()
	var line = _line(srb, "arms")
	var iron_mult: float = srb.budget.resources.iron.mult
	_check(iron_mult < 1.0 and line.limit == "iron" and line.made < line.factories * Mil.cfg.equipment.categories.arms.output, "Serbia buys no iron (landlocked, no sellers): its line is slowed by it (x%.2f, %s)" % [iron_mult, line.limit])
	_fresh()
	var fra = gs.nations["FRA"]
	fra.treasury = 100.0
	Clock.advance_day()
	line = _line(fra, "arms")
	_check(line.made > 0.0 and fra.equipment_spent == 0.0, "a nation that can trade for its iron runs its line and pays no money")


func _test_budget() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	var b = ger.budget
	_check(b.equipment == 0.0, "the lines cost the treasury nothing: they run on IC and materials")


func _test_shells() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	var gun = null
	for a in gs.armies.values():
		if a.tag == "GER":
			for u in a.units:
				if u.type == "artillery":
					gun = u
					break
		if gun != null:
			break
	_check(gun != null, "Germany has artillery")
	var army = null
	for a in gs.armies.values():
		if gun in a.units:
			army = a
	var full: float = gun.power()
	ger.equipment["shells"] = 100.0
	Mil._burn_shells(gs, army)
	_check(ger.equipment.shells < 100.0 and not gun.shell_starved and is_equal_approx(gun.power(), full), "a day's fighting burns shells from the stockpile")
	ger.equipment["shells"] = 0.0
	Mil._burn_shells(gs, army)
	_check(gun.shell_starved and is_equal_approx(gun.power(), full * (1.0 - Mil.cfg.combat.shell_penalty)), "with none left the guns lose 75%% of their attack (%.2f of %.2f)" % [gun.power(), full])


func _test_commands() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	Clock.advance_day()
	var arms = _line(ger, "arms")
	var total = Prod.total_factories(ger)
	_check(not gs.issue(SetLine.new("GER", 0, "arms", 1)), "no new line without a free factory")
	_check(gs.issue(SetLine.new("GER", arms.id, "arms", arms.factories - 2)) and not ger.lines_auto, "a line can be cut, and that ends automatic production")
	_check(Prod.free_factories(ger) == 2, "freeing its factories")
	_check(gs.issue(SetLine.new("GER", 0, "artillery", 2)) and ger.production_lines.size() == 4, "which a new line can take")
	_check(not gs.issue(SetLine.new("GER", arms.id, "arms", arms.factories + 1)), "a line cannot grow beyond the free factories")
	Clock.advance_day()
	_check(Prod.assigned(ger) == total, "the assignment holds from day to day")
	_check(gs.issue(SetAuto.new("GER", true)) and ger.production_lines.size() == 3, "automatic production folds the lines again")


func _test_efficiency() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	Clock.advance_day()
	var arms = _line(ger, "arms")
	gs.issue(SetLine.new("GER", arms.id, "artillery", arms.factories))
	var line = _line(ger, "artillery")
	_check(is_equal_approx(Prod.efficiency(line), Mil.cfg.equipment.efficiency_start), "a line that changes product keeps 20%% of its efficiency, but not below the start (%.3f)" % Prod.efficiency(line))
	var at_switch: float = Prod.efficiency(line)
	for i in 30:
		Clock.advance_day()
	var later: float = Prod.efficiency(_line(ger, "artillery"))
	_check(later > at_switch and later < Mil.cfg.equipment.efficiency_cap, "and climbs as it runs (%.2f after 30 days)" % later)
	for i in 120:
		Clock.advance_day()
	_check(Prod.efficiency(_line(ger, "artillery")) >= Mil.cfg.equipment.efficiency_cap - 0.001, "to the cap, 50%")


func _test_save() -> void:
	var SaveGame = load("res://scripts/sim/save_game.gd")
	SaveGame.dir = "user://test_production_saves/"
	_fresh()
	var ger = gs.nations["GER"]
	Clock.advance_day()
	var arms = _line(ger, "arms")
	gs.issue(SetLine.new("GER", arms.id, "artillery", arms.factories))
	var path: String = SaveGame.dir + "production.sav"
	_check(gs.save_game(path) == "", "a game with lines saves")
	_fresh()
	_check(gs.load_game(path) == "", "and loads")
	var back = gs.nations["GER"]
	_check(not back.lines_auto and back.production_lines.size() == 3 and _line(back, "artillery").factories > 0, "the player's lines are as saved")
	DirAccess.remove_absolute(path)
