extends SceneTree
## The Overview with the cabinet briefing: godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/screenshot_briefing.gd -- out.png [TAG]
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_brief_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	await process_frame
	var a := OS.get_cmdline_user_args()
	gs.set_player(a[1] if a.size() > 1 else "GER")
	gs.ai_enabled = false
	root.get_node("Clock").advance_day()
	for i in 20:
		root.get_node("Clock").advance_day()
	gs.tension_history.assign([38.0, 39.0, 41.0, 40.0, 44.0, 47.0, 50.0, 49.0, 53.0, 58.0, 61.0, 64.0])
	var screen: Node = get_first_node_in_group("nation_screen")
	screen.open_page(get_first_node_in_group("overview_panel"))
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(a[0])
	quit(0)
