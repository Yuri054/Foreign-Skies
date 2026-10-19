extends SceneTree
## WINDOWED
## Checks that menus take mouse input instead of passing it to the map.
## Needs a real window (headless mode does not dispatch GUI mouse events):
##   godot --path . -s res://tests/ui_input_test.gd --windowed --resolution 1280x720

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _mouse(pos: Vector2, button := 0, pressed := false) -> void:
	var e: InputEvent
	if button == 0:
		e = InputEventMouseMotion.new()
	else:
		e = InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)
	await process_frame
	await process_frame


func _wheel(pos: Vector2, up: bool) -> void:
	await _mouse(pos)
	var button := MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	await _mouse(pos, button, true)
	await _mouse(pos, button, false)


func _click(pos: Vector2) -> void:
	await _mouse(pos)
	await _mouse(pos, MOUSE_BUTTON_LEFT, true)
	await _mouse(pos, MOUSE_BUTTON_LEFT, false)


func _initialize() -> void:
	load("res://scripts/ui/ui_settings.gd").path = "user://test_settings.cfg"
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var cam: Camera2D = main.get_node("Camera")
	var view = main.get_node("MapView")
	var ui: CanvasLayer = main.get_node("UI")
	for c in ui.get_children():
		if c.get_script() != null and c.get_script().resource_path.ends_with("nation_picker.gd"):
			c.queue_free()
	var bar = get_first_node_in_group("map_modes")
	var eco = get_first_node_in_group("economy_panel")
	eco.toggle()
	await process_frame

	var z: float = cam.zoom.x
	await _wheel(Vector2(300, 400), true)
	_check(cam.zoom.x > z, "wheel over the map zooms it")

	var panel: Rect2 = eco.get_global_rect()
	var spots := {
		"the economy panel": panel.position + panel.size * 0.5,
		"the top of the economy panel": panel.position + Vector2(panel.size.x * 0.5, 6),
		"the map mode bar": bar.get_global_rect().get_center(),
		"the top bar": Vector2(400, 8),
	}
	for name in spots:
		z = cam.zoom.x
		await _wheel(spots[name], true)
		await _wheel(spots[name], false)
		_check(is_equal_approx(cam.zoom.x, z), "wheel over %s does not zoom the map" % name)

	# Clicks on menus must not select the province underneath.
	view.select(0)
	var before: int = view.selected_id
	await _click(panel.position + Vector2(panel.size.x * 0.5, 6))
	await _click(panel.position + panel.size * 0.5)
	_check(view.selected_id == before, "clicking the economy panel does not select a province")

	# The mode bar buttons work with real clicks.
	var economy_button: Button = bar._buttons[2]
	await _click(economy_button.get_global_rect().get_center())
	_check(view.mode == view.Mode.INCOME, "clicking the Economy button switches the map mode")
	var pop_button: Button = bar._buttons[3]
	await _click(pop_button.get_global_rect().get_center())
	_check(view.mode == view.Mode.POPULATION, "clicking the Population button switches the map mode")

	print("FAILURES: ", _failures)
	quit(1 if _failures else 0)

