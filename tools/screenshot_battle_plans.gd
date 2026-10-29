extends SceneTree
## Pictures of the Battle Plans toolbar: Germany at war with Russia, two armies on the eastern front, the 8th Army
## selected with a push planned; then the Attack line tool in hand mid-drag, the card's menu of orders, a fallback line
## being dragged, an army group, division chips and the map modes list, and 3D:
##   godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/screenshot_battle_plans.gd -- out_dir
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_toolbar_settings.cfg"
	load("res://scripts/ui/ui_settings.gd").command_open = true
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("Clock")
	var MD: Node = root.get_node("MapData")
	var out: String = OS.get_cmdline_user_args()[0]
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
	for w in gs.wars.values().duplicate():
		gs.set_war(w.a, w.b, false)
	gs.set_war("GER", "RUS", true)
	gs.pending_joins.clear()
	var Mil = load("res://scripts/sim/military.gd")
	var FS = load("res://scripts/sim/front_solver.gd")
	var make = load("res://scripts/sim/designate_front.gd").new("GER", "Eastern Front", [] as Array[int], "RUS")
	gs.issue(make)
	var front = gs.fronts[make.front_id]
	var line: Array[int] = FS.order_line(front.provinces)
	var UnitC = load("res://scripts/sim/unit.gd")
	var armies: Array = []
	for k in 2:
		var a = Mil.new_army(gs, "GER", ["8th Army", "9th Army"][k], line[[line.size() / 2 + 2, line.size() - 2][k]])
		for i in 14:
			a.units.append(UnitC.new("infantry" if i % 4 != 3 else "artillery"))
		armies.append(a)
	gs.issue(load("res://scripts/sim/assign_to_front.gd").new("GER", front.id, [armies[0].id, armies[1].id] as Array[int]))
	for d in 25:
		clock.advance_day()
	# The 9th Army has a spearhead at Warsaw.
	var warsaw := 0
	for c in gs.cities:
		if c.name == "Warsaw":
			warsaw = c.province
	gs.issue(load("res://scripts/sim/plan_offensive.gd").new("GER", armies[1].id, "spearhead", [warsaw] as Array[int], "aggressive"))
	for d in 5:
		clock.advance_day()
	var cam: Camera2D = main.camera
	cam.position = MD.provinces[line[line.size() / 2]].center + Vector2(40, 60)
	cam.zoom = Vector2.ONE * 0.62
	var stack = FS.stacks_of(gs, armies[0])[0]
	get_first_node_in_group("military_panel").select_ids([stack.id] as Array[int])
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png("%s/toolbar_1_selected.png" % out)
	# The Offensive line tool in hand, dragged across Russian ground in front of the 8th Army.
	var bar: Node = get_first_node_in_group("battle_plan_toolbar")
	bar.set_tool("offensive")
	# Russian ground two provinces in from the border, near the 8th Army.
	var from: Vector2 = MD.provinces[stack.province].center
	var ring1 := {}
	for id in range(1, gs.province_controller.size()):
		if gs.province_controller[id] == "RUS" and Mil.neighbors(id).any(func(n: int) -> bool: return gs.province_controller[n] == "GER"):
			ring1[id] = true
	var near: Array[int] = []
	for id in range(1, gs.province_controller.size()):
		if gs.province_controller[id] == "RUS" and not ring1.has(id) and Mil.neighbors(id).any(func(n: int) -> bool: return ring1.has(n)):
			near.append(id)
	near.sort_custom(func(a: int, b: int) -> bool: return (MD.provinces[a].center as Vector2).distance_to(from) < (MD.provinces[b].center as Vector2).distance_to(from))
	var stroke: Array[int] = near.slice(0, 4)
	stroke.sort_custom(func(a: int, b: int) -> bool: return (MD.provinces[a].center as Vector2).y < (MD.provinces[b].center as Vector2).y)
	bar.map_press(stroke[0], 0, MOUSE_BUTTON_RIGHT, false)
	for p in stroke:
		bar.map_drag(p)
	var screen_at: Vector2 = main.get_viewport().get_canvas_transform() * (MD.provinces[stroke[-1]].center as Vector2)
	Input.warp_mouse(screen_at)
	bar._hint.position = screen_at + Vector2(18, 20)
	for i in 6:
		await process_frame
	bar._hint.position = screen_at + Vector2(18, 20)
	await process_frame
	root.get_texture().get_image().save_png("%s/toolbar_2_offensive_drag.png" % out)
	bar.map_release(stroke[-1], MOUSE_BUTTON_RIGHT)
	Input.warp_mouse(Vector2(800, 150))
	var o = load("res://scripts/sim/offensives.gd").of_army(gs, armies[0])
	print("PLAN %s targets %d" % [o.kind if o != null else "none", o.targets().size() if o != null else 0])
	for d in 3:
		clock.advance_day()
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png("%s/toolbar_3_planned.png" % out)
	# The 8th Army advances (its card's green arrow) and goes on exercise; the card's right click menu of orders.
	var cmd: Node = get_first_node_in_group("command_panel")
	cmd._on_card_advance("army", armies[0].id)
	gs.issue(load("res://scripts/sim/set_training.gd").new("GER", [armies[1].id] as Array[int], true))
	for i in 4:
		await process_frame
	var card_8 = cmd._cards.find_children("*", "CommandCard", true, false).filter(func(c) -> bool: return c.title == "8th Army")[0]
	cmd._on_card_context(card_8.get_global_rect().position + Vector2(30, -10), "army", armies[0].id)
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png("%s/toolbar_4_card_menu.png" % out)
	cmd._menu.hide()
	# A fallback line dragged behind the front.
	var behind: Array[int] = []
	for id in range(1, gs.province_controller.size()):
		if gs.province_controller[id] == "GER" and Mil.neighbors(id).all(func(n: int) -> bool: return gs.province_controller[n] == "GER"):
			if (MD.provinces[id].center as Vector2).distance_to(MD.provinces[stack.province].center) < 260.0:
				behind.append(id)
	behind = FS.order_line(behind).slice(0, 4)
	bar.set_tool("fallback")
	bar.map_press(behind[0], 0, MOUSE_BUTTON_LEFT, false)
	for p in behind:
		bar.map_drag(p)
	var at2: Vector2 = main.get_viewport().get_canvas_transform() * (MD.provinces[behind[-1]].center as Vector2)
	for i in 6:
		await process_frame
	bar._hint.position = at2 + Vector2(18, 20)
	await process_frame
	root.get_texture().get_image().save_png("%s/toolbar_5_fallback_drag.png" % out)
	bar.set_tool("")
	# An army group: the 8th and 9th Armies under a field marshal, the whole group selected from his card.
	var made = load("res://scripts/sim/create_army_group.gd").new("GER", "Army Group East", [armies[0].id, armies[1].id] as Array[int])
	gs.issue(made)
	var marshal = Mil.new_general(gs, "GER", "Paul von Hindenburg", 1.2)
	gs.issue(load("res://scripts/sim/set_marshal.gd").new("GER", made.group_id, marshal.id))
	cmd._on_select_group(made.group_id, false)
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png("%s/toolbar_7_army_group.png" % out)
	# The row the "+" button opens.
	bar._extend.button_pressed = true
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png("%s/toolbar_9_plus_row.png" % out)
	bar._extend.button_pressed = false
	# The division chips of one army, and the map modes' list, open.
	get_first_node_in_group("military_panel").select_ids([armies[0].id] as Array[int])
	cmd._more_open = true
	cmd._refresh()
	get_first_node_in_group("map_modes").set_open(true)
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png("%s/toolbar_8_chips_and_map_modes.png" % out)
	cmd._more_open = false
	cmd._refresh()
	get_first_node_in_group("map_modes").set_open(false)
	var m3: Node = get_first_node_in_group("map_3d")
	m3.set_enabled(true)
	cam.zoom = Vector2.ONE * 0.95
	m3.tilt = 50.0
	m3._apply_tilt()
	for i in 16:
		await process_frame
	root.get_texture().get_image().save_png("%s/toolbar_6_3d.png" % out)
	quit(0)
