extends SceneTree
## WINDOWED
## Checks the floating windows with real mouse events: every menu is a window, and each can
## be dragged by its title bar, resized by its edges, minimized, restored, closed with the X
## and brought to the front.
## Needs a real window (headless mode does not dispatch GUI mouse events):
##   godot --path . -s res://tests/window_test.gd --windowed --resolution 1280x720

var _failures := 0
var main: Node
var gs: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _mouse(pos: Vector2, button := 0, pressed := false, mask := 0) -> void:
	var e: InputEvent
	if button == 0:
		e = InputEventMouseMotion.new()
		e.button_mask = mask
	else:
		e = InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)
	await process_frame
	await process_frame


func _click(pos: Vector2) -> void:
	await _mouse(pos)
	await _mouse(pos, MOUSE_BUTTON_LEFT, true)
	await _mouse(pos, MOUSE_BUTTON_LEFT, false)


## Drags with the left button from one point to another.
func _drag(from: Vector2, to: Vector2) -> void:
	await _mouse(from)
	await _mouse(from, MOUSE_BUTTON_LEFT, true)
	for i in 4:
		await _mouse(from.lerp(to, (i + 1) / 4.0), 0, false, MOUSE_BUTTON_MASK_LEFT)
	await _mouse(to, MOUSE_BUTTON_LEFT, false)


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://test_settings.cfg"
	gs = root.get_node("GameState")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for c in main.get_node("UI").get_children():
		if c.get_script() != null and "nation_picker" in c.get_script().resource_path:
			c.queue_free()
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.wars.clear()
	gs.join_calls.clear()
	gs.set_player("FRA")
	await process_frame

	_test_all_are_windows()
	await _test_move_and_resize()
	await _test_corners()
	await _test_minimize_and_close()
	await _test_front_and_limits()

	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


func _windows() -> Dictionary:
	return {
		"economy": get_first_node_in_group("economy_panel"),
		"military": get_first_node_in_group("military_panel"),
		"diplomacy": get_first_node_in_group("diplomacy_panel"),
		"country panel": get_first_node_in_group("nation_stats"),
		"peace screen": get_first_node_in_group("peace_screen"),
		"join prompt": get_first_node_in_group("join_prompt"),
		"battle screen": get_first_node_in_group("battle_screen"),
	}


func _test_all_are_windows() -> void:
	var windows := _windows()
	for name: String in windows:
		var w: Node = windows[name]
		_check(w != null and w.has_method("setup_window") and w.has_method("toggle_minimized"), "the %s is a floating window" % name)
	_check(windows["join prompt"].closable == false, "the join prompt cannot be closed until it is answered")
	_check(windows["economy"].closable and windows["military"].closable, "the other menus can")


func _bar_center(w: Node) -> Vector2:
	var r: Rect2 = w._bar.get_global_rect()
	return r.get_center() - Vector2(r.size.x * 0.25, 0)


func _test_move_and_resize() -> void:
	var eco: Node = get_first_node_in_group("economy_panel")
	eco.toggle()
	await process_frame
	await process_frame
	var view: Vector2 = root.get_visible_rect().size
	_check(eco.visible and eco.get_global_rect().end.x <= view.x + 1.0 and eco.get_global_rect().position.y >= 30.0, "the economy window opens on screen below the top bar")
	_check(eco._title_label.text == "Economy", "with its title in the bar")

	var before: Vector2 = eco.position
	await _drag(_bar_center(eco), _bar_center(eco) + Vector2(-220, 90))
	_check(eco.position.distance_to(before + Vector2(-220, 90)) < 3.0, "dragging the title bar moves the window (%s to %s)" % [str(before), str(eco.position)])

	var rect: Rect2 = eco.get_global_rect()
	var size_before: Vector2 = eco.size
	var corner := rect.end - Vector2(2, 2)
	await _drag(corner, corner + Vector2(90, 60))
	_check(eco.size.x > size_before.x + 80.0 and eco.size.y > size_before.y + 50.0, "dragging the corner enlarges it (%s to %s)" % [str(size_before), str(eco.size)])
	_check(eco.user_sized, "and it keeps the size it was given")

	rect = eco.get_global_rect()
	var left_edge := Vector2(rect.position.x + 2.0, rect.get_center().y)
	var width_before: float = eco.size.x
	var x_before: float = eco.position.x
	await _drag(left_edge, left_edge + Vector2(-70, 0))
	_check(eco.size.x > width_before + 60.0 and eco.position.x < x_before - 60.0, "dragging the left edge widens it leftwards")

	rect = eco.get_global_rect()
	var bottom_right := rect.end - Vector2(2, 2)
	await _drag(bottom_right, bottom_right - Vector2(900, 700))
	var min_size: Vector2 = eco.get_combined_minimum_size()
	_check(eco.size.x >= min_size.x - 0.5 and eco.size.y >= min_size.y - 0.5, "it cannot be made smaller than its content allows (%s, minimum %s)" % [str(eco.size), str(min_size)])
	eco.close_window()


func _test_minimize_and_close() -> void:
	var mil: Node = get_first_node_in_group("military_panel")
	mil.toggle()
	await process_frame
	await process_frame
	var full_height: float = mil.size.y
	_check(full_height > 150.0, "the military window opens at a useful height (%d)" % full_height)
	await _click(mil._min_button.get_global_rect().get_center())
	_check(mil.minimized and mil.size.y < 60.0, "the minimize button folds it to its title bar (%d high)" % mil.size.y)
	_check(not mil._holder.visible and mil._title_label.text == "Military", "the content is hidden, the title stays")
	var bar_before: Vector2 = mil.position
	await _drag(_bar_center(mil), _bar_center(mil) + Vector2(-100, 40))
	_check(mil.position.distance_to(bar_before + Vector2(-100, 40)) < 3.0, "a minimized window can still be moved")
	await _click(mil._min_button.get_global_rect().get_center())
	_check(not mil.minimized and absf(mil.size.y - full_height) < 2.0, "pressed again, it is restored to its height")
	await _mouse(Vector2(50, 300))
	mil._on_bar_input(_double_click())
	_check(mil.minimized, "double-clicking the title bar minimizes it as well")
	mil.set_minimized(false)

	var pos: Vector2 = mil.position
	await _click(mil._close_button.get_global_rect().get_center())
	_check(not mil.visible, "the X button closes it")
	mil.toggle()
	await process_frame
	_check(mil.visible and mil.position.distance_to(pos) < 1.0, "and reopening puts it back where it was left")


func _double_click() -> InputEvent:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.double_click = true
	return e


func _test_front_and_limits() -> void:
	var eco: Node = get_first_node_in_group("economy_panel")
	var mil: Node = get_first_node_in_group("military_panel")
	var dip: Node = get_first_node_in_group("diplomacy_panel")
	eco.toggle()
	dip.toggle()
	await process_frame
	var parent := eco.get_parent()
	_check(dip.get_index() > eco.get_index() and dip.get_index() > mil.get_index(), "the window opened last is in front")
	# Park the economy window where nothing else covers its title bar, then click it.
	eco.position = Vector2(20, 120)
	dip.position = Vector2(700, 120)
	mil.position = Vector2(700, 420)
	await process_frame
	await _click(_bar_center(eco))
	_check(eco.get_index() == parent.get_child_count() - 1, "clicking a window brings it to the front")

	await _drag(_bar_center(eco), Vector2(-500, -500))
	var view: Vector2 = root.get_visible_rect().size
	_check(eco.position.y >= 30.0 and eco.position.x + eco.size.x >= 30.0, "a window cannot be dragged off the screen (%s)" % str(eco.position))
	await _drag(_bar_center(eco) if eco.get_global_rect().has_point(_bar_center(eco)) else eco.get_global_rect().position + Vector2(20, 14), view + Vector2(500, 500))
	_check(eco.position.x < view.x and eco.position.y < view.y, "nor off the other side (%s)" % str(eco.position))
	for w in [eco, mil, dip]:
		w.close_window()

	# A decision cannot be closed, but can be minimized and moved.
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("FRA")
	var prompt: Node = get_first_node_in_group("join_prompt")
	for i in 80:
		if not gs.pending_joins.is_empty():
			break
		get_root().get_node("Clock").advance_day()
	await process_frame
	_check(prompt.visible and prompt._close_button.disabled, "the join prompt's X is switched off while it waits")
	prompt.close_window()
	_check(prompt.visible, "and does nothing")
	prompt.set_minimized(true)
	_check(prompt.minimized and prompt.visible, "it can be folded away out of the way")
	prompt.set_minimized(false)
	prompt._answer(false)


func _test_corners() -> void:
	var win: Node = get_first_node_in_group("diplomacy_panel")
	win.toggle()
	await process_frame
	win.position = Vector2(300, 140)
	win.size = Vector2(520, 420)
	await process_frame
	_check(win._edges_at(win.size - Vector2(10, 10)) == Vector2i(1, 1), "the area just inside the bottom right corner counts as the corner")
	_check(win._edges_at(Vector2(10, win.size.y - 10)) == Vector2i(-1, 1), "and the bottom left")
	_check(win._edges_at(Vector2(win.size.x * 0.5, 40)) == Vector2i.ZERO, "the middle of the title bar is not an edge")
	_check(win._edges_at(win._close_button.get_global_rect().get_center() - win.global_position) == Vector2i.ZERO, "nor is the close button")

	# Bottom right, grabbed over the content rather than on the border.
	var rect: Rect2 = win.get_global_rect()
	var start := rect.end - Vector2(12, 12)
	var before: Vector2 = win.size
	await _drag(start, start + Vector2(40, 30))
	_check(win.size.is_equal_approx(before + Vector2(40, 30)) and win.position.is_equal_approx(rect.position), "the bottom right corner resizes both ways at once (%s)" % str(win.size - before))

	rect = win.get_global_rect()
	start = Vector2(rect.position.x + 12, rect.end.y - 12)
	before = win.size
	var pos_before: Vector2 = win.position
	await _drag(start, start + Vector2(-30, 25))
	_check(win.size.is_equal_approx(before + Vector2(30, 25)) and win.position.is_equal_approx(pos_before + Vector2(-30, 0)), "the bottom left corner grows it left and down (%s)" % str(win.size - before))

	rect = win.get_global_rect()
	start = rect.position + Vector2(3, 3)
	before = win.size
	pos_before = win.position
	await _drag(start, start + Vector2(-25, -20))
	_check(win.size.is_equal_approx(before + Vector2(25, 20)) and win.position.is_equal_approx(pos_before + Vector2(-25, -20)), "the top left corner grows it left and up (%s)" % str(win.size - before))

	rect = win.get_global_rect()
	start = Vector2(rect.end.x - 3, rect.position.y + 3)
	before = win.size
	pos_before = win.position
	await _drag(start, start + Vector2(30, -20))
	_check(win.size.is_equal_approx(before + Vector2(30, 20)) and win.position.is_equal_approx(pos_before + Vector2(0, -20)), "the top right corner grows it right and up (%s)" % str(win.size - before))

	# Shrinking from a corner stops at the content's minimum in both directions.
	rect = win.get_global_rect()
	start = rect.end - Vector2(12, 12)
	await _drag(start, start - Vector2(1200, 900))
	var min_size: Vector2 = win.get_combined_minimum_size()
	_check(win.size.x <= min_size.x + 1.0 and win.size.y <= min_size.y + 1.0, "pulled in hard, it settles at its minimum (%s)" % str(win.size))
	_check(win.get_global_rect().end.x > 100.0, "and stays on screen")
	win.close_window()
