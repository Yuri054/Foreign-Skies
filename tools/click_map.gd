extends SceneTree
## Clicks the open map with real mouse events and reports whether a province was selected, then
## presses on the map and releases over a window to check that does not select one. Run in a window.
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://clickmap_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	gs.set_player("FRA")
	for i in 6:
		await process_frame
	var picked := []
	main.map_view.province_selected.connect(func(id: int) -> void: picked.append(id))
	var tf := root.get_final_transform()
	await _click(tf * Vector2(400, 250), tf * Vector2(400, 250))
	print("click on the open map selected: ", picked)
	picked.clear()
	get_first_node_in_group("economy_panel").toggle()
	for i in 4:
		await process_frame
	var win: Control = get_first_node_in_group("economy_panel")
	var over: Vector2 = tf * win.get_global_rect().get_center()
	await _click(tf * Vector2(400, 250), over)
	print("press on the map, release over a window selected: ", picked)
	quit(0)


func _click(down: Vector2, up: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = down
	mm.global_position = down
	Input.parse_input_event(mm)
	await process_frame
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.position = down
	mb.global_position = down
	mb.pressed = true
	Input.parse_input_event(mb)
	await process_frame
	mm = InputEventMouseMotion.new()
	mm.position = up
	mm.global_position = up
	Input.parse_input_event(mm)
	await process_frame
	mb = mb.duplicate()
	mb.position = up
	mb.global_position = up
	mb.pressed = false
	Input.parse_input_event(mb)
	await process_frame
	await process_frame
