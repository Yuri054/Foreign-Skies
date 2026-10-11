extends SceneTree
## Headless test of the Construction map mode's view: the armies and fleets fade back so the slot
## numbers can be read, and come back with any other mode; the numbers are drawn above them.
## Run: godot --headless --path . -s res://tests/build_mode_view_test.gd

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
	var view: Sprite2D = main.map_view
	var Mode = view.get_script().Mode
	var army_layer: Node2D = null
	var fleet_layer: Node2D = null
	var labels: Node2D = null
	for c in main.get_children():
		if c.get_script() == null:
			continue
		var path: String = c.get_script().resource_path
		if path.ends_with("army_layer.gd"):
			army_layer = c
		elif path.ends_with("fleet_layer.gd"):
			fleet_layer = c
		elif path.ends_with("slot_labels.gd"):
			labels = c
	_check(army_layer != null and fleet_layer != null and labels != null, "the layers and the slot numbers exist")
	_check(army_layer.modulate.a == 1.0 and fleet_layer.modulate.a == 1.0, "armies and fleets are solid at first")
	view.set_mode(Mode.CONSTRUCTION, "factory")
	_check(army_layer.modulate.a < 0.5 and fleet_layer.modulate.a < 0.5, "they fade back in the Construction mode")
	_check(labels.z_index > army_layer.z_index and labels.z_index > fleet_layer.z_index, "and the slot numbers are drawn above them")
	view.set_mode(Mode.POLITICAL)
	_check(army_layer.modulate.a == 1.0 and fleet_layer.modulate.a == 1.0, "any other mode brings them back")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
