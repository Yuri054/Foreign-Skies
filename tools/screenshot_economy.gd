extends SceneTree
## Saves pictures of the Economy window's tabs and the Construction panel. Run (with a window):
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
	var eco: Node = get_first_node_in_group("economy_panel")
	eco.toggle()
	for tab in eco._tabs.get_tab_count():
		eco._tabs.current_tab = tab
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png("%s/economy_%d_%s.png" % [dir, tab, eco._tabs.get_tab_title(tab).to_lower().replace(" ", "_")])
	eco.toggle()
	get_first_node_in_group("construction_panel").toggle()
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png("%s/construction.png" % dir)
	quit(0)
