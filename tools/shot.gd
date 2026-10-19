extends SceneTree
## Saves a screenshot of a scene after a few frames. Needs a window, so run it without --headless:
## godot --path . --resolution 1280x720 -s res://tools/shot.gd -- res://scenes/main.tscn out.png [province id [Mode [submode [war]]]]
## Mode is a name from MapView.Mode (MILITARY, CONSTRUCTION...); war starts a war between France and Germany.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var gs: Node = root.get_node("GameState")
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("FRA")
	var scene: Node = load(args[0]).instantiate()
	root.add_child(scene)
	for i in 30:
		await process_frame
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	if args.size() > 2 and int(args[2]) > 0:
		scene.get_node("MapView").select(int(args[2]))
	if args.size() > 5:
		gs.set_war("FRA", "GER", true)
	if args.size() > 3:
		var view: Sprite2D = scene.get_node("MapView")
		view.set_mode(view.get_script().Mode[args[3]], args[4] if args.size() > 4 else "")
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png(args[1])
	quit()
