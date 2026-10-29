extends SceneTree
## Pictures of fleets in port, on the flat map and in 3D, to see that the ships lie on the water:
##   godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/screenshot_ports.gd -- out_dir
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_ports_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var out: String = OS.get_cmdline_user_args()[0]
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
	var FL = load("res://scripts/map/fleet_layer.gd")
	var ports: Array = []
	var seen := {}
	for f in gs.fleets.values():
		if f.port > 0 and not seen.has(f.tag) and ports.size() < 4:
			seen[f.tag] = true
			ports.append([f.tag, f.port])
	var cam: Camera2D = main.camera
	var m3: Node = get_first_node_in_group("map_3d")
	for p: Array in ports:
		cam.position = FL.harbour_spot(p[1])
		cam.zoom = Vector2.ONE * 1.6
		for i in 6:
			await process_frame
		root.get_texture().get_image().save_png("%s/port_%s_2d.png" % [out, p[0]])
	m3.set_enabled(true)
	for p: Array in ports:
		cam.position = FL.harbour_spot(p[1])
		cam.zoom = Vector2.ONE * 2.6
		m3.tilt = 45.0
		m3._apply_tilt()
		for i in 16:
			await process_frame
		root.get_texture().get_image().save_png("%s/port_%s_3d.png" % [out, p[0]])
	quit(0)
