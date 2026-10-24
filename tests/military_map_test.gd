extends SceneTree
## Headless test of the Military map's variants: the front line lights the provinces held next to
## an enemy at war, the strength map shades provinces by men stationed.
## Run: godot --headless --path . -s res://tests/military_map_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	var gs: Node = root.get_node("GameState")
	load("res://scripts/ui/ui_settings.gd").path = "user://test_settings.cfg"
	gs.load_scenario(gs.DEFAULT_SCENARIO)
	gs.set_player("FRA")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for p in get_nodes_in_group("nation_picker"):
		p.queue_free()
	var view: Sprite2D = main.map_view
	var Mode = view.get_script().Mode
	var Mil = load("res://scripts/sim/military.gd")

	# A French province next to a German one, and a German province in the rear.
	var edge := 0
	var rear := 0
	for id in range(1, gs.province_owner.size()):
		if gs.province_owner[id] != "FRA":
			continue
		for n in Mil.neighbors(id):
			if gs.province_owner[n] == "GER":
				edge = id
		if edge != 0:
			break
	for id in range(1, gs.province_owner.size()):
		if gs.province_owner[id] == "FRA" and not Mil.neighbors(id).any(func(n: int) -> bool: return gs.province_owner[n] != "FRA"):
			rear = id
			break
	_check(edge > 0 and rear > 0, "there is a border province (%d) and a rear one (%d)" % [edge, rear])

	view.set_mode(Mode.MILITARY, view.MIL_FRONT)
	gs.set_war("FRA", "GER", false)
	_check(not view.on_front(edge), "at peace nothing is a front")
	var peace_color: Color = view.military_color(edge)
	gs.set_war("FRA", "GER", true)
	view.repaint()
	_check(view.on_front(edge) and not view.on_front(rear), "at war the border province is on the front and the rear is not")
	_check(view.military_color(edge) != peace_color and view.military_color(edge).r > view.military_color(rear).r, "and it is lit")

	# Strength.
	for a in gs.armies.values():
		if a.tag == "FRA":
			a.province = rear
			break
	view.set_mode(Mode.MILITARY, view.MIL_STRENGTH)
	var with_army: Color = view.military_color(rear)
	var without: Color = view.military_color(edge)
	_check(with_army != without and view.legend().has("high"), "a province with an army is shaded apart from one without")
	_check(view.legend().high != "none", "the legend gives the biggest garrison (%s)" % view.legend().high)

	view.set_mode(Mode.CONSTRUCTION, "factory")
	_check(view.legend().get("swatches", []).size() == 5, "the Construction legend has a swatch for each colour")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
