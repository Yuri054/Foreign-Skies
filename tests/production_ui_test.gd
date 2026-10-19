extends SceneTree
## Headless test of the Production tab of the Economy window: it lists the player's lines, the
## buttons change them, "Automatic" folds them again.
## Run: godot --headless --path . -s res://tests/production_ui_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _find(node: Node, cls: String, text: String) -> Node:
	if node.get_class() == cls and "text" in node and node.text == text:
		return node
	for c in node.get_children():
		var r := _find(c, cls, text)
		if r != null:
			return r
	return null


func _initialize() -> void:
	var gs: Node = root.get_node("GameState")
	var Prod = load("res://scripts/sim/production.gd")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	gs.set_player("GER")
	var eco: Node = get_first_node_in_group("economy_panel")
	eco.toggle()
	eco._tabs.current_tab = 2
	await process_frame
	await process_frame
	var ger = gs.nations["GER"]
	_check(eco._tabs.get_tab_title(2) == "Production", "the Economy window has a Production tab")
	_check(ger.production_lines.size() == 3 and _find(eco._production, "CheckButton", "Automatic") != null, "it shows the lines and the Automatic switch")
	var minus: Node = _find(eco._production, "Button", "-")
	minus.pressed.emit()
	await process_frame
	_check(not ger.lines_auto and Prod.free_factories(ger) == 1, "the minus button frees a factory and ends automatic production")
	var add: Node = _find(eco._production, "Button", "New line")
	_check(not add.disabled, "New line is open with a free factory")
	add.pressed.emit()
	await process_frame
	_check(ger.production_lines.size() == 4 and Prod.free_factories(ger) == 0, "and opens a line")
	_find(eco._production, "CheckButton", "Automatic").toggled.emit(true)
	await process_frame
	_check(ger.lines_auto and ger.production_lines.size() == 3, "Automatic folds the lines again")
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
