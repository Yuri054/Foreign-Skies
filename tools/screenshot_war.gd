extends SceneTree
## Plays an AI-only 1914 and saves pictures of the war at given dates, the whole of Europe and the two main fronts.
##   godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/screenshot_war.gd -- out_dir [seed] [days,days,...]
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_war_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("Clock")
	var a := OS.get_cmdline_user_args()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	await process_frame
	gs.load_scenario("res://data/scenarios/july_1914/")
	gs.set_player("ESP")
	gs.player_tag = ""   # nobody plays: every army is shown, and the AI plays every nation
	gs.ai_enabled = true
	gs.ai_seed = int(a[1]) if a.size() > 1 else 0
	var days: PackedStringArray = (a[2] if a.size() > 2 else "70,140,230,330").split(",")
	var cam: Camera2D = main.camera
	var views := [["europe", Vector2(3100, 2650), 0.36], ["west", Vector2(2480, 2560), 0.62], ["east", Vector2(3250, 2380), 0.62]]
	for d in days:
		while clock.days_elapsed < int(d):
			clock.advance_day()
			gs.pending_events.clear()
			gs.pending_offers.clear()
			gs.pending_joins.clear()
		for prompt in get_nodes_in_group("event_prompt"):
			prompt.visible = false
		for v in views:
			cam.position = v[1]
			cam.zoom = Vector2.ONE * float(v[2])
			for i in 10:
				await process_frame
			root.get_texture().get_image().save_png("%s/war_%s_%s.png" % [a[0], d, v[0]])
		print("saved day ", d, " ", clock.date_string())
	quit(0)
