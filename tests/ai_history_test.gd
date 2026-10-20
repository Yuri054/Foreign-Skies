extends SceneTree
## Headless test of the 1914 crisis played by the AI alone (the player is a bystander): the
## markers that make it look like the war it models, determinism, and the daily cost.
## Run: godot --headless --path . -s res://tests/ai_history_test.gd
## Class names are loaded at runtime because this script compiles before the autoloads exist.

var _failures := 0
var gs: Node
var clock: Node
var A


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
	A = load("res://scripts/ai/ai.gd")
	_test_history()
	_test_determinism()
	_test_cost()
	_test_overlay()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _start() -> void:
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.ai_enabled = true
	gs.set_player("ESP")


func _great_debt_leader() -> String:
	var worst := ""
	for tag in ["GER", "FRA", "RUS", "AUH", "GBR"]:
		if worst.is_empty() or gs.nations[tag].treasury < gs.nations[worst].treasury:
			worst = tag
	return worst


func _test_history() -> void:
	_start()
	var battles := {}
	var collapsed: Array = []
	var peaces: Array = []
	var declared: Array = []
	gs.battle_fought.connect(func(_p: int, tags: Array) -> void:
		for t: String in tags:
			battles[t] = battles.get(t, 0) + 1)
	gs.nation_collapsed.connect(func(tag: String, _men: int) -> void: collapsed.append(tag))
	gs.war_changed.connect(func(a: String, b: String, at_war: bool) -> void:
		if at_war:
			declared.append({"a": a, "b": b, "day": clock.days_elapsed})
		else:
			peaces.append({"a": a, "b": b, "day": clock.days_elapsed}))
	var winter_cross := -1
	var debt_leader := ""
	var survived := true
	for day in 460:
		clock.advance_day()
		if day == 120:
			_check(battles.get("RUS", 0) > 0 and battles.get("GER", 0) > 0, "by day 120 there is fighting on the Eastern front")
			_check(battles.get("FRA", 0) > 0, "and on the Western front")
		if day == 125:
			# The first winter: the west is a line, not a collapse.
			winter_cross = _held_across(["FRA", "GER", "BEL"])
		if day == 240:
			debt_leader = _great_debt_leader()
			for tag in ["SRB", "BEL", "MNE"]:
				survived = survived and not gs.nations[tag].provinces.is_empty()
		if gs.wars.is_empty() and day > 150:
			if debt_leader.is_empty():
				debt_leader = _great_debt_leader()
			break
	_check(winter_cross <= 12, "the Western front is a static line by the first winter (%d provinces held across it)" % winter_cross)
	_check(collapsed.is_empty(), "no nation collapses (%s)" % str(collapsed))
	_check(survived, "Serbia, Belgium and Montenegro are still there after eight months")
	_check(debt_leader == "RUS", "Russia carries the heaviest debt of the great powers by month eight (%s)" % debt_leader)
	_check(not peaces.is_empty() and peaces[0].day >= 100, "the first peace comes after the first hundred days (day %d)" % (peaces[0].day if not peaces.is_empty() else -1))
	_check(gs.wars.is_empty() and clock.days_elapsed < 460, "the general war has run its course by day %d" % clock.days_elapsed)
	# A truce follows each peace: nobody re-declares on the nation they just made peace with.
	var broken := 0
	for p in peaces:
		for d in declared:
			if d.day > p.day and d.day - p.day < 200 and ((d.a == p.a and d.b == p.b) or (d.a == p.b and d.b == p.a)):
				broken += 1
	_check(broken == 0, "no peace is broken within 200 days (%d)" % broken)
	var unjust: int = gs.ai_declarations.unjustified
	var total: int = gs.ai_declarations.total
	_check(unjust <= 1 and float(unjust) / maxf(total, 1) <= 0.15, "unjustified wars are %d of %d, within the cap" % [unjust, total])
	var lost := 0
	for tag in ["GER", "FRA", "RUS", "AUH", "GBR"]:
		if gs.nations[tag].provinces.size() < 0.8 * MapData_count(tag):
			lost += 1
	_check(lost == 0, "no great power has lost a fifth of its land")


## Provinces held across the lines between the given nations.
func _held_across(tags: Array) -> int:
	var n := 0
	for id in range(1, gs.province_owner.size()):
		var o: String = gs.province_owner[id]
		var c: String = gs.province_controller[id]
		if o != c and o in tags and c in tags:
			n += 1
	return n


## What a nation owned when the scenario began.
func MapData_count(tag: String) -> int:
	var map: Node = root.get_node("MapData")
	var n := 0
	for id in range(1, map.provinces.size()):
		if map.provinces[id].owner == tag:
			n += 1
	return n


func _fingerprint(days: int) -> String:
	_start()
	for i in days:
		clock.advance_day()
	var owners := ",".join(gs.province_owner)
	var controllers := ",".join(gs.province_controller)
	return "%s|%s|%s" % [JSON.stringify(gs.command_log), owners, controllers]


func _test_determinism() -> void:
	var first := _fingerprint(90)
	var second := _fingerprint(90)
	_check(first == second and first.length() > 1000, "the same scenario run twice gives the same orders and the same map after 90 days")


## Costs are measured over the busiest months of the war, with the AI timed on its own.
func _test_cost() -> void:
	_start()
	for i in 40:
		clock.advance_day()
	A.profile = true
	A.timings.clear()
	var t0 := Time.get_ticks_usec()
	var days := 100
	for i in days:
		clock.advance_day()
	var total_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / days
	var ai_us := 0
	for part in A.timings:
		ai_us += int(A.timings[part])
	var ai_ms := float(ai_us) / 1000.0 / days
	A.profile = false
	print("      (a day costs %.1f ms in all, %.1f ms of it the AI)" % [total_ms, ai_ms])
	_check(OS.get_environment("SPEED_TESTS") == "0" or ai_ms < 25.0, "the AI costs under 25 ms a day through the busiest war months")
	_check(OS.get_environment("SPEED_TESTS") == "0" or total_ms < 90.0, "the whole day step stays under 90 ms")


## The debug overlay's data: orders, campaign targets and fronts of the nations the AI plays.
func _test_overlay() -> void:
	var overlay = load("res://scripts/map/ai_overlay.gd")
	_start()
	for i in 60:
		clock.advance_day()
	var marks: Array = overlay.marks(gs)
	var kinds := {}
	for m in marks:
		kinds[m.kind] = kinds.get(m.kind, 0) + 1
		_check(m.tag != gs.player_tag, "the overlay shows no mark of the player")
		break
	_check(kinds.size() > 0 or marks.size() > 0, "the overlay has something to show once the war is on (%d marks)" % marks.size())
	var seen := {}
	for m in marks:
		seen[m.kind] = true
	_check(seen.has("front") and seen.has("order"), "fronts and march orders are drawn (%s)" % str(seen.keys()))
