extends SceneTree
## Pictures of a spreading front: Germany's eastern armies put on a front facing Russia, forty days on, on the flat map
## and in 3D:
##   godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/screenshot_front.gd -- out_dir
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_front_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var clock: Node = root.get_node("Clock")
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
	gs.pending_joins.clear()
	var Mil = load("res://scripts/sim/military.gd")
	var FS = load("res://scripts/sim/front_solver.gd")
	var make = load("res://scripts/sim/designate_front.gd").new("GER", "Eastern Front", [] as Array[int], "RUS")
	gs.issue(make)
	var front = gs.fronts[make.front_id]
	var line: Array[int] = FS.order_line(front.provinces)
	var middle: Vector2 = root.get_node("MapData").provinces[line[line.size() / 2]].center
	var ids: Array[int] = []
	for a in Mil.armies_of(gs, "GER"):
		if (root.get_node("MapData").provinces[a.province].center as Vector2).distance_to(middle) < 700.0:
			ids.append(a.id)
	gs.issue(load("res://scripts/sim/assign_to_front.gd").new("GER", front.id, ids))
	for d in 45:
		clock.advance_day()
	var cam: Camera2D = main.camera
	cam.position = middle
	cam.zoom = Vector2.ONE * 0.55
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png("%s/front_2d.png" % out)
	var m3: Node = get_first_node_in_group("map_3d")
	m3.set_enabled(true)
	cam.zoom = Vector2.ONE * 1.1
	m3.tilt = 50.0
	m3._apply_tilt()
	for i in 16:
		await process_frame
	root.get_texture().get_image().save_png("%s/front_3d.png" % out)
	for a in Mil.armies_of(gs, "GER"):
		var r = FS.root_of(gs, a)
		if r != null and r.front_id == front.id:
			print("STACK %d root %d units %d on_line %s path %d prov %s" % [a.id, r.id, a.units.size(), front.provinces.has(a.province), a.path.size(), root.get_node("MapData").provinces[a.province].name])
	print("LINE %d provinces" % front.provinces.size())
	print("ARMIES %d STACKS %d" % [ids.size(), gs.armies.values().filter(func(a) -> bool: return a.tag == "GER" and a.parent_id != 0).size()])
	quit(0)
