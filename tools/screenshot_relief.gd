extends SceneTree
## Saves pictures of the 3D map with its relief, over the Alps, tilted and turned. Run in a window:
##   godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/screenshot_relief.gd -- out_dir
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_relief_settings.cfg"
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
	cam.zoom = Vector2(0.45, 0.45)
	cam.position = Vector2(2900, 3300)
	var m3: Node = get_first_node_in_group("map_3d")
	m3.set_enabled(true)
	var shots := [["relief_tilt", 40.0, 0.0], ["relief_turned", 40.0, 60.0], ["relief_flat", 40.0, 0.0]]
	for s in shots:
		m3.relief_on = s[0] != "relief_flat"
		m3.tilt = s[1]
		m3.yaw = s[2]
		m3._apply_tilt()
		for i in 10:
			await process_frame
		root.get_texture().get_image().save_png("%s/%s.png" % [dir, s[0]])
	quit(0)
