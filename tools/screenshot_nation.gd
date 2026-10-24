extends SceneTree
## Saves a picture of every tab of the Nation screen. Run (with a window):
##   godot --path . --resolution 1600x900 -s res://tools/screenshot_nation.gd -- out_dir [war]
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	await process_frame
	var dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	gs.set_player("GER")
	gs.ai_enabled = false
	if OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "war":
		gs.set_war("GER", "FRA", true)
		for i in 15:
			root.get_node("Clock").advance_day()
	var screen: Node = get_first_node_in_group("nation_screen")
	for title in ["Overview", "Economy", "Build", "Military", "Navy", "Diplomacy", "Focus"]:
		screen.open_page(title)
		for i in 6:
			await process_frame
		root.get_texture().get_image().save_png("%s/nation_%s.png" % [dir, title.to_lower()])
	quit(0)
