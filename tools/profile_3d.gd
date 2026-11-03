extends SceneTree
## What a frame of the 3D map costs in the ways it is used: panning (the map moved the same distance each frame, as the
## keys move it at 60 frames a second), the mouse moved over a still map, the map left alone with the clock running,
## and a step of the wheel; then the map's own per-frame script work, timed by calling it with its caches cleared.
## Each line gives the frame's wall time, the frames in which the picture of the flat map was painted, and the draw
## calls and primitives. Runs on the old Map3D too (the repaint count is then left out).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/profile_3d.gd
## Under xvfb there is no graphics card (llvmpipe draws on the CPU, without vsync), so a frame's wall time is all of its
## work, CPU and GPU: the figures are far above a real card's but compare fairly.

var cam: Camera2D
var m3: Node
var spot := Vector2(3300, 2400)
var _dir := 1.0


func _frames(label: String, n: int, step: Callable) -> float:
	for i in 3:
		step.call()
		await process_frame
	var calls := 0.0
	var prims := 0.0
	var paints := 0
	var last_paint: int = m3.get("_painted_at") if "_painted_at" in m3 else 0
	var wall := Time.get_ticks_usec()
	for i in n:
		step.call()
		await process_frame
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		if "_painted_at" in m3 and m3._painted_at != last_paint:
			last_paint = m3._painted_at
			paints += 1
	var ms := (Time.get_ticks_usec() - wall) / 1000.0 / n
	var painted := ("%3d of %d" % [paints, n]) if "_painted_at" in m3 else "   ?     "
	print("%-30s frame %6.1f ms | picture painted %s | draw calls %4.0f | primitives %7.0f" % [label, ms, painted, calls / n, prims / n])
	return ms


## A pan as the keys make it at 60 frames a second (800 screen pixels a second), back and forth along a stretch.
func _pan() -> void:
	cam.position.x += _dir * 800.0 / 60.0 / cam.zoom.x
	if absf(cam.position.x - spot.x) > 600.0 / cam.zoom.x:
		_dir = -_dir


func _hover() -> void:
	var ev := InputEventMouseMotion.new()
	var t := Time.get_ticks_msec() / 400.0
	ev.position = Vector2(800, 450) + Vector2(cos(t), sin(t)) * 200.0
	ev.global_position = ev.position
	ev.relative = Vector2(3, 2)
	Input.parse_input_event(ev)


func _time(label: String, n: int, work: Callable) -> void:
	var start := Time.get_ticks_usec()
	for i in n:
		work.call()
	print("%-30s %7.3f ms per call" % [label, (Time.get_ticks_usec() - start) / 1000.0 / n])


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://profile_3d_settings.cfg"
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
	gs.ai_enabled = false
	var clock: Node = root.get_node("Clock")
	cam = main.camera
	m3 = get_first_node_in_group("map_3d")
	for a in gs.armies.values():
		if a.tag == "GER":
			spot = root.get_node("MapData").provinces[a.province].center
			break
	m3.set_enabled(true)
	m3.tilt = 50.0
	m3._apply_tilt()
	var still := func() -> void: pass
	for z in [0.45, 1.0, 2.0]:
		cam.zoom = Vector2(z, z)
		cam.position = spot
		print("zoom %.2f" % z)
		await _frames("  panning", 60, _pan)
		cam.position = spot
		await _frames("  mouse over a still map", 60, _hover)
		clock.paused = false
		clock.speed = 3
		await _frames("  left alone, clock running", 60, still)
		clock.paused = true
		await _frames("  left alone, paused", 60, still)
	cam.zoom = Vector2(1.0, 1.0)
	cam.position = spot
	var wheel := func() -> void:
		cam.zoom *= 1.1 if _dir > 0.0 else 1.0 / 1.1
		if cam.zoom.x > 2.0 or cam.zoom.x < 0.6:
			_dir = -_dir
	await _frames("wheel turned every frame", 30, wheel)
	cam.zoom = Vector2(1.0, 1.0)
	var armies: Node = get_first_node_in_group("army_layer")
	var fleets: Node = get_first_node_in_group("fleet_layer")
	print("script work per call (zoom 1)")
	_time("  markers (layers' lists)", 10, func() -> void: armies.collect_markers(); fleets.collect_markers())
	_time("  unit models, camera moved", 10, func() -> void:
		m3._marker_signature = []
		m3._update_markers())
	_time("  unit models, layers changed", 10, func() -> void:
		m3._markers_dirty = true
		m3._marker_signature = []
		m3._update_markers())
	_time("  city models", 10, func() -> void: m3._cities.update(m3, 1.0))
	quit(0)
