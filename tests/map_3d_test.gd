extends SceneTree
## Headless test of the 3D map mode: the geometry of looking through the plane (a ray at the
## picture's centre, one that misses, the picture's size), the mode off at the start, the layers
## moving into the off-screen picture and back in the order they were, the camera tilt kept in its
## range, and a click on the screen reaching the picture where it lies.
## Run: godot --headless --path . -s res://tests/map_3d_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	var M3 = load("res://scripts/map/map_3d.gd")
	var size := Vector2(16, 9)
	_check(M3.plane_hit(Vector3(0, 5, 0), Vector3(0, -1, 0), size).is_equal_approx(Vector2(0.5, 0.5)), "a ray straight down at the centre hits the middle of the picture")
	_check(M3.plane_hit(Vector3(8, 5, 4.5), Vector3(0, -1, 0), size).is_equal_approx(Vector2(1.0, 1.0)), "and at the far corner the corner")
	_check(M3.plane_hit(Vector3(9, 5, 0), Vector3(0, -1, 0), size).x < 0.0, "a ray past the edge misses")
	_check(M3.plane_hit(Vector3(0, 5, 0), Vector3(0, 1, 0), size).x < 0.0 and M3.plane_hit(Vector3(0, 5, 0), Vector3(1, 0, 0), size).x < 0.0, "so do rays that go up or along the plane")
	var picture: Vector2i = M3.picture_size(Vector2i(1600, 900))
	_check(picture == Vector2i(2400, 1350), "the picture is 1.5 times the window (%s)" % str(picture))
	_check(M3.picture_size(Vector2i(3840, 2160)).x <= 3840, "and is held to its largest size")
	_check(M3.camera_distance(9.0) > 0.0, "the camera has a distance")

	var gs: Node = root.get_node("GameState")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var mode: Node = get_first_node_in_group("map_3d")
	_check(mode != null and not mode.enabled, "the 3D mode exists and is off at the start")
	var before: Array = []
	for c in main.get_children():
		before.append(c)
	var map_view: Node = main.map_view
	mode.set_enabled(true)
	await process_frame
	_check(mode.enabled and map_view.get_parent() is SubViewport, "switched on, the map is in the off-screen picture")
	var layers_inside := true
	for c in before:
		if c is CanvasItem:
			layers_inside = layers_inside and c.get_parent() is SubViewport
	_check(layers_inside, "and so is every layer drawn on it")
	_check(main.camera.get_parent() is SubViewport and main.camera.is_current(), "the 2D camera goes with them and is the one in use")
	mode.tilt = 500.0
	mode._apply_tilt()
	_check(is_equal_approx(mode.tilt, M3.MAX_TILT), "the tilt stops at straight down")
	mode.tilt = -5.0
	mode._apply_tilt()
	_check(is_equal_approx(mode.tilt, M3.MIN_TILT), "and at the lowest angle")
	mode.tilt = 90.0
	mode._apply_tilt()
	var centre: Vector2 = mode.to_picture(root.get_visible_rect().size / 2.0)
	var picture_centre := Vector2(map_view.get_viewport().size) / 2.0
	_check(centre.distance_to(picture_centre) < 3.0, "looking straight down, the centre of the screen is the centre of the picture (%s)" % str(centre))
	# Turning: the screen's centre stays on the picture's centre, and a turn of 90 degrees puts the
	# picture's left side at the top of the screen, so the panning keys turn with it.
	mode.yaw = 90.0
	mode._apply_tilt()
	var turned: Vector2 = mode.to_picture(root.get_visible_rect().size / 2.0)
	_check(turned.distance_to(picture_centre) < 3.0, "turned round, the centre of the screen is still the picture's centre")
	var top: Vector2 = mode.to_picture(Vector2(root.get_visible_rect().size.x / 2.0, 20.0))
	_check(top.x < picture_centre.x - 100.0 and absf(top.y - picture_centre.y) < 5.0, "and the top of the screen shows the picture's left side (%s)" % str(top))
	_check(is_equal_approx(main.camera.pan_rotation, M3.pan_rotation_for(90.0)), "the panning keys are turned the same way")
	var up := Vector2(0, -1).rotated(main.camera.pan_rotation)
	_check(up.x < -0.99, "so that up goes toward the picture's left (%s)" % str(up))
	mode.yaw = 270.0
	mode._apply_tilt()
	_check(absf(mode.yaw + 90.0) < 0.001, "the turn wraps round (270 is -90)")
	mode.yaw = 0.0
	mode._apply_tilt()
	_check(is_equal_approx(main.camera.pan_rotation, 0.0), "turned back, the keys are as they were")
	for i in 3:
		root.get_node("Clock").advance_day()
	await process_frame
	mode.set_enabled(false)
	await process_frame
	var restored := true
	for c in before:
		restored = restored and c.get_parent() == main
	_check(restored, "switched off, everything is back under the main scene")
	var order_same := true
	for i in before.size():
		order_same = order_same and main.get_child(i) == before[i]
	_check(order_same and main.camera.is_current(), "in the same order, with the 2D camera in use again")
	mode.toggle()
	_check(mode.enabled, "toggle switches it on")
	mode.toggle()
	_check(not mode.enabled, "and off")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
