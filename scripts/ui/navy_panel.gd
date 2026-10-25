extends FloatingWindow
## The navy page of the Nation screen (Y): the shipyard of the selected province (build squadrons) and the
## state of the sea: upkeep, strength against enemies, who holds which zone and who is blockaded. Orders to
## the fleets themselves (missions, merge, split, back to port) are the command panel's (C). It also keeps the
## selection: clicking a fleet banner selects its fleets (dragging a box selects every fleet inside it); a right
## click on water sends the selected fleets there, and a right click on a port brings them in.


var _page := ScrollContainer.new()

var _yard_box := VBoxContainer.new()
var _yard_title := Label.new()
var _yard_info := Label.new()
var _type_picker := OptionButton.new()
var _count := SpinBox.new()
var _build := Button.new()
var _build_label := Label.new()
var _yard_list := ItemList.new()
var _yards: Array[int] = []
var _queue_label := Label.new()

var _sea_box := VBoxContainer.new()
var _sea_summary := Label.new()
var _sea_list := ItemList.new()
var _sea_zones_listed: Array[int] = []

## Ids of the selected fleets; the list mirrors it.
var _selected: Array[int] = []
var _province := 0


func _ready() -> void:
	add_to_group("navy_panel")
	name = "Navy"
	_build_yard_tab()
	_build_sea_tab()
	_page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page.custom_minimum_size = Vector2(340, 100)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	_page.add_child(column)
	for part: Array in [["Shipyard", _yard_box], ["Sea", _sea_box]]:
		var heading := Label.new()
		heading.text = part[0]
		heading.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95))
		column.add_child(heading)
		column.add_child(part[1])
	add_child(_page)
	setup_window("Navy", true, Vector2(500, 0), 1)
	GameState.fleets_changed.connect(_refresh)
	GameState.economy_updated.connect(_refresh)
	GameState.player_changed.connect(func(_t: String) -> void:
		_selected.clear()
		_sync_selection()
		_refresh())
	Clock.day_ticked.connect(_refresh)
	_refresh()


# ------------------------------------------------------------------ building the tabs

func _row(label: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(90, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _build_yard_tab() -> void:
	_yard_box.add_theme_constant_override("separation", 4)
	_yard_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_yard_title.add_theme_font_size_override("font_size", 15)
	_yard_box.add_child(_yard_title)
	_yard_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_yard_info.custom_minimum_size = Vector2(300, 0)
	_yard_box.add_child(_yard_info)
	for type in Navy.type_ids():
		var def: Dictionary = Navy.cfg.types[type]
		_type_picker.add_item(def.name)
		_type_picker.set_item_metadata(_type_picker.item_count - 1, type)
	_type_picker.focus_mode = Control.FOCUS_NONE
	_type_picker.tooltip_text = "The kind of ship. Bigger ships fight better but cost more IC and take longer."
	_type_picker.item_selected.connect(func(_i: int) -> void: _refresh_yard())
	_yard_box.add_child(_row("Build", _type_picker))
	_count.min_value = 1
	_count.max_value = 8
	_count.value = 1
	_count.tooltip_text = "How many squadrons to lay down at once. Ships are paid in industry (IC), not money."
	_count.value_changed.connect(func(_v: float) -> void: _refresh_yard())
	_yard_box.add_child(_row("Squadrons", _count))
	_build.text = "Build"
	_build.focus_mode = Control.FOCUS_NONE
	_build.tooltip_text = "Starts the ships in the selected port. They are paid from the daily IC and come out when finished."
	_build.pressed.connect(_on_build)
	_yard_box.add_child(_build)
	_build_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_label.custom_minimum_size = Vector2(300, 0)
	_yard_box.add_child(_build_label)
	_queue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_queue_label.custom_minimum_size = Vector2(300, 0)
	_yard_box.add_child(_queue_label)
	var yards_title := Label.new()
	yards_title.text = "Your ports"
	yards_title.modulate = Fmt.DIM
	_yard_box.add_child(yards_title)
	_yard_list.custom_minimum_size = Vector2(0, 110)
	_yard_list.item_selected.connect(func(i: int) -> void:
		if i >= 0 and i < _yards.size():
			get_tree().call_group("map_view", "select", _yards[i])
			get_tree().call_group("camera_focus", "focus_on", MapData.provinces[_yards[i]].center))
	_yard_box.add_child(_yard_list)


func _build_sea_tab() -> void:
	_sea_box.add_theme_constant_override("separation", 4)
	_sea_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sea_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sea_summary.custom_minimum_size = Vector2(300, 0)
	_sea_box.add_child(_sea_summary)
	var title := Label.new()
	title.text = "Who holds the sea"
	title.modulate = Fmt.DIM
	_sea_box.add_child(title)
	_sea_list.custom_minimum_size = Vector2(0, 150)
	_sea_list.item_selected.connect(func(i: int) -> void:
		if i >= 0 and i < _sea_zones_listed.size():
			get_tree().call_group("map_view", "select_zone", _sea_zones_listed[i])
			get_tree().call_group("camera_focus", "focus_on", MapData.sea_zones[_sea_zones_listed[i]].center))
	_sea_box.add_child(_sea_list)


# ------------------------------------------------------------------ selection and orders

## Opens the Nation screen on this tab, or closes it if it is already showing it.
func toggle() -> void:
	toggle_window()
	if visible:
		_refresh()


## The map's selected province changed: the shipyard tab follows it.
func set_province(id: int) -> void:
	_province = id
	if is_visible_in_tree():
		_refresh_yard()


func has_selection() -> bool:
	return not _selected.is_empty()


func clear_selection() -> void:
	_selected.clear()
	_sync_selection()
	_refresh()


## Another kind of selection (armies) took over.
func clear_selection_quiet() -> void:
	if _selected.is_empty():
		return
	_selected.clear()
	get_tree().call_group("fleet_layer", "set_selection", _selected.duplicate())
	get_tree().call_group("command_panel", "set_fleet_selection", _selected.duplicate())
	if is_visible_in_tree():
		_refresh()


## A fleet banner was clicked: select the player's fleets in it. Shift adds them (or removes them
## if they are all selected already).
func select_fleets(ids: Array[int], additive := false) -> void:
	var mine: Array[int] = []
	for id in ids:
		var f: Fleet = GameState.fleets.get(id)
		if f != null and f.tag == GameState.player_tag:
			mine.append(id)
	if mine.is_empty():
		return
	get_tree().call_group("military_panel", "clear_selection")
	if additive:
		if mine.all(func(x: int) -> bool: return _selected.has(x)):
			for id in mine:
				_selected.erase(id)
		else:
			for id in mine:
				if not _selected.has(id):
					_selected.append(id)
	elif _selected.size() == mine.size() and mine.all(func(x: int) -> bool: return _selected.has(x)):
		_selected.clear()
	else:
		_selected = mine
	_sync_selection()
	_refresh()


## Selects exactly these fleets (the fleet bar after a merge or a detachment).
func select_ids(ids: Array[int]) -> void:
	get_tree().call_group("military_panel", "clear_selection")
	_selected = ids.duplicate()
	_sync_selection()
	_refresh()


## A box was dragged on the map: select the player's fleets inside it. The army panel selects
## the armies in the same box, so the two selections coexist.
func select_in_rect(rect: Rect2, additive := false) -> void:
	var ids := FleetLayer.fleets_in_rect(rect, GameState.player_tag)
	if ids.is_empty():
		if not additive:
			clear_selection_quiet()
		return
	var all: Array[int] = []
	if additive:
		all.append_array(_selected)
	for id in ids:
		if not all.has(id):
			all.append(id)
	_selected = all
	_sync_selection()
	_refresh()


## Right click on water: send the selected fleets to the zone.
func order_zone(zone: int) -> void:
	if _selected.is_empty():
		return
	var failed := 0
	for id in _selected.duplicate():
		if not GameState.issue(MoveFleet.new(GameState.player_tag, id, zone)):
			failed += 1
	if failed > 0:
		get_tree().call_group("event_feed", "say", "%d of %d fleets cannot reach the %s." % [failed, _selected.size(), MapData.sea_zones[zone].name], Fmt.WARN)
	_refresh()


## Right click on a province with fleets selected: bring them into its port. Returns whether the
## click was used (it is not if no selected fleet could use that port).
func order_port(province: int) -> bool:
	if _selected.is_empty():
		return false
	if MapData.zones_of_port(province).is_empty():
		return false
	var done := 0
	for id in _selected.duplicate():
		if GameState.issue(MoveFleet.new(GameState.player_tag, id, 0, province)):
			done += 1
	if done == 0:
		get_tree().call_group("event_feed", "say", "The fleet cannot enter %s." % MapData.provinces[province].name, Fmt.WARN)
	_refresh()
	return true


func _sync_selection() -> void:
	get_tree().call_group("fleet_layer", "set_selection", _selected.duplicate())
	get_tree().call_group("command_panel", "set_fleet_selection", _selected.duplicate())


func _selected_fleets() -> Array[Fleet]:
	var out: Array[Fleet] = []
	for id in _selected:
		if GameState.fleets.has(id):
			out.append(GameState.fleets[id])
	return out


# ------------------------------------------------------------------ refreshing

func _refresh() -> void:
	if not is_visible_in_tree() or GameState.get_player() == null:
		return
	_selected = _selected.filter(func(id: int) -> bool: return GameState.fleets.has(id))
	_refresh_yard()
	_refresh_sea()
	_fit_height.call_deferred()


func _fit_height() -> void:
	fit_window(_page.get_child(0).get_combined_minimum_size().y + 34.0)


static func _shortest_range(f: Fleet) -> int:
	var shortest := 9999
	for s in f.ships:
		shortest = mini(shortest, s.def().range_days)
	return shortest


func _refresh_yard() -> void:
	var tag := GameState.player_tag
	var n := GameState.get_player()
	if n == null:
		return
	var type: String = _type_picker.get_item_metadata(_type_picker.selected)
	var count := int(_count.value)
	var ok_province := _province > 0 and GameState.province_owner[_province] == tag and not MapData.zones_of_port(_province).is_empty()
	if ok_province:
		var level := Navy.port_level(GameState, _province)
		_yard_title.text = "%s — level %d yard" % [MapData.provinces[_province].name, level]
		var zones: PackedStringArray = []
		for z in MapData.zones_of_port(_province):
			zones.append(MapData.sea_zones[z].name)
		var docked := Navy.fleets_in_port(GameState, _province)
		var ships := 0
		for f in docked:
			if f.tag == tag:
				ships += f.ships.size()
		_yard_info.text = "Opens on the %s.\nOn the slips: %d of %d. In port: %d squadrons." % [
				" and ".join(zones), Navy.building_in(GameState, tag, _province), Navy.yard_slots(GameState, _province), ships]
	else:
		_yard_title.text = "No port selected"
		_yard_info.text = "Select one of your coastal provinces on the map to build ships there."
	var problem := Navy.build_problem(GameState, tag, _province, type, count) if ok_province else "Select a coastal province of yours."
	var def: Dictionary = Navy.cfg.types[type]
	var cost := "£%.1fM, %s IC, at least %d days, needs a level %d port" % [def.cost * count, Fmt.thousands(roundi(def.ic * count)), def.build_days, def.min_port]
	_build.disabled = not problem.is_empty()
	_build_label.text = cost if problem.is_empty() else "%s (%s)" % [problem, cost]
	_build_label.modulate = Color.WHITE if problem.is_empty() else Fmt.WARN
	var queue: Array = n.shipbuilding.duplicate()
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.days_left < b.days_left)
	var lines: PackedStringArray = []
	for job in queue:
		lines.append("%s at %s: %d days" % [Navy.cfg.types[job.type].name, MapData.provinces[job.province].name, job.days_left])
	_queue_label.text = "Under construction:\n" + "\n".join(lines) if not lines.is_empty() else "Nothing under construction."
	# The nation's ports with a yard.
	var yards: Array[int] = []
	for id in n.provinces:
		if Navy.port_level(GameState, id) > 0 and not MapData.zones_of_port(id).is_empty():
			yards.append(id)
	yards.sort_custom(func(a: int, b: int) -> bool: return Navy.port_level(GameState, a) > Navy.port_level(GameState, b) or (Navy.port_level(GameState, a) == Navy.port_level(GameState, b) and a < b))
	if yards != _yards:
		_yards = yards
		_yard_list.clear()
		for id in yards:
			_yard_list.add_item("%s · level %d" % [MapData.provinces[id].name, Navy.port_level(GameState, id)])


func _on_build() -> void:
	var type: String = _type_picker.get_item_metadata(_type_picker.selected)
	GameState.issue(RaiseShips.new(GameState.player_tag, _province, type, int(_count.value)))
	_refresh()


func _refresh_sea() -> void:
	var tag := GameState.player_tag
	var n := GameState.get_player()
	var lines: PackedStringArray = []
	var mine := 0
	var power := 0.0
	for f in Navy.fleets_of(GameState, tag):
		mine += f.ships.size()
		power += f.power()
	lines.append("%d squadrons afloat, fighting power %.0f. Navy costs £%.1fM a month (£%.1fM of it ships)." % [
			mine, power, Fmt.monthly(n.naval_budget), Fmt.monthly(Navy.ship_upkeep(GameState, tag))])
	var theirs := 0.0
	var their_ships := 0
	for other in GameState.nations:
		if other != tag and GameState.at_war(tag, other):
			for f in Navy.fleets_of(GameState, other):
				theirs += f.power()
				their_ships += f.ships.size()
	if their_ships > 0:
		lines.append("The navies of your enemies: %d squadrons, fighting power %.0f." % [their_ships, theirs])
	if n.blockade > 0.005:
		var by: PackedStringArray = []
		for t in n.blockade_by:
			by.append(GameState.nations[t].display_name)
		lines.append("YOU ARE BLOCKADED: %d%% of your trade is cut%s." % [roundi(n.blockade * 100.0), (" by " + ", ".join(by)) if not by.is_empty() else ""])
	for other_tag in GameState.nations:
		var o: Nation = GameState.nations[other_tag]
		if other_tag != tag and o.blockade > 0.05 and o.blockade_by.has(tag):
			lines.append("You blockade %s: %d%%." % [o.display_name, roundi(o.blockade * 100.0)])
	_sea_summary.text = "\n".join(lines)
	var zones: Array[int] = []
	for z: int in GameState.sea_control:
		zones.append(z)
	zones.sort()
	_sea_zones_listed = zones
	_sea_list.clear()
	for z in zones:
		var c: Dictionary = GameState.sea_control[z]
		var who := "contested" if c.contested else ", ".join(c.holders.map(func(t: String) -> String: return GameState.nations[t].display_name))
		_sea_list.add_item("%s · %s" % [MapData.sea_zones[z].name, who])
		_sea_list.set_item_custom_fg_color(_sea_list.item_count - 1, Fmt.BAD if c.contested else (Fmt.GOOD if c.holders.has(tag) else Color.WHITE))
	if zones.is_empty():
		_sea_list.add_item("No fleet holds any zone.")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Y and not event.ctrl_pressed and not event.alt_pressed:
			toggle()
		elif event.keycode == KEY_ESCAPE and not _selected.is_empty():
			clear_selection()
			get_viewport().set_input_as_handled()
