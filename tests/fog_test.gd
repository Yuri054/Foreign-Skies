extends SceneTree
## Drives the fog on troops through the main scene: the army layer draws friends exactly and the
## rest as estimates or not at all, the hover card, the province panel's forces, the Strength map
## mode, and the "under arms" figure on another nation's country panel.
## Run: godot --headless --path . -s res://tests/fog_test.gd

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
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var Intel = load("res://scripts/sim/intel.gd")
	var Dip = load("res://scripts/sim/diplomacy.gd")
	gs.wars.clear()
	gs.join_calls.clear()
	gs.set_player("FRA")
	await process_frame
	var layer: Node = get_first_node_in_group("army_layer")
	var provinces: Node = get_first_node_in_group("province_panel")

	var exact = null
	var guess = null
	var hidden = null
	for a in gs.armies.values():
		match layer.seen(a):
			2:
				if a.tag != "FRA" and exact == null:
					exact = a
			1:
				if guess == null:
					guess = a
			0:
				if hidden == null:
					hidden = a
	_check(exact != null and guess != null and hidden != null, "there are allied, estimated and hidden armies (%s, %s, %s)" % [exact.tag if exact else "-", guess.tag if guess else "-", hidden.tag if hidden else "-"])
	_check(Dip.are_allied(gs, "FRA", exact.tag), "the exact one is an ally's")
	_check(layer.shows(guess) and not layer.shows(hidden), "the layer draws estimated armies and leaves hidden ones out")

	# The hover card: an ally in detail, a stranger only as a figure.
	layer.set_hover(exact.province)
	_check(layer.card_armies().has(exact) and layer.card_guesses().is_empty(), "the card describes an ally's army in detail")
	layer.set_hover(guess.province)
	var guesses: Dictionary = layer.card_guesses()
	_check(guesses.has(guess.tag) and not layer.card_armies().has(guess), "an estimated army appears only as a figure per nation")
	_check(absf(guesses[guess.tag] - guess.men()) <= guess.men() * Intel.ERROR + 5000.0 or layer.card_armies().size() > 0, "and the figure is close to the truth")
	layer.set_hover(hidden.province)
	_check(not layer.card_armies().has(hidden) and not layer.card_guesses().has(hidden.tag), "a hidden army has no card")
	layer.set_hover(0)

	# The province panel: names and figures for friends, a figure for the rest, nothing for hidden armies.
	provinces.show_province(guess.province)
	var text: String = provinces.plain_text()
	_check("estimate" in text and guess.display_name not in text, "the province panel gives an estimate and not the army's name (%s)" % text.replace("\n", " | ").substr(0, 120))
	provinces.show_province(exact.province)
	_check(exact.display_name in provinces.plain_text(), "and names an ally's army")
	provinces.show_province(hidden.province)
	_check(hidden.display_name not in provinces.plain_text() and "%s forces" % hidden.tag not in provinces.plain_text(), "a hidden army is not mentioned")

	# The Strength map mode counts only what is seen.
	var view: Sprite2D = main.map_view
	view._count_forces()
	_check(not view._men_at.has(hidden.province) or view._men_at[hidden.province] <= 0.0 or _other_visible_in(gs, hidden.province, layer), "the Strength mode counts no men where nothing is seen")
	var seen_men: float = view._men_at.get(guess.province, 0.0)
	_check(seen_men > 0.0, "and counts an estimate where an army is only guessed (%d)" % seen_men)

	# The country panel of a stranger gives an estimate; an ally's gives the figure.
	var stats: Node = get_first_node_in_group("nation_stats")
	stats.show_nation(guess.tag)
	await process_frame
	var panel_text: String = _all_text(stats)
	_check("men (estimate)" in panel_text, "a stranger's country panel gives a guess at its strength")
	stats.show_nation(exact.tag)
	await process_frame
	_check("(estimate)" not in _all_text(stats) and "Under arms" in _all_text(stats), "an ally's gives the real figure")
	stats.show_nation("FRA")
	await process_frame
	_check("(estimate)" not in _all_text(stats), "and so does your own")

	# The setting can hide more, never more than the eyes reach.
	var Settings = load("res://scripts/ui/ui_settings.gd")
	Settings.set_army_view("allies")
	_check(layer.shows(exact) and not layer.shows(guess), "'Mine and allies' hides the estimated armies")
	Settings.set_army_view("all")
	_check(layer.shows(guess) and not layer.shows(hidden), "'Everything I can see' still leaves out what is out of sight")

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_settings.cfg"))
	print("FAILURES: ", _failures)
	quit(1 if _failures > 0 else 0)


## Whether some other army that is seen stands in the province (then the mode counts it).
func _other_visible_in(gs: Node, province: int, layer: Node) -> bool:
	for a in gs.armies.values():
		if a.province == province and layer.seen(a) != 0:
			return true
	return false


func _all_text(node: Node) -> String:
	var out := ""
	if node is Label:
		out += node.text + "\n"
	for c in node.get_children():
		out += _all_text(c)
	return out
