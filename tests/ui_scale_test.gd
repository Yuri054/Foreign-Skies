extends SceneTree
## Headless test for the UI scale setting and the compact theme.
## Run: godot --headless --path . -s res://tests/ui_scale_test.gd

var _failures := 0
var main: Node
var Settings


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://test_settings.cfg"
	Settings = load("res://scripts/ui/ui_settings.gd")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var gs: Node = root.get_node("GameState")
	for c in main.get_node("UI").get_children():
		if c.get_script() != null and "nation_picker" in c.get_script().resource_path:
			c.queue_free()
	gs.set_player("FRA")
	await process_frame

	_check(root.theme != null and root.theme.default_font_size == 14, "the compact theme is on the root window")
	_check(is_equal_approx(root.content_scale_factor, Settings.scale), "the saved scale is applied at the start (%.2f)" % Settings.scale)

	var settings: Node = get_first_node_in_group("settings_window")
	_check(settings != null and settings.has_method("setup_window"), "the settings window exists and is a window")
	settings.toggle()
	await process_frame
	_check(settings.visible and is_equal_approx(settings._slider.min_value, 0.5) and is_equal_approx(settings._slider.max_value, 2.0), "it has a slider from 50%% to 200%% (%s to %s)" % [settings._slider.min_value, settings._slider.max_value])

	var base := Vector2(root.get_visible_rect().size)
	settings._slider.value = 2.0
	await process_frame
	await process_frame
	_check(is_equal_approx(root.content_scale_factor, 2.0), "choosing 200% scales the window")
	var scaled := Vector2(root.get_visible_rect().size)
	_check(absf(scaled.x - base.x / 2.0) < 2.0, "which halves the room the interface is laid out in (%s to %s)" % [str(base), str(scaled)])
	var bar: Node = main.get_node("UI/TopBar")
	var clock_visible: bool = bar._date.is_visible_in_tree() and bar._speed_buttons[4].is_visible_in_tree()
	_check(clock_visible and bar.get_global_rect().end.x <= scaled.x + 1.0, "the top bar still fits, with its clock")
	_check(not bar._chips["population"].visible, "by dropping the least important figures")

	var cfg := ConfigFile.new()
	_check(cfg.load(Settings.path) == OK and float(cfg.get_value("ui", "scale", 0.0)) == 2.0, "the choice is saved to the settings file")

	# Keyboard: Ctrl and - steps down, Ctrl 0 resets.
	var down := InputEventKey.new()
	down.keycode = KEY_MINUS
	down.pressed = true
	down.ctrl_pressed = true
	bar._unhandled_key_input(down)
	_check(is_equal_approx(root.content_scale_factor, 1.75), "Ctrl and - goes to the next smaller scale")
	var reset := InputEventKey.new()
	reset.keycode = KEY_0
	reset.pressed = true
	reset.ctrl_pressed = true
	bar._unhandled_key_input(reset)
	_check(is_equal_approx(root.content_scale_factor, 1.0), "Ctrl 0 returns to 100%")
	var plain := InputEventKey.new()
	plain.keycode = KEY_EQUAL
	plain.pressed = true
	var speed: int = root.get_node("Clock").speed
	bar._unhandled_key_input(plain)
	_check(root.get_node("Clock").speed == speed + 1 or speed == 5, "while + alone still changes the game speed")
	_check(is_equal_approx(Settings.step_scale(root, 1), 1.1) and is_equal_approx(Settings.step_scale(root, -1), 1.0), "step_scale moves one preset at a time")
	_check(is_equal_approx(Settings.set_scale(root, 1.27), 1.25) and is_equal_approx(Settings.set_scale(root, 9.0), 2.0), "and set_scale rounds to a step and holds the top")
	_check(is_equal_approx(Settings.set_scale(root, 0.52), 0.5) and is_equal_approx(Settings.set_scale(root, 0.1), 0.5), "it goes down to 50% and no further")
	Settings.set_scale(root, 0.5)
	await process_frame
	_check(is_equal_approx(Settings.step_scale(root, -1), 0.5) and is_equal_approx(Settings.step_scale(root, 1), 0.6), "Ctrl and + or - step through the small scales too")
	var small := Vector2(root.get_visible_rect().size)
	_check(bar.get_global_rect().end.x <= small.x + 1.0, "at 50%% the top bar still fits (%s)" % str(small))
	Settings.set_scale(root, 1.0)

	# The windows are tighter than before.
	var eco: Node = get_first_node_in_group("economy_panel")
	eco.toggle()
	await process_frame
	await process_frame
	_check(eco.size.y < 560.0 and eco.size.x >= 480.0, "the economy window opens snug around its content (%s)" % str(eco.size))
	var dip: Node = get_first_node_in_group("diplomacy_panel")
	dip.toggle()
	await process_frame
	_check(dip.size.x >= 640.0, "the diplomacy window uses two panes side by side (%s)" % str(dip.size))
	var mil: Node = get_first_node_in_group("military_panel")
	mil.toggle()
	await process_frame
	_check(mil._sections.keys() == ["Fronts", "Recruit", "Wars"], "the military page folds into Fronts, Recruit and Wars (%s)" % str(mil._sections.keys()))

	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
