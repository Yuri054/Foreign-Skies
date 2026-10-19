extends SceneTree
## Headless test of the "Armies on the map" setting and the hover card: which armies the army
## layer draws for each view, that the choice is saved, and what the card says.
## Run: godot --headless --path . -s res://tests/army_view_test.gd

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
	Settings.path = "user://test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	var gs: Node = root.get_node("GameState")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	gs.set_player("FRA")
	await process_frame
	var layer: Node = get_first_node_in_group("army_layer")
	var settings: Node = get_first_node_in_group("settings_window")

	var mine = null
	var ally = null
	var stranger = null
	var Dip = load("res://scripts/sim/diplomacy.gd")
	for a in gs.armies.values():
		if a.tag == "FRA" and mine == null:
			mine = a
		elif a.tag != "FRA" and Dip.are_allied(gs, "FRA", a.tag) and ally == null:
			ally = a
		elif a.tag != "FRA" and not Dip.are_allied(gs, "FRA", a.tag) and stranger == null:
			stranger = a
	_check(mine != null and stranger != null, "found a French and a foreign army")

	_check(Settings.army_view == "all" and layer.shows(mine) and layer.shows(stranger), "by default every army is drawn")
	_check(not Settings.set_army_view("nonsense") and Settings.army_view == "all", "an unknown view is refused")
	_check(Settings.set_army_view("allies"), "the allies view can be chosen")
	_check(layer.shows(mine) and not layer.shows(stranger), "it draws mine and hides a stranger's")
	if ally != null:
		_check(layer.shows(ally), "and shows an ally's (%s)" % ally.tag)
	Settings.set_army_view("own")
	_check(layer.shows(mine) and not layer.shows(stranger) and (ally == null or not layer.shows(ally)), "mine only draws just my armies")

	# The choice is saved and read back.
	var cfg := ConfigFile.new()
	_check(cfg.load(Settings.path) == OK and cfg.get_value("map", "army_view") == "own", "the choice is written to the settings file")
	Settings.army_view = "all"
	Settings.apply_saved(root)
	_check(Settings.army_view == "own", "and read again at the start")

	# The setting in the window follows it and changes it.
	settings.toggle()
	await process_frame
	var picked: String = settings._army_view.get_item_metadata(settings._army_view.selected)
	_check(picked == "own", "the Settings window shows the saved view")
	settings._army_view.select(0)
	settings._army_view.item_selected.emit(0)
	_check(Settings.army_view == "all", "choosing in the window changes the view")

	# Hover card: the armies drawn in the hovered province, with a line each.
	layer.set_hover(mine.province)
	var card: Array = layer.card_armies()
	_check(card.has(mine) and card[0].tag == "FRA", "the card lists the armies in the hovered province, mine first")
	var line: String = layer.card_line(mine)
	_check(line.contains(mine.display_name) and line.contains("morale"), "its line names the army and its morale (%s)" % line)
	if not mine.general_name.is_empty():
		_check(line.contains(mine.general_name), "and its general")
	Settings.set_army_view("own")
	layer.set_hover(stranger.province)
	_check(not layer.card_armies().has(stranger), "hidden armies are left off the card")
	layer.set_hover(0)
	_check(layer.card_armies().is_empty(), "with nothing hovered there is no card")

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_settings.cfg"))
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)
