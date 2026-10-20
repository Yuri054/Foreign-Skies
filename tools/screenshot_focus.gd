extends SceneTree
## Saves a picture of the national focus window. Run in a window:
##   godot --path . --resolution 1280x720 -s res://tools/screenshot_focus.gd -- out_dir
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_focus_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	for picker in get_nodes_in_group("nation_picker"):
		picker.queue_free()
	await process_frame
	gs.set_player("GER")
	gs.issue(load("res://scripts/sim/set_focus.gd").new("GER", "industrial_drive"))
	gs.nations["GER"].focus.days_left = 30
	gs.nations["GER"].focus_done.append("army_reform")
	get_nodes_in_group("focus_panel")[0].toggle()
	get_nodes_in_group("focus_panel")[0].select("heavy_industry")
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(dir + "/focus.png")
	quit(0)
