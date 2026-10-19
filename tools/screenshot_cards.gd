extends SceneTree
## Saves pictures of the nation picker, the closed command panel and the province card folded and
## open. Run in a window: godot --path . --resolution 1600x900 -s res://tools/screenshot_cards.gd -- out_dir
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_cards_settings.cfg"
	DirAccess.remove_absolute("user://shot_cards_settings.cfg")
	var gs: Node = root.get_node("GameState")
	var dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(dir + "/picker.png")
	for picker in get_nodes_in_group("nation_picker"):
		picker.queue_free()
	await process_frame
	gs.set_player("FRA")
	main.map_view.select(gs.nations["FRA"].provinces[10])
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(dir + "/game_folded.png")
	get_first_node_in_group("province_panel")._toggle.pressed.emit()
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(dir + "/game_details.png")
	quit(0)
