extends SceneTree
## Saves pictures of Norway and Sweden on the political map. Run in a window:
##   godot --path . --resolution 1600x900 -s res://tools/screenshot_scandinavia.gd -- out_dir
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_scand_settings.cfg"
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
	gs.set_player("SWE")
	var cam: Camera2D = main.camera
	var shots := [["wide", Vector2(0.28, 0.28), Vector2(3900, 1500)], ["near", Vector2(0.55, 0.55), Vector2(3300, 1300)]]
	for s in shots:
		cam.zoom = s[1]
		cam.position = s[2]
		for i in 8:
			await process_frame
		root.get_texture().get_image().save_png("%s/scand_%s.png" % [dir, s[0]])
	quit(0)
