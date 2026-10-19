extends SceneTree
## Headless test of what the interface now shows about resources and war support: where each
## resource goes and what a shortage costs, what the equipment lines draw, and what war support
## is doing and what moves it.
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
	var Prod = load("res://scripts/sim/production.gd")
	var ger = gs.nations["GER"]
	for r in ["coal", "iron", "wood"]:
		var info: Dictionary = ger.budget.resources[r]
		var parts: float = info.from_industry + info.from_homes + info.from_buildings + info.from_lines + info.from_works + info.from_army
		_check(absf(parts - info.demand) < 0.01, "%s: industry, homes and buildings make up the demand (%.0f of %.0f)" % [r, parts, info.demand])
	var kit: Dictionary = Prod.planned_materials(ger)
	_check(kit.get("iron", 0.0) > 0.0 and kit.get("coal", 0.0) > 0.0, "the equipment lines draw iron and coal (%s)" % str(kit))
	ger.stock.iron = 0.0
	ger.intensity["iron"] = 80.0
	ger.blockade = 1.0
	load("res://scripts/sim/economy.gd").recompute(gs)
	var iron: Dictionary = ger.budget.resources.iron
	_check(iron.shortage > 0.0 and iron.cost_industry > 0.0, "a shortage says what it costs (industry %.2f, output %.2f)" % [iron.cost_industry, iron.cost_gdp])
	ger.blockade = 0.0
	ger.intensity["iron"] = 1.0


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
	eco._tabs.current_tab = 1
	await process_frame
	await process_frame
	_check(_find_text(eco._resources, "Where it goes"), "the Resources tab says where each resource goes")
	_check(_find_text(eco._resources, "Equipment"), "with a column for the equipment lines")
	var ger = gs.nations["GER"]
	ger.war_support = 20.0
	gs.set_war("GER", "FRA", true)
	eco._tabs.current_tab = 0
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
