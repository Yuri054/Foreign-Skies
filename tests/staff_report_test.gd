extends SceneTree
## Headless test for the battle staff report and the event advisor line: the forecast follows the rules the fighting uses (and
## changes nothing), a "what if" moves it the right way, the report reads out of it for a battle the player is in, and an
## event option names its largest effect.
## Run: godot --headless --path . -s res://tests/staff_report_test.gd

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
	load("res://scripts/ui/ui_settings.gd").path = "user://test_settings.cfg"
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	var M = load("res://scripts/sim/military.gd")
	var P = load("res://scripts/sim/pressure.gd")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	gs.load_scenario("res://data/scenarios/jan_1900/")
	gs.wars.clear()
	gs.join_calls.clear()
	gs.set_player("GER")
	gs.ai_enabled = false
	await process_frame

	# A German and a French army meet.
	var ger = null
	var fra = null
	for a in gs.armies.values():
		if a.tag == "GER" and ger == null and not a.embarked():
			ger = a
		if a.tag == "FRA" and fra == null and not a.embarked():
			fra = a
	fra.province = ger.province
	ger.attacking = true
	gs.set_war("GER", "FRA", true, "none")
	var before := [ger.men(), fra.men()]
	var f: Dictionary = M.battle_forecast(gs, ger.province)
	_check(f.ok and f.sides.has("GER") and f.sides.has("FRA"), "a forecast is made for a province where armies of two nations at war meet")
	_check(f.sides.GER.loss > 0.0 and f.sides.FRA.loss > 0.0 and f.sides.GER.rate > 0.0, "each side is expected to lose men (%.0f and %.0f a day)" % [f.sides.GER.loss, f.sides.FRA.loss])
	_check(ger.men() == before[0] and fra.men() == before[1], "the forecast changes nothing")
	var stronger: Dictionary = M.battle_forecast(gs, ger.province, {"power": {"GER": 1.25}})
	_check(stronger.sides.FRA.loss > f.sides.FRA.loss and is_equal_approx(stronger.sides.GER.loss, f.sides.GER.loss), "more power for Germany raises France's losses and leaves its own")
	var weaker: Dictionary = M.battle_forecast(gs, ger.province, {"power": {"FRA": 0.75}})
	_check(weaker.sides.GER.loss < f.sides.GER.loss, "a weaker enemy costs Germany less")
	var dug: Dictionary = M.battle_forecast(gs, ger.province, {"entrench": {"FRA": 2}})
	_check(dug.sides.FRA.loss < f.sides.FRA.loss, "trenches cut the defender's losses")
	_check(not M.battle_forecast(gs, M.neighbors(ger.province)[0]).ok, "there is no forecast where none are fighting")

	# The report, from a real battle.
	clock.advance_day()
	gs.finish_day()
	var battle: Dictionary = gs.battle_at(ger.province)
	_check(not battle.is_empty() and battle.active, "a battle begins")
	var screen: Node = get_first_node_in_group("battle_screen")
	var report: String = screen.staff_report(battle)
	_check(report.begins_with("Staff report:") and report.contains("What would change it"), "the report says how it goes and what would change it: %s" % report.replace("\n", " | "))
	_check(report.contains("quarter more fighting power") and report.contains("quarter weaker"), "with what-ifs")
	gs.set_player("ESP")
	_check(screen.staff_report(battle) == "", "a player who is not in the battle gets no report")
	gs.set_player("GER")
	screen.open_battle(battle.id)
	await process_frame
	_check(screen._staff.visible and screen._staff.text.begins_with("Staff report"), "the battle screen shows it")

	# The advisor line.
	var option := {"label": "x", "text": "y", "effects": [{"tension": -12}, {"prestige": ["a", 2]}, {"treasury": ["a", -1]}]}
	var roles := {"a": "GER", "b": "FRA"}
	_check(P.advisor_line(gs, option, roles) == "Tension -12", "an option's largest effect is named: %s" % P.advisor_line(gs, option, roles))
	var war_option := {"effects": [{"war": ["a", "b"]}, {"tension": 5}]}
	_check(P.advisor_line(gs, war_option, roles).begins_with("War with"), "a war outweighs the rest: %s" % P.advisor_line(gs, war_option, roles))
	_check(P.advisor_line(gs, {"effects": []}, roles) == "", "an option with no effect has none")
	_check(P.advisor_line(gs, {"effects": [], "tip": "Gives up land.\nMore"}, roles) == "Gives up land.", "an option with its own account uses its first line")
	var real: Dictionary = {}
	for e: Dictionary in P.events:
		if e.id == "concert":
			real = e
	if not real.is_empty():
		_check(P.advisor_line(gs, real.options[0], {"a": "GER"}) != "", "the shipped events have advice too (%s)" % P.advisor_line(gs, real.options[0], {"a": "GER"}))

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
