extends SceneTree
## Saves pictures of the cities as 3D models: over Germany and the Alps, and close on one big city.
##   godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/screenshot_cities3d.gd -- out_dir
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
	var shots := [["cities_far", 0.35, Vector2(2700, 2900), 52.0], ["cities_wide", 0.75, Vector2(2700, 2900), 52.0], ["cities_mid", 1.3, Vector2(2500, 2700), 48.0]]
	for city in gs.cities:
		if city.name == "Berlin":
			shots.append(["cities_berlin", 2.6, city.pos, 42.0])
		if city.name == "London":
			shots.append(["cities_london", 2.6, city.pos, 42.0])
	for s in shots:
		cam.zoom = Vector2(s[1], s[1])
		cam.position = s[2]
		m3.tilt = s[3]
		m3._apply_tilt()
		for i in 12:
			await process_frame
		root.get_texture().get_image().save_png("%s/%s.png" % [dir, s[0]])
	quit(0)
