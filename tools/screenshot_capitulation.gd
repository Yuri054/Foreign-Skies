extends SceneTree
## Pictures of capitulation (0.17.0): France's capital falls and the player picks where the government goes; the
## Military page's war panel with each side's capitulation progress; and Germany, as the player, dictating the peace
## after France capitulates:
##   godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/screenshot_capitulation.gd -- out_dir
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_capitulation_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var C = load("res://scripts/sim/capitulation.gd")
	var P = load("res://scripts/sim/peace.gd")
	var out: String = OS.get_cmdline_user_args()[0]
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	await process_frame
	gs.set_player("FRA")
	gs.ai_enabled = false
	for w in gs.wars.values().duplicate():
		gs.set_war(w.a, w.b, false)
	gs.pending_joins.clear()
	gs.set_war("FRA", "GER", true)
	gs.pending_joins.clear()
	# Germany takes the north of France and Paris.
	var ids: Array = gs.nations["FRA"].provinces.duplicate()
	var paris: Vector2 = root.get_node("MapData").provinces[233].center
	ids.sort_custom(func(a: int, b: int) -> bool:
		return (root.get_node("MapData").provinces[a].center as Vector2).distance_to(paris) < (root.get_node("MapData").provinces[b].center as Vector2).distance_to(paris))
	for id: int in ids.slice(0, 14):
		gs.set_controller(id, "GER")
	var war = gs.war_between("FRA", "GER")
	P.record_battle(war, {"winner": "GER", "lost": {"FRA": 60000.0, "GER": 20000.0}})
	C.step_day(gs)
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png("%s/capital_prompt.png" % out)

	var pick: int = gs.capital_choice.candidates[0]
	gs.issue(load("res://scripts/sim/move_capital.gd").new("FRA", pick))
	var panel: Node = get_first_node_in_group("military_panel")
	call_group("nation_screen", "open_page", "Military")
	panel._war_selected = war.id
	panel.show_tab("Wars")
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png("%s/war_panel.png" % out)
	call_group("nation_screen", "close_screen")

	# Germany as the player: France capitulates and the peace screen opens to dictate.
	gs.set_player("GER")
	ids.sort_custom(func(a: int, b: int) -> bool: return P.province_value(gs, a) < P.province_value(gs, b))
	for id: int in ids:
		if C.progress(gs, "FRA") >= 0.8:
			break
		gs.set_controller(id, "GER")
	gs.set_controller(gs.nations["FRA"].capital, "GER")
	C.step_day(gs)
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png("%s/dictate_peace.png" % out)
	quit()
