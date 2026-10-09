extends SceneTree
## Headless test for the province borders (tools/build_borders.py) and the front line drawn on them.
## Run: godot --headless --path . -s res://tests/borders_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://test_settings.cfg"
	var gs: Node = root.get_node("GameState")
	var map: Node = root.get_node("MapData")
	var Mil = load("res://scripts/sim/military.gd")
	var nancy := 0
	for id in range(1, gs.province_owner.size()):
		if map.provinces[id].name == "Meurthe-et-Moselle":
			nancy = id
	var german := 0
	for n in Mil.neighbors(nancy):
		if gs.province_owner[n] == "GER":
			german = n
	_check(nancy > 0 and german > 0, "a French province borders a German one")
	var lines: Array = map.border_lines(nancy, german)
	_check(not lines.is_empty() and lines[0].size() >= 2, "the border between them is traced (%d stretches)" % lines.size())
	_check(map.border_lines(german, nancy) == lines, "in either order")
	var near := 0
	var total := 0
	for line: PackedVector2Array in lines:
		for pt in line:
			total += 1
			var found := false
			for dx in range(-3, 4):
				for dy in range(-3, 4):
					var id: int = map.province_at_pixel(Vector2i(pt) + Vector2i(dx, dy))
					found = found or id == nancy or id == german
			near += 1 if found else 0
	_check(near == total, "every point of the line lies on the two provinces (%d of %d)" % [near, total])
	_check(map.border_lines(nancy, 1).is_empty(), "provinces that do not touch have no border")
	var covered := 0
	for key in map._borders:
		covered += 1
	_check(covered > 2000, "the whole map's borders are there (%d pairs)" % covered)

	# The front lies along it.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	gs.set_player("FRA")
	gs.set_war("FRA", "GER", true)
	var cmd = load("res://scripts/sim/designate_front.gd").new("FRA", "", [] as Array[int], "GER")
	gs.issue(cmd)
	var layer: Node = get_first_node_in_group("army_layer")
	var stretches: Array = layer._front_stretches(gs.fronts[cmd.front_id])
	_check(not stretches.is_empty(), "a front against Germany is drawn on %d stretches of the border" % stretches.size())
	var held := true
	for s in stretches:
		held = held and gs.province_controller[s.enemy] == "GER"
	_check(held, "each pointing at a German province")
	layer.set_selected_front(cmd.front_id)
	layer.queue_redraw()
	await process_frame
	await process_frame
	_check(true, "and it draws without trouble")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_settings.cfg"))
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
