extends SceneTree
## Saves pictures of the Economy window and the Construction panel: Germany in peace with factories under way and one
## waiting (or, with "war", at war with France). Run (with a window):
##   godot --path . --resolution 1600x900 -s res://tools/screenshot_economy.gd -- out_dir


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	var dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	gs.set_player("GER")
	gs.ai_enabled = false
	if OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "war":
		_war_state(gs)
	else:
		_peace_state(gs)
	var eco: Node = get_first_node_in_group("economy_panel")
	eco.toggle()
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png("%s/economy.png" % dir)
	eco.toggle()
	var cons: Node = get_first_node_in_group("construction_panel")
	cons.toggle()
	if OS.get_cmdline_user_args().size() > 1:
		cons._rows["trench"].pressed.emit()
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png("%s/construction.png" % dir)
	quit(0)


## Germany at war with France for a while: casualties, queued trenches and a fortification, a
## day's production behind it.
func _war_state(gs: Node) -> void:
	var Build = load("res://scripts/sim/construct_building.gd")
	var ger = gs.nations["GER"]
	gs.set_war("GER", "FRA", true)
	ger.war_dead = 400000.0
	var Eco = load("res://scripts/sim/economy.gd")
	var n := 0
	for id in ger.provinces:
		if n >= 6:
			break
		if Eco.build_problem(gs, "GER", id, "trench").is_empty():
			gs.issue(Build.new("GER", id, "trench"))
			n += 1
	for id in ger.provinces:
		if Eco.build_problem(gs, "GER", id, "fortification").is_empty():
			gs.issue(Build.new("GER", id, "fortification"))
			break
	for i in 20:
		root.get_node("Clock").advance_day()


## Germany in peace, a month into building: a civilian factory and a construction sector under way, a factory waiting
## for the gold and points.
func _peace_state(gs: Node) -> void:
	var Build = load("res://scripts/sim/construct_building.gd")
	var Eco = load("res://scripts/sim/economy.gd")
	var ger = gs.nations["GER"]
	ger.treasury = 110.0
	ger.cp = 420.0
	var queued := 0
	for pair: Array in [["civilian_factory", 2], ["construction_sector", 1]]:
		var left: int = pair[1]
		for id in ger.provinces:
			if left <= 0:
				break
			if id != ger.capital and Eco.build_problem(gs, "GER", id, pair[0]).is_empty() and not Eco.province_busy(ger, id) \
					and not ger.construction.any(func(j: Dictionary) -> bool: return j.province == id):
				gs.issue(Build.new("GER", id, pair[0]))
				left -= 1
				queued += 1
	for i in 12:
		root.get_node("Clock").advance_day()
