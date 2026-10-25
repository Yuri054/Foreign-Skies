extends SceneTree
## The Diplomacy mode's mouse tip: godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/screenshot_diplo_tip.gd -- out.png
func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://shot_tip_settings.cfg"
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
	var cam: Camera2D = main.camera
	var fra: int = 0
	for id in gs.province_owner.size():
		if gs.province_owner[id] == "FRA":
			fra = id
			break
	cam.position = root.get_node("MapData").provinces[fra].center
	cam.zoom = Vector2.ONE * 0.6
	main.map_view.set_mode(main.map_view.Mode.DIPLOMACY)
	for i in 6:
		await process_frame
	var at := Vector2(root.get_visible_rect().size / 2.0)
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	Input.warp_mouse(at)
	Input.parse_input_event(ev)
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit(0)
