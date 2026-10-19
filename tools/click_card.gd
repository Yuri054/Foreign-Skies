extends SceneTree
## Clicks the first army card of the command panel with real mouse events and reports what
## happened. Run in a window: xvfb-run -a godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/click_card.gd
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://click_settings.cfg"
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
	main.map_view.province_selected.connect(func(id: int) -> void:
		picked.append(id)
		print_stack())
	var cards := []
	var stack := [get_first_node_in_group("command_panel")]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n.get_script() != null and n.get_script().resource_path.ends_with("command_card.gd") and n.is_visible_in_tree():
			cards.append(n)
	print("cards: ", cards.size())
	cards.sort_custom(func(a, b) -> bool: return a.get_global_rect().position.x < b.get_global_rect().position.x)
	for c in cards:
		print("  card ", c.get_global_rect(), " title ", c.title)
	var card: Control = cards[0]
	var pos: Vector2 = root.get_final_transform() * card.get_global_rect().get_center()
	print("card at ", card.get_global_rect(), " hovered control: ", root.gui_get_hovered_control())
	var selected_before: Array = main.get("selected_armies") if main.get("selected_armies") != null else []
	card.pressed.connect(func(shift: bool) -> void: print("card pressed signal, shift ", shift))
	main.map_view.army_clicked.connect(func(id: int, add: bool) -> void: print("army_clicked on map ", id))
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	Input.parse_input_event(mm)
	await process_frame
	await process_frame
	print("hovered control after motion: ", root.gui_get_hovered_control())
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.position = pos
		mb.global_position = pos
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		Input.parse_input_event(mb)
		await process_frame
		await process_frame
	var mil := get_first_node_in_group("military_panel")
	print("map pressing: ", main.map_view._pressing)
	print("province_selected fired: ", picked, "  military selection: ", mil.get("selected") if mil.get("selected") != null else mil.get("_selected"))
	quit(0)
