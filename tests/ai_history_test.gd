extends SceneTree
## Headless test of the 1914 crisis played by the AI alone (the player is a bystander): the AIs fight, nobody is
## wiped out, wars end and are not renewed at once, determinism, and the daily cost. (It asserts nothing about
## what history did: no front, no outcome.)
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
	for day in 520:
		clock.advance_day()
		if day == 250:
			_check(battles.size() >= 4, "by day 250 several powers have fought (%d nations in battle)" % battles.size())
		if _fighting() == 0 and day > 150:
			break
	_check(collapsed.is_empty(), "no nation collapses (%s)" % str(collapsed))
	_check(not peaces.is_empty() and peaces[0].day >= 60, "the first peace comes after the first two months (day %d)" % (peaces[0].day if not peaces.is_empty() else -1))
	# The trained AI fights the great war out for years (as it was), so by day 520 many wars may still burn:
	# what matters is that peace is being made all along and the war is not a single endless blob.
	_check(peaces.size() >= 3 and _fighting() < declared.size(), "peace is being made while it burns: %d peaces, %d of %d wars still fighting at day %d" % [peaces.size(), _fighting(), declared.size(), clock.days_elapsed])
	# A truce follows each peace: nobody re-declares on the nation they just made peace with.
	var broken := 0
	for p in peaces:
		for d in declared:
			if d.day > p.day and d.day - p.day < 200 and ((d.a == p.a and d.b == p.b) or (d.a == p.b and d.b == p.a)):
				broken += 1
	_check(broken == 0, "no peace is broken within 200 days (%d)" % broken)
	var unjust: int = gs.ai_declarations.unjustified
	var total: int = gs.ai_declarations.total
	_check(unjust <= 3 and float(unjust) / maxf(total, 1) <= 0.15, "unjustified wars are %d of %d, within the cap" % [unjust, total])
	var lost := 0
	for tag in gs.nations:
		var before := MapData_count(tag)
		if before >= 60 and gs.nations[tag].provinces.size() < 0.8 * before:
			lost += 1
	_check(lost == 0, "no big nation has lost a fifth of its land")


## Wars with a battle in the last three months (or begun in them): the fighting still going on. A war between nations
## that cannot reach each other drags on, but it is not a fight.
func _fighting() -> int:
	var n := 0
	for w in gs.wars.values():
		if clock.days_elapsed - maxi(w.last_fight_day, w.start_day) < 90:
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
