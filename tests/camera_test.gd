extends SceneTree
## Headless test of the camera at the map's edge: it cannot run off the map, so a pan back from
## an edge moves the view at once, and a map smaller than the view is centred.
## Run: godot --headless --path . -s res://tests/camera_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var cam: Camera2D = main.get_node("Camera")
	var map_size := Vector2(root.get_node("MapData").map_size)
	cam.zoom = Vector2(1.0, 1.0)
	var half := cam.get_viewport_rect().size / cam.zoom / 2.0
	var room := half * 0.7

	cam.position = Vector2(-5000, -5000)
	cam.keep_on_map()
	_check(is_equal_approx(cam.position.x, half.x - room.x) and is_equal_approx(cam.position.y, half.y - room.y), "pushed past the top left corner it stops a little past the edge (%s)" % str(cam.position))
	cam.position += Vector2(80, 0)
	cam.keep_on_map()
	_check(is_equal_approx(cam.position.x, half.x - room.x + 80.0), "and a pan back from the edge moves the view at once")

	cam.position = map_size + Vector2(9000, 9000)
	cam.keep_on_map()
	_check(is_equal_approx(cam.position.x, map_size.x - half.x + room.x) and is_equal_approx(cam.position.y, map_size.y - half.y + room.y), "the bottom right corner is held the same way")

	cam.zoom = Vector2(0.01, 0.01)
	cam.keep_on_map()
	_check(is_equal_approx(cam.position.x, map_size.x / 2.0) and is_equal_approx(cam.position.y, map_size.y / 2.0), "a map smaller than the view is centred")

	cam.zoom = Vector2(3.0, 3.0)
	cam.position = Vector2(-100, 200)
	cam.keep_on_map()
	var half_in := cam.get_viewport_rect().size / 3.0 / 2.0
	_check(cam.position.x >= half_in.x * (1.0 - 0.7) - 0.01, "zoomed in, the edge is nearer: the centre may go closer to it (%s)" % str(cam.position))
	cam.zoom = Vector2(1.0, 1.0)
	cam.position = map_size / 2.0
	var at := Vector2(cam.get_viewport_rect().size.x * 0.75, cam.get_viewport_rect().size.y * 0.5)
	var centre := cam.get_viewport_rect().size / 2.0
	var under := cam.position + (at - centre) / cam.zoom.x
	cam.call("_set_zoom", 2.0, at)
	var under_after := cam.position + (at - centre) / cam.zoom.x
	_check(under.distance_to(under_after) < 0.01, "zooming keeps the map point under the mouse where it is")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
