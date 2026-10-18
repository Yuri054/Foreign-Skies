extends PanelContainer
## The command panel along the bottom of the screen, as in Hearts of Iron: your armies as cards
## under their field marshals, or your fleets as cards, with the orders for the selection on a
## strip above them. A card carries the commander's initials and skill (there are no portraits),
## the name, the units and men, and strength and morale bars. Each army group has a header that
## folds it down to its marshal. The panel can be hidden with its button or the C key, and shows
## the fleets alone while a fleet is selected. Everything goes through the same commands the
## Military and Navy windows use.

const GAP := 8.0
const RIGHT_MARGIN := 12.0
const BOTTOM := 34.0
## Room the build queue takes at the right while it shows.
const QUEUE_ROOM := 318.0
const MIN_CARDS := 220.0
## The share of the screen width the panel may take; the cards scroll beyond it.
const MAX_SHARE := 0.7
## Room under the cards for the scroll bar.
const SCROLLBAR := 12.0

## Selected armies and fleets (the Military and Navy windows hold the selection).
var _ids: Array[int] = []
var _fleet_ids: Array[int] = []
## "army" or "navy": what the cards show.
var _mode := "army"
var _open := true
## Army groups folded down to their marshal (group id to true; 0 is the unassigned armies).
var _collapsed: Dictionary = {}
var _layout_key := -1
var _toggle := Button.new()
var _tab_army := Button.new()
var _tab_navy := Button.new()
var _title := Label.new()
var _top := PanelContainer.new()
var _div_frame := PanelContainer.new()
var _tabs_col := PanelContainer.new()
var _army_orders := HFlowContainer.new()
var _fleet_orders := HFlowContainer.new()
var _scroll := ScrollContainer.new()
var _div_row := HFlowContainer.new()
var _div_new := Button.new()
## The divisions (positions in the army's units) picked in the divisions row, and the army they
## belong to; right clicking another army card moves them there.
var _div_sel: Array[int] = []
var _div_army := 0
var _div_key := -1
var _cards := HBoxContainer.new()
var _menu := PopupMenu.new()
var _menu_calls: Array[Callable] = []
var _front := MenuButton.new()
var _release := Button.new()
var _merge := Button.new()
var _split := Button.new()
var _detach := MenuButton.new()
var _halt := Button.new()
var _board := Button.new()
var _land := Button.new()
var _general := MenuButton.new()
var _group := MenuButton.new()
var _attack := MenuButton.new()
var _symbol := MenuButton.new()
var _show := Button.new()
var _deselect := Button.new()
var _f_orders := MenuButton.new()
var _f_merge := Button.new()
var _f_detach := MenuButton.new()
var _f_home := Button.new()
var _f_show := Button.new()
var _f_deselect := Button.new()
var _front_ids: Array[int] = []
## Enemies a new border front can face, in menu order.
var _front_enemies: Array[String] = []
var _detach_types: Array[String] = []
var _symbol_ids: Array[String] = []
## Generals the menu offers, in menu order (the last entry may be "relieve", id 0).
var _general_ids: Array[int] = []
## Groups and marshals the Group menu offers, by menu id (see _fill_group).
var _group_ids: Array[int] = []
## Enemies the Attack menu offers, by menu id.
var _attack_enemies: Array[String] = []
var _marshal_ids: Array[int] = []
var _mission_keys: Array[String] = []
var _f_detach_types: Array[String] = []


func _ready() -> void:
	add_to_group("command_panel")
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
	_open = UiSettings.command_open
	# No box around the whole panel: the map shows between the framed blocks, as in the
	# Paradox games.
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	# Smaller text than the rest of the interface keeps the panel short.
	var small := UiTheme.build()
	small.default_font_size = 12
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := small.get_stylebox(state, "Button").duplicate() as StyleBoxFlat
		box.content_margin_left = 5
		box.content_margin_right = 5
		box.content_margin_top = 0
		box.content_margin_bottom = 0
		small.set_stylebox(state, "Button", box)
		small.set_stylebox(state, "MenuButton", box)
	small.set_constant("separation", "HBoxContainer", 3)
	small.set_constant("separation", "VBoxContainer", 2)
	theme = small

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	add_child(box)
	# The orders for the selection sit in a frame of their own above the cards.
	_top.add_theme_stylebox_override("panel", frame_style())
	_top.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_div_frame.add_theme_stylebox_override("panel", frame_style())
	_div_frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(_top)
	box.add_child(_div_frame)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 4)
	box.add_child(strip)
	_toggle.tooltip_text = "Show or hide the command panel (C)."
	_toggle.pressed.connect(toggle)
	_tab_army.text = "Armies"
	_tab_army.toggle_mode = true
	_tab_army.tooltip_text = "Your armies under their field marshals."
	_tab_army.pressed.connect(func() -> void: _set_mode("army"))
	_tab_navy.text = "Fleets"
	_tab_navy.toggle_mode = true
	_tab_navy.tooltip_text = "Your fleets. They also show when you select one."
	_tab_navy.pressed.connect(func() -> void: _set_mode("navy"))
	_army_orders.add_theme_constant_override("h_separation", 2)
	_fleet_orders.add_theme_constant_override("h_separation", 2)
	_army_orders.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fleet_orders.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var orders := HBoxContainer.new()
	orders.add_child(_army_orders)
	orders.add_child(_fleet_orders)
	_top.add_child(orders)
	_div_row.add_theme_constant_override("h_separation", 2)
	_div_row.add_theme_constant_override("v_separation", 2)
	_div_frame.add_child(_div_row)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(MIN_CARDS, CommandCard.SIZE.y + 24.0)
	_cards.add_theme_constant_override("separation", 4)
	_scroll.add_child(_cards)
	strip.add_child(_scroll)
	# The tabs stand in a column at the right end of the strip, as in the Paradox games.
	_tabs_col.add_theme_stylebox_override("panel", frame_style())
	_tabs_col.size_flags_vertical = Control.SIZE_SHRINK_END
	var tabs := VBoxContainer.new()
	tabs.add_child(_toggle)
	tabs.add_child(_tab_army)
	tabs.add_child(_tab_navy)
	_tabs_col.add_child(tabs)
	strip.add_child(_tabs_col)
	add_child(_menu)
	_menu.id_pressed.connect(func(id: int) -> void:
		if id >= 0 and id < _menu_calls.size():
			_menu_calls[id].call())

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
	_general.text = "General"
	_general.tooltip_text = "Choose who commands this army. A general's skill multiplies the army's power."
	_general.get_popup().about_to_popup.connect(_fill_generals)
	_general.get_popup().id_pressed.connect(_on_general)
	_group.text = "Group"
	_group.tooltip_text = "Army groups: put the selected armies in a group under a field marshal, whose skill adds to theirs."
	_group.get_popup().about_to_popup.connect(_fill_group)
	_group.get_popup().id_pressed.connect(_on_group)
	_attack.text = "Attack"
	_attack.tooltip_text = "Attack line: send the army group against an enemy along a front. Start and stop it here."
	_attack.get_popup().about_to_popup.connect(_fill_attack)
	_attack.get_popup().id_pressed.connect(_on_attack)
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
	for c: Control in [_front, _release, _merge, _split, _detach, _halt, _board, _land, _general, _group, _attack, _symbol, _show, _deselect]:
		c.focus_mode = Control.FOCUS_NONE
		_army_orders.add_child(c)

	_f_orders.text = "Orders"
	_f_orders.tooltip_text = "Standing orders: stationed, on patrol, blockading, escorting or raiding."
	_f_orders.get_popup().about_to_popup.connect(_fill_orders)
	_f_orders.get_popup().id_pressed.connect(_on_orders)
	_f_merge.text = "Merge"
	_f_merge.tooltip_text = "Combine the selected fleets that lie together."
	_f_merge.pressed.connect(_on_fleet_merge)
	_f_detach.text = "Detach"
	_f_detach.tooltip_text = "Detach one squadron of a type into a new fleet."
	_f_detach.get_popup().about_to_popup.connect(_fill_fleet_detach)
	_f_detach.get_popup().id_pressed.connect(_on_fleet_detach)
	_f_home.text = "To port"
	_f_home.tooltip_text = "Send the selected fleets to the nearest port you may use."
	_f_home.pressed.connect(_on_fleet_home)
	_f_show.text = "Show"
	_f_show.tooltip_text = "Centre the map on the selection."
	_f_show.pressed.connect(_on_fleet_show)
	_f_deselect.text = "Deselect"
	_f_deselect.tooltip_text = "Clear the selection (Esc, or click empty water)."
	_f_deselect.pressed.connect(func() -> void: get_tree().call_group("navy_panel", "clear_selection"))
	for c: Control in [_f_orders, _f_merge, _f_detach, _f_home, _f_show, _f_deselect]:
		c.focus_mode = Control.FOCUS_NONE
		_fleet_orders.add_child(c)
	for c: Control in [_toggle, _tab_army, _tab_navy]:
		c.focus_mode = Control.FOCUS_NONE

	GameState.armies_changed.connect(_refresh)
	GameState.fronts_changed.connect(_refresh)
	GameState.fleets_changed.connect(_refresh)
	GameState.player_changed.connect(func(_t: String) -> void: _refresh())
	get_viewport().size_changed.connect(_place)
	resized.connect(_place)
	_refresh()


## C shows or hides the panel.
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C \
			and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		toggle()
		get_viewport().set_input_as_handled()


## Shows or hides the cards and orders (the header stays); the choice is saved.
func toggle() -> void:
	_open = not _open
	UiSettings.set_command_open(_open)
	_refresh()


func is_open() -> bool:
	return _open


## The map layer or the Military window changed the army selection.
func set_selection(ids: Array[int]) -> void:
	_ids = ids
	if not _armies().is_empty():
		_mode = "army"
	_refresh()


## The Navy window changed the fleet selection. Selecting a fleet puts the fleets on show.
func set_fleet_selection(ids: Array[int]) -> void:
	_fleet_ids = ids
	if not _fleets().is_empty() and _armies().is_empty():
		_mode = "navy"
	_refresh()


func _set_mode(mode: String) -> void:
	_mode = mode
	_refresh()


func _armies() -> Array[Army]:
	var out: Array[Army] = []
	for id in _ids:
		var a: Army = GameState.armies.get(id)
		if a != null and a.tag == GameState.player_tag:
			out.append(a)
	return out


func _fleets() -> Array[Fleet]:
	var out: Array[Fleet] = []
	for id in _fleet_ids:
		var f: Fleet = GameState.fleets.get(id)
		if f != null and f.tag == GameState.player_tag:
			out.append(f)
	return out


func _refresh() -> void:
	visible = GameState.get_player() != null
	if not visible:
		return
	_toggle.text = "Hide (C)" if _open else "Command (C)"
	_tab_army.set_pressed_no_signal(_mode == "army")
	_tab_navy.set_pressed_no_signal(_mode == "navy")
	_tab_army.visible = _open
	_tab_navy.visible = _open
	_scroll.visible = _open
	var armies := _armies()
	var fleets := _fleets()
	_army_orders.visible = _open and _mode == "army" and not armies.is_empty()
	_fleet_orders.visible = _open and _mode == "navy" and not fleets.is_empty()
	_top.visible = _army_orders.visible or _fleet_orders.visible
	_title.text = _army_title(armies) if _mode == "army" else _fleet_title(fleets)
	tooltip_text = _title.text
	_refresh_divisions(armies)
	if _army_orders.visible:
		_refresh_army_orders(armies)
	if _fleet_orders.visible:
		_refresh_fleet_orders(fleets)
	if _open:
		_rebuild_cards()
	_place.call_deferred()


## The divisions of the one selected army, as small buttons to pick (the letter is the type, the
## number the strength). The picked ones move to another army when you right click its card.
func _refresh_divisions(armies: Array[Army]) -> void:
	var show := _open and _mode == "army" and armies.size() == 1 and not armies[0].embarked()
	_div_row.visible = show
	_div_frame.visible = show
	if not show:
		_div_sel.clear()
		_div_army = 0
		_div_key = -1
		return
	var a := armies[0]
	if a.id != _div_army:
		_div_army = a.id
		_div_sel.clear()
	_div_sel = _div_sel.filter(func(i: int) -> bool: return i < a.units.size())
	var key := _div_state_key(a)
	if key == _div_key:
		return
	_div_key = key
	for c in _div_row.get_children():
		_div_row.remove_child(c)
		if c != _div_new:
			c.queue_free()
	var label := Label.new()
	label.text = "Divisions:"
	label.modulate = Fmt.DIM
	_div_row.add_child(label)
	for i in a.units.size():
		var u: Unit = a.units[i]
		var chip := Button.new()
		chip.toggle_mode = true
		chip.focus_mode = Control.FOCUS_NONE
		chip.text = Military.cfg.unit_types[u.type].name.substr(0, 1)
		if u.strength < 0.995:
			chip.text += " %d" % roundi(u.strength * 100.0)
		chip.button_pressed = _div_sel.has(i)
		chip.tooltip_text = "%s: %s men, strength %d%%, morale %d%%.\nPick divisions, then right click another army's card to move them there." % [
				Military.cfg.unit_types[u.type].name, Fmt.people(u.men()), roundi(u.strength * 100.0), roundi(u.morale * 100.0)]
		chip.toggled.connect(_on_division_toggled.bind(i))
		_div_row.add_child(chip)
	_div_new.text = "New army"
	_div_new.tooltip_text = "Make a new army of the picked divisions, in the same province."
	_div_new.focus_mode = Control.FOCUS_NONE
	if not _div_new.pressed.is_connected(_on_division_new):
		_div_new.pressed.connect(_on_division_new)
	_div_row.add_child(_div_new)
	_update_division_buttons(a)


func _div_state_key(a: Army) -> int:
	var parts: Array = [a.id, _div_sel]
	for u in a.units:
		parts.append([u.type, roundi(u.strength * 100.0)])
	return parts.hash()


func _update_division_buttons(a: Army) -> void:
	_div_new.disabled = _div_sel.is_empty() or _div_sel.size() >= a.units.size()


func _on_division_toggled(on: bool, index: int) -> void:
	if on and not _div_sel.has(index):
		_div_sel.append(index)
	elif not on:
		_div_sel.erase(index)
	var a: Army = GameState.armies.get(_div_army)
	if a != null:
		# The chips are already in the right state; only the key and the button follow.
		_div_key = _div_state_key(a)
		_update_division_buttons(a)


func _on_division_new() -> void:
	var idx: Array[int] = _div_sel.duplicate()
	var cmd := SplitArmy.new(GameState.player_tag, _div_army, idx)
	_div_sel.clear()
	if GameState.issue(cmd):
		_select([_div_army, cmd.new_army_id] as Array[int])


## Moves the picked divisions into the army whose card was right clicked.
func _move_divisions_to(target_id: int) -> void:
	var idx: Array[int] = _div_sel.duplicate()
	var from := _div_army
	_div_sel.clear()
	if GameState.issue(TransferUnits.new(GameState.player_tag, from, idx, target_id)):
		_select([target_id] as Array[int])


func _army_title(armies: Array[Army]) -> String:
	if armies.is_empty():
		var mine := Military.armies_of(GameState, GameState.player_tag)
		var total := 0.0
		for a in mine:
			total += a.men()
		return "%d armies · %s men" % [mine.size(), Fmt.people(total)]
	var men := 0.0
	var morale := 0.0
	for a in armies:
		men += a.men()
		morale += a.morale() * a.men()
	var line := _line()
	if line != null:
		return "%s · %s" % [line.display_name, _line_status(line)]
	if armies.size() == 1:
		var a := armies[0]
		return "%s · %s men · morale %d%% · %s" % [a.display_name, Fmt.people(men), roundi(a.morale() * 100.0), MapData.provinces[a.province].name]
	return "%d armies · %s men · morale %d%%" % [armies.size(), Fmt.people(men), roundi(morale / maxf(men, 1.0) * 100.0)]


func _fleet_title(fleets: Array[Fleet]) -> String:
	if fleets.is_empty():
		var n := 0
		for f: Fleet in GameState.fleets.values():
			if f.tag == GameState.player_tag:
				n += 1
		return "%d fleets" % n
	var ships := 0
	for f in fleets:
		ships += f.ships.size()
	if fleets.size() == 1:
		return "%s · %d ships · morale %d%% · %s" % [fleets[0].display_name, ships, roundi(fleets[0].morale() * 100.0), _where(fleets[0])]
	return "%d fleets · %d ships" % [fleets.size(), ships]


func _where(f: Fleet) -> String:
	if f.is_in_port():
		return MapData.provinces[f.port].name
	if f.zone > 0:
		return MapData.sea_zones[f.zone].name
	return ""


func _refresh_army_orders(armies: Array[Army]) -> void:
	var places := {}
	for a in armies:
		places[a.province] = true
	var any_front := armies.any(func(a: Army) -> bool: return a.front_id != 0)
	var landlubbers := armies.filter(func(a: Army) -> bool: return not a.embarked())
	var together := armies.size() >= 2 and places.size() == 1 and landlubbers.size() == armies.size()
	_front.disabled = landlubbers.is_empty()
	_release.disabled = not any_front
	_merge.disabled = not together
	_split.disabled = not (armies.size() == 1 and armies[0].units.size() >= 2 and not armies[0].embarked())
	_detach.disabled = not (armies.size() == 1 and armies[0].units.size() >= 2 and not armies[0].embarked())
	_general.disabled = not (armies.size() == 1 and not armies[0].embarked())
	_group.disabled = false
	_attack.visible = _common_group() != null
	_halt.disabled = not armies.any(func(a: Army) -> bool: return not a.path.is_empty() and not a.embarked())
	var boardable := armies.any(func(a: Army) -> bool: return not a.embarked() and Navy.fleets_in_port(GameState, a.province).any(func(f: Fleet) -> bool: return f.tag == a.tag and f.capacity() > 0))
	_board.visible = boardable
	_land.visible = armies.any(func(a: Army) -> bool: return a.embarked() and GameState.fleets.has(a.fleet_id) and GameState.fleets[a.fleet_id].is_in_port())


func _refresh_fleet_orders(fleets: Array[Fleet]) -> void:
	var places := {}
	for f in fleets:
		places[_where(f)] = true
	_f_merge.disabled = not (fleets.size() >= 2 and places.size() == 1)
	_f_detach.disabled = not (fleets.size() == 1 and fleets[0].ships.size() >= 2 and not fleets[0].fighting)
	_f_home.disabled = fleets.all(func(f: Fleet) -> bool: return f.is_in_port() and not f.is_moving())


## Bottom left of the screen, resting on the map mode palette, and short of the build queue
## while it shows. It is as wide as its cards need, between MIN_WIDE and the room there is.
func _place() -> void:
	if not visible or not is_inside_tree():
		return
	var view := get_viewport_rect().size
	var left := GAP
	var bottom := BOTTOM
	var palette := get_tree().get_first_node_in_group("map_modes") as Control
	if palette != null and palette.visible:
		bottom = maxf(view.y - palette.get_global_rect().position.y + GAP, BOTTOM)
	var right := view.x - RIGHT_MARGIN
	var n := GameState.get_player()
	if n != null and not (n.construction.is_empty() and n.shipbuilding.is_empty()):
		right -= QUEUE_ROOM
	var tabs_w := _tabs_col.get_combined_minimum_size().x
	var avail := minf(maxf(right - left, 320.0), view.x * MAX_SHARE) - tabs_w - 4.0
	# Wide enough for the orders to stay on one line.
	var orders_w := _natural_width(_army_orders) if _army_orders.visible else (_natural_width(_fleet_orders) if _fleet_orders.visible else 0.0)
	orders_w += 14.0
	var inner := clampf(maxf(maxf(_cards.get_combined_minimum_size().x + 4.0, MIN_CARDS), orders_w - tabs_w), 120.0, avail)
	var want := inner + tabs_w + 4.0
	if not _open:
		want = tabs_w
	_scroll.custom_minimum_size = Vector2(inner, _cards.get_combined_minimum_size().y + SCROLLBAR)
	# The frames over the cards are as wide as their buttons need, up to the width of the panel,
	# so a flow of buttons wraps only when it must.
	var room := inner + tabs_w + 4.0
	_top.custom_minimum_size.x = minf(orders_w, room)
	_div_frame.custom_minimum_size.x = minf(_natural_width(_div_row) + 14.0, room)
	offset_left = left
	offset_right = left + want
	offset_top = -bottom
	offset_bottom = -bottom


## The dark, brass-edged frame the blocks of the panel sit in.
static func frame_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.09, 0.1, 0.11, 0.94)
	box.border_color = Color(0.5, 0.45, 0.31)
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 2
	box.content_margin_bottom = 3
	return box


## The width a flow of buttons needs to stay on one line.
func _natural_width(flow: Control) -> float:
	var total := 0.0
	var n := 0
	for c in flow.get_children():
		if c is Control and c.visible:
			total += (c as Control).get_combined_minimum_size().x
			n += 1
	return total + 2.0 * maxf(n - 1, 0)


# ------------------------------------------------------------------ cards

func _rebuild_cards() -> void:
	var blocks := _army_blocks() if _mode == "army" else _fleet_blocks()
	var key := [_mode, blocks, _ids, _fleet_ids].hash()
	if key == _layout_key:
		return
	_layout_key = key
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()
	for block: Dictionary in blocks:
		_cards.add_child(_make_block(block))


## One column of the strip: an optional header (fold button and a Select button) over a row of
## cards.
func _make_block(block: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	if block.has("header"):
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 2)
		var fold := Button.new()
		fold.text = ("▸ " if block.collapsed else "▾ ") + block.header
		fold.flat = true
		fold.alignment = HORIZONTAL_ALIGNMENT_LEFT
		fold.focus_mode = Control.FOCUS_NONE
		fold.tooltip_text = "Fold the group down to its marshal, or open it again."
		fold.pressed.connect(_on_fold.bind(block.group))
		head.add_child(fold)
		if block.group != 0:
			var pick := Button.new()
			pick.text = "Select"
			pick.flat = true
			pick.focus_mode = Control.FOCUS_NONE
			pick.tooltip_text = "Select every army of the group."
			pick.pressed.connect(_on_select_group.bind(block.group, false))
			head.add_child(pick)
		col.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for spec: Dictionary in block.cards:
		row.add_child(_make_card(spec))
	col.add_child(row)
	var framed := PanelContainer.new()
	framed.add_theme_stylebox_override("panel", frame_style())
	framed.add_child(col)
	return framed


func _make_card(spec: Dictionary) -> CommandCard:
	var card := CommandCard.new()
	for key: String in ["title", "badge", "skill", "line1", "line2", "strength", "morale", "tint", "selected", "fighting", "marshal", "empty", "marks"]:
		if spec.has(key):
			card.set(key, spec[key])
	card.tooltip_text = spec.get("tip", "")
	card.pressed.connect(_on_card.bind(spec.kind, spec.id))
	card.context_requested.connect(_on_card_context.bind(spec.kind, spec.id))
	return card


func _army_card(a: Army, tint: Color) -> Dictionary:
	var full := 0.0
	for u in a.units:
		full += u.full_size()
	var marks := PackedStringArray()
	if not a.supplied:
		marks.append("!")
	if a.embarked():
		marks.append("⚓")
	elif not a.path.is_empty():
		marks.append("›")
	var has_general := a.general_id != 0
	var tip := "%s\n%s men in %d units, morale %d%%\n%s" % [a.display_name, Fmt.people(a.men()), a.units.size(),
			roundi(a.morale() * 100.0), MapData.provinces[a.province].name]
	if has_general:
		tip += "\nLed by %s (skill %.2f)" % [a.general_name, a.general_skill]
	else:
		tip += "\nNo general: right click to give it one."
	return {"kind": "army", "id": a.id, "title": a.display_name, "badge": CommandCard.initials(a.general_name),
			"skill": ("%.2f" % a.general_skill) if has_general else "", "empty": not has_general,
			"line1": "%d · %s" % [a.units.size(), Fmt.people(a.men())],
			"strength": a.men() / maxf(full, 1.0), "morale": a.morale(), "tint": tint, "selected": _ids.has(a.id),
			"fighting": a.fighting, "marks": marks, "tip": tip}


func _marshal_card(group: ArmyGroup, tint: Color) -> Dictionary:
	var m: General = GameState.generals.get(group.marshal_id)
	var men := 0.0
	var all_selected := not group.army_ids.is_empty()
	for id in group.army_ids:
		if GameState.armies.has(id):
			men += GameState.armies[id].men()
		all_selected = all_selected and _ids.has(id)
	var tip := "%s: %d armies, %s men." % [group.display_name, group.army_ids.size(), Fmt.people(men)]
	if m != null:
		tip += "\nField marshal %s (skill %.2f): his skill adds to every army's own general." % [m.display_name, m.skill]
	else:
		tip += "\nNo field marshal: right click to appoint one."
	return {"kind": "marshal", "id": group.id, "title": "Marshal", "badge": CommandCard.initials(m.display_name) if m != null else "",
			"skill": ("%.2f" % m.skill) if m != null else "", "empty": m == null, "marshal": true,
			"line1": "%d armies" % group.army_ids.size(),
			"tint": tint, "selected": all_selected, "tip": tip}


## The army view: a block per army group (folded to the marshal if it was), the armies in no
## group, and a "+" card that makes a group of the selected armies.
func _army_blocks() -> Array:
	var tag := GameState.player_tag
	var blocks: Array = []
	var groups: Array[ArmyGroup] = []
	for g: ArmyGroup in GameState.army_groups.values():
		if g.tag == tag:
			groups.append(g)
	groups.sort_custom(func(x: ArmyGroup, y: ArmyGroup) -> bool: return x.id < y.id)
	var tint: Color = GameState.nations[tag].color if GameState.nations.has(tag) else Color.GRAY
	for g in groups:
		var folded: bool = _collapsed.get(g.id, false)
		var armies: Array[Army] = []
		var men := 0.0
		for id in g.army_ids:
			var a: Army = GameState.armies.get(id)
			if a != null:
				armies.append(a)
				men += a.men()
		var cards: Array = [_marshal_card(g, tint)]
		if not folded:
			for a in armies:
				cards.append(_army_card(a, tint))
		var line := AttackLines.of_group(GameState, g.id)
		var status := "" if line == null else " · " + _line_status(line)
		blocks.append({"group": g.id, "collapsed": folded, "cards": cards,
				"header": "%s · %d armies · %s men%s" % [g.display_name, armies.size(), Fmt.people(men), status]})
	var loose: Array[Army] = []
	for a in Military.armies_of(GameState, tag):
		if a.group_id == 0:
			loose.append(a)
	if not loose.is_empty():
		var folded: bool = _collapsed.get(0, false)
		var cards: Array = []
		if not folded:
			for a in loose:
				cards.append(_army_card(a, tint))
		else:
			cards.append({"kind": "unassigned", "id": 0, "title": "Unassigned", "badge": str(loose.size()), "line1": "%d armies" % loose.size(),
					"tint": tint, "tip": "Armies in no group. Open the header to see them."})
		blocks.append({"group": 0, "collapsed": folded, "cards": cards, "header": "Unassigned · %d armies" % loose.size()})
	blocks.append({"cards": [{"kind": "newgroup", "id": 0, "title": "New group", "empty": true, "tint": tint,
			"line1": "from the selection", "tip": "Make an army group of the selected armies, to put a field marshal over them."}]})
	return blocks


func _fleet_blocks() -> Array:
	var tag := GameState.player_tag
	var tint: Color = GameState.nations[tag].color if GameState.nations.has(tag) else Color.GRAY
	var list: Array[Fleet] = []
	for f: Fleet in GameState.fleets.values():
		if f.tag == tag:
			list.append(f)
	list.sort_custom(func(x: Fleet, y: Fleet) -> bool: return x.id < y.id)
	var cards: Array = []
	for f in list:
		var strength := 0.0
		for s in f.ships:
			strength += s.strength
		var count := maxf(f.ships.size(), 1)
		var marks := PackedStringArray()
		if f.fighting:
			marks.append("!")
		if f.is_in_port():
			marks.append("⚓")
		elif f.is_moving():
			marks.append("›")
		var mission: String = Navy.cfg.missions.get(f.mission, f.mission)
		cards.append({"kind": "fleet", "id": f.id, "title": f.display_name, "badge": str(f.ships.size()), "skill": mission,
				"line1": "%d · %d%%" % [f.ships.size(), roundi(strength / count * 100.0)],
				"strength": strength / count, "morale": f.morale(), "tint": tint, "selected": _fleet_ids.has(f.id),
				"fighting": f.fighting, "marks": marks,
				"tip": "%s\n%d ships, morale %d%%\n%s: %s" % [f.display_name, f.ships.size(), roundi(f.morale() * 100.0), mission, _where(f)]})
	if cards.is_empty():
		return [{"cards": [{"kind": "none", "id": 0, "title": "No fleets", "empty": true, "tint": tint}]}]
	return [{"cards": cards}]


func _on_fold(group: int) -> void:
	_collapsed[group] = not _collapsed.get(group, false)
	_layout_key = -1
	_refresh()


func _on_select_group(group_id: int, additive: bool) -> void:
	var g: ArmyGroup = GameState.army_groups.get(group_id)
	if g == null:
		return
	var ids: Array[int] = []
	if additive:
		ids.append_array(_ids)
	for id in g.army_ids:
		if not ids.has(id):
			ids.append(id)
	_select(ids)


func _toggled(current: Array[int], id: int, shift: bool) -> Array[int]:
	var ids: Array[int] = []
	if shift:
		ids.append_array(current)
		if ids.has(id):
			ids.erase(id)
		else:
			ids.append(id)
	else:
		ids.append(id)
	return ids


func _on_card(shift: bool, kind: String, id: int) -> void:
	match kind:
		"army":
			_select(_toggled(_ids, id, shift))
		"marshal":
			_on_select_group(id, shift)
		"unassigned":
			_on_fold(0)
		"fleet":
			get_tree().call_group("navy_panel", "select_ids", _toggled(_fleet_ids, id, shift))
		"newgroup":
			var ids: Array[int] = []
			for a in _armies():
				ids.append(a.id)
			if not ids.is_empty():
				GameState.issue(CreateArmyGroup.new(GameState.player_tag, "", ids))


func _on_card_context(at: Vector2, kind: String, id: int) -> void:
	var tag := GameState.player_tag
	var items: Array = []
	var pool := Military.pool_of(GameState, tag)
	match kind:
		"army":
			var a: Army = GameState.armies.get(id)
			if a == null:
				return
			if not _div_sel.is_empty() and a.id != _div_army:
				var why := TransferUnits.block(GameState, GameState.armies.get(_div_army), a)
				items.append({"sep": "Divisions"})
				items.append({"text": "Move %d picked divisions here%s" % [_div_sel.size(), "" if why.is_empty() else " (%s)" % why],
						"disabled": not why.is_empty(), "call": func() -> void: _move_divisions_to(a.id)})
			items.append({"sep": "General"})
			for g in pool.slice(0, 8):
				items.append({"text": "%s · skill %.2f" % [g.display_name, g.skill], "call": func() -> void: GameState.issue(AssignGeneral.new(tag, g.id, a.id))})
			if pool.is_empty():
				items.append({"text": "No free general", "disabled": true})
			if a.general_id != 0:
				items.append({"text": "Relieve %s" % a.general_name, "call": func() -> void: GameState.issue(AssignGeneral.new(tag, a.general_id, 0))})
			items.append({"sep": "Group"})
			items.append({"text": "New group with this army", "call": func() -> void: GameState.issue(CreateArmyGroup.new(tag, "", [a.id] as Array[int]))})
			for grp: ArmyGroup in GameState.army_groups.values():
				if grp.tag == tag and grp.id != a.group_id:
					items.append({"text": "Join %s" % grp.display_name, "call": func() -> void: GameState.issue(AssignToGroup.new(tag, grp.id, [a.id] as Array[int]))})
			if a.group_id != 0:
				items.append({"text": "Leave the group", "call": func() -> void: GameState.issue(AssignToGroup.new(tag, 0, [a.id] as Array[int]))})
		"marshal":
			var grp: ArmyGroup = GameState.army_groups.get(id)
			if grp == null:
				return
			items.append({"sep": "Field marshal"})
			for g in pool.slice(0, 8):
				items.append({"text": "%s · skill %.2f" % [g.display_name, g.skill], "call": func() -> void: GameState.issue(SetMarshal.new(tag, grp.id, g.id))})
			if pool.is_empty():
				items.append({"text": "No free general", "disabled": true})
			if grp.marshal_id != 0:
				items.append({"text": "Relieve the marshal", "call": func() -> void: GameState.issue(SetMarshal.new(tag, grp.id, 0))})
			items.append({"sep": ""})
			items.append({"text": "Disband %s" % grp.display_name, "call": func() -> void: GameState.issue(DisbandArmyGroup.new(tag, grp.id))})
	if not items.is_empty():
		_open_menu(items, at)


## Pops up a menu at a screen position. Items are {sep: title}, or {text, call, disabled}.
func _open_menu(items: Array, at: Vector2) -> void:
	_menu.clear()
	_menu_calls.clear()
	for item: Dictionary in items:
		if item.has("sep"):
			_menu.add_separator(item.sep)
		else:
			var id := _menu_calls.size()
			_menu_calls.append(item.get("call", func() -> void: pass))
			_menu.add_item(item.text, id)
			if item.get("disabled", false):
				_menu.set_item_disabled(_menu.get_item_index(id), true)
	_menu.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


# ------------------------------------------------------------------ fleet orders

func _fill_orders() -> void:
	var popup := _f_orders.get_popup()
	popup.clear()
	_mission_keys.clear()
	for key: String in Navy.cfg.missions:
		_mission_keys.append(key)
		popup.add_item(Navy.cfg.missions[key], _mission_keys.size() - 1)


func _on_orders(index: int) -> void:
	if index < 0 or index >= _mission_keys.size():
		return
	for f in _fleets():
		GameState.issue(SetFleetMission.new(GameState.player_tag, f.id, _mission_keys[index]))


func _on_fleet_merge() -> void:
	var ids: Array[int] = []
	for f in _fleets():
		ids.append(f.id)
	if GameState.issue(MergeFleets.new(GameState.player_tag, ids)):
		get_tree().call_group("navy_panel", "select_ids", [ids[0]] as Array[int])


func _fill_fleet_detach() -> void:
	var popup := _f_detach.get_popup()
	popup.clear()
	_f_detach_types.clear()
	var fleets := _fleets()
	if fleets.size() != 1:
		return
	var comp := fleets[0].composition()
	for type: String in comp:
		_f_detach_types.append(type)
		popup.add_item("%s (%d)" % [Navy.cfg.types[type].name, comp[type]], _f_detach_types.size() - 1)


func _on_fleet_detach(index: int) -> void:
	var fleets := _fleets()
	if fleets.size() != 1 or index < 0 or index >= _f_detach_types.size():
		return
	var cmd := SplitFleet.new(GameState.player_tag, fleets[0].id, SplitFleet.indices_of_type(fleets[0], _f_detach_types[index], 1))
	if GameState.issue(cmd):
		get_tree().call_group("navy_panel", "select_ids", [cmd.new_fleet_id] as Array[int])


func _on_fleet_home() -> void:
	for f in _fleets():
		var p := Navy.nearest_port(GameState, f)
		if p > 0 and p != f.port:
			GameState.issue(MoveFleet.new(GameState.player_tag, f.id, 0, p))


func _on_fleet_show() -> void:
	var fleets := _fleets()
	if not fleets.is_empty():
		get_tree().call_group("camera_focus", "focus_on", FleetLayer.position_of(fleets[0]))


# ------------------------------------------------------------------ orders

func _via_panel(method: String) -> void:
	get_tree().call_group("military_panel", method)


func _select(ids: Array[int]) -> void:
	get_tree().call_group("military_panel", "select_ids", ids)


const NEW_FRONT_BASE := 100
const DRAW_FRONT := 200
const FACE_FRONT := 201


func _fill_fronts() -> void:
	var popup := _front.get_popup()
	popup.clear()
	_front_ids.clear()
	_front_enemies.clear()
	for f: Front in GameState.fronts.values():
		if f.tag == GameState.player_tag:
			_front_ids.append(f.id)
	_front_ids.sort()
	for i in _front_ids.size():
		var f: Front = GameState.fronts[_front_ids[i]]
		popup.add_item("Assign to %s (%d)" % [f.display_name, f.army_ids.size()], i)
	var me := GameState.player_tag
	var others: Array = GameState.nations.keys()
	others.sort()
	for tag: String in others:
		if tag != me and GameState.at_war(me, tag) and not Military.border_provinces(GameState, me, tag).is_empty():
			_front_enemies.append(tag)
	if not _front_ids.is_empty() or not _front_enemies.is_empty():
		popup.add_separator("New front")
	for i in _front_enemies.size():
		popup.add_item("Face %s" % GameState.nations[_front_enemies[i]].display_name, NEW_FRONT_BASE + i)
	popup.add_item("Draw a line on the map…", DRAW_FRONT)
	popup.add_item("Face a nation (click it)…", FACE_FRONT)


func _on_front(id: int) -> void:
	var me := GameState.player_tag
	if id == DRAW_FRONT or id == FACE_FRONT:
		get_tree().call_group("military_panel", "begin_front", "draw" if id == DRAW_FRONT else "face")
		return
	var ids: Array[int] = []
	for a in _armies():
		if not a.embarked():
			ids.append(a.id)
	if ids.is_empty():
		return
	var front := 0
	if id >= NEW_FRONT_BASE and id < DRAW_FRONT:
		var i := id - NEW_FRONT_BASE
		if i >= _front_enemies.size():
			return
		var cmd := DesignateFront.new(me, "", [], _front_enemies[i])
		if not GameState.issue(cmd):
			return
		front = cmd.front_id
	elif id >= 0 and id < _front_ids.size():
		front = _front_ids[id]
	if front == 0:
		return
	GameState.issue(AssignToFront.new(me, front, ids))
	get_tree().call_group("army_layer", "set_selected_front", front)
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


func _fill_generals() -> void:
	var popup := _general.get_popup()
	popup.clear()
	_general_ids.clear()
	var armies := _armies()
	if armies.size() != 1:
		return
	var army := armies[0]
	var tag := GameState.player_tag
	var led: Array[General] = []
	for g: General in GameState.generals.values():
		if g.tag == tag and g.id != army.general_id:
			led.append(g)
	# The pool first, best first, then generals who lead other armies.
	led.sort_custom(func(x: General, y: General) -> bool:
		if (x.army_id == 0) != (y.army_id == 0):
			return x.army_id == 0
		return x.skill > y.skill or (x.skill == y.skill and x.id < y.id))
	for g in led:
		var where := "" if g.army_id == 0 else " (leads %s)" % GameState.armies[g.army_id].display_name
		_general_ids.append(g.id)
		popup.add_item("%s · skill %.2f%s" % [g.display_name, g.skill, where], g.id)
	if army.general_id != 0:
		popup.add_separator()
		popup.add_item("Relieve %s" % army.general_name, RELIEVE)
	if popup.item_count == 0:
		popup.add_item("No general available", NONE)
		popup.set_item_disabled(0, true)


const RELIEVE := -1
const NONE := -2


func _on_general(id: int) -> void:
	var armies := _armies()
	if armies.size() != 1:
		return
	if id == RELIEVE:
		GameState.issue(AssignGeneral.new(GameState.player_tag, armies[0].general_id, 0))
	elif _general_ids.has(id):
		GameState.issue(AssignGeneral.new(GameState.player_tag, id, armies[0].id))


const GROUP_NEW := -1
const GROUP_LEAVE := -2
const GROUP_RELIEVE := -3
const GROUP_DISBAND := -4
const MARSHAL_BASE := 1000


## The one group every selected army belongs to, or null.
func _common_group() -> ArmyGroup:
	var armies := _armies()
	if armies.is_empty() or armies[0].group_id == 0:
		return null
	for a in armies:
		if a.group_id != armies[0].group_id:
			return null
	return GameState.army_groups.get(armies[0].group_id)


func _fill_group() -> void:
	var popup := _group.get_popup()
	popup.clear()
	_group_ids.clear()
	_marshal_ids.clear()
	var armies := _armies()
	if armies.is_empty():
		return
	var tag := GameState.player_tag
	popup.add_item("New group", GROUP_NEW)
	for grp: ArmyGroup in GameState.army_groups.values():
		if grp.tag == tag:
			_group_ids.append(grp.id)
			popup.add_item("Join %s (%d)" % [grp.display_name, grp.army_ids.size()], _group_ids.size() - 1)
	if armies.any(func(a: Army) -> bool: return a.group_id != 0):
		popup.add_item("Leave group", GROUP_LEAVE)
	var current := _common_group()
	if current == null:
		return
	popup.add_separator()
	for g in Military.pool_of(GameState, tag):
		_marshal_ids.append(g.id)
		popup.add_item("Marshal: %s · skill %.2f" % [g.display_name, g.skill], MARSHAL_BASE + _marshal_ids.size() - 1)
	if current.marshal_id != 0:
		popup.add_item("Relieve marshal %s" % GameState.generals[current.marshal_id].display_name, GROUP_RELIEVE)
	popup.add_item("Disband %s" % current.display_name, GROUP_DISBAND)


func _on_group(id: int) -> void:
	var ids: Array[int] = []
	for a in _armies():
		ids.append(a.id)
	if ids.is_empty():
		return
	var tag := GameState.player_tag
	var current := _common_group()
	if id == GROUP_NEW:
		GameState.issue(CreateArmyGroup.new(tag, "", ids))
	elif id == GROUP_LEAVE:
		GameState.issue(AssignToGroup.new(tag, 0, ids))
	elif id == GROUP_RELIEVE and current != null:
		GameState.issue(SetMarshal.new(tag, current.id, 0))
	elif id == GROUP_DISBAND and current != null:
		GameState.issue(DisbandArmyGroup.new(tag, current.id))
	elif id >= MARSHAL_BASE and current != null and id - MARSHAL_BASE < _marshal_ids.size():
		GameState.issue(SetMarshal.new(tag, current.id, _marshal_ids[id - MARSHAL_BASE]))
	elif id >= 0 and id < _group_ids.size():
		GameState.issue(AssignToGroup.new(tag, _group_ids[id], ids))


const ATTACK_TOGGLE := -1
const ATTACK_DELETE := -2


## The attack line of the selected armies' group, or null.
func _line() -> AttackLine:
	var group := _common_group()
	return null if group == null else AttackLines.of_group(GameState, group.id)


func _line_status(line: AttackLine) -> String:
	if not line.active:
		return "attack line off"
	var c := line.campaign
	if c.is_empty():
		return "looking for a target" if Clock.days_elapsed >= line.wait else "no target at these odds"
	var name: String = MapData.provinces[c.target].name
	return ("gathering to attack %s" if c.phase == "gather" else "advancing on %s") % name


func _fill_attack() -> void:
	var popup := _attack.get_popup()
	popup.clear()
	_attack_enemies.clear()
	var group := _common_group()
	if group == null:
		return
	var line := AttackLines.of_group(GameState, group.id)
	if line != null:
		var toggle := "Stop the attack" if line.active else "Start the attack"
		popup.add_item("%s (%s)" % [toggle, line.display_name], ATTACK_TOGGLE)
		popup.set_item_disabled(0, not line.active and AttackLines.block(GameState, line) != "")
		popup.add_item("Delete the attack line", ATTACK_DELETE)
		return
	for enemy in AI.enemies(GameState, GameState.player_tag):
		_attack_enemies.append(enemy)
		popup.add_item("Draw a line against %s" % GameState.nations[enemy].display_name, _attack_enemies.size() - 1)
	if popup.item_count == 0:
		popup.add_item("Not at war", ATTACK_DELETE)
		popup.set_item_disabled(0, true)


func _on_attack(id: int) -> void:
	var group := _common_group()
	if group == null:
		return
	var tag := GameState.player_tag
	var line := AttackLines.of_group(GameState, group.id)
	if line != null:
		if id == ATTACK_TOGGLE:
			GameState.issue(SetAttackLine.new(tag, line.id, not line.active))
		elif id == ATTACK_DELETE:
			GameState.issue(DeleteAttackLine.new(tag, line.id))
	elif id >= 0 and id < _attack_enemies.size():
		var enemy := _attack_enemies[id]
		# Tie the line to the front that faces this enemy, if the player drew one.
		var front_id := 0
		for f: Front in GameState.fronts.values():
			if f.tag == tag and f.against == enemy:
				front_id = f.id
				break
		var made := CreateAttackLine.new(tag, group.id, enemy, front_id)
		if GameState.issue(made):
			GameState.issue(SetAttackLine.new(tag, made.line_id, true))


func _on_show() -> void:
	var armies := _armies()
	if armies.is_empty():
		return
	var sum := Vector2.ZERO
	for a in armies:
		sum += MapData.provinces[a.province].center
	get_tree().call_group("camera_focus", "focus_on", sum / armies.size())
