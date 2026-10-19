extends SceneTree
## A long UI soak: the real main scene in a window, with random actions at it for a few thousand
## steps (windows opened and closed, map modes, provinces and armies picked, real key presses and
## mouse clicks, time running). Watch the output for SCRIPT ERROR and ERROR lines.
## Run: xvfb-run -a godot --path . --resolution 1600x900 --rendering-driver opengl3 -s res://tools/ui_soak.gd -- seed steps player

var rng := RandomNumberGenerator.new()
var gs: Node
var clock: Node
var main: Node
var shots := 0
var _clicking := false
var _over_name := ""


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	rng.seed = int(args[0]) if args.size() > 0 else 1
	var steps := int(args[1]) if args.size() > 1 else 800
	var player: String = args[2] if args.size() > 2 else "GER"
	load("res://scripts/ui/ui_settings.gd").path = "user://soak_ui_settings_%d.cfg" % rng.seed
	gs = root.get_node("GameState")
	clock = root.get_node("Clock")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	load("res://scripts/ui/ui_settings.gd").apply_saved(root)
	gs.set_player(player)
	gs.ai_enabled = true
	main.map_view.province_selected.connect(func(id: int) -> void:
		if _clicking:
			var frames := []
			for f in get_stack():
				frames.append("%s:%d %s" % [str(f.source).get_file(), f.line, f.function])
			print("SELECT %d during click on %s via %s" % [id, _over_name, " < ".join(frames.slice(1, 7))]))
	var started := Time.get_ticks_msec()
	for step in steps:
		await _act()
		if step % 200 == 199:
			print("UI step %d, day %d, %.0f s" % [step + 1, clock.days_elapsed, float(Time.get_ticks_msec() - started) / 1000.0])
	print("UI SOAK done: %d steps, day %d" % [steps, clock.days_elapsed])
	quit(0)


func _groups() -> Array:
	return ["economy_panel", "construction_panel", "military_panel", "navy_panel", "diplomacy_panel", "nation_stats",
			"rankings_window", "settings_window", "map_modes", "command_panel", "event_feed", "province_panel"]


func _act() -> void:
	var roll := rng.randi() % 14
	match roll:
		0, 1:
			var g: String = _groups()[rng.randi() % _groups().size()]
			var node := get_first_node_in_group(g)
			if node != null and node.has_method("toggle"):
				node.toggle()
		2:
			var modes := get_first_node_in_group("map_modes")
			if modes != null:
				modes.pick_group(rng.randi() % 6)
				await process_frame
				if modes._sub_picker != null and rng.randf() < 0.5:
					modes.pick_item(rng.randi() % 6, rng.randi() % 5)
		3, 4:
			var view: Node = main.map_view
			view.select(rng.randi_range(1, gs.province_owner.size() - 1))
		5:
			var mine: Array[int] = []
			for a in gs.armies.values():
				if a.tag == gs.player_tag and rng.randf() < 0.3:
					mine.append(a.id)
			var panel := get_first_node_in_group("military_panel")
			if panel != null and not mine.is_empty():
				panel.select_ids(mine)
		6:
			var keys := [KEY_V, KEY_V, KEY_PAGEUP, KEY_PAGEDOWN, KEY_E, KEY_B, KEY_M, KEY_F, KEY_N, KEY_R, KEY_C, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_SPACE, KEY_ESCAPE, KEY_TAB, KEY_Q, KEY_W]
			var ev := InputEventKey.new()
			ev.keycode = keys[rng.randi() % keys.size()]
			ev.physical_keycode = ev.keycode
			ev.pressed = true
			Input.parse_input_event(ev)
			await process_frame
			ev = ev.duplicate()
			ev.pressed = false
			Input.parse_input_event(ev)
		7, 8:
			var pos := root.get_final_transform() * Vector2(rng.randf_range(0, 1280), rng.randf_range(40, 720))
			var motion := InputEventMouseMotion.new()
			motion.position = pos
			motion.global_position = pos
			Input.parse_input_event(motion)
			await process_frame
			await process_frame
			var over: Control = root.gui_get_hovered_control()
			var before: int = main.map_view.selected_id
			var armies_before: Array = []
			var mil0 := get_first_node_in_group("military_panel")
			if mil0 != null:
				armies_before = mil0._selected.duplicate()
			var mb := InputEventMouseButton.new()
			mb.position = pos
			mb.global_position = pos
			mb.button_index = MOUSE_BUTTON_LEFT if rng.randf() < 0.7 else MOUSE_BUTTON_RIGHT
			mb.pressed = true
			_over_name = "%s (%s)" % [over.name if over != null else "map", over.get_class() if over != null else ""]
			_clicking = over != null
			Input.parse_input_event(mb)
			await process_frame
			mb = mb.duplicate()
			mb.pressed = false
			Input.parse_input_event(mb)
			await process_frame
			_clicking = false
			# A click on a control must not reach the map: no province picked under it.
			if over != null and over.mouse_filter == Control.MOUSE_FILTER_STOP and mb.button_index == MOUSE_BUTTON_LEFT \
					and main.map_view.selected_id != before and main.map_view.selected_id != 0:
				print("CLICK-THROUGH at %s over %s (%s): province %d -> %d" % [str(pos), over.name, over.get_script().resource_path if over.get_script() else over.get_class(), before, main.map_view.selected_id])
		9:
			var wheel := InputEventMouseButton.new()
			wheel.position = Vector2(rng.randf_range(0, 1600), rng.randf_range(50, 900))
			wheel.button_index = MOUSE_BUTTON_WHEEL_UP if rng.randf() < 0.5 else MOUSE_BUTTON_WHEEL_DOWN
			wheel.pressed = true
			Input.parse_input_event(wheel)
		10, 11:
			for i in rng.randi_range(1, 15):
				clock.advance_day()
		12:
			var panel2 := get_first_node_in_group("construction_panel")
			if panel2 != null and panel2.visible:
				var types: Array = panel2._rows.keys()
				panel2._rows[types[rng.randi() % types.size()]].pressed.emit()
		13:
			var eco := get_first_node_in_group("economy_panel")
			if eco != null and eco.visible and eco._tabs != null:
				eco._tabs.current_tab = rng.randi() % eco._tabs.get_tab_count()
	await process_frame
