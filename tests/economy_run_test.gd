extends SceneTree
## Headless test of two years of AI play with the economy of money, industry and manpower: no
## treasury runs away, no figure goes bad, nations at peace stay inside their mobilization range, the
## raw materials hold, and the day step stays cheap.
## Run: godot --headless --path . -s res://tests/economy_run_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("Clock")
	var Eco = load("res://scripts/sim/economy.gd")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("ESP")
	gs.ai_enabled = true
	var started := Time.get_ticks_msec()
	for i in 730:
		clock.advance_day()
	var ms_per_day := float(Time.get_ticks_msec() - started) / 730.0
	var worst := 0.0
	var bad := 0
	var out_of_range := 0
	var starved := 0
	for t in gs.nations:
		var n = gs.nations[t]
		worst = minf(worst, n.treasury)
		for k in n.budget:
			if n.budget[k] is float and not is_finite(n.budget[k]):
				bad += 1
		if gs.wars_of(t).is_empty():
			var r: Vector2 = Eco.mobilization_range(gs, n)
			if n.mobilization > r.y + 0.001:
				out_of_range += 1
		if n.starving:
			starved += 1
	_check(worst > -300.0, "no treasury has run away (worst %.0f)" % worst)
	_check(bad == 0, "no budget figure is out of order (%d)" % bad)
	_check(out_of_range == 0, "no nation at peace is mobilized past what it may be (%d are)" % out_of_range)
	_check(starved <= 3, "few nations starve after two years (%d)" % starved)
	for t in ["GER", "FRA", "RUS", "GBR", "AUH", "ITA"]:
		var n = gs.nations[t]
		_check(n.budget.materials.ratio > 0.5 and n.budget.construction_points > 0.0, "%s still has its raw materials and its works (%.0f%%)" % [t, n.budget.materials.ratio * 100.0])
	_check(OS.get_environment("SPEED_TESTS") == "0" or ms_per_day < 90.0, "a day costs under 90 ms over two years (%.0f ms)" % ms_per_day)
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
