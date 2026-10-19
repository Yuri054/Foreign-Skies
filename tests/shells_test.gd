extends SceneTree
## Headless test of the shell economy: in peace a power's shell stock grows; in a long offensive,
## twenty artillery brigades firing every day empty it after a while (and then lose their attack),
## which is the point of making shells a thing to build.
## Run: godot --headless --path . -s res://tests/shells_test.gd

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
	var M = load("res://scripts/sim/military.gd")
	gs.ai_enabled = false
	var ger = gs.nations["GER"]
	var guns: Array = []
	var holder = null
	for a in gs.armies.values():
		if a.tag == "GER":
			for u in a.units:
				if M.cfg.unit_types[u.type].get("shells", 0.0) > 0.0 and guns.size() < 20:
					guns.append(u)
					holder = a
	_check(guns.size() >= 10, "Germany has artillery to fire (%d brigades)" % guns.size())
	var before: float = ger.equipment.shells
	for i in 30:
		clock.advance_day()
	_check(ger.equipment.shells > before, "in peace the shell stock grows (%.0f to %.0f)" % [before, ger.equipment.shells])
	# A campaign: the guns fire every day.
	var empty_day := -1
	var stock: float = ger.equipment.shells
	for day in 150:
		clock.advance_day()
		for a in gs.armies.values():
			if a.tag == "GER":
				M._burn_shells(gs, a)
		if empty_day < 0 and ger.equipment.shells < 1.0:
			empty_day = day
	_check(empty_day > 15 and empty_day < 140, "a campaign with every gun firing empties the stock after a while (day %d, from %.0f)" % [empty_day, stock])
	var starved := 0
	for u in guns:
		if u.shell_starved:
			starved += 1
	_check(starved >= guns.size() / 2 and holder != null, "and then most guns have no shells (%d of %d): what is made each day goes to the first in line" % [starved, guns.size()])
	var last = guns.back()
	var full: float = last.men() / 1000.0 * M.cfg.unit_types[last.type].attack
	_check(last.shell_starved and last.power() < full * 0.5, "a gun without shells has lost most of its attack (%.2f of %.2f)" % [last.power(), full])
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
