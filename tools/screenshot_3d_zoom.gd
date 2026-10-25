extends SceneTree
## Pictures of the 3D map zoomed in on a border, at the default tilt and top-down:
##   godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/screenshot_3d_zoom.gd -- out_dir [x y zoom]
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_3d_zoom_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var a := OS.get_cmdline_user_args()
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
	cam.zoom = Vector2.ONE * (float(a[3]) if a.size() > 3 else 1.4)
	cam.position = Vector2(float(a[1]), float(a[2])) if a.size() > 2 else Vector2(2560, 2640)
	var m3: Node = get_first_node_in_group("map_3d")
	m3.set_enabled(true)
	for tilt in [58.0, 90.0]:
		m3.tilt = tilt
		m3._apply_tilt()
		for i in 14:
			await process_frame
		root.get_texture().get_image().save_png("%s/3d_zoom_%d.png" % [a[0], int(tilt)])
	quit(0)
