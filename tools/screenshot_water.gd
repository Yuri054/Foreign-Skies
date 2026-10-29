extends SceneTree
## Pictures of the 3D map's sea: the Channel and the Aegean, close and far, tilted and top-down, and one with the
## moving sea off to compare:
##   godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/screenshot_water.gd -- out_dir
const VIEWS := [
	["channel_close", Vector2(985, 2700), 2.2, 52.0],
	["channel_far", Vector2(1100, 2600), 0.7, 45.0],
	["aegean", Vector2(3900, 4560), 1.4, 58.0],
	["aegean_top", Vector2(3900, 4560), 1.4, 90.0],
]


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_water_settings.cfg"
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
	gs.set_player("GBR")
	gs.ai_enabled = false
	var cam: Camera2D = main.camera
	var m3: Node = get_first_node_in_group("map_3d")
	m3.set_enabled(true)
	for v: Array in VIEWS:
		cam.position = v[1]
		cam.zoom = Vector2.ONE * float(v[2])
		m3.tilt = float(v[3])
		m3._apply_tilt()
		for i in 16:
			await process_frame
		root.get_texture().get_image().save_png("%s/water_%s.png" % [out, v[0]])
	m3.water_on = false
	cam.position = VIEWS[0][1]
	cam.zoom = Vector2.ONE * float(VIEWS[0][2])
	m3.tilt = float(VIEWS[0][3])
	m3._apply_tilt()
	for i in 16:
		await process_frame
	root.get_texture().get_image().save_png("%s/water_off.png" % out)
	quit(0)
