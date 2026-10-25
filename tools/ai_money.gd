extends SceneTree
## Monthly money and manpower of nations in an AI-only war: for judging what limits recruiting.
## godot --headless --path . -s res://tools/ai_money.gd -- tags months [scenario_dir]
func _initialize() -> void:
	await process_frame
	var gs = root.get_node("GameState")
	var clock = root.get_node("Clock")
	var Mil = load("res://scripts/sim/military.gd")
	var args := OS.get_cmdline_user_args()
	gs.load_scenario(args[2] if args.size() > 2 else "res://data/scenarios/july_1914/")
	gs.ai_enabled = true
	gs.set_player("ESP")
	var last := -1
	for d in int(args[1]) * 31:
		clock.advance_day()
		if clock.month == last:
			continue
		last = clock.month
		for tag in args[0].split(","):
			var n = gs.nations[tag]
			var b: Dictionary = n.budget
			print("%d-%02d %s men_in_service %dk manpower %dk (max %dk) treasury %.1f revenue/mo %.1f net/mo %.1f training %d war_mult_target %dk" % [clock.year, clock.month, tag, Mil.men_in_service(gs, tag) / 1000.0, n.manpower / 1000.0, b.get("manpower_max", 0.0) / 1000.0, n.treasury, b.get("revenue", 0.0) / 12.0, b.get("net", 0.0) / 12.0, n.recruiting.size(), n.peacetime_army * 4.5 / 1000.0])
	quit()
