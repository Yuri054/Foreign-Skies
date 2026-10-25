extends SceneTree
## Saves a picture of the national focus window. Run in a window:
##   godot --path . --resolution 1280x720 -s res://tools/screenshot_focus.gd -- out_dir [nation] [focus_to_select]
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_focus_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	for picker in get_nodes_in_group("nation_picker"):
		picker.queue_free()
	await process_frame
	var args := OS.get_cmdline_user_args()
	var nation: String = args[1] if args.size() > 1 else "GER"
	var tree: Array = load("res://scripts/sim/focus.gd").tree_of(nation)
	var pick: String = args[2] if args.size() > 2 else tree[1].id
	gs.set_player(nation)
	gs.issue(load("res://scripts/sim/set_focus.gd").new(nation, tree[0].id))
	gs.nations[nation].focus.days_left = 30
	get_nodes_in_group("focus_panel")[0].toggle()
	get_nodes_in_group("focus_panel")[0].select(pick)
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png("%s/focus_%s.png" % [dir, nation])
	quit(0)
