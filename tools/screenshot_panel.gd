extends SceneTree
## Saves a picture of the main scene with the command panel showing a group, to look at the
## layout. Run (with a window, not headless):
##   godot --path . --resolution 1600x900 -s res://tools/screenshot_panel.gd -- out.png [navy]


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var args := OS.get_cmdline_user_args()
	var Mil = load("res://scripts/sim/military.gd")
	gs.set_player("FRA")
	var mine: Array = []
	for a in gs.armies.values():
		if a.tag == "FRA":
			mine.append(a)
	mine.sort_custom(func(x, y) -> bool: return x.id < y.id)
	var ids: Array[int] = [mine[0].id, mine[1].id, mine[2].id]
	var made = load("res://scripts/sim/create_army_group.gd").new("FRA", "1st Army Group", ids)
	gs.issue(made)
	var marshal = Mil.new_general(gs, "FRA", "Maurice Sarrail", 1.1)
	gs.issue(load("res://scripts/sim/set_marshal.gd").new("FRA", made.group_id, marshal.id))
	var rest: Array[int] = [mine[3].id, mine[4].id]
	gs.issue(load("res://scripts/sim/create_army_group.gd").new("FRA", "2nd Army Group", rest))
	var sel: Array[int] = [mine[1].id]
	get_first_node_in_group("military_panel").select_ids(sel)
	if args.size() > 1 and args[1] == "navy":
		gs.set_player("GBR")
		var navy: Node = get_first_node_in_group("navy_panel")
		for f in gs.fleets.values():
			if f.tag == "GBR" and f.display_name == "Grand Fleet":
				var fid: Array[int] = [f.id]
				navy.select_fleets(fid)
	for i in 6:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(args[0] if args.size() > 0 else "user://panel.png")
	quit(0)
