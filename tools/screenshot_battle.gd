extends SceneTree
## Plays an AI-only 1914 until the first land battle ends (and a sea battle appears if one does) and saves pictures of
## the battle windows:  godot --path . --resolution 1280x720 -s res://tools/screenshot_battle.gd -- out_dir
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_battle_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("Clock")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	var dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://"
	gs.load_scenario("res://data/scenarios/july_1914/")
	gs.set_player("ESP")
	gs.ai_enabled = true
	var land := 0
	var sea := 0
	for d in 400:
		clock.advance_day()
		if land == 0:
			for b: Dictionary in gs.battle_archive.values():
				if b.days >= 4:
					land = b.id
					break
		if sea == 0 and not gs.sea_battle_archive.is_empty():
			sea = gs.sea_battle_archive.keys()[0]
		if land > 0 and (sea > 0 or d > 300):
			break
	print("land battle ", land, " sea battle ", sea)
	if land > 0:
		get_first_node_in_group("battle_screen").open_battle(land)
		for i in 6:
			await process_frame
		root.get_texture().get_image().save_png("%s/battle.png" % dir)
	if sea > 0:
		get_first_node_in_group("naval_battle_screen").open_battle(sea)
		for i in 6:
			await process_frame
		root.get_texture().get_image().save_png("%s/naval_battle.png" % dir)
	quit(0)
