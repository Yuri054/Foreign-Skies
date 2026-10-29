extends SceneTree
## Headless test for the staff tools: the order preview (days, arrival, supply on the way, what is known of the enemy, never
## more than Intel allows), the Supply variant of Military mode, the preview text on the map, and that an order given by hand
## takes an army off the front it was handed to.
## Run: godot --headless --path . -s res://tests/staff_tools_test.gd

var _failures := 0
var gs: Node
var M
var clock


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _army_of(tag: String):
	for a in gs.armies.values():
		if a.tag == tag and not a.embarked():
			return a
	return null


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://test_settings.cfg"
	gs = root.get_node("GameState")
	M = load("res://scripts/sim/military.gd")
	clock = root.get_node("Clock")
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

	# --- The preview ------------------------------------------------------------------------
	var a = _army_of("GER")
	var home: int = -1
	for n: int in M.neighbors(a.province):
		if gs.province_controller[n] == "GER":
			home = n
			break
	var p: Dictionary = M.order_preview(gs, [a.id], home)
	_check(p.ok and p.reason == "" and p.hops >= 1, "an order to a neighbouring province can be given (%d stages)" % p.hops)
	var path: Array[int] = M.find_path(gs, "GER", a.speed(), a.province, home)
	var expected := 0.0
	var at: int = a.province
	for step in path:
		expected += M.move_days(gs, "GER", a.speed(), at, step)
		at = step
	_check(is_equal_approx(p.days, expected), "the days are those of the road (%.0f)" % p.days)
	_check(p.eta == clock.date_after(int(p.days)) and p.eta != "", "and the date of arrival is given: %s" % p.eta)
	_check(p.unsupplied == 0 and p.ends_supplied, "at home it is all in supply")
	_check(M.order_preview(gs, [a.id], a.province).reason == "here" and not M.order_preview(gs, [a.id], a.province).ok, "an order to where the army stands is not an order")
	_check(M.order_preview(gs, [], home).reason == "none" and not M.order_preview(gs, [99999], home).ok, "with no army there is no preview")

	# Far into an enemy's land the supply gives out.
	gs.set_war("GER", "RUS", true, "none")
	var far := -1
	var far_cost := 0.0
	for id: int in gs.nations["RUS"].provinces:
		var cost: float = M.supply_cost(gs, "GER", id)
		if cost == INF and not M.find_path(gs, "GER", a.speed(), a.province, id).is_empty():
			far = id
			break
	if far > 0:
		var q: Dictionary = M.order_preview(gs, [a.id], far)
		_check(q.ok and q.unsupplied >= 1 and not q.ends_supplied, "deep in Russia the army would be out of supply (%d of %d stages)" % [q.unsupplied, q.hops])
		_check(not q.enemy_seen, "and no enemy is known there")
	else:
		_check(true, "(no Russian province beyond supply and still reachable)")

	# What is known of the enemy: a range, never the truth, and nothing of what is not seen.
	var rus = _army_of("RUS")
	var target: int = home
	rus.province = target
	var seen: Dictionary = M.order_preview(gs, [a.id], target)
	_check(seen.enemy_seen and seen.enemy.x < seen.enemy.y, "an enemy army that is seen gives a range (%s to %s)" % [str(roundi(seen.enemy.x)), str(roundi(seen.enemy.y))])
	_check(seen.enemy.x <= rus.men() and rus.men() <= seen.enemy.y + 0.001, "the truth lies inside it")
	_check(seen.odds.x <= seen.odds.y and seen.odds.x > 0.0, "the odds are a range too (%.2f to %.2f)" % [seen.odds.x, seen.odds.y])
	var fra = _army_of("FRA")
	fra.province = target
	rus.province = M.neighbors(target)[0]
	var hidden: Dictionary = M.order_preview(gs, [a.id], target)
	_check(not hidden.enemy_seen, "an army of a nation not at war with you is not counted")
	_check(M.order_preview(gs, [a.id], target).enemy == Vector2.ZERO, "and nothing of it is given away")

	# --- The Supply variant --------------------------------------------------------------------
	var view: Node = main.map_view
	var submodes: Array = view.submodes(view.Mode.MILITARY)
	_check(submodes.any(func(o: Array) -> bool: return o[0] == view.MIL_SUPPLY), "Military mode has a Supply variant")
	view.set_mode(view.Mode.MILITARY, view.MIL_SUPPLY)
	await process_frame
	_check(view.supply_color(a.province) == view.SUPPLY_HOME, "home ground is green")
	if far > 0:
		_check(view.supply_color(far) == view.SUPPLY_NONE, "ground beyond supply is red")
	var legend: Dictionary = view.legend()
	_check(legend.get("title", "") == "Supply for your armies" and legend.swatches.size() == 3, "the legend explains the colours")

	# --- The text on the map -------------------------------------------------------------------
	var tip: String = view.order_tip_for([a.id], home)
	_check(tip.contains("days") and tip.contains(p.eta) and tip.contains("supply"), "the preview text names the days, the arrival and the supply: %s" % tip.replace("\n", " | "))
	rus.province = home
	var tip2: String = view.order_tip_for([a.id], home)
	_check(tip2.contains("Enemy seen") and tip2.contains("Odds"), "and what is seen of the enemy: %s" % tip2.replace("\n", " | "))

	# --- Delegation does not outrank an order ---------------------------------------------------
	gs.wars.clear()
	var DesignateFront = load("res://scripts/sim/designate_front.gd")
	var AssignToFront = load("res://scripts/sim/assign_to_front.gd")
	var MoveArmy = load("res://scripts/sim/move_army.gd")
	var border: Array[int] = []
	var df = DesignateFront.new("GER", "Test front", border, "FRA")
	if gs.issue(df):
		var ids: Array[int] = [a.id]
		gs.issue(AssignToFront.new("GER", df.front_id, ids))
		_check(a.front_id == df.front_id, "an army handed to a front is on it")
		gs.issue(MoveArmy.new("GER", a.id, home))
		_check(a.front_id == df.front_id and a.pin == home, "an order given by hand pins it: it stays on its front, left alone until it gets there")
	else:
		_check(true, "(no border front could be drawn)")

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
