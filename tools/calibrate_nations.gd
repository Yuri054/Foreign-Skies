extends SceneTree
## Prints each nation's population, area, GDP, revenue and food balance, to calibrate the
## scenario's development and agri_yield. Run:
##   godot --headless --path . -s res://tools/calibrate_nations.gd


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GameState")
	var md: Node = root.get_node("MapData")
	print("tag\tprovinces\tpop_M\tarea_km2\tdensity\tgdp\tgdp_per_head\trevenue\tfood_ratio\tdev\tagri")
	var tags: Array = gs.nations.keys()
	tags.sort()
	for tag in tags:
		var n = gs.nations[tag]
		var area := 0.0
		for id in n.provinces:
			area += md.provinces[id].area * 0.48
		var b: Dictionary = n.budget
		var pop := maxf(n.population, 1.0)
		print("%s\t%d\t%.2f\t%.0f\t%.0f\t%.1f\t%.1f\t%.1f\t%.2f\t%.3f\t%.3f	%.2f" % [tag, n.provinces.size(), pop / 1e6, area, pop / maxf(area, 1.0), b.gdp, b.gdp * 1e6 / pop, b.revenue, b.food_production / pop, n.development, n.agri_yield, b.net])
	print("
tag	resource	production	demand	intensity")
	for tag in tags:
		var n = gs.nations[tag]
		for r in n.budget.resources:
			var info: Dictionary = n.budget.resources[r]
			print("%s	%s	%.0f	%.0f	%.3f" % [tag, r, info.production, info.demand, n.intensity.get(r, 1.0)])
	quit()
