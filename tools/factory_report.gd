extends SceneTree
## Prints each nation's factories at the start: civilian and military, slots, industry and the
## military factories' share, to calibrate data/economy.json "factories" and the scenario.
## Run: godot --headless --path . -s res://tools/factory_report.gd

func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GameState")
	var rows := []
	for tag in gs.nations:
		var n = gs.nations[tag]
		var civ := 0
		var mil := 0
		var slots := 0
		for id in n.provinces:
			civ += gs.province_buildings[id].get("factory", 0)
			mil += gs.province_buildings[id].get("military_factory", 0)
			slots += gs.province_slots[id]
		rows.append([tag, n.provinces.size(), civ, mil, slots, n.budget.industry, n.budget.gdp, n.peacetime_army])
	rows.sort_custom(func(a, b): return a[2] + a[3] > b[2] + b[3])
	print("tag  provs  civ  mil  slots  industry  gdp  army")
	for r in rows:
		if r[2] + r[3] > 0 or r[7] > 0:
			print("%-4s %5d %4d %4d %6d %9.1f %6.1f %8d" % r)
	quit()
