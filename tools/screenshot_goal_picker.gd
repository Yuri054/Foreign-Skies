extends SceneTree
## The demand picker (the goal picker) and the peace screen with a goal: godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/screenshot_goal_picker.gd -- out_dir
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_goal_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var G = load("res://scripts/sim/war_goal.gd")
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
	gs.nations["GER"].diplomacy_points = 120.0
	var out: String = OS.get_cmdline_user_args()[0]
	var panel: Node = get_first_node_in_group("diplomacy_panel")
	var picker: Node = get_first_node_in_group("goal_picker")
	panel.show_nation("BEL")
	for i in 3:
		await process_frame
	picker.open("BEL")
	picker._provinces.select(0, false)
	picker._refresh()
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png(out + "/goal_picker.png")
	picker.visible = false
	gs.set_war("GER", "BEL", true, "fabricated_claim")
	var war = gs.war_between("GER", "BEL")
	war.goal = G.provinces_goal([gs.nations["BEL"].provinces[0], gs.nations["BEL"].provinces[1]])
	var screen: Node = get_first_node_in_group("peace_screen")
	screen.open_war(war.id)
	for i in 4:
		await process_frame
	screen._goal_button.pressed.emit()
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png(out + "/goal_peace.png")
	quit(0)
