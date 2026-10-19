extends SceneTree
## Headless test of what the interface starts as: the command panel closed, the province card
## folded to its summary, and the card's Details button opening it and closing it again.
## Run: godot --headless --path . -s res://tests/ui_defaults_test.gd

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _initialize() -> void:
	await process_frame
	var Settings = load("res://scripts/ui/ui_settings.gd")
	Settings.path = "user://ui_defaults_settings.cfg"
	DirAccess.remove_absolute(Settings.path)
	_check(not Settings.command_open and not Settings.province_details, "the command panel and the province details start closed")
	var gs: Node = root.get_node("GameState")
	var map: Node = root.get_node("MapData")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	for picker in get_nodes_in_group("nation_picker"):
		picker.queue_free()
	await process_frame
	gs.set_player("FRA")
	await process_frame
	var bar: Node = get_first_node_in_group("command_panel")
	_check(bar.visible and not bar.is_open() and not bar._scroll.visible, "in a game the command panel shows only its button until C opens it")
	var card: Control = get_first_node_in_group("province_panel")
	var id: int = gs.nations["GER"].provinces[0]
	main.map_view.select(id)
	await process_frame
	await process_frame
	_check(card.visible and not card._detail.visible, "a selected province shows a card without its details")
	var small: float = card.size.y
	_check(small < 160.0 and card.size.x <= 240.0, "which is small (%d by %d)" % [card.size.x, small])
	card._toggle.pressed.emit()
	await process_frame
	await process_frame
	_check(card._detail.visible and card.size.y > small, "Details opens the rest (%d high)" % card.size.y)
	card._toggle.pressed.emit()
	await process_frame
	await process_frame
	_check(not card._detail.visible and is_equal_approx(card.size.y, small), "and closes it again")
	# A long name shows in full, wrapped.
	var long_id := 0
	for pid in range(1, gs.province_owner.size()):
		if map.provinces[pid].name.length() >= 20:
			long_id = pid
			break
	main.map_view.select(long_id)
	await process_frame
	await process_frame
	var shown := ""
	for l in card._box.get_child(0).get_children():
		if l is Label:
			shown = l.text
	var wrapped := false
	for l in card._box.get_child(0).get_children():
		if l is Label and l.autowrap_mode != TextServer.AUTOWRAP_OFF and not l.clip_text:
			wrapped = true
	_check(shown == map.provinces[long_id].name and wrapped, "a long province name wraps instead of being cut (%s)" % shown)
	DirAccess.remove_absolute(Settings.path)
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
