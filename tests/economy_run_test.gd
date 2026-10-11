extends SceneTree
## Headless test of two years of AI play with the reworked economy: equipment keeps being made
## (also by nations that import their iron), armies stay equipped, no treasury runs away, the
## laws come down after the wars, and the day step stays cheap.
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
	var Mil = load("res://scripts/sim/military.gd")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("ESP")
	gs.ai_enabled = true
	var powers := ["GER", "FRA", "RUS", "GBR", "AUH", "ITA"]
	var store_mid := {}
	var started := Time.get_ticks_msec()
	for i in 730:
		clock.advance_day()
		if i == 399:
			for t in powers:
				store_mid[t] = gs.nations[t].equipment.arms + gs.nations[t].equipment.artillery
	var ms_per_day := float(Time.get_ticks_msec() - started) / 730.0
	var worst := 0.0
	var laws := 0
	for t in gs.nations:
		var n = gs.nations[t]
		worst = minf(worst, n.treasury)
		if n.economy_law != "civilian" and gs.wars_of(t).is_empty():
			laws += 1
		for cat in n.equipment:
			if not (is_finite(n.equipment[cat]) and n.equipment[cat] >= 0.0):
				_check(false, "%s's %s store is a sound number (%s)" % [t, cat, str(n.equipment[cat])])
	_check(worst > -300.0, "no treasury has run away (worst %.0f)" % worst)
	_check(laws == 0, "no nation at peace keeps a war law (%d do)" % laws)
	for t in powers:
		var n = gs.nations[t]
		var now: float = n.equipment.arms + n.equipment.artillery
		_check(now > store_mid[t] or gs.wars_of(t).size() > 0, "%s keeps making equipment (%.0f, was %.0f)" % [t, now, store_mid[t]])
		var cover := 0.0
		var men := 0.0
		for a in gs.armies.values():
			if a.tag == t:
				cover += Mil.army_coverage(a) * a.men()
				men += a.men()
		_check(men <= 0.0 or cover / men > 0.8, "%s's army is equipped (%.2f)" % [t, cover / men if men > 0.0 else 1.0])
	_check(ms_per_day < 90.0, "a day costs under 90 ms over two years (%.0f ms)" % ms_per_day)
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
