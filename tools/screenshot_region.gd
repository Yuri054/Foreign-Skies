extends SceneTree
## Saves the flat political map centred on a point: godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/screenshot_region.gd -- out.png x y zoom [mode]
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_region_settings.cfg"
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
	cam.position = Vector2(float(a[1]), float(a[2]))
	cam.zoom = Vector2.ONE * float(a[3])
	for i in 12:
		await process_frame
	root.get_texture().get_image().save_png(a[0])
	quit(0)
