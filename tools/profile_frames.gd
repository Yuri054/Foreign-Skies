extends SceneTree
## Where a frame goes, flat and in 3D: the engine's process and physics times, draw calls and objects per frame,
## and the time of the map's own per-frame work (markers, cities, banners), measured by calling it directly.
##   godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/profile_frames.gd
func _frames(label: String, n: int) -> void:
	var process := 0.0
	var calls := 0.0
	var objects := 0.0
	var prims := 0.0
	var wall := Time.get_ticks_usec()
	for i in n:
		await process_frame
		process += Performance.get_monitor(Performance.TIME_PROCESS)
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var ms := (Time.get_ticks_usec() - wall) / 1000.0 / n
	print("%-28s frame %6.1f ms | script-process %5.2f ms | draw calls %6.0f | objects %6.0f | primitives %8.0f" % [label, ms, process / n * 1000.0, calls / n, objects / n, prims / n])


func _time(label: String, n: int, work: Callable) -> void:
	var start := Time.get_ticks_usec()
	for i in n:
		work.call()
	print("%-28s %7.3f ms per call" % [label, (Time.get_ticks_usec() - start) / 1000.0 / n])


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://profile_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	await process_frame
	gs.set_player("GER")
	var cam: Camera2D = main.camera
	var m3: Node = get_first_node_in_group("map_3d")
	var spot := Vector2(3300, 2400)
	for a in gs.armies.values():
		if a.tag == "GER":
			spot = root.get_node("MapData").provinces[a.province].center
			break
	for z in [0.3, 1.0, 2.5]:
		cam.zoom = Vector2(z, z)
		cam.position = spot
		await _frames("2D zoom %.1f" % z, 60)
	var armies: Node = get_first_node_in_group("army_layer")
	var fleets: Node = get_first_node_in_group("fleet_layer")
	_time("army collect_markers", 30, func() -> void: armies.collect_markers())
	_time("fleet collect_markers", 30, func() -> void: fleets.collect_markers())
	m3.set_enabled(true)
	for z in [0.3, 1.0, 2.5]:
		cam.zoom = Vector2(z, z)
		cam.position = spot
		m3.tilt = 45.0
		m3._apply_tilt()
		await _frames("3D zoom %.1f" % z, 60)
		_time("  Map3D._update_markers", 20, func() -> void: m3._update_markers())
		_time("  CityModels.update", 20, func() -> void: m3._cities.update(m3, z))
	m3.cities_on = false
	cam.zoom = Vector2(1.0, 1.0)
	await _frames("3D, cities off", 60)
	m3.markers_on = false
	await _frames("3D, cities+units off", 60)
	quit(0)
