extends SceneTree
## Saves pictures of the whole continent, flat and as a tilted 3D map.
##   godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/screenshot_continent.gd -- out_dir
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_cities3d_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var dir: String = OS.get_cmdline_user_args()[0]
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	await process_frame
	gs.set_player("GER")
	gs.ai_enabled = false
	var cam: Camera2D = main.camera
	var m3: Node = get_first_node_in_group("map_3d")
	m3.set_enabled(true)
	m3.markers_on = false
	m3.set_enabled(false)
	for i in 12:
		await process_frame
	var shots := [["continent_flat", false, 0.0], ["continent_3d", true, 48.0]]
	for s in shots:
		m3.set_enabled(s[1])
		cam.position = Vector2(3930, 2576)
		var fit: float = cam.far_zoom()
		cam.zoom = Vector2(fit, fit)
		if s[1]:
			m3.tilt = s[2]
			m3._apply_tilt()
		for i in 15:
			await process_frame
		root.get_texture().get_image().save_png("%s/%s.png" % [dir, s[0]])
	quit(0)
