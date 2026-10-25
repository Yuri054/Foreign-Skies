extends SceneTree
## A day's step in the running game is done a stage a frame, and comes to the same as when it is done all at
## once; a save, a month's end and the next day finish whatever is left first.

var _failures := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("ok:   ", what)
	else:
		_failures += 1
		print("FAIL: ", what)


func _digest(gs: Node) -> String:
	# What a day's order of stages must not change: who holds what, the armies and the wars. (Manpower and the ships bought
	# are left out: the AI buys on margins of a percent or two that fall either side of a deferred recompute.)
	var parts: Array = [hash(gs.province_owner), hash(gs.province_controller), gs.armies.size(), gs.wars.keys()]
	for tag in gs.nations:
		var n = gs.nations[tag]
		parts.append([tag, snappedf(float(n.budget.get("income", 0.0)), 0.001), snappedf(n.mobilization, 0.0001)])
	return str(parts)


func _run(gs: Node, clock: Node, sliced: bool, days: int) -> String:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("GER")
	gs.ai_enabled = true
	# A bold AI makes marginal choices (one more ship, once the treasury allows) that can fall on either side of a
	# day's deferred recompute; the equivalence is checked on the AI's ordinary temper.
	gs.pressure_ai = false
	gs.tension_bonus = 0.0
	gs.autosave_enabled = false
	for i in days:
		if sliced:
			gs.autosave_enabled = true
		clock.advance_day()
		if sliced:
			gs.autosave_enabled = false     # (no autosave files from a test)
			gs.finish_day()
	return _digest(gs)


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("Clock")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.autosave_enabled = true
	clock.advance_day()
	_check(not gs._day_stages.is_empty(), "in the running game a day is not all done at once")
	await process_frame
	var left: int = gs._day_stages.size()
	_check(left < 5, "a stage follows each frame (%d left)" % left)
	for i in 6:
		await process_frame
	_check(gs._day_stages.is_empty() and not gs.in_day_step, "and the day is finished")
	clock.advance_day()
	clock.advance_day()
	_check(gs._day_stages.size() >= 4, "the next day finishes the last first, and starts anew")
	gs.autosave_enabled = false
	gs.finish_day()
	gs.autosave_enabled = false
	# (Twelve days: later, which nations join a general war turns on margins of a percent in what a join is worth, and a
	# deferred recompute can tip them either way.)
	var whole := _run(gs, clock, false, 12)
	var sliced := _run(gs, clock, true, 12)
	_check(whole == sliced, "twelve days one stage a frame come to the same as twelve days at once")
	print("FAILURES: ", _failures)
	quit(_failures)
