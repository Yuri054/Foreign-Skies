extends SceneTree
## Headless test of what the interface shows about raw materials and war support: where the
## materials come from and what a shortage costs, and what war support is doing and what moves it.
## Run: godot --headless --path . -s res://tests/visibility_test.gd

var _failures := 0
var gs: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _find_text(node: Node, needle: String) -> bool:
	if "text" in node and str(node.text).contains(needle):
		return true
	for c in node.get_children():
		if _find_text(c, needle):
			return true
	return false


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	gs = root.get_node("GameState")
	for c in main.get_node("UI").get_children():
		if c.get_script() != null and "nation_picker" in c.get_script().resource_path:
			c.queue_free()
	gs.ai_enabled = false
	gs.set_player("GER")
	await process_frame
	_test_budget()
	_test_support()
	await _test_panels()
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _test_budget() -> void:
	var ger = gs.nations["GER"]
	var mats: Dictionary = ger.budget.materials
	_check(absf(mats.own + mats.imported - mats.need) < 0.01 or mats.own > mats.need, "own deposits and imports meet the need (%.0f + %.0f of %.0f)" % [mats.own, mats.imported, mats.need])
	ger.blockade_pinned = 1.0
	ger.blockade = 1.0
	load("res://scripts/sim/economy.gd").recompute(gs)
	var cut: Dictionary = ger.budget.materials
	_check(cut.imported == 0.0 and cut.ratio <= mats.ratio, "a blockade stops the imports (%d%% of the need)" % roundi(cut.ratio * 100.0))
	ger.blockade_pinned = -1.0
	ger.blockade = 0.0
	load("res://scripts/sim/economy.gd").recompute(gs)


func _test_support() -> void:
	var WS = load("res://scripts/sim/war_support.gd")
	var fra = gs.nations["FRA"]
	_check(WS.effects_text(gs, "FRA").contains("does nothing"), "in peace the effects text says support does nothing yet")
	gs.set_war("FRA", "GER", true)
	_check(WS.effects_text(gs, "FRA").contains("Fighting power x"), "at war it gives the multipliers (%s)" % WS.effects_text(gs, "FRA"))
	fra.men_lost_month = 50000.0
	fra.blockade = 0.5
	var items: Dictionary = WS.monthly_changes(gs, "FRA")
	_check(items["men lost"] < 0.0 and items["blockade"] < 0.0 and items["the war itself"] < 0.0, "the causes are listed: casualties, blockade, the war")
	var text: String = WS.drivers_text(gs, "FRA")
	_check(text.contains("men lost") and text.contains("blockade"), "and written out biggest first")
	var total := 0.0
	for v: float in items.values():
		total += v
	var before: float = fra.war_support
	WS.step_month(gs)
	_check(is_equal_approx(fra.war_support, clampf(before + total, 0.0, 100.0)), "and they add up to what a month does (%.2f)" % (fra.war_support - before))
	fra.blockade = 0.0


func _test_panels() -> void:
	var eco: Node = get_first_node_in_group("economy_panel")
	eco.toggle()
	await process_frame
	await process_frame
	_check(_find_text(eco._industry, "Raw materials") and _find_text(eco._industry, "Own deposits"), "the Industry section says where the raw materials come from")
	var ger = gs.nations["GER"]
	ger.war_support = 20.0
	gs.set_war("GER", "FRA", true)
	eco._refresh()
	await process_frame
	_check(_find_text(eco._alerts, "War support is 20"), "the Economy window warns when war support is low at war")
	var mil: Node = get_first_node_in_group("military_panel")
	mil.toggle()
	await process_frame
	mil._refresh()
	_check(mil._rows["support"][1].text == "20" and mil._rows["support"][1].tooltip_text.contains("Fighting power"), "the Military window shows war support with what it does")
	var stats: Node = get_first_node_in_group("nation_stats")
	stats.show_nation("FRA")
	await process_frame
	await process_frame
	_check(_find_text(stats, "War support"), "and so does the nation window")
