extends SceneTree
## Saves pictures of the map with the cities at three zoom levels. Run in a window:
##   godot --path . --resolution 1600x900 -s res://tools/screenshot_cities.gd -- out_dir
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_cities_settings.cfg"
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
	var cam: Camera2D = main.camera
	var shots := [["wide", Vector2(0.25, 0.25), Vector2(3300, 2900)], ["mid", Vector2(0.5, 0.5), Vector2(2400, 2700)], ["near", Vector2(1.0, 1.0), Vector2(1800, 2750)]]
	for s in shots:
		cam.zoom = s[1]
		cam.position = s[2]
		for i in 8:
			await process_frame
		root.get_texture().get_image().save_png("%s/cities_%s.png" % [dir, s[0]])
	main.map_view.select(233)
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(dir + "/cities_card.png")
	quit(0)
