extends SceneTree
## Saves pictures of a historical event waiting for the player and of the Overview with Europe's tension.
##   godot --path . --resolution 1600x900 -s res://tools/screenshot_event.gd -- out_dir [event_month_year e.g. 1905-3]
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("Clock")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	var args := OS.get_cmdline_user_args()
	var dir: String = args[0] if args.size() > 0 else "user://"
	var when: PackedStringArray = (args[1] if args.size() > 1 else "1905-4").split("-")
	gs.load_scenario("res://data/scenarios/jan_1900/")
	gs.set_player(args[2] if args.size() > 2 else "FRA")
	gs.ai_enabled = true
	while clock.year * 12 + clock.month < int(when[0]) * 12 + int(when[1]):
		clock.advance_day()
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png("%s/event.png" % dir)
	for d: Dictionary in gs.pending_events.duplicate():
		gs.issue(load("res://scripts/sim/answer_event.gd").new(d.id, 0))
	for i in 4:
		await process_frame
	get_first_node_in_group("nation_screen").open_page("Overview")
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png("%s/event_overview.png" % dir)
	quit(0)
