extends SceneTree
## Headless test for the nation stats window.
## Run: godot --headless --path . -s res://tests/nation_stats_test.gd

var _failures := 0
var main: Node
var gs: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


## All the text the window shows, joined.
func _text(win: Node) -> String:
	var parts: PackedStringArray = [win._name.text, win._sub.text]
	var stack: Array = [win._content]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Label:
			parts.append(node.text)
		for c in node.get_children():
			stack.append(c)
	return "\n".join(parts)


func _key(win: Node, code: int, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	win._unhandled_key_input(e)


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://test_settings.cfg"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	gs = root.get_node("GameState")
	for c in main.get_node("UI").get_children():
		if c.get_script() != null and "nation_picker" in c.get_script().resource_path:
			c.queue_free()
	gs.wars.clear()
	gs.join_calls.clear()
	gs.set_player("FRA")
	await process_frame

	var win: Node = get_first_node_in_group("nation_stats")
	_check(win != null and win.has_method("setup_window"), "the nation stats window exists and is a window")
	_check(not win.visible, "and starts closed")
	_key(win, KEY_N)
	await process_frame
	_check(win.visible, "N opens it")
	_key(win, KEY_N, true)
	_check(win.visible, "Ctrl and N does not close it")
	var bar: Node = main.get_node("UI/TopBar")
	_check(bar._nation_button.button_pressed and bar._nation_button.text == "Nation", "the top bar's Nation button is lit")

	_check(win.shown_tag() == "FRA" and win._name.text == "France" and win._flag.tag == "FRA", "it shows the player's nation, with its flag")
	var text: String = _text(win)
	for needle in ["your nation", "Capital", "Paris", "Population", "Output a month", "Net per month", "Treasury", "Under arms", "Mobilization", "War support", "Diplomacy points", "Alliances", "Russian Empire", "At war with", "nobody", "Coal"]:
		_check(text.contains(needle), "it lists %s" % needle)
	_check(text.contains("#") and text.contains(" of 22"), "and ranks the figures that can be compared")
	_check(not text.contains("Opinion of you"), "there is no opinion of yourself")
	_check(win._picker.item_count == 22 and win._picker.get_item_text(win._tags.find("FRA")).ends_with("(you)"), "the picker lists all 22 nations, marking yours")

	# Another nation, by the picker.
	var ger: int = win._tags.find("GER")
	win._picker.select(ger)
	win._picker.item_selected.emit(ger)
	await process_frame
	text = _text(win)
	_check(win.shown_tag() == "GER" and win._name.text == "German Empire" and win._flag.tag == "GER", "picking Germany shows Germany")
	_check(text.contains("Berlin") and text.contains("Austria-Hungary") and text.contains("Opinion of you"), "with its capital, alliances and opinion of you")
	_check(text.contains("protects Belgium"), "and its guarantee of Belgium")
	_check(win.title == "Nation: German Empire", "the title names it (%s)" % win.title)

	# It follows events while open.
	gs.set_war("FRA", "GER", true)
	await process_frame
	await process_frame
	_check(_text(win).contains("YOU"), "a war with the player is shown as YOU")
	gs.set_war("FRA", "GER", false)
	var treasury: float = gs.nations["GER"].treasury
	gs.nations["GER"].treasury = -12.0
	gs.economy_updated.emit()
	await process_frame
	await process_frame
	_check(_text(win).contains("£-12.0M"), "and a debt shows as one")
	gs.nations["GER"].treasury = treasury

	# Capital lost, ground occupied.
	gs.set_war("FRA", "GER", true)
	gs.set_controller(gs.nations["GER"].capital, "FRA")
	win._refresh()
	text = _text(win)
	_check(text.contains("held by France") and text.contains("occupied"), "a lost capital and occupied ground are reported")
	gs.set_controller(gs.nations["GER"].capital, "GER")
	gs.set_war("FRA", "GER", false)

	# show_nation, and the player changing.
	win.show_nation("RUS")
	await process_frame
	_check(win.shown_tag() == "RUS" and win._name.text == "Russian Empire", "show_nation picks a nation")
	gs.set_player("GBR")
	await process_frame
	await process_frame
	_check(win.shown_tag() == "GBR" and win._name.text == "United Kingdom", "changing the player's nation brings the window back to the player")
	win.close_window()
	_check(not win.visible and not bar._nation_button.button_pressed, "the X closes it and unlights the button")

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_settings.cfg"))
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
