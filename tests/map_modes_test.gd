extends SceneTree
## Headless test for the map mode palette: the six kinds, their variants, remembered choices,
## the number keys, the building list and the Diplomacy window switching the map.
## Run: godot --headless --path . -s res://tests/map_modes_test.gd

var _failures := 0
var main: Node
var view: Sprite2D
var palette: Node
var Mode


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok:   ", msg)


func _key(code: int, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	palette._unhandled_key_input(e)


func _initialize() -> void:
	await process_frame
	load("res://scripts/ui/ui_settings.gd").path = "user://test_settings.cfg"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var gs: Node = root.get_node("GameState")
	for c in main.get_node("UI").get_children():
		if c.get_script() != null and "nation_picker" in c.get_script().resource_path:
			c.queue_free()
		if c.get_script() != null and "map_modes" in c.get_script().resource_path:
			palette = c
	gs.set_player("FRA")
	view = main.map_view
	Mode = view.get_script().Mode
	await process_frame

	var names: PackedStringArray = []
	for b: Button in palette._buttons:
		names.append(b.text)
	_check(names == PackedStringArray(["Political", "Diplomacy", "Economy", "Population", "Military", "Terrain"]), "the palette has the six kinds (%s)" % ", ".join(names))
	_check(palette._buttons[0].button_pressed and view.mode == Mode.POLITICAL, "it starts on Political")
	_check(not palette._strip.visible, "a kind with one map has no strip of variants")

	palette.pick_group(2)
	await process_frame
	_check(view.mode == Mode.INCOME and palette._buttons[2].button_pressed, "Economy opens on tax income")
	var labels: PackedStringArray = []
	for c in palette._strip.get_children():
		labels.append(c.text)
	_check(labels == PackedStringArray(["Tax income", "Coal", "Iron / Steel", "Nitrates", "Draft animals", "Chemicals", "Timber", "Buildings"]), "with its variants as chips (%s)" % ", ".join(labels))
	_check(palette._strip_title.text == "Economy ›", "and the kind named beside them")
	palette._chips[1].pressed.emit()
	await process_frame
	_check(view.mode == Mode.RESOURCES and view.submode == "coal", "the Coal chip shows coal")
	_check(palette._legend_panel.visible and palette._legend_title.text.contains("Coal"), "with a legend for coal (%s)" % palette._legend_title.text)
	_check(palette._chips[1].button_pressed and not palette._chips[0].button_pressed, "and the chip lit")

	palette.pick_group(3)
	await process_frame
	_check(view.mode == Mode.POPULATION and not palette._strip.visible, "Population is a single map")
	palette.pick_group(2)
	await process_frame
	_check(view.mode == Mode.RESOURCES and view.submode == "coal", "going back to Economy remembers the coal you left it on")

	# Buildings and their kinds.
	palette._chips[7].pressed.emit()
	await process_frame
	_check(view.mode == Mode.BUILDINGS and palette._sub_picker.visible and palette._sub_picker.item_count >= 5, "Buildings brings up a list of building kinds (%d)" % palette._sub_picker.item_count)
	palette._sub_picker.select(2)
	palette._sub_picker.item_selected.emit(2)
	await process_frame
	_check(view.submode == palette._sub_picker.get_item_metadata(2) and view.submode != view.ALL_BUILDINGS, "choosing one shows just that building")
	palette.pick_group(0)
	await process_frame
	_check(not palette._sub_picker.visible, "the list goes away with other maps")

	# Number keys.
	_key(KEY_2)
	_check(view.mode == Mode.DIPLOMACY, "2 shows Diplomacy")
	_key(KEY_1)
	_check(view.mode == Mode.POLITICAL, "1 shows Political")
	_key(KEY_5)
	_check(view.mode == Mode.MILITARY, "5 shows Military")
	_key(KEY_6)
	_check(view.mode == Mode.TERRAIN, "6 shows Terrain")
	_key(KEY_6)
	_check(view.mode == Mode.PROVINCES, "pressing 6 again steps to the next variant, the raw province colours")
	_key(KEY_6)
	_check(view.mode == Mode.TERRAIN, "and round again")
	_key(KEY_3)
	var first: int = view.mode
	_key(KEY_3)
	_check(first == Mode.BUILDINGS and view.mode == Mode.INCOME, "3 returns to Economy where it was left, and again steps on (%d)" % view.mode)
	_key(KEY_1, true)
	_check(view.mode == Mode.INCOME, "Ctrl and a number does nothing here")
	_key(KEY_8)
	_check(view.mode == Mode.INCOME, "nor does a number past the palette")
	_key(KEY_7)
	_check(view.mode == Mode.INCOME, "nor does 7, now that the sea maps are in Military")
	# Military and its variants, the sea maps among them.
	palette.pick_group(4)
	await process_frame
	_check(view.mode == Mode.MILITARY and view.submode == view.MIL_CONTROL, "Military opens on who holds the ground")
	var chips: PackedStringArray = []
	for c in palette._strip.get_children():
		chips.append(c.text)
	_check(chips == PackedStringArray(["Control", "Front line", "Strength", "Equipment", "Sea control", "Blockade"]), "with six variants (%s)" % ", ".join(chips))
	for sub in [view.MIL_FRONT, view.MIL_STRENGTH, view.MIL_EQUIPMENT]:
		palette.pick_item(4, [view.MIL_CONTROL, view.MIL_FRONT, view.MIL_STRENGTH, view.MIL_EQUIPMENT].find(sub))
		await process_frame
		_check(view.mode == Mode.MILITARY and view.submode == sub and palette._legend_panel.visible, "the %s variant has a legend" % sub)
	palette.pick_item(4, 4)
	_check(view.mode == Mode.SEA_CONTROL and palette._buttons[4].button_pressed, "Sea control lives under Military")
	palette.pick_item(4, 5)
	_check(view.mode == Mode.BLOCKADE and not view.legend().is_empty() and palette._buttons[4].button_pressed, "so does Blockade, with a legend")
	palette.pick_item(4, 0)
	_check(view.legend().is_empty(), "the control variant needs no legend")
	palette.pick_group(2)
	palette.pick_group(4)
	_check(view.mode == Mode.MILITARY and view.submode == view.MIL_CONTROL, "Military comes back on the variant it was left on")
	_key(KEY_1)

	# The Diplomacy window shows the Diplomacy map while it is open.
	var dip: Node = get_first_node_in_group("diplomacy_panel")
	palette.pick_group(0)
	dip.toggle()
	await process_frame
	_check(view.mode == Mode.DIPLOMACY and palette._buttons[1].button_pressed, "opening the Diplomacy window switches the map to Diplomacy")
	dip.close_window()
	await process_frame
	_check(view.mode == Mode.POLITICAL and palette._buttons[0].button_pressed, "and closing it brings the old map back")
	palette.pick_group(4)
	dip.toggle()
	await process_frame
	_check(view.mode == Mode.DIPLOMACY, "it works from any map")
	palette.pick_group(2)
	await process_frame
	dip.close_window()
	await process_frame
	_check(view.mode == Mode.INCOME, "but a map you chose yourself while it was open stays")
	palette.pick_group(1)
	dip.toggle()
	await process_frame
	dip.close_window()
	await process_frame
	_check(view.mode == Mode.DIPLOMACY, "and if you were on Diplomacy already, nothing changes either way")

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_settings.cfg"))
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
