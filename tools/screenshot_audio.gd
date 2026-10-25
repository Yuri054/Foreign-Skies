extends SceneTree
## Saves pictures of the audio controls: the main menu's settings window, the settings window and the pause menu.
##   godot --path . --resolution 1280x720 --rendering-driver opengl3 -s res://tools/screenshot_audio.gd -- out_dir
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_audio_settings.cfg"
	var dir: String = OS.get_cmdline_user_args()[0]
	var menu: Node = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	for i in 6:
		await process_frame
	menu._toggle_settings()
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png("%s/audio_menu.png" % dir)
	menu.queue_free()
	await process_frame
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	var gs: Node = root.get_node("GameState")
	gs.set_player("GER")
	for i in 6:
		await process_frame
	get_first_node_in_group("settings_window").toggle()
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png("%s/audio_settings.png" % dir)
	get_first_node_in_group("settings_window").toggle()
	get_first_node_in_group("pause_menu").open()
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png("%s/audio_pause.png" % dir)
	quit(0)
