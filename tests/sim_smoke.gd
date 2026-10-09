extends SceneTree
## Headless smoke test for the simulation core.
## Run: godot --headless --path . -s res://tests/sim_smoke.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame  # let the autoloads finish _ready
	var clock: Node = root.get_node("Clock")
	var state: Node = root.get_node("GameState")
	var map: Node = root.get_node("MapData")

	_check(clock.date_string() == "28 July 1914", "scenario starts on 28 July 1914 (got %s)" % clock.date_string())
	_check(clock.paused, "clock starts paused")

	var month_ticks := [0]
	clock.month_ticked.connect(func() -> void: month_ticks[0] += 1)
	for i in 4:
		clock.advance_day()
	_check(clock.date_string() == "1 August 1914", "month rolls over (got %s)" % clock.date_string())
	_check(month_ticks[0] == 1, "month tick fired once")

	clock.start(1915, 12, 31)
	var year_ticks := [0]
	clock.year_ticked.connect(func() -> void: year_ticks[0] += 1)
	clock.advance_day()
	_check(clock.date_string() == "1 January 1916" and year_ticks[0] == 1, "year rolls over")
	_check(clock.days_in_month(1916, 2) == 29 and clock.days_in_month(1900, 2) == 28, "leap years")

	_check(map.provinces.size() > 500, "%d provinces loaded" % (map.provinces.size() - 1))
	var total := 0
	for tag in state.nations:
		var n = state.nations[tag]
		total += n.provinces.size()
		_check(n.provinces.size() > 0 and n.population > 0, "%s has %d provinces, %.1fM people" % [tag, n.provinces.size(), n.population / 1e6])
	_check(total == map.provinces.size() - 1, "every province has exactly one owner")

	# every adjacency is symmetric
	var symmetric := true
	for id in map.adjacency:
		for n in map.adjacency[id]:
			symmetric = symmetric and map.adjacency[n].has(id)
	_check(symmetric, "adjacency is symmetric")
	_check(map.adjacency.size() == map.provinces.size() - 1, "every province has at least one neighbour")

	var some: int = state.nations["GER"].provinces[0]
	state.transfer_province(some, "FRA")
	_check(state.province_owner[some] == "FRA" and some in state.nations["FRA"].provinces, "province transfer updates ownership")

	print("FAILURES: ", _failures)
	quit(1 if _failures else 0)
