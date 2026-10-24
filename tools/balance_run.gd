extends SceneTree
## A long AI-only run of a scenario that prints a yearly table of the great powers and Europe: for judging the
## balance (finances, growth, armies, wars, tension) after changing numbers.
## Run: godot --headless --path . -s res://tools/balance_run.gd -- [scenario_dir] [years] [bystander]
func _initialize() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var clock = root.get_node("Clock")
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "res://data/scenarios/jan_1900/"
	var years := int(args[1]) if args.size() > 1 else 10
	gs.load_scenario(dir)
	gs.ai_enabled = true
	gs.set_player(args[2] if args.size() > 2 else "ESP")
	var wars := [0]
	gs.war_changed.connect(func(_a: String, _b: String, w: bool) -> void: wars[0] += 1 if w else 0)
	var tags := ["GBR", "FRA", "GER", "RUS", "AUH", "ITA", "OTT"]
	print("year  tension wars(new/now) | per nation: gdp £M/mo, treasury £M, net £M/mo, pop M, men k, provinces")
	for y in years:
		for d in 365:
			clock.advance_day()
		var parts: PackedStringArray = []
		for t in tags:
			var n = gs.nations[t]
			var b: Dictionary = n.budget
			parts.append("%s %.0f/%.0f/%+.1f/%.1f/%d/%d" % [t, b.get("gdp", 0.0) / 12.0, n.treasury, b.get("net", 0.0) / 12.0, n.population / 1e6, n.men_in_units / 1000, n.provinces.size()])
		print("%d  %3d  %d/%d | %s" % [clock.year, roundi(gs.tension), wars[0], gs.wars.size(), " | ".join(parts)])
	var collapsed := []
	for t in gs.nations:
		if gs.nations[t].provinces.is_empty():
			collapsed.append(t)
	print("no land at the end: ", collapsed)
	quit()
