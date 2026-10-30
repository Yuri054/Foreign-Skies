extends SceneTree
## Headless test of the January 1900 scenario: it loads with the 1900 map and treaties, starts at
## peace, and the AI plays five years of it with sane finances and no collapse.
## Run: godot --headless --path . -s res://tests/scenario_1900_test.gd

var _failures := 0
var gs: Node
var clock: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	gs.load_scenario("res://data/scenarios/jan_1900/")
	gs.ai_enabled = true
	gs.set_player("ESP")
	_check(clock.year == 1900 and clock.month == 1, "the clock starts in January 1900")
	_check(gs.wars.is_empty(), "Europe starts at peace")
	_check(gs.nations["ALB"].provinces.is_empty() and gs.nations["OTT"].provinces.size() > 30, "Albania and Macedonia are Ottoman land in 1900")
	_check(gs.nations["SRB"].provinces.size() < 20 and gs.nations["BUL"].provinces.size() >= 24, "Serbia is the small kingdom of 1900")
	_check(not gs.get_player().budget.is_empty(), "the economy has been worked out")
	var declared := 0
	gs.war_changed.connect(func(_a: String, _b: String, at_war: bool) -> void: declared += 1 if at_war else 0)
	var collapsed: Array = []
	gs.nation_collapsed.connect(func(tag: String, _m: int) -> void: collapsed.append(tag))
	var worst := 0.0
	for day in 365 * 5:
		clock.advance_day()
		if day % 30 == 0:
			for tag in ["GER", "FRA", "GBR", "RUS", "AUH", "ITA"]:
				var n = gs.nations[tag]
				worst = minf(worst, n.treasury / maxf(12.0 * n.budget.income, 1.0))
	print("wars declared in five years: ", declared, "; worst treasury in years of income: ", worst)
	_check(collapsed.is_empty(), "no nation collapses in five years (%s)" % str(collapsed))
	_check(worst > -1.5, "no great power sinks past a year and a half of income in debt (%.2f)" % worst)
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
