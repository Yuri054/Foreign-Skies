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
	_check(ger.lines_auto and ger.production_lines.size() == 2, "a nation starts on two automatic lines")
	_check(Prod.assigned(ger) == Prod.total_factories(ger) and Prod.free_factories(ger) == 0, "which use all its factories (%d)" % Prod.total_factories(ger))
	_check(Prod.efficiency(_line(ger, "arms")) >= 0.999, "running at full efficiency")


func _test_output() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	Clock.advance_day()
	var arms_before: float = ger.equipment.arms
	var money_before: float = ger.treasury
	var line = _line(ger, "arms")
	var expected: float = line.factories * Mil.cfg.equipment.categories.arms.output * Eco.law_of(ger).military
	Clock.advance_day()
	_check(is_equal_approx(_line(ger, "arms").made, expected), "a line makes factories x output (%.2f)" % expected)
	_check(ger.equipment.arms > arms_before, "and adds it to the store")
	_check(ger.treasury < money_before + ger.budget.net / 365.0 + 1.0 and _line(ger, "arms").made > 0.0, "and the items cost money")


func _test_shortage() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	ger.treasury = 0.0
	Clock.advance_day()
	var line = _line(ger, "arms")
	_check(line.made < line.factories * Mil.cfg.equipment.categories.arms.output and line.limit == "money", "with no money a line makes less (%.3f, limited by %s)" % [line.made, line.limit])
	_fresh()
	var srb = gs.nations["SRB"]
	Clock.advance_day()
	line = _line(srb, "arms")
	var iron_mult: float = srb.budget.resources.iron.mult
	_check(iron_mult < 1.0 and line.limit == "iron" and line.made < line.factories * Mil.cfg.equipment.categories.arms.output, "Serbia buys no iron (landlocked, no sellers): its line is slowed by it (x%.2f, %s)" % [iron_mult, line.limit])
	_fresh()
	var fra = gs.nations["FRA"]
	fra.treasury = 100.0
	Clock.advance_day()
	line = _line(fra, "arms")
	_check(line.made > 0.0 and fra.equipment_spent > 0.0, "a nation that can trade for its iron runs its line and pays for the items (%.4f paid)" % fra.equipment_spent)


func _test_budget() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	var b = ger.budget
	_check(b.equipment > 0.0 and b.expenses > b.equipment, "the budget counts the lines' spending as an expense (%.1f a year)" % b.equipment)
	var arms = _line(ger, "arms")
	var expected: float = (arms.factories * Mil.cfg.equipment.categories.arms.output * Mil.cfg.equipment.categories.arms.cost.money + _line(ger, "artillery").factories * Mil.cfg.equipment.categories.artillery.output * Mil.cfg.equipment.categories.artillery.cost.money) * 365.0 * Eco.law_of(ger).military * Prod.paid_share(ger)
	_check(is_equal_approx(b.equipment, expected), "which is what the lines cost at full tilt (%.1f)" % expected)


func _test_commands() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	Clock.advance_day()
	var arms = _line(ger, "arms")
	var total = Prod.total_factories(ger)
	_check(not gs.issue(SetLine.new("GER", 0, "arms", 1)), "no new line without a free factory")
	_check(gs.issue(SetLine.new("GER", arms.id, "arms", arms.factories - 2)) and not ger.lines_auto, "a line can be cut, and that ends automatic production")
	_check(Prod.free_factories(ger) == 2, "freeing its factories")
	_check(gs.issue(SetLine.new("GER", 0, "artillery", 2)) and ger.production_lines.size() == 3, "which a new line can take")
	_check(not gs.issue(SetLine.new("GER", arms.id, "arms", arms.factories + 1)), "a line cannot grow beyond the free factories")
	Clock.advance_day()
	_check(Prod.assigned(ger) == total, "the assignment holds from day to day")
	_check(gs.issue(SetAuto.new("GER", true)) and ger.production_lines.size() == 2, "automatic production folds the lines again")


func _test_efficiency() -> void:
	_fresh()
	var ger = gs.nations["GER"]
	Clock.advance_day()
	var arms = _line(ger, "arms")
	gs.issue(SetLine.new("GER", arms.id, "artillery", arms.factories))
	var line = _line(ger, "artillery")
	_check(is_equal_approx(Prod.efficiency(line), Mil.cfg.equipment.efficiency_start), "a line that changes product starts over (%.2f)" % Prod.efficiency(line))
	for i in 30:
		Clock.advance_day()
	var later: float = Prod.efficiency(_line(ger, "artillery"))
	_check(later > Mil.cfg.equipment.efficiency_start and later < 1.0, "and climbs as it runs (%.2f after 30 days)" % later)
	for i in 70:
		Clock.advance_day()
	_check(Prod.efficiency(_line(ger, "artillery")) >= 0.999, "to full efficiency")


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
	_check(not back.lines_auto and back.production_lines.size() == 2 and _line(back, "artillery").factories > 0, "the player's lines are as saved")
	DirAccess.remove_absolute(path)
