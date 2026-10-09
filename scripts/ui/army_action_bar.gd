extends PanelContainer
## The orders for the selected armies, in a bar at the bottom of the screen (as in Hearts of
## Iron): assign to a front or release from it, merge, split in half, detach one type, halt a
## march, board a ship or go ashore, change the map symbol, show on the map, deselect. It appears
## when the player has armies selected and goes when they are deselected. Everything goes through
## the same commands the Military window uses.

const GAP := 8.0
const RIGHT_MARGIN := 12.0
const BOTTOM := 34.0

var _ids: Array[int] = []
var _title := Label.new()
var _front := MenuButton.new()
var _release := Button.new()
var _merge := Button.new()
var _split := Button.new()
var _detach := MenuButton.new()
var _halt := Button.new()
var _board := Button.new()
var _land := Button.new()
var _symbol := MenuButton.new()
var _show := Button.new()
var _deselect := Button.new()
var _front_ids: Array[int] = []
var _detach_types: Array[String] = []
var _symbol_ids: Array[String] = []


func _ready() -> void:
	add_to_group("army_action_bar")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_top = -BOTTOM
	offset_bottom = -BOTTOM
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.95)
	style.border_color = Color(0.4, 0.46, 0.58)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.modulate = Fmt.DIM
	box.add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	add_child(box)

	_front.text = "Assign to front"
	_front.tooltip_text = "Put the selected armies on one of your fronts: they spread along it and hold it."
	_front.get_popup().about_to_popup.connect(_fill_fronts)
	_front.get_popup().id_pressed.connect(_on_front)
	_release.text = "Release"
	_release.tooltip_text = "Take the selected armies off their fronts."
	_release.pressed.connect(_on_release)
	_merge.text = "Merge"
	_merge.tooltip_text = "Combine the selected armies standing in one province into one."
	_merge.pressed.connect(_on_merge)
	_split.text = "Split"
	_split.tooltip_text = "Divide the army in two, half of its units each."
	_split.pressed.connect(_on_split)
	_detach.text = "Detach"
	_detach.tooltip_text = "Detach one unit of a type into a new army."
	_detach.get_popup().about_to_popup.connect(_fill_detach)
	_detach.get_popup().id_pressed.connect(_on_detach)
	_halt.text = "Halt"
	_halt.tooltip_text = "Stop the march: the army stays where it stands."
	_halt.pressed.connect(_on_halt)
	_board.text = "Board ship"
	_board.tooltip_text = "Put the armies aboard a fleet with transports in the same port."
	_board.pressed.connect(func() -> void: _via_panel("_on_board"))
	_land.text = "Disembark"
	_land.tooltip_text = "Put the armies ashore in the port their fleet lies in. At sea, right click a coast."
	_land.pressed.connect(func() -> void: _via_panel("_on_land"))
	_symbol.text = "Symbol"
	_symbol.tooltip_text = "The marker the map shows for these armies."
	_symbol.get_popup().about_to_popup.connect(_fill_symbols)
	_symbol.get_popup().id_pressed.connect(_on_symbol)
	_show.text = "Show"
	_show.tooltip_text = "Centre the map on the selection."
	_show.pressed.connect(_on_show)
	_deselect.text = "Deselect"
	_deselect.tooltip_text = "Clear the selection (Esc, or click empty ground)."
	_deselect.pressed.connect(func() -> void: get_tree().call_group("military_panel", "clear_selection"))
	for c: Control in [_front, _release, _merge, _split, _detach, _halt, _board, _land, _symbol, _show, _deselect]:
		c.focus_mode = Control.FOCUS_NONE
		row.add_child(c)

	GameState.armies_changed.connect(_refresh)
	GameState.fronts_changed.connect(_refresh)
	get_viewport().size_changed.connect(_place)
	resized.connect(_place)


## The map layer or the Military window changed the selection.
func set_selection(ids: Array[int]) -> void:
	_ids = ids
	_refresh()


func _armies() -> Array[Army]:
	var out: Array[Army] = []
	for id in _ids:
		var a: Army = GameState.armies.get(id)
		if a != null and a.tag == GameState.player_tag:
			out.append(a)
	return out


func _refresh() -> void:
	var armies := _armies()
	visible = not armies.is_empty()
	if not visible:
		return
	var men := 0.0
	var morale := 0.0
	var places := {}
	for a in armies:
		men += a.men()
		morale += a.morale() * a.men()
		places[a.province] = true
	if armies.size() == 1:
		var a := armies[0]
		_title.text = "%s · %s men · morale %d%% · %s" % [a.display_name, Fmt.people(men), roundi(a.morale() * 100.0), MapData.provinces[a.province].name]
	else:
		_title.text = "%d armies · %s men · morale %d%%" % [armies.size(), Fmt.people(men), roundi(morale / maxf(men, 1.0) * 100.0)]
	var any_front := armies.any(func(a: Army) -> bool: return a.front_id != 0)
	var landlubbers := armies.filter(func(a: Army) -> bool: return not a.embarked())
	var together := armies.size() >= 2 and places.size() == 1 and landlubbers.size() == armies.size()
	_front.disabled = landlubbers.is_empty()
	_release.disabled = not any_front
	_merge.disabled = not together
	_split.disabled = not (armies.size() == 1 and armies[0].units.size() >= 2 and not armies[0].embarked())
	_detach.disabled = not (armies.size() == 1 and armies[0].units.size() >= 2 and not armies[0].embarked())
	_halt.disabled = not armies.any(func(a: Army) -> bool: return not a.path.is_empty() and not a.embarked())
	var boardable := armies.any(func(a: Army) -> bool: return not a.embarked() and Navy.fleets_in_port(GameState, a.province).any(func(f: Fleet) -> bool: return f.tag == a.tag and f.capacity() > 0))
	_board.visible = boardable
	_land.visible = armies.any(func(a: Army) -> bool: return a.embarked() and GameState.fleets.has(a.fleet_id) and GameState.fleets[a.fleet_id].is_in_port())
	_place.call_deferred()


## Bottom centre of the screen, clear of the map mode palette on the left.
func _place() -> void:
	if not visible or not is_inside_tree():
		return
	var view := get_viewport_rect().size
	var wide := get_combined_minimum_size().x
	var left := 0.0
	var palette := get_tree().get_first_node_in_group("map_modes") as Control
	if palette != null:
		left = palette.get_global_rect().end.x + GAP
	var x := clampf((view.x - wide) * 0.5, left, maxf(left, view.x - wide - RIGHT_MARGIN))
	offset_left = x
	offset_right = x + wide


# ------------------------------------------------------------------ orders

func _via_panel(method: String) -> void:
	get_tree().call_group("military_panel", method)


func _select(ids: Array[int]) -> void:
	get_tree().call_group("military_panel", "select_ids", ids)


func _fill_fronts() -> void:
	var popup := _front.get_popup()
	popup.clear()
	_front_ids.clear()
	for f: Front in GameState.fronts.values():
		if f.tag == GameState.player_tag:
			_front_ids.append(f.id)
	_front_ids.sort()
	for i in _front_ids.size():
		var f: Front = GameState.fronts[_front_ids[i]]
		popup.add_item("%s (%d)" % [f.display_name, f.army_ids.size()], i)
	if _front_ids.is_empty():
		popup.add_item("No fronts yet: draw one in the Military window", 0)
		popup.set_item_disabled(0, true)


func _on_front(index: int) -> void:
	if index < 0 or index >= _front_ids.size():
		return
	var ids: Array[int] = []
	for a in _armies():
		if not a.embarked():
			ids.append(a.id)
	GameState.issue(AssignToFront.new(GameState.player_tag, _front_ids[index], ids))
	_refresh()


func _on_release() -> void:
	var ids: Array[int] = []
	for a in _armies():
		if a.front_id != 0:
			ids.append(a.id)
	if not ids.is_empty():
		GameState.issue(AssignToFront.new(GameState.player_tag, 0, ids))
	_refresh()


func _on_merge() -> void:
	var ids: Array[int] = []
	for a in _armies():
		ids.append(a.id)
	if GameState.issue(MergeArmies.new(GameState.player_tag, ids)):
		_select([ids[0]] as Array[int])


func _on_split() -> void:
	var armies := _armies()
	if armies.size() != 1:
		return
	var idx: Array[int] = []
	for i in range(1, armies[0].units.size(), 2):
		idx.append(i)
	var cmd := SplitArmy.new(GameState.player_tag, armies[0].id, idx)
	if GameState.issue(cmd):
		_select([armies[0].id, cmd.new_army_id] as Array[int])


func _fill_detach() -> void:
	var popup := _detach.get_popup()
	popup.clear()
	_detach_types.clear()
	var armies := _armies()
	if armies.size() != 1:
		return
	var comp := armies[0].composition()
	for type: String in comp:
		_detach_types.append(type)
		popup.add_item("%s (of %d)" % [Military.cfg.unit_types[type].name, comp[type]], _detach_types.size() - 1)


func _on_detach(index: int) -> void:
	var armies := _armies()
	if armies.size() != 1 or index < 0 or index >= _detach_types.size():
		return
	var picked := SplitArmy.indices_of_type(armies[0], _detach_types[index], 1)
	if picked.size() >= armies[0].units.size():
		return
	var cmd := SplitArmy.new(GameState.player_tag, armies[0].id, picked)
	if GameState.issue(cmd):
		_select([armies[0].id, cmd.new_army_id] as Array[int])


func _on_halt() -> void:
	for a in _armies():
		if not a.path.is_empty() and not a.embarked():
			GameState.issue(MoveArmy.new(GameState.player_tag, a.id, a.province))
	_refresh()


func _fill_symbols() -> void:
	var popup := _symbol.get_popup()
	popup.clear()
	_symbol_ids.clear()
	for key: String in Military.cfg.icons:
		_symbol_ids.append(key)
		popup.add_item(Military.cfg.icons[key], _symbol_ids.size() - 1)


func _on_symbol(index: int) -> void:
	if index < 0 or index >= _symbol_ids.size():
		return
	var ids: Array[int] = []
	for a in _armies():
		ids.append(a.id)
	GameState.issue(SetArmyIcon.new(GameState.player_tag, ids, _symbol_ids[index]))


func _on_show() -> void:
	var armies := _armies()
	if armies.is_empty():
		return
	var sum := Vector2.ZERO
	for a in armies:
		sum += MapData.provinces[a.province].center
	get_tree().call_group("camera_focus", "focus_on", sum / armies.size())
