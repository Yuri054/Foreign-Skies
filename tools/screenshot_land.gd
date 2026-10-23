extends SceneTree
## Saves pictures of the map with its land texture at several zooms and in 3D. Run in a window:
##   godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/screenshot_land.gd -- out_dir
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_land_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var dir: String = OS.get_cmdline_user_args()[0]
	var style: String = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else "satellite"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	await process_frame
	main.map_view.land_style = style
	gs.set_player("GER")
	gs.ai_enabled = false
	var cam: Camera2D = main.camera
	var shots := [["land_far", 0.3, Vector2(3300, 2900)], ["land_mid", 0.6, Vector2(3000, 3300)], ["land_near", 1.2, Vector2(2900, 3350)]]
	for s in shots:
		cam.zoom = Vector2(s[1], s[1])
		cam.position = s[2]
		for i in 8:
			await process_frame
		root.get_texture().get_image().save_png("%s/%s_%s.png" % [dir, style, s[0]])
	var m3: Node = get_first_node_in_group("map_3d")
	m3.set_enabled(true)
	cam.zoom = Vector2(0.5, 0.5)
	cam.position = Vector2(2900, 3300)
	m3.tilt = 42.0
	m3._apply_tilt()
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png("%s/%s_3d.png" % [dir, style])
	quit(0)
