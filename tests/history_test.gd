extends SceneTree
## Plays the July 1914 scenario forward with nobody at the controls and checks that history
## unfolds from the rules alone: the Austro-Serbian war spreads through the alliances into a
## general war by mid-August, Britain enters over Belgium, Italy and the neutrals stay out,
## the war runs down on its own, and a world without the starting war stays at peace.
## Run: godot --headless --path . -s res://tests/history_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var clock: Node
var D


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	gs = root.get_node("GameState")
	gs.ai_enabled = true  # the AI starts the war on Belgium (it is switched off for the run-down below)
	clock = root.get_node("Clock")
	D = load("res://scripts/sim/diplomacy.gd")

	_test_chain()
	_test_quiet_world()

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _test_chain() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("ESP")  # a bystander: nobody at the controls of the great powers
	var started := {}
	gs.war_changed.connect(func(a: String, b: String, at_war: bool) -> void:
		if at_war:
			var war = gs.war_between(a, b)
			started[D.pair_key(a, b)] = {"day": clock.days_elapsed, "month": clock.month, "year": clock.year, "cb": war.casus_belli}
	)
	_check(gs.wars.size() == 1 and gs.at_war("AUH", "SRB"), "on 28 July only Austria-Hungary and Serbia are at war")
	for i in 30:
		clock.advance_day()
	var need := ["GER|SRB", "GER|RUS", "FRA|GER", "BEL|GER", "GBR|GER"]
	for key in need:
		_check(started.has(key), "%s goes to war" % key)
	var day := func(key: String) -> int: return started[key].day if started.has(key) else 9999
	_check(day.call("GER|SRB") <= day.call("GER|RUS") and day.call("GER|RUS") <= day.call("FRA|GER"), "Germany and Russia go in before France")
	_check(day.call("FRA|GER") <= day.call("BEL|GER") and day.call("BEL|GER") < day.call("GBR|GER"), "Germany then marches on Belgium, and Britain follows")
	_check(started.get("BEL|GER", {}).get("cb", "") == "none" and started.get("GBR|GER", {}).get("cb", "") == "guarantee_defence", "Germany has no justification, Britain defends a guarantee")
	_check(started.has("GBR|GER") and started["GBR|GER"].month == 8 and started["GBR|GER"].year == 1914, "Britain is at war in August 1914")
	_check(started.has("GBR|GER") and started["GBR|GER"].day <= 20, "within three weeks of the start (day %d)" % started.get("GBR|GER", {}).get("day", -1))
	for tag in ["ITA", "ESP", "NED", "SUI", "DEN", "POR", "ROM", "BUL", "GRE", "OTT", "ALB", "LUX"]:
		_check(gs.wars_of(tag).is_empty(), "%s stays out" % tag)
	_check(gs.nations["GER"].prestige <= -15.0, "Germany paid in prestige for the invasion (%d)" % gs.nations["GER"].prestige)
	_check(D.relation(gs, "GBR", "GER") < -30.0, "and in Britain's opinion")

	gs.ai_enabled = false
	# Nobody fights, so the war runs down: the AI's urge for peace (debt, weariness, time at war) ends
	# the wars one after the other.
	for i in 480:
		clock.advance_day()
		if gs.wars.is_empty():
			break
	_check(gs.wars.is_empty(), "by day %d every war has ended" % clock.days_elapsed)
	var end_of := func(a: String, b: String) -> int:
		for w in gs.war_history:
			if (w.a == a and w.b == b) or (w.a == b and w.b == a):
				return w.end_day
		return 99999
	# Which of them gives up first depends on how the first month went, which tension's push changes; each does within the year.
	_check(end_of.call("RUS", "GER") < 99999 and end_of.call("FRA", "GER") < 99999, "Russia and France each leave the war against Germany")
	_check(clock.year == 1915 or clock.year == 1914, "before the end of 1915")
	for tag: String in gs.nations:
		if gs.nations[tag].mobilization > 0.0 and gs.wars_of(tag).is_empty():
			clock.advance_day()
	for i in 90:
		clock.advance_day()
	var calm := true
	for tag: String in gs.nations:
		if gs.nations[tag].mobilization > 0.0:
			calm = false
	_check(calm, "and after the peace the armies demobilize")


func _test_quiet_world() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.wars.clear()
	gs.join_calls.clear()
	gs.set_player("ESP")
	var wars := [0]
	gs.war_changed.connect(func(_a: String, _b: String, at_war: bool) -> void:
		if at_war:
			wars[0] += 1
	)
	for i in 400:
		clock.advance_day()
	_check(wars[0] == 0, "with no war at the start, none breaks out in over a year")
	var calm := true
	for tag: String in gs.nations:
		if gs.nations[tag].mobilization > 0.0:
			calm = false
	_check(calm and gs.alarms.is_empty() and gs.mobilization_calls.is_empty(), "nobody mobilizes and nobody is alarmed")
	_check(gs.casus_belli.is_empty() and gs.treaties.size() > 0, "no casus belli appears and the treaty web is intact")
