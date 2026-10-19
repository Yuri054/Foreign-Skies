extends SceneTree
## Saves pictures of the 3D map mode (top-down, tilted) and checks that a click through the plane
## selects the province that lies under it. Run in a window:
##   godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/screenshot_3d.gd -- out_dir
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_3d_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var dir: String = OS.get_cmdline_user_args()[0]
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
	var cam: Camera2D = main.camera
	cam.zoom = Vector2(0.45, 0.45)
	cam.position = Vector2(2900, 2800)
	var m3: Node = get_first_node_in_group("map_3d")
	m3.set_enabled(true)
	m3.tilt = 90.0
	m3._apply_tilt()
	for i in 12:
		await process_frame
	root.get_texture().get_image().save_png(dir + "/3d_topdown.png")
	m3.tilt = 58.0
	m3._apply_tilt()
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(dir + "/3d_tilt.png")
	# A click through the plane: where the centre of the screen lands, and what the map says is there.
	var picked := []
	main.map_view.province_selected.connect(func(id: int) -> void: picked.append(id))
	var screen := root.get_final_transform() * Vector2(640, 360)
	var at: Vector2 = m3.to_picture(Vector2(640, 360))
	var world: Vector2 = main.map_view.to_local(cam.get_canvas_transform().affine_inverse() * at)
	var expected: int = root.get_node("MapData").province_at_pixel(Vector2i(world.floor()))
	print("centre of the screen is picture point ", at, " world ", world, " province ", expected)
	for pressed in [null, true, false]:
		var ev: InputEvent
		if pressed == null:
			var mm := InputEventMouseMotion.new()
			mm.position = screen
			mm.global_position = mm.position
			ev = mm
		else:
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.position = screen
			mb.global_position = mb.position
			mb.pressed = pressed
			ev = mb
		Input.parse_input_event(ev)
		for i in 3:
			await process_frame
	print("click selected province ", picked, " expected ", expected)
	# Off-centre, high on the tilted screen.
	for spot in [Vector2(1000, 180), Vector2(200, 600)]:
		picked.clear()
		var shot: Vector2 = m3.to_picture(spot)
		var w2: Vector2 = main.map_view.to_local(cam.get_canvas_transform().affine_inverse() * shot)
		var want: int = root.get_node("MapData").province_at_pixel(Vector2i(w2.floor()))
		var sc: Vector2 = root.get_final_transform() * spot
		for pressed2 in [null, true, false]:
			var ev2: InputEvent
			if pressed2 == null:
				var mm2 := InputEventMouseMotion.new()
				mm2.position = sc
				mm2.global_position = sc
				ev2 = mm2
			else:
				var mb2 := InputEventMouseButton.new()
				mb2.button_index = MOUSE_BUTTON_LEFT
				mb2.position = sc
				mb2.global_position = sc
				mb2.pressed = pressed2
				ev2 = mb2
			Input.parse_input_event(ev2)
			for i in 3:
				await process_frame
		print("click at ", spot, " selected ", picked, " expected ", want)
	m3.set_enabled(false)
	for i in 4:
		await process_frame
	print("back in 2D: map parent is Main: ", main.map_view.get_parent() == main, " camera current: ", main.camera.is_current())
	quit(0)
