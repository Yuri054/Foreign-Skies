extends SceneTree
## Pictures of the 0.14.0 front UI: the plans of tools/screenshot_plans.gd, a fallback line behind them held by a
## reserve army and a garrison on three cities; the Military tab open on the Fronts section with the 8th Army
## selected (its attack plan); the command bar's Plan menu; and the same in 3D:
##   godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/screenshot_plan_ui.gd -- out_dir
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_plans_settings.cfg"
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
		var a = Mil.new_army(gs, "GER", ["8th Army", "9th Army"][k], line[[1, line.size() - 2][k]])
		for i in 14:
			a.units.append(UnitC.new("infantry" if i % 4 != 3 else "artillery"))
		armies.append(a)
	gs.issue(load("res://scripts/sim/assign_to_front.gd").new("GER", front.id, [armies[0].id, armies[1].id] as Array[int]))
	for d in 30:
		clock.advance_day()
	# Rings of Russian provinces one and two deep, the northern half for the 8th Army's push.
	var ring1: Array[int] = []
	var ring2: Array[int] = []
	var seen := {}
	for id in range(1, gs.province_controller.size()):
		if gs.province_controller[id] == "GER":
			for n: int in Mil.neighbors(id):
				if gs.province_controller[n] == "RUS" and not seen.has(n):
					seen[n] = true
					ring1.append(n)
	for p in ring1:
		for n: int in Mil.neighbors(p):
			if gs.province_controller[n] == "RUS" and not seen.has(n):
				seen[n] = true
				ring2.append(n)
	var north := func(list: Array[int]) -> Array[int]:
		# The four provinces of the ring nearest to the 8th Army's stretch of the front.
		var out_: Array[int] = []
		var mid := Vector2.ZERO
		var stacks: Array = FS.stacks_of(gs, armies[0])
		for st in stacks:
			mid += MD.provinces[st.province].center
		mid /= maxf(stacks.size(), 1.0)
		out_.assign(list)
		out_.sort_custom(func(a: int, b: int) -> bool: return (MD.provinces[a].center as Vector2).distance_to(mid) < (MD.provinces[b].center as Vector2).distance_to(mid))
		return out_.slice(0, 4)
	var plan = load("res://scripts/sim/plan_offensive.gd").new("GER", armies[0].id, "broad", north.call(ring2), "balanced")
	gs.issue(plan)
	var deeper: Array[int] = []
	for p in north.call(ring2):
		for n: int in Mil.neighbors(p):
			if gs.province_controller[n] == "RUS" and not seen.has(n):
				seen[n] = true
				deeper.append(n)
	gs.issue(load("res://scripts/sim/set_offensive.gd").new("GER", plan.offensive_id, "phase", deeper))
	var warsaw := 0
	for c in gs.cities:
		if c.name == "Warsaw":
			warsaw = c.province
	gs.issue(load("res://scripts/sim/plan_offensive.gd").new("GER", armies[1].id, "spearhead", [warsaw] as Array[int], "aggressive"))
	# A fallback line: German ground three steps from the Russian border, near the 8th Army; a reserve army holds it.
	var depth := {}
	var frontier: Array[int] = []
	for id in range(1, gs.province_controller.size()):
		if gs.province_controller[id] == "GER" and Mil.neighbors(id).any(func(n: int) -> bool: return gs.province_controller[n] == "RUS"):
			depth[id] = 1
			frontier.append(id)
	for step in 3:
		var next: Array[int] = []
		for p in frontier:
			for n: int in Mil.neighbors(p):
				if gs.province_controller[n] == "GER" and not depth.has(n):
					depth[n] = step + 2
					next.append(n)
		frontier = next
	# A chain of neighbouring provinces two to four steps back, from the one three steps back nearest the 8th Army.
	var anchor: Vector2 = MD.provinces[armies[0].province].center
	var start := 0
	for p: int in depth:
		if depth[p] == 3 and (start == 0 or (MD.provinces[p].center as Vector2).distance_to(anchor) < (MD.provinces[start].center as Vector2).distance_to(anchor)):
			start = p
	var back: Array[int] = [start]
	for k in 5:
		var best := 0
		for n: int in Mil.neighbors(back[-1]):
			if depth.get(n, 0) in [2, 3, 4] and not back.has(n) and (best == 0 or abs(depth[n] - 3) < abs(depth[best] - 3)):
				best = n
		if best == 0:
			break
		back.append(best)
	var DF = load("res://scripts/sim/designate_front.gd")
	print("FALLBACK %d problem '%s'" % [back.size(), DF.problem(gs, "GER", back)])
	var fb = DF.new("GER", "Warthe Line", back)
	gs.issue(fb)
	var reserve = Mil.new_army(gs, "GER", "Reserve Army", back[0])
	for i in 8:
		reserve.units.append(UnitC.new("infantry"))
	gs.issue(load("res://scripts/sim/assign_to_front.gd").new("GER", fb.front_id, [reserve.id] as Array[int]))
	# A garrison on three cities, held by a guard army.
	var guarded: Array[int] = []
	for c in gs.cities:
		if c.name in ["Berlin", "Danzig", "Breslau"]:
			guarded.append(c.province)
	var gar = DF.new("GER", "Home Garrison", guarded, "", "garrison")
	print("GARRISON %d problem '%s'" % [guarded.size(), DF.problem(gs, "GER", guarded, "", "garrison")])
	gs.issue(gar)
	var guard = Mil.new_army(gs, "GER", "Guard Army", guarded[0])
	for i in 6:
		guard.units.append(UnitC.new("infantry"))
	gs.issue(load("res://scripts/sim/assign_to_front.gd").new("GER", gar.front_id, [guard.id] as Array[int]))
	for d in 16:
		clock.advance_day()
	# A fresh army put on the Eastern Front marches its detachments to their places; an army from the west goes east by
	# rail.
	var fresh = Mil.new_army(gs, "GER", "10th Army", guarded[0])
	for i in 10:
		fresh.units.append(UnitC.new("infantry"))
	gs.issue(load("res://scripts/sim/assign_to_front.gd").new("GER", front.id, [fresh.id] as Array[int]))
	var western = null
	for a in Mil.armies_of(gs, "GER"):
		if a.front_id == 0 and a.parent_id == 0 and (MD.provinces[a.province].center as Vector2).x < anchor.x - 500.0:
			western = a
			break
	if western != null:
		gs.issue(load("res://scripts/sim/move_army.gd").new("GER", western.id, back[back.size() / 2]))
	clock.advance_day()
	var rail := 0
	for p in range(1, gs.province_controller.size()):
		if gs.province_controller[p] == "GER" and gs.province_buildings[p].get("railway", 0) > 0:
			rail += 1
	print("RAIL provinces %d western %s path %d" % [rail, western.display_name if western != null else "-", western.path.size() if western != null else 0])
	var cam: Camera2D = main.camera
	cam.position = MD.provinces[line[line.size() / 2]].center + Vector2(120, 0)
	cam.zoom = Vector2.ONE * 0.6
	for i in 6:
		await process_frame
	main.map_view.select(armies[0].province)
	var panel: Node = get_first_node_in_group("military_panel")
	call_group("nation_screen", "open_page", "Military")
	panel.show_tab("Fronts")
	await process_frame
	panel._refresh_fronts()
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png("%s/plan_ui_2d.png" % out)
	call_group("nation_screen", "close_screen")
	# The command bar with its Plan menu open.
	var bar: Node = get_first_node_in_group("command_panel")
	if not bar.is_open():
		bar.toggle()
	for i in 4:
		await process_frame
	bar._plan.show_popup()
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png("%s/plan_bar_2d.png" % out)
	bar._plan.get_popup().hide()
	var m3: Node = get_first_node_in_group("map_3d")
	m3.set_enabled(true)
	cam.zoom = Vector2.ONE * 0.9
	m3.tilt = 52.0
	m3._apply_tilt()
	for i in 16:
		await process_frame
	root.get_texture().get_image().save_png("%s/plan_ui_3d.png" % out)
	quit(0)
