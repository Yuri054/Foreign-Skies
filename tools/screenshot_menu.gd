extends SceneTree
## Saves a picture of the main menu. Run (with a window, not headless):
##   godot --path . --resolution 1600x900 -s res://tools/screenshot_menu.gd -- out.png


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_settings.cfg"
	var menu: Node = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	for i in 8:
		await process_frame
	var args := OS.get_cmdline_user_args()
	root.get_texture().get_image().save_png(args[0] if args.size() > 0 else "user://menu.png")
	quit(0)
