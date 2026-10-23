extends SceneTree
## Saves pictures of the armies and fleets as 3D models, near and far.
##   godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/screenshot_units3d.gd -- out_dir
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
	m3.set_enabled(true)
	m3.markers_on = true
	var spot := Vector2(2500, 2700)
	var best := 0
	for a in gs.armies.values():
		if a.tag == "GER":
			spot = root.get_node("MapData").provinces[a.province].center
			break
	var sea := spot
	for f in gs.fleets.values():
		if f.port > 0:
			sea = root.get_node("MapData").provinces[f.port].center
			break
	var shots := [["fleet_near", 2.4, sea, 42.0], ["fleet_close", 3.6, sea, 36.0], ["units_far", 0.6, spot, 48.0], ["units_mid", 1.1, spot, 46.0], ["units_near", 2.2, spot, 40.0], ["units_close", 3.4, spot, 36.0]]
	for s in shots:
		cam.zoom = Vector2(s[1], s[1])
		cam.position = s[2]
		m3.tilt = s[3]
		m3._apply_tilt()
		for i in 14:
			await process_frame
		root.get_texture().get_image().save_png("%s/%s.png" % [dir, s[0]])
	quit(0)
