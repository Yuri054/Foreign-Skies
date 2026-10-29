extends SceneTree
## Pictures of plans of attack on the map: Germany at war with Russia, two armies on a broad front facing it, one
## pushing to a line in two phases, the other with a spearhead at Warsaw; on the flat map and in 3D:
##   godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/screenshot_plans.gd -- out_dir
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
	for d in 16:
		clock.advance_day()
	var cam: Camera2D = main.camera
	cam.position = MD.provinces[line[line.size() / 2]].center + Vector2(120, 0)
	cam.zoom = Vector2.ONE * 0.6
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png("%s/plans_2d.png" % out)
	var m3: Node = get_first_node_in_group("map_3d")
	m3.set_enabled(true)
	cam.zoom = Vector2.ONE * 0.9
	m3.tilt = 52.0
	m3._apply_tilt()
	for i in 16:
		await process_frame
	root.get_texture().get_image().save_png("%s/plans_3d.png" % out)
	quit(0)
